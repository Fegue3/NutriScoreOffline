import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models.dart';
import '../../domain/repos.dart';
import 'db.dart';

/// Converte dinamicamente para `int?`, aceitando `int`, `double`, `num` ou `String`.
int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// NutriScore — Repositório de Produtos (SQLite/Drift)
///
/// Implementação local de [ProductsRepo] suportada por SQLite (via Drift).
/// Funcionalidades:
/// - **Pesquisa** por nome/marca/barcode com ordenação por relevância;
/// - **Lookup** rápido por código de barras;
/// - Pesquisa local paginada com filtros opcionais (ex.: países) — [searchLocal];
/// - **Upsert** de produtos, preservando `barcode` como chave única.
///
/// Notas:
/// - A pesquisa dá prioridade a **nome exato** e **prefixos**, seguida de
///   início de palavra, contém e barcode.
/// - Campos nutricionais seguem o padrão por 100 g: `energyKcal_100g`, `proteins_100g`, etc.
class ProductsRepoSqlite implements ProductsRepo {
  /// Base de dados local.
  final NutriDatabase db;

  /// Constrói o repositório de produtos.
  ProductsRepoSqlite(this.db);

  /// Pesquisa produtos por [q] usando heurística de relevância.
  ///
  /// Critérios (por ordem):
  /// 0. `name == q` (exato);
  /// 1. `name LIKE q%` (prefixo);
  /// 2. `name LIKE '% q%'` (início de palavra);
  /// 3. `name LIKE '%q%'` (contém);
  /// 4. `barcode == q` (exato);
  /// 5. `barcode LIKE '%q%'` (contém);
  /// 6. restante.
  ///
  /// Retorna até [limit] resultados. Normaliza espaços em [q].
  @override
  Future<List<ProductModel>> searchByName(String q, {int limit = 50}) async {
    final qNorm = q.trim().replaceAll(RegExp(r'\s+'), ' ');
    final likeAll = '%$qNorm%';
    final likePrefix = '$qNorm%';
    final likeWord = '% $qNorm%'; // início de palavra: “... snickers”

    final rows = await db
        .customSelect(
          '''
    SELECT
      id, barcode, name, brand,
      energyKcal_100g, proteins_100g, carbs_100g, fat_100g,
      sugars_100g, fiber_100g, salt_100g
    FROM Product
    WHERE (brand IS NOT NULL AND TRIM(brand) <> '')
      AND (
           name    LIKE ? COLLATE NOCASE
        OR barcode LIKE ?
        OR brand   LIKE ? COLLATE NOCASE
      )
    ORDER BY
      CASE
        WHEN lower(name) = lower(?)        THEN 0  -- nome EXATO
        WHEN lower(name) LIKE lower(?)     THEN 1  -- prefixo: q%
        WHEN lower(name) LIKE lower(?)     THEN 2  -- palavra: % q%
        WHEN lower(name) LIKE lower(?)     THEN 3  -- contém: %q%
        WHEN barcode = ?                   THEN 4  -- barcode exato (abaixo de nomes)
        WHEN barcode LIKE ?                THEN 5  -- barcode contém
        ELSE 6
      END,
      length(name) ASC,
      name COLLATE NOCASE ASC
    LIMIT ?
    ''',
          variables: [
            Variable.withString(likeAll),     // name LIKE ?
            Variable.withString(likeAll),     // barcode LIKE ?
            Variable.withString(likeAll),     // brand LIKE ?
            Variable.withString(qNorm),       // exact
            Variable.withString(likePrefix),  // prefix
            Variable.withString(likeWord),    // word-boundary
            Variable.withString(likeAll),     // contains
            Variable.withString(qNorm),       // barcode exact
            Variable.withString(likeAll),     // barcode contains
            Variable.withInt(limit),
          ],
        )
        .get();

    return rows.map((r) {
      final m = r.data;
      return ProductModel(
        id: m['id'] as String,
        barcode: m['barcode'] as String,
        name: (m['name'] as String).trim(),
        brand: (m['brand'] as String?)?.trim(),
        energyKcal100g: _toInt(m['energyKcal_100g']),
        protein100g: (m['proteins_100g'] as num?)?.toDouble(),
        carb100g: (m['carbs_100g'] as num?)?.toDouble(),
        fat100g: (m['fat_100g'] as num?)?.toDouble(),
        sugars100g: (m['sugars_100g'] as num?)?.toDouble(),
        fiber100g: (m['fiber_100g'] as num?)?.toDouble(),
        salt100g: (m['salt_100g'] as num?)?.toDouble(),
      );
    }).toList();
  }

