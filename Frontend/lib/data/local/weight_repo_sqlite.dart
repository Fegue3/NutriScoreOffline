import 'package:drift/drift.dart';
import '../../domain/models.dart';
import '../../domain/repos.dart';
import 'db.dart';
import 'utils/dates.dart'; // justDateIso(DateTime)

class WeightRepoSqlite implements WeightRepo {
  final NutriDatabase db;
  WeightRepoSqlite(this.db);

  // Insere 1 log (não agrega por dia – fica histórico completo)
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

  // Série por dia no intervalo, devolvendo o ÚLTIMO registo de cada dia
  // (equivalente ao backend que considera o último do dia)
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

  // (opcional) último peso global do utilizador
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
