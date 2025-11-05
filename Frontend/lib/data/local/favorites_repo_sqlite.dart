import 'package:drift/drift.dart';
import '../../domain/models.dart';
import '../../domain/repos.dart';
import 'db.dart';

class FavoritesRepoSqlite implements FavoritesRepo {
  final NutriDatabase db;
  FavoritesRepoSqlite(this.db);

  // ---------------------------------------------------------------------------
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

  /// Útil na UI quando já tens os dados do produto carregados.
  Future<void> addWithProduct(
    String userId,
    String barcode, {
    String? name,
    String? brand,
  }) async {
    await _upsertProductBasic(barcode: barcode, name: name, brand: brand);
    await add(userId, barcode);
  }

  // ---------------------------------------------------------------------------

  @override
  Future<bool> isFavorited(String userId, String barcode) async {
    final r = await db.customSelect(
      'SELECT 1 FROM FavoriteProduct WHERE userId=? AND barcode=? LIMIT 1;',
      variables: [Variable.withString(userId), Variable.withString(barcode)],
    ).get();
    return r.isNotEmpty;
  }

  @override
  Future<void> add(String userId, String barcode) async {
    await db.customStatement(
      'INSERT OR IGNORE INTO FavoriteProduct (userId, barcode) VALUES (?, ?);',
      [userId, barcode],
    );
  }

  @override
  Future<void> remove(String userId, String barcode) async {
    await db.customStatement(
      'DELETE FROM FavoriteProduct WHERE userId=? AND barcode=?;',
      [userId, barcode],
    );
  }

  @override
  Future<bool> toggle(String userId, String barcode) async {
    final exists = await isFavorited(userId, barcode);
    if (exists) {
      await remove(userId, barcode);
      return false;
    } else {
      await add(userId, barcode);
      return true;
    }
  }

  @override
  Future<List<ProductModel>> list(
    String userId, {
    int page = 1,
    int pageSize = 20,
    String? q,
  }) async {
    final offset = (page - 1) * pageSize;

    final vars = <Variable>[Variable.withString(userId)];
    final sb = StringBuffer()
      ..writeln('SELECT p.id, p.barcode, p.name, p.brand,')
      ..writeln('       p.energyKcal_100g, p.proteins_100g, p.carbs_100g, p.fat_100g')
      ..writeln('FROM FavoriteProduct f')
      // LEFT JOIN para não “perder” favoritos se ainda não existir linha em Product
      ..writeln('LEFT JOIN Product p ON p.barcode = f.barcode')
      ..writeln('WHERE f.userId = ?');

    if (q != null && q.trim().isNotEmpty) {
      final like = '%${q.trim()}%';
      sb.writeln(
        'AND (p.name LIKE ? COLLATE NOCASE OR p.brand LIKE ? COLLATE NOCASE OR p.barcode LIKE ?)',
      );
      vars.addAll([
        Variable.withString(like),
        Variable.withString(like),
        Variable.withString(like),
      ]);
    }

    sb
      ..writeln('ORDER BY f.createdAt DESC')
      ..writeln('LIMIT ? OFFSET ?;');

    vars.addAll([Variable.withInt(pageSize), Variable.withInt(offset)]);

    final rows = await db.customSelect(sb.toString(), variables: vars).get();

    return rows.map((row) {
      final r = row.data;
      return ProductModel(
        // id pode vir INT → força string segura
        id: '${r['id']}',
        barcode: (r['barcode'] as String?) ?? '',
        name: ((r['name'] as String?) ?? '').trim(),
        brand: (r['brand'] as String?)?.trim(),
        energyKcal100g: r['energyKcal_100g'] as int?,
        protein100g: (r['proteins_100g'] as num?)?.toDouble(),
        carb100g: (r['carbs_100g'] as num?)?.toDouble(),
        fat100g: (r['fat_100g'] as num?)?.toDouble(),
      );
    }).toList();
  }
}
