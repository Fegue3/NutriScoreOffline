// lib/data/local/db.dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path_provider/path_provider.dart';

part 'db.g.dart';

LazyDatabase _openDb() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'nutriscore.db'));
    return NativeDatabase.createInBackground(file, logStatements: kDebugMode,);
  });
}

@DriftDatabase(tables: [], daos: [])
class NutriDatabase extends _$NutriDatabase {
  NutriDatabase() : super(_openDb());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.database.customStatement('PRAGMA foreign_keys = ON;');
      await _bootstrapFromAsset(m.database); // executa script corretamente
    },
    onUpgrade: (m, from, to) async {
      await m.database.customStatement('PRAGMA foreign_keys = ON;');
      await _ensureSchema(m.database);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON;');
      await _ensureSchema(this);
    },
  );

  Future<void> _ensureSchema(GeneratedDatabase db) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='User' LIMIT 1;"
    ).get();
    if (rows.isEmpty) {
      await _bootstrapFromAsset(db);
    }
  }

  Future<void> _bootstrapFromAsset(GeneratedDatabase db) async {
    final sql = await rootBundle.loadString('assets/sql/offline_schema.sql');
    await _execSqlScript(db, sql);
  }
}

/// Executa o .sql respeitando blocos CREATE TRIGGER ... BEGIN ... END;
Future<void> _execSqlScript(GeneratedDatabase db, String script) async {
  final buf = StringBuffer();
  var inTriggerBlock = false;

  for (final rawLine in script.split(RegExp(r'\r?\n'))) {
    var line = rawLine.trim();
    if (line.isEmpty || line.startsWith('--')) continue;

    final upper = line.toUpperCase();

    // Entrou num CREATE TRIGGER → começa bloco
    if (!inTriggerBlock && upper.startsWith('CREATE TRIGGER')) {
      inTriggerBlock = true;
    }

    buf.writeln(rawLine); // manter formatação original

    if (inTriggerBlock) {
      // Fim de bloco de trigger
      if (upper == 'END;' || upper.endsWith('\nEND;')) {
        await db.customStatement(buf.toString());
        buf.clear();
        inTriggerBlock = false;
      }
    } else {
      // Statement “normal”: termina em ';'
      if (line.endsWith(';')) {
        await db.customStatement(buf.toString());
        buf.clear();
      }
    }
  }
}