import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models.dart';
import '../../domain/repos.dart';
import 'db.dart';

class ProductsRepoSqlite implements ProductsRepo {
  final NutriDatabase db;
  ProductsRepoSqlite(this.db);

  @override
  Future<ProductModel?> getByBarcode(String barcode) async {
    final rows = await db.customSelect('''
      SELECT id, barcode, name, energyKcal_100g, proteins_100g, carbs_100g, fat_100g, sugars_100g, fiber_100g, salt_100g
      FROM Product WHERE barcode = ? LIMIT 1;
    ''', variables: [Variable.withString(barcode)]).get();

    if (rows.isEmpty) return null;
    final r = rows.first.data;
    return ProductModel(
      id: r['id'] as String,
      barcode: r['barcode'] as String,
      name: r['name'] as String,
      energyKcal100g: r['energyKcal_100g'] as int?,
      protein100g: (r['proteins_100g'] as num?)?.toDouble(),
      carb100g: (r['carbs_100g'] as num?)?.toDouble(),
      fat100g: (r['fat_100g'] as num?)?.toDouble(),
      sugars100g: (r['sugars_100g'] as num?)?.toDouble(),
      fiber100g: (r['fiber_100g'] as num?)?.toDouble(),
      salt100g: (r['salt_100g'] as num?)?.toDouble(),
    );
  }

  @override
  Future<List<ProductModel>> searchByName(String q, {int limit = 50}) async {
    final rows = await db.customSelect('''
      SELECT id, barcode, name, energyKcal_100g, proteins_100g, carbs_100g, fat_100g
      FROM Product 
      WHERE name LIKE ? OR barcode LIKE ?
      ORDER BY name LIMIT ?;
    ''', variables: [
      Variable.withString('%$q%'),
      Variable.withString('%$q%'),
      Variable.withInt(limit)
    ]).get();

    return rows.map((row) {
      final r = row.data;
      return ProductModel(
        id: r['id'] as String,
        barcode: r['barcode'] as String,
        name: r['name'] as String,
        energyKcal100g: r['energyKcal_100g'] as int?,
        protein100g: (r['proteins_100g'] as num?)?.toDouble(),
        carb100g: (r['carbs_100g'] as num?)?.toDouble(),
        fat100g: (r['fat_100g'] as num?)?.toDouble(),
      );
    }).toList();
  }

  @override
  Future<void> upsert(ProductModel p) async {
    final id = p.id.isEmpty ? const Uuid().v4() : p.id;
    await db.customStatement('''
      INSERT INTO Product (id, barcode, name, energyKcal_100g, proteins_100g, carbs_100g, fat_100g, updatedAt)
      VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
      ON CONFLICT(barcode) DO UPDATE SET
        name=excluded.name,
        energyKcal_100g=excluded.energyKcal_100g,
        proteins_100g=excluded.proteins_100g,
        carbs_100g=excluded.carbs_100g,
        fat_100g=excluded.fat_100g,
        updatedAt=datetime('now');
    ''', [
      id,
      p.barcode,
      p.name,
      p.energyKcal100g,
      p.protein100g,
      p.carb100g,
      p.fat100g,
    ]);
  }
}
