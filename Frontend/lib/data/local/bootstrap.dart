// lib/data/local/bootstrap.dart
import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'db.dart';

/// NutriScore — Bootstrap Local (SQLite/Drift)
///
/// Responsável por **garantir o esquema local** da base de dados e executar o
/// *seed* inicial a partir de um ficheiro SQL (`assets/sql/offline_schema.sql`).
///
/// Funcionalidades:
/// - Verifica se a tabela base (`User`) existe; se existir, **não** reaplica o schema;
/// - Carrega o SQL de assets e executa-o dentro de uma **transação**;
/// - Ativa `PRAGMA foreign_keys = ON;`;
/// - Divide corretamente o ficheiro SQL em *statements*, respeitando blocos
///   `CREATE TRIGGER ... BEGIN ... END;` (ver [_splitSqlStatements]).
class LocalBootstrap {
  /// Instância da base de dados Drift.
  final NutriDatabase db;

  /// Cria o bootstrapper para a [db] fornecida.
  LocalBootstrap(this.db);

  /// Garante que o **schema** existe e aplica o **seed** se necessário.
  ///
  /// Passos:
  /// 1) Verifica a existência da tabela `User` com [_tableExists];
  /// 2) Se não existir, carrega `assets/sql/offline_schema.sql`;
  /// 3) Abre transação, ativa `PRAGMA foreign_keys = ON;`, divide e executa
  ///    *statements* com [_splitSqlStatements].
  Future<void> ensureSchemaAndSeed() async {
    // 1) Verificar se já temos a tabela base
    final hasUserTable = await _tableExists('User');
    if (hasUserTable) return;

    // 2) Carregar schema e executar com split seguro (triggers etc.)
    final schemaSql =
        await rootBundle.loadString('assets/sql/offline_schema.sql');

    await db.transaction(() async {
      // garantir chaves estrangeiras
      await db.customStatement('PRAGMA foreign_keys = ON;');

      for (final stmt in _splitSqlStatements(schemaSql)) {
        final s = stmt.trim();
        if (s.isEmpty) continue;
        await db.customStatement(s);
      }
    });
  }

  /// Verifica se existe um objeto `type='table'` com o [table] indicado
  /// no `sqlite_master`. Devolve `true` se existir.
  Future<bool> _tableExists(String table) async {
    final rows = await db.customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1;",
      variables: [
        const Variable<String>('table'),
        Variable<String>(table),
      ],
    ).get();
    return rows.isNotEmpty;
  }
}

/// Divide o SQL em *statements* preservando blocos `CREATE TRIGGER ... BEGIN ... END;`.
///
/// Regras:
/// - Remove linhas vazias e comentários simples (`-- ...`);
/// - Quando dentro de um trigger, **apenas** termina ao encontrar `END;` na linha;
/// - Fora de trigger, termina em `;`;
/// - Garante *flush* final com `;` se necessário.
///
/// Recebe [sql] (conteúdo completo do ficheiro) e retorna uma lista de *statements*.
List<String> _splitSqlStatements(String sql) {
  final lines = sql
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('--')) // remove comentários simples
      .toList();

  final List<String> out = [];
  final StringBuffer buf = StringBuffer();
  bool inTrigger = false;

  bool isEndLine(String l) =>
      l.toUpperCase() == 'END;' || l.toUpperCase().endsWith(' END;');

  for (final line in lines) {
    final upper = line.toUpperCase();

    // detetar início de trigger
    if (!inTrigger && upper.startsWith('CREATE TRIGGER')) {
      inTrigger = true;
    }

    buf.writeln(line);

    if (inTrigger) {
      // num trigger só termina quando aparecer END;
      if (isEndLine(line)) {
        out.add(buf.toString());
        buf.clear();
        inTrigger = false;
      }
      continue;
    }

    // fora de trigger, termina em ';'
    if (line.endsWith(';')) {
      out.add(buf.toString());
      buf.clear();
    }
  }

  // flush final se restou algo
  final tail = buf.toString().trim();
  if (tail.isNotEmpty) out.add(tail.endsWith(';') ? tail : '$tail;');

  return out;
}
