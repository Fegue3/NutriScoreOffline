import 'package:drift/drift.dart';
import '../../domain/repos.dart';
import '../../domain/models.dart';
import 'db.dart';

class HistoryRepoSqlite implements HistoryRepo {
  final NutriDatabase db;
  HistoryRepoSqlite(this.db);

  // (Opcional) igual ao dos favoritos — útil se quiseres garantir que Product
  // tem name/brand antes de inserir histórico (não altera schema).
  Future<void> _upsertProductBasic({
    required String barcode,
    String? name,
    String? brand,
  }) async {
    await db.customStatement('''
      INSERT INTO Product (barcode, name, brand)
      VALUES (?, ?, ?)
      ON CONFLICT(barcode) DO UPDATE SET
        name  = COALESCE(excluded.name,  Product.name),
        brand = COALESCE(excluded.brand, Product.brand);
    ''', [barcode, name, brand]);
  }

  /// Variante opcional: usa quando tiveres o produto carregado (name/brand).
  Future<void> addIfNotDuplicateWithProduct(
    String userId, {
    required String barcode,
    String? name,
    String? brand,
    int? calories,
    double? proteins,
    double? carbs,
    double? fat,
  }) async {
    final last = await db
        .customSelect(
          '''
      SELECT barcode FROM ProductHistory
      WHERE userId=? ORDER BY scannedAt DESC LIMIT 1;
      ''',
          variables: [Variable.withString(userId)],
        )
        .getSingleOrNull();

    if (last != null && (last.data['barcode'] as String?) == barcode) {
      return;
    }

    // garante que o JOIN tem algo para mostrar
    await _upsertProductBasic(barcode: barcode, name: name, brand: brand);

    await db.customStatement(
      '''
      INSERT INTO ProductHistory
        (userId, barcode, calories, proteins, carbs, fat, scannedAt)
      VALUES (?, ?, ?, ?, ?, ?, datetime('now'));
      ''',
      [userId, barcode, calories, proteins, carbs, fat],
    );
  }

  @override
  Future<void> addIfNotDuplicate(String userId, HistorySnapshot s) async {
    // Evita repetir o mesmo barcode imediatamente anterior
    final last = await db
        .customSelect(
          '''
      SELECT barcode FROM ProductHistory
      WHERE userId=? ORDER BY scannedAt DESC LIMIT 1;
      ''',
          variables: [Variable.withString(userId)],
        )
        .getSingleOrNull();

    if (last != null && (last.data['barcode'] as String?) == s.barcode) {
      return;
    }

    // Se o teu HistorySnapshot já tiver name/brand, podes ligar isto:
    // await _upsertProductBasic(barcode: s.barcode, name: s.name, brand: s.brand);

    await db.customStatement(
      '''
      INSERT INTO ProductHistory
        (userId, barcode, calories, proteins, carbs, fat, scannedAt)
      VALUES (?, ?, ?, ?, ?, ?, datetime('now'));
      ''',
      [userId, s.barcode, s.calories, s.proteins, s.carbs, s.fat],
    );
  }

  @override
  Future<List<HistoryEntry>> list(
    String userId, {
    int page = 1,
    int pageSize = 20,
    String? fromIso,
    String? toIso,
  }) async {
    final offset = (page - 1) * pageSize;

    final vars = <Variable>[Variable.withString(userId)];
    final sb = StringBuffer()
      ..writeln('SELECT')
      ..writeln(
          '  h.id, h.barcode, h.scannedAt, h.calories, h.proteins, h.carbs, h.fat,')
      ..writeln('  p.name  AS productName,')
      ..writeln('  p.brand AS productBrand')
      ..writeln('FROM ProductHistory h')
      ..writeln('LEFT JOIN Product p ON p.barcode = h.barcode')
      ..writeln('WHERE h.userId = ?');

    if (fromIso != null) {
      sb.writeln('AND h.scannedAt >= ?');
      vars.add(Variable.withString(fromIso));
    }
    if (toIso != null) {
      sb.writeln('AND h.scannedAt <= ?');
      vars.add(Variable.withString(toIso));
    }

    sb
      ..writeln('ORDER BY h.scannedAt DESC')
      ..writeln('LIMIT ? OFFSET ?;');

    vars.addAll([Variable.withInt(pageSize), Variable.withInt(offset)]);

    final rows = await db.customSelect(sb.toString(), variables: vars).get();

    return rows.map((row) {
      final r = row.data;
      return HistoryEntry(
        id: '${r['id']}', // força string segura
        barcode: r['barcode'] as String?,
        scannedAtIso: r['scannedAt'] as String,
        calories: r['calories'] as int?,
        proteins: (r['proteins'] as num?)?.toDouble(),
        carbs: (r['carbs'] as num?)?.toDouble(),
        fat: (r['fat'] as num?)?.toDouble(),
        name: (r['productName'] as String?)?.trim(),
        brand: (r['productBrand'] as String?)?.trim(),
      );
    }).toList();
  }
}