  /// Obtém um produto pelo **código de barras**.
  ///
  /// Devolve `null` se não existir.
  @override
  Future<ProductModel?> getByBarcode(String barcode) async {
    final rows = await db
        .customSelect(
          '''
  SELECT
    id, barcode, name,
    brand,
    energyKcal_100g AS energyKcal100g,
    proteins_100g   AS protein100g,
    carbs_100g      AS carb100g,
    fat_100g        AS fat100g,
    sugars_100g     AS sugars100g,
    fiber_100g      AS fiber100g,
    salt_100g       AS salt100g
  FROM Product
  WHERE barcode = ?
  LIMIT 1;
  ''',
          variables: [Variable.withString(barcode)],
        )
        .get();

    if (rows.isEmpty) return null;
    final d = rows.first.data;
    return ProductModel(
      id: d['id'] as String,
      barcode: d['barcode'] as String,
      name: (d['name'] as String).trim(),
      brand: (d['brand'] as String?)?.trim(),
      energyKcal100g: d['energyKcal100g'] as int?,
      protein100g: (d['protein100g'] as num?)?.toDouble(),
      carb100g: (d['carb100g'] as num?)?.toDouble(),
      fat100g: (d['fat100g'] as num?)?.toDouble(),
      sugars100g: (d['sugars100g'] as num?)?.toDouble(),
      fiber100g: (d['fiber100g'] as num?)?.toDouble(),
      salt100g: (d['salt100g'] as num?)?.toDouble(),
    );
  }

  /// Pesquisa local paginada (utilitário extra, fora da interface).
  ///
  /// - Suporta [page]/[pageSize] e filtro opcional por países (`countriesFilter`,
  ///   ex.: `'%portugal%'`).
  /// - Ordena por `name` (`COLLATE NOCASE`).
  Future<List<ProductModel>> searchLocal(
    String q, {
    int page = 1,
    int pageSize = 20,
    String? countriesFilter, // ex.: '%portugal%' ou '%spain%'
  }) async {
    final qNorm = q.trim().replaceAll(RegExp(r'\s+'), ' ');
    final like = '%$qNorm%';
    final offset = (page - 1) * pageSize;

    final vars = <Variable>[
      Variable.withString(like),
      Variable.withString(like),
    ];

    final buffer = StringBuffer()
      ..writeln('SELECT id, barcode, name,')
      ..writeln('       energyKcal_100g, proteins_100g, carbs_100g, fat_100g')
      ..writeln('FROM Product')
      ..writeln('WHERE (name LIKE ? COLLATE NOCASE OR barcode LIKE ?)')
      ..writeln('  AND (brand IS NOT NULL AND TRIM(brand) <> \'\')');

    if (countriesFilter != null && countriesFilter.trim().isNotEmpty) {
      buffer.writeln('AND countries LIKE ?');
      vars.add(Variable.withString(countriesFilter));
    }

    buffer
      ..writeln('ORDER BY name COLLATE NOCASE ASC')
      ..writeln('LIMIT ? OFFSET ?;');

    vars.addAll([Variable.withInt(pageSize), Variable.withInt(offset)]);

    final rows = await db.customSelect(buffer.toString(), variables: vars).get();

    return rows.map((row) {
      final r = row.data;
      return ProductModel(
        id: r['id'] as String,
        barcode: r['barcode'] as String,
        name: (r['name'] as String?)?.trim() ?? '',
        energyKcal100g: r['energyKcal_100g'] as int?,
        protein100g: (r['proteins_100g'] as num?)?.toDouble(),
        carb100g: (r['carbs_100g'] as num?)?.toDouble(),
        fat100g: (r['fat_100g'] as num?)?.toDouble(),
      );
    }).toList();
  }

  /// Insere ou atualiza um produto.
  ///
  /// - Gera `id` se vier vazio (UUID v4);
  /// - Usa `ON CONFLICT(barcode) DO UPDATE` para garantir unicidade por `barcode`;
  /// - Atualiza os valores nutricionais por 100 g e `updatedAt`.
  @override
  Future<void> upsert(ProductModel p) async {
    final id = p.id.isEmpty ? const Uuid().v4() : p.id;
    await db.customStatement(
      '''
      INSERT INTO Product (
        id, barcode, name, brand,
        energyKcal_100g, proteins_100g, carbs_100g, fat_100g, 
        sugars_100g, fiber_100g, salt_100g, updatedAt
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
      ON CONFLICT(barcode) DO UPDATE SET
        name=excluded.name,
        brand=excluded.brand,
        energyKcal_100g=excluded.energyKcal_100g,
        proteins_100g=excluded.proteins_100g,
        carbs_100g=excluded.carb_100g,
        fat_100g=excluded.fat_100g,
        sugars_100g=excluded.sugars_100g,
        fiber_100g=excluded.fiber_100g,
        salt_100g=excluded.salt_100g,
        updatedAt=datetime('now');
    ''',
      [
        id,
        p.barcode,
        p.name,
        p.brand, 
        p.energyKcal100g,
        p.protein100g,
        p.carb100g,
        p.fat100g,
        p.sugars100g,
        p.fiber100g,
        p.salt100g,
      ],
    );
  }
}
