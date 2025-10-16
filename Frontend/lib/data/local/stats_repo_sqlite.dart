import 'package:drift/drift.dart';
import '../../domain/models.dart';
import '../../domain/repos.dart';
import 'db.dart';
import 'utils/dates.dart';

class StatsRepoSqlite implements StatsRepo {
  final NutriDatabase db;
  StatsRepoSqlite(this.db);

  @override
  Future<DailyStatsModel> computeDaily(String userId, DateTime dayUtcCanon) async {
    final day = canonDayUtcIso(dayUtcCanon);
    final rows = await db.customSelect('''
      SELECT 
        COALESCE(SUM(MealItem.kcal),0) AS kcal,
        COALESCE(SUM(MealItem.protein),0) AS protein,
        COALESCE(SUM(MealItem.carb),0) AS carb,
        COALESCE(SUM(MealItem.fat),0) AS fat,
        COALESCE(SUM(MealItem.sugars),0) AS sugars,
        COALESCE(SUM(MealItem.fiber),0) AS fiber,
        COALESCE(SUM(MealItem.salt),0) AS salt
      FROM Meal JOIN MealItem ON MealItem.mealId = Meal.id
      WHERE Meal.userId=? AND Meal.date=?;
    ''', variables: [Variable.withString(userId), Variable.withString(day)]).get();

    final r = rows.first.data;
    final model = DailyStatsModel(
      userId: userId,
      dateIso: day,
      kcal: r['kcal'] ?? 0,
      protein: (r['protein'] as num?)?.toDouble() ?? 0.0,
      carb: (r['carb'] as num?)?.toDouble() ?? 0.0,
      fat: (r['fat'] as num?)?.toDouble() ?? 0.0,
      sugars: (r['sugars'] as num?)?.toDouble() ?? 0.0,
      fiber: (r['fiber'] as num?)?.toDouble() ?? 0.0,
      salt: (r['salt'] as num?)?.toDouble() ?? 0.0,
    );

    await putCached(model);
    return model;
  }

  @override
  Future<DailyStatsModel?> getCached(String userId, DateTime dayUtcCanon) async {
    final day = canonDayUtcIso(dayUtcCanon);
    final rows = await db.customSelect('''
      SELECT userId, date, kcal, protein, carb, fat, sugars, fiber, salt
      FROM DailyStats WHERE userId=? AND date=? LIMIT 1;
    ''', variables: [Variable.withString(userId), Variable.withString(day)]).get();

    if (rows.isEmpty) return null;
    final r = rows.first.data;
    return DailyStatsModel(
      userId: r['userId'] as String,
      dateIso: r['date'] as String,
      kcal: r['kcal'] as int,
      protein: (r['protein'] as num).toDouble(),
      carb: (r['carb'] as num).toDouble(),
      fat: (r['fat'] as num).toDouble(),
      sugars: (r['sugars'] as num).toDouble(),
      fiber: (r['fiber'] as num).toDouble(),
      salt: (r['salt'] as num).toDouble(),
    );
  }

  @override
  Future<void> putCached(DailyStatsModel stats) async {
    await db.customStatement('''
      INSERT INTO DailyStats (userId, date, kcal, protein, carb, fat, sugars, fiber, salt)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(userId, date) DO UPDATE SET
        kcal=excluded.kcal, protein=excluded.protein, carb=excluded.carb, fat=excluded.fat,
        sugars=excluded.sugars, fiber=excluded.fiber, salt=excluded.salt,
        updatedAt=datetime('now');
    ''', [
      stats.userId,
      stats.dateIso,
      stats.kcal,
      stats.protein,
      stats.carb,
      stats.fat,
      stats.sugars,
      stats.fiber,
      stats.salt,
    ]);
  }
}
