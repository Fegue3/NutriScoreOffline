// lib/data/local/bootstrap.dart
import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'db.dart';

class LocalBootstrap {
  final NutriDatabase db;
  LocalBootstrap(this.db);

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

    // 3) (Opcional) seed inicial
    // await db.customStatement(
    //   "INSERT INTO User(id,email,name,createdAt,updatedAt) VALUES(?,?,?,datetime('now'),datetime('now'))",
    //   ['u_demo', 'demo@local', 'Demo'],
    // );
  }

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

/// Divide o SQL em statements respeitando blocos CREATE TRIGGER ... BEGIN ... END;
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
