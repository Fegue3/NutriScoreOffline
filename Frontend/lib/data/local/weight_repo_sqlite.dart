import 'package:drift/drift.dart';
import '../../domain/models.dart';
import '../../domain/repos.dart';
import 'db.dart';
import 'utils/dates.dart';

class WeightRepoSqlite implements WeightRepo {
  final NutriDatabase db;
  WeightRepoSqlite(this.db);

  @override
  Future<void> addLog(String userId, DateTime day, double kg, {String? note}) async {
    final iso = justDateIso(day);
    await db.customStatement('''
      INSERT INTO WeightLog (id, userId, day, weightKg, note)
      VALUES (lower(hex(randomblob(16))), ?, ?, ?, ?);
    ''', [userId, iso, kg, note]);
  }

  @override
  Future<List<WeightLogModel>> getRange(String userId, DateTime fromDay, DateTime toDay) async {
    final fromIso = justDateIso(fromDay);
    final toIso = justDateIso(toDay);
    final rows = await db.customSelect('''
      SELECT day, weightKg FROM WeightLog
      WHERE userId=? AND day BETWEEN ? AND ?
      ORDER BY day;
    ''', variables: [Variable.withString(userId), Variable.withString(fromIso), Variable.withString(toIso)]).get();

    return rows.map((r) => WeightLogModel(
      dayIso: r.data['day'] as String,
      kg: (r.data['weightKg'] as num).toDouble(),
    )).toList();
  }
}
