import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models.dart';
import '../../domain/repos.dart';
import '../local/db.dart';
import 'dto.dart';
import 'mappers.dart';
import 'products_remote_datasource.dart';
import 'sync_queue.dart';
import 'config.dart';

/// Repositório híbrido (offline-first) compatível com BD antiga.
/// - Busca local primeiro (com ranking: EXATO > prefixo > palavra > contém > barcode exato > barcode contém).
/// - Só vai online no getByBarcode() ou fetchOnlineAndCache() (quando o user submete).
/// - Gera IDs únicos para evitar conflitos.
class ProductsRepoHybrid implements ProductsRepo {
  final NutriDatabase db;
  final ProductsRemoteDataSource remote;
  final SyncQueue queue;
  final _uuid = const Uuid();

  ProductsRepoHybrid({
    required this.db,
    required this.remote,
    SyncQueue? queue,
  }) : queue = queue ?? SyncQueue(concurrency: kMaxConcurrentRequests);

  // ====================== Helpers =========================

  int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  Future<Map<String, dynamic>?> _getLocalRowByBarcode(String barcode) async {
    final rows = await db.customSelect(
      '''
      SELECT id, barcode, name, brand,
             energyKcal_100g, proteins_100g, carbs_100g, fat_100g,
             sugars_100g, fiber_100g, salt_100g
      FROM Product
      WHERE barcode = ?
      LIMIT 1;
      ''',
      variables: [Variable.withString(barcode)],
    ).get();
    return rows.isEmpty ? null : rows.first.data;
  }

