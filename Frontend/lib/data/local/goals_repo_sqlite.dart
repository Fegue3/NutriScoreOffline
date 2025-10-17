import 'package:drift/drift.dart' show Variable;
import '../../domain/models.dart';
import '../../domain/repos.dart';
import 'utils/nutrition_calc.dart' show NutritionCalc;
import 'db.dart';

class GoalsRepoSqlite implements GoalsRepo {
  final NutriDatabase db;
  GoalsRepoSqlite(this.db);

@override
Future<void> upsert(UserGoalsModel m) async {
  // ---- calcular calorias alvo se não vierem preenchidas
  final computedDaily = () {
    try {
      // lazy import para evitar ciclo
      // ignore: unused_import
      return NutritionCalc.computeFromGoals(m).calories;
    } catch (_) {
      return null;
    }
  }();

  final daily = m.dailyCalories ?? computedDaily;

  await db.transaction(() async {
    await db.customStatement('PRAGMA foreign_keys = ON;');

    await db.customStatement(
      '''
      INSERT INTO UserGoals (
        userId, sex, dateOfBirth, heightCm, currentWeightKg, targetWeightKg, targetDate, activityLevel,
        dailyCalories, carbPercent, proteinPercent, fatPercent, updatedAt
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
      ON CONFLICT(userId) DO UPDATE SET
        sex=excluded.sex,
        dateOfBirth=excluded.dateOfBirth,
        heightCm=excluded.heightCm,
        currentWeightKg=excluded.currentWeightKg,
        targetWeightKg=excluded.targetWeightKg,
        targetDate=excluded.targetDate,
        activityLevel=excluded.activityLevel,
        dailyCalories=excluded.dailyCalories,
        carbPercent=excluded.carbPercent,
        proteinPercent=excluded.proteinPercent,
        fatPercent=excluded.fatPercent,
        updatedAt=datetime('now');
      ''',
      [
        m.userId,
        m.sex,
        m.dateOfBirth?.toIso8601String(),
        m.heightCm,
        m.currentWeightKg,
        m.targetWeightKg,
        m.targetDate?.toIso8601String(),
        m.activityLevel,
        daily,                // <- aqui entra o valor calculado (ou o que veio)
        m.carbPercent,
        m.proteinPercent,
        m.fatPercent,
      ],
    );

    await db.customStatement(
      "UPDATE User SET onboardingCompleted=1, updatedAt=datetime('now') WHERE id=?;",
      [m.userId],
    );

    if (m.currentWeightKg > 0) {
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, today.day);
      await db.customStatement(
        '''
        INSERT OR REPLACE INTO WeightLog (id, userId, day, weightKg, source, createdAt)
        VALUES (hex(randomblob(16)), ?, ?, ?, 'onboarding', datetime('now'));
        ''',
        [m.userId, day.toIso8601String().substring(0, 10), m.currentWeightKg],
      );
    }
  });
}


  @override
  Future<UserGoalsModel?> getByUser(String userId) async {
    final rows = await db.customSelect(
      '''
      SELECT userId, sex, dateOfBirth, heightCm, currentWeightKg, targetWeightKg, targetDate, activityLevel,
             dailyCalories, carbPercent, proteinPercent, fatPercent
      FROM UserGoals WHERE userId=? LIMIT 1;
      ''',
      variables: [Variable.withString(userId)],
    ).get();

    if (rows.isEmpty) return null;
    final r = rows.first.data;

    DateTime? parseDate(String? s) => (s == null || s.isEmpty) ? null : DateTime.parse(s);

    return UserGoalsModel(
      userId: r['userId'] as String,
      sex: r['sex'] as String? ?? 'OTHER',
      dateOfBirth: parseDate(r['dateOfBirth'] as String?),
      heightCm: (r['heightCm'] as int?) ?? 0,
      currentWeightKg: (r['currentWeightKg'] as num?)?.toDouble() ?? 0,
      targetWeightKg: (r['targetWeightKg'] as num?)?.toDouble() ?? 0,
      targetDate: parseDate(r['targetDate'] as String?),
      activityLevel: r['activityLevel'] as String? ?? 'sedentary',
      dailyCalories: r['dailyCalories'] as int?,
      carbPercent: r['carbPercent'] as int?,
      proteinPercent: r['proteinPercent'] as int?,
      fatPercent: r['fatPercent'] as int?,
    );
  }
}
