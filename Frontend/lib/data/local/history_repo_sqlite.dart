import 'package:drift/drift.dart';
import '../../domain/repos.dart';
import '../../domain/models.dart';
import 'db.dart';

/// NutriScore — Repositório de Histórico de Produtos (SQLite/Drift)
///
/// Guarda os **scans/consultas de produtos** por utilizador, evitando duplicados
/// consecutivos e permitindo listar com paginação e janelas temporais.
///
/// Funcionalidades:
/// - `_upsertProductBasic` garante que existe linha em `Product` (nome/marca)
///   para enriquecer o JOIN da listagem, **sem alterar o schema**;
/// - `addIfNotDuplicateWithProduct` regista entrada evitando duplicar o **mesmo
///   barcode imediatamente anterior**, recebendo opcionalmente metadados do produto;
/// - `addIfNotDuplicate` (implementação da interface) idem, com `HistorySnapshot`;
/// - `list` suporta **página/tamanho**, e filtros `fromIso`/`toIso` em `scannedAt`.
class HistoryRepoSqlite implements HistoryRepo {
  /// Base de dados local.
  final NutriDatabase db;

  /// Constrói o repositório de histórico.
  HistoryRepoSqlite(this.db);

  /// Faz *upsert* mínimo em `Product` (barcode + nome/marca se disponíveis).
  ///
  /// Útil para garantir que a listagem com `LEFT JOIN Product` tem algo para mostrar,
  /// mesmo quando o produto ainda não foi sincronizado na totalidade.
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

  /// Adiciona ao histórico **se não for duplicado consecutivo**, com metadados opcionais.
  ///
  /// Regras:
  /// - Obtém o **último** barcode do utilizador; se igual ao recebido, **não regista**;
  /// - Faz `_upsertProductBasic` para enriquecer a listagem;
  /// - Insere entrada com `datetime('now')`.
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

  /// Implementação padrão: adiciona ao histórico **se não for duplicado consecutivo**.
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

    await db.customStatement(
      '''
      INSERT INTO ProductHistory
        (userId, barcode, calories, proteins, carbs, fat, scannedAt)
      VALUES (?, ?, ?, ?, ?, ?, datetime('now'));
      ''',
      [userId, s.barcode, s.calories, s.proteins, s.carbs, s.fat],
    );
  }

  /// Lista entradas do histórico do [userId].
  ///
  /// Parâmetros:
  /// - [page]: página (1-based), por omissão `1`;
  /// - [pageSize]: tamanho da página, por omissão `20`;
  /// - [fromIso]/[toIso]: intervalos opcionais (ISO-8601) aplicados a `scannedAt`.
  ///
  /// Notas:
  /// - `LEFT JOIN Product` para obter `name/brand` se disponíveis;
  /// - Ordena por `scannedAt DESC`.
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
