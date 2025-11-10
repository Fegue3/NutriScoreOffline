import 'package:drift/drift.dart';
import '../../domain/models.dart';
import '../../domain/repos.dart';
import 'db.dart';
import 'utils/dates.dart'; // justDateIso(DateTime)

/// NutriScore — Repositório de Peso (SQLite/Drift)
///
/// Guarda e consulta registos de **peso corporal** do utilizador.
///
/// Funcionalidades:
/// - [addLog] insere um registo (não agrega; mantém histórico completo);
/// - [getRange] obtém série de registos entre duas datas, **ordenados**;
/// - [latest] devolve o **registo mais recente** do utilizador.
///
/// Convenções:
/// - Datas de dia usam o formato ISO curto `"YYYY-MM-DD"` via [justDateIso].
class WeightRepoSqlite implements WeightRepo {
  /// Base de dados local.
  final NutriDatabase db;

  /// Constrói o repositório de peso.
  WeightRepoSqlite(this.db);

  /// Insere **um registo de peso** para o [userId] no dia [day] com valor [kg].
  ///
  /// Notas:
  /// - O ID é gerado via `lower(hex(randomblob(16)))`;
  /// - `createdAt` é definido para `datetime('now')`;
  /// - Campo [note] é opcional (pode ser `null`).
  @override
  Future<void> addLog(
    String userId,
    DateTime day,
    double kg, {
    String? note,
  }) async {
    final iso = justDateIso(day); // "YYYY-MM-DD"
    await db.customStatement(
      '''
      INSERT INTO WeightLog (id, userId, day, weightKg, note, createdAt)
      VALUES (lower(hex(randomblob(16))), ?, ?, ?, ?, datetime('now'));
      ''',
      [userId, iso, kg, note],
    );
  }

  /// Obtém a **série de registos** entre [fromDay] e [toDay] (inclusive),
  /// **ordenada por dia** e, dentro do dia, por `createdAt` ascendente.
  ///
  /// Regressa **todos os registos** do intervalo. (Se a UI quiser colapsar
  /// para “último do dia”, poderá fazê-lo após esta leitura.)
  @override
  Future<List<WeightLogModel>> getRange(
    String userId,
    DateTime fromDay,
    DateTime toDay,
  ) async {
    final fromIso = justDateIso(fromDay); // "YYYY-MM-DD"
    final toIso = justDateIso(toDay);

    // AGORA: devolve TODOS os logs no intervalo, ordenados por dia e createdAt.
    final rows = await db
        .customSelect(
          '''
    SELECT day, weightKg, createdAt
    FROM WeightLog
    WHERE userId = ? AND day BETWEEN ? AND ?
    ORDER BY day ASC, datetime(createdAt) ASC;
    ''',
          variables: [
            Variable.withString(userId),
            Variable.withString(fromIso),
            Variable.withString(toIso),
          ],
        )
        .get();

    return rows
        .map(
          (r) => WeightLogModel(
            dayIso: r.data['day'] as String,
            kg: (r.data['weightKg'] as num).toDouble(),
          ),
        )
        .toList();
  }

  /// Obtém o **último peso** registado pelo utilizador, considerando
  /// `ORDER BY createdAt DESC, day DESC`.
  ///
  /// Devolve `null` se não existirem registos.
  Future<WeightLogModel?> latest(String userId) async {
    final rows = await db
        .customSelect(
          '''
      SELECT day, weightKg
      FROM WeightLog
      WHERE userId=?
      ORDER BY createdAt DESC, day DESC
      LIMIT 1;
      ''',
          variables: [Variable.withString(userId)],
        )
        .get();

    if (rows.isEmpty) return null;
    final r = rows.first.data;
    return WeightLogModel(
      dayIso: r['day'] as String,
      kg: (r['weightKg'] as num).toDouble(),
    );
  }
}