  Future<void> _upsertLocalFromDto(OffProductDto d, {String? etag}) async {
    final m = dtoToProductModel(d);
    final args = [
      _uuid.v4(), // gera novo ID único
      m.barcode,
      m.name,
      m.brand,
      m.energyKcal100g,
      m.protein100g,
      m.carb100g,
      m.fat100g,
      m.sugars100g,
      m.fiber100g,
      m.salt100g,
    ];

    try {
      // tentativa com colunas novas
      await db.customStatement(
        '''
        INSERT INTO Product (
          id, barcode, name, brand,
          energyKcal_100g, proteins_100g, carbs_100g, fat_100g,
          sugars_100g, fiber_100g, salt_100g,
          etag, lastFetchedAt, nutrimentsJson, updatedAt
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
        ON CONFLICT(barcode) DO UPDATE SET
          name=excluded.name,
          brand=excluded.brand,
          energyKcal_100g=excluded.energyKcal_100g,
          proteins_100g=excluded.proteins_100g,
          carbs_100g=excluded.carbs_100g,
          fat_100g=excluded.fat_100g,
          sugars_100g=excluded.sugars_100g,
          fiber_100g=excluded.fiber_100g,
          salt_100g=excluded.salt_100g,
          updatedAt=datetime('now');
        ''',
        [
          ...args,
          etag,
          DateTime.now().toIso8601String(),
          nutrimentsToJson(d),
        ],
      );
    } catch (e) {
      // fallback para bases antigas
      // ignore: avoid_print
      print("⚠️ [HybridRepo] Fallback insert sem colunas novas: $e");
      try {
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
            carbs_100g=excluded.carbs_100g,
            fat_100g=excluded.fat_100g,
            sugars_100g=excluded.sugars_100g,
            fiber_100g=excluded.fiber_100g,
            salt_100g=excluded.salt_100g,
            updatedAt=datetime('now');
          ''',
          args,
        );
      } catch (e2) {
        // ignore: avoid_print
        print("❌ [HybridRepo] Erro no fallback insert: $e2");
      }
    }
  }

  ProductModel _rowToModel(Map<String, dynamic> r) {
    return ProductModel(
      id: (r['id'] as String?) ?? '',
      barcode: (r['barcode'] as String),
      name: (r['name'] as String?)?.trim() ?? '',
      brand: (r['brand'] as String?)?.trim(),
      energyKcal100g: _toInt(r['energyKcal_100g']),
      protein100g: (r['proteins_100g'] as num?)?.toDouble(),
      carb100g: (r['carbs_100g'] as num?)?.toDouble(),
      fat100g: (r['fat_100g'] as num?)?.toDouble(),
      sugars100g: (r['sugars_100g'] as num?)?.toDouble(),
      fiber100g: (r['fiber_100g'] as num?)?.toDouble(),
      salt100g: (r['salt_100g'] as num?)?.toDouble(),
    );
  }

  // ====================== Interface =========================

  @override
  Future<ProductModel?> getByBarcode(String barcode) async {
    final local = await _getLocalRowByBarcode(barcode);

    if (local != null) {
      // ignore: avoid_print
      print("🔎 [HybridRepo] Produto $barcode encontrado localmente");
      return _rowToModel(local);
    }

    // ignore: avoid_print
    print("🌍 [HybridRepo] A ir à OFF API para barcode $barcode");
    try {
      final (dto, newEtag, _) = await remote.getByBarcode(barcode, etag: null);
      if (dto != null) {
        await _upsertLocalFromDto(dto, etag: newEtag);
        final refreshed = await _getLocalRowByBarcode(barcode);
        // ignore: avoid_print
        print("✅ [HybridRepo] Produto $barcode guardado localmente");
        return refreshed != null ? _rowToModel(refreshed) : null;
      }
    } catch (e) {
      // ignore: avoid_print
      print("⚠️ [HybridRepo] Falha ao obter produto online: $e");
    }

    return null;
  }

  @override
  Future<List<ProductModel>> searchByName(String q, {int limit = 50}) async {
    // mesma prioridade do repo sqlite: EXATO > prefixo > palavra > contém > barcode exato > barcode contém
    final qNorm = q.trim().replaceAll(RegExp(r'\s+'), ' ');
    final likeAll = '%$qNorm%';
    final likePrefix = '$qNorm%';
    final likeWord = '% $qNorm%';

    final rows = await db.customSelect(
      '''
      SELECT id, barcode, name, brand,
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
          WHEN lower(name) = lower(?)        THEN 0
          WHEN lower(name) LIKE lower(?)     THEN 1
          WHEN lower(name) LIKE lower(?)     THEN 2
          WHEN lower(name) LIKE lower(?)     THEN 3
          WHEN barcode = ?                   THEN 4
          WHEN barcode LIKE ?                THEN 5
          ELSE 6
        END,
        length(name) ASC,
        name COLLATE NOCASE ASC
      LIMIT ?;
      ''',
      variables: [
        Variable.withString(likeAll),
        Variable.withString(likeAll),
        Variable.withString(likeAll),
        Variable.withString(qNorm),
        Variable.withString(likePrefix),
        Variable.withString(likeWord),
        Variable.withString(likeAll),
        Variable.withString(qNorm),
        Variable.withString(likeAll),
        Variable.withInt(limit),
      ],
    ).get();

    final localResults = rows.map((r) => _rowToModel(r.data)).toList();

    if (localResults.isNotEmpty) {
      // ignore: avoid_print
      print("🔎 [HybridRepo] '$qNorm' encontrado localmente (${localResults.length} resultados, rankeados)");
      return localResults;
    }

    // ⚙️ Só vai online quando o utilizador submete explicitamente via UI (fetchOnlineAndCache)
    // ignore: avoid_print
    print("🕓 [HybridRepo] '$qNorm' não existe localmente — aguardar submit do user");
    return localResults;
  }

  /// Chama isto quando o utilizador pressiona “Enter/Pesquisar”.
  /// Faz fetch online, guarda localmente e volta a pesquisar com o mesmo ranking.
  Future<List<ProductModel>> fetchOnlineAndCache(String q, {int limit = 50}) async {
    final qNorm = q.trim().replaceAll(RegExp(r'\s+'), ' ');
    // ignore: avoid_print
    print("🌍 [HybridRepo] Fetch online submit → '$qNorm'");
    try {
      final list = await remote.search(qNorm, limit: limit);
      if (list.isNotEmpty) {
        await db.transaction(() async {
          for (final d in list) {
            if (d.code.isEmpty) continue;
            await _upsertLocalFromDto(d);
          }
        });
        // ignore: avoid_print
        print("✅ [HybridRepo] ${list.length} produtos da OFF API guardados");

        // reutiliza a mesma query local com ranking
        return await searchByName(qNorm, limit: limit);
      }
    } catch (e) {
      // ignore: avoid_print
      print("⚠️ [HybridRepo] Erro ao fazer fetch online: $e");
    }
    return [];
  }

  @override
  Future<void> upsert(ProductModel p) async {
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
        _uuid.v4(),
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
