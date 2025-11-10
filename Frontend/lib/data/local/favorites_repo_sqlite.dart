import 'package:drift/drift.dart';
import '../../domain/models.dart';
import '../../domain/repos.dart';
import 'db.dart';

/// NutriScore — Repositório de Favoritos (SQLite/Drift)
///
/// Implementação local de [FavoritesRepo] baseada em SQLite (via Drift).
/// Responsável por:
/// - Marcar/desmarcar produtos como favoritos por utilizador;
/// - Listar favoritos com paginação e pesquisa;
/// - Garantir que existe uma linha mínima em `Product` (via [_upsertProductBasic])
///   quando a UI já conhece `barcode`/`name`/`brand` (evita *joins* vazios).
class FavoritesRepoSqlite implements FavoritesRepo {
  /// Instância da base de dados local.
  final NutriDatabase db;

  /// Cria o repositório de favoritos SQLite.
  FavoritesRepoSqlite(this.db);

  // ---------------------------------------------------------------------------

  /// Faz *upsert* básico de um produto em `Product` para assegurar integridade
  /// de chaves quando marcamos como favorito um produto ainda não sincronizado.
  ///
  /// - Usa `INSERT ... ON CONFLICT(barcode) DO UPDATE` atualizando **apenas**
  ///   os campos não nulos (`COALESCE(excluded.col, Product.col)`).
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

  /// Adiciona favorito **já** com dados básicos do produto (se conhecidos).
  ///
  /// Útil quando a UI tem o produto carregado e quer evitar um estado intermédio
  /// sem metadados em `Product`.
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

  /// Indica se o [barcode] está favoritado pelo [userId].
  @override
  Future<bool> isFavorited(String userId, String barcode) async {
    final r = await db.customSelect(
      'SELECT 1 FROM FavoriteProduct WHERE userId=? AND barcode=? LIMIT 1;',
      variables: [Variable.withString(userId), Variable.withString(barcode)],
    ).get();
    return r.isNotEmpty;
  }

  /// Marca um produto como favorito (idempotente, usa `INSERT OR IGNORE`).
  @override
  Future<void> add(String userId, String barcode) async {
    await db.customStatement(
      'INSERT OR IGNORE INTO FavoriteProduct (userId, barcode) VALUES (?, ?);',
      [userId, barcode],
    );
  }

  /// Remove um favorito.
  @override
  Future<void> remove(String userId, String barcode) async {
    await db.customStatement(
      'DELETE FROM FavoriteProduct WHERE userId=? AND barcode=?;',
      [userId, barcode],
    );
  }

  /// Alterna o estado de favorito, devolvendo `true` se ficou favoritado.
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

  /// Lista os produtos favoritos do [userId], com **paginação** e pesquisa opcional.
  ///
  /// Parâmetros:
  /// - [page]: página 1-based (default `1`);
  /// - [pageSize]: tamanho da página (default `20`);
  /// - [q]: termo de pesquisa aplicado a `name`, `brand` ou `barcode`
  ///   (`LIKE` e `COLLATE NOCASE`).
  ///
  /// Notas:
  /// - Usa `LEFT JOIN` para não “perder” favoritos sem linha correspondente em `Product`;
  /// - Ordena por `f.createdAt DESC`.
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
