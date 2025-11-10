// lib/data/local/db.dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'db.g.dart';

/// NutriScore — Base de Dados Local (Drift/SQLite)
///
/// Responsável por:
/// - Preparar o ficheiro de base de dados na primeira execução, preferindo
///   **copiar um catálogo pré-carregado** de `assets/db/nutriscore.db`;
/// - Criar e abrir a BD com **Drift** em modo `LazyDatabase`;
/// - Aplicar o **schema inicial** via `offline_schema.sql` quando não existe
///   o asset pré-carregado (caminho *fallback*);
/// - Ativar `PRAGMA foreign_keys = ON;` em `onCreate`, `onUpgrade` e `beforeOpen`.
///
/// Estrutura:
/// - [_prepareDatabaseFile] tenta copiar o asset e faz *fallback* para criação
///   do ficheiro vazio (o *bootstrap* corre em `onCreate`);
/// - [_execSqlScript] executa ficheiros `.sql` respeitando blocos
///   `CREATE TRIGGER ... BEGIN ... END;`.

/// Copia a BD pré-carregada (`assets/db/nutriscore.db`) para o armazenamento
/// da app no **primeiro arranque**. Se não existir o asset, faz *fallback* para
/// criar via SQL no `onCreate`.
Future<File> _prepareDatabaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(dir.path, 'nutriscore.db'); // nome "oficial" da app
  final dbFile = File(dbPath);

  if (await dbFile.exists()) {
    return dbFile; // já tens BD → abre
  }

  // 1) Tenta copiar o asset pré-carregado
  try {
    final bytes = (await rootBundle.load('assets/db/nutriscore.db')).buffer.asUint8List();
    await dbFile.writeAsBytes(bytes, flush: true);
    debugPrint('✅ Copiado catálogo inicial para $dbPath');
    return dbFile; // já vem com schema+dados → onCreate NÃO corre
  } catch (e) {
    debugPrint('ℹ️ Sem asset preloaded (assets/db/nutriscore.db). '
        'Vamos criar via offline_schema.sql no onCreate. Detalhe: $e');
  }

  // 2) Fallback: deixa o Drift criar o ficheiro vazio
  //    (o onCreate irá correr e aplicar o offline_schema.sql)
  return dbFile;
}

/// Abre a base de dados de forma preguiçosa (`LazyDatabase`),
/// possibilitando correr trabalho de IO antes da criação do *engine*.
LazyDatabase _openDb() {
  return LazyDatabase(() async {
    final file = await _prepareDatabaseFile();
    // Se o ficheiro já vinha dos assets, tem schema + dados → onCreate não dispara.
    // Se for novo/vazio, o SQLite cria → onCreate dispara e corremos o SQL.
    return NativeDatabase.createInBackground(
      file,
      logStatements: kDebugMode,
    );
  });
}

/// Entrada principal da base de dados Drift.
///
/// **Nota**: As `tables` e `daos` são geradas em `part 'db.g.dart'`.
@DriftDatabase(tables: [], daos: [])
class NutriDatabase extends _$NutriDatabase {
  /// Constrói a BD usando o *opener* preguiçoso.
  NutriDatabase() : super(_openDb());

  /// Versão do schema local. Incrementar quando introduzir migrações.
  @override
  int get schemaVersion => 1;

  /// Estratégia de migração com *hooks* para criação/upgrade/abertura.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          // Só corre quando o ficheiro foi criado de raiz (fallback, sem asset)
          await m.database.customStatement('PRAGMA foreign_keys = ON;');
          await _bootstrapFromAsset(m.database); // aplica offline_schema.sql
        },
        onUpgrade: (m, from, to) async {
          await m.database.customStatement('PRAGMA foreign_keys = ON;');
          // Se precisares de migrações futuras, mete aqui.
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
          // Se a BD veio do asset, já tem tudo criado → nada a fazer aqui.
        },
      );

  /// Aplica o **schema inicial** a partir do `offline_schema.sql`.
  ///
  /// Chamado apenas no *fallback* quando não existe catálogo pré-carregado.
  Future<void> _bootstrapFromAsset(GeneratedDatabase db) async {
    // Cria schema via SQL (só no fallback sem asset)
    final sql = await rootBundle.loadString('assets/sql/offline_schema.sql');
    await _execSqlScript(db, sql);
  }
}

/// Executa um script `.sql` **respeitando blocos de triggers**:
/// `CREATE TRIGGER ... BEGIN ... END;`.
///
/// Regras:
/// - Ignora linhas vazias e comentários (`-- ...`);
/// - Dentro de triggers, **só termina** ao encontrar `END;` na linha;
/// - Fora de triggers, termina em `;` (ponto e vírgula).
Future<void> _execSqlScript(GeneratedDatabase db, String script) async {
  final buf = StringBuffer();
  var inTriggerBlock = false;

  for (final rawLine in script.split(RegExp(r'\r?\n'))) {
    var line = rawLine.trim();
    if (line.isEmpty || line.startsWith('--')) continue;

    final upper = line.toUpperCase();

    if (!inTriggerBlock && upper.startsWith('CREATE TRIGGER')) {
      inTriggerBlock = true;
    }

    buf.writeln(rawLine);

    if (inTriggerBlock) {
      if (upper == 'END;' || upper.endsWith('\nEND;')) {
        await db.customStatement(buf.toString());
        buf.clear();
        inTriggerBlock = false;
      }
    } else {
      if (line.endsWith(';')) {
        await db.customStatement(buf.toString());
        buf.clear();
      }
    }
  }
}
