import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models.dart';
import '../../domain/repos.dart';
import 'db.dart';
import 'utils/dates.dart';
import 'utils/nutrition_calc.dart';

class MealsRepoSqlite implements MealsRepo {
  final NutriDatabase db;
  MealsRepoSqlite(this.db);

  @override
  Future<List<MealWithItems>> getMealsForDay(String userId, DateTime dayUtcCanon) async {
    final day = canonDayUtcIso(dayUtcCanon);
    final meals = await db.customSelect('''
      SELECT id, type, date, COALESCE(totalKcal,0) as totalKcal, 
             COALESCE(totalProtein,0) as totalProtein, COALESCE(totalCarb,0) as totalCarb, COALESCE(totalFat,0) as totalFat
      FROM Meal WHERE userId=? AND date=? ORDER BY type;
    ''', variables: [Variable.withString(userId), Variable.withString(day)]).get();

    final result = <MealWithItems>[];
    for (final m in meals) {
      final mid = m.data['id'] as String;
      final items = await db.customSelect('''
        SELECT id, mealId, productBarcode, customFoodId, unit, quantity, gramsTotal, kcal, protein, carb, fat, sugars, fiber, salt
        FROM MealItem WHERE mealId=? ORDER BY position NULLS LAST, id;
      ''', variables: [Variable.withString(mid)]).get();

      final parsedItems = items.map((row) {
        final r = row.data;
        return MealItemModel(
          id: r['id'] as String,
          mealId: r['mealId'] as String,
          productBarcode: r['productBarcode'] as String?,
          customFoodId: r['customFoodId'] as String?,
          unit: r['unit'] as String,
          quantity: (r['quantity'] as num).toDouble(),
          gramsTotal: (r['gramsTotal'] as num?)?.toDouble(),
          kcal: r['kcal'] as int?,
          protein: (r['protein'] as num?)?.toDouble(),
          carb: (r['carb'] as num?)?.toDouble(),
          fat: (r['fat'] as num?)?.toDouble(),
          sugars: (r['sugars'] as num?)?.toDouble(),
          fiber: (r['fiber'] as num?)?.toDouble(),
          salt: (r['salt'] as num?)?.toDouble(),
        );
      }).toList();

      result.add(MealWithItems(
        id: mid,
        type: m.data['type'] as String,
        dateIso: m.data['date'] as String,
        totalKcal: (m.data['totalKcal'] as int?) ?? 0,
        protein: (m.data['totalProtein'] as num?)?.toDouble() ?? 0.0,
        carb: (m.data['totalCarb'] as num?)?.toDouble() ?? 0.0,
        fat: (m.data['totalFat'] as num?)?.toDouble() ?? 0.0,
        items: parsedItems,
      ));
    }
    return result;
  }

  @override
  Future<void> addOrUpdateMealItem(AddMealItemInput input) async {
    final day = canonDayUtcIso(input.dayUtcCanon);

    await db.transaction(() async {
      // 1) garantir meal
      final mealId = await _ensureMeal(input.userId, day, input.mealType);

      // 2) buscar perfil nutricional (100g) da fonte
      Nutr100g nutr = const Nutr100g();
      double? gramsPerUnit;

      if (input.productBarcode != null) {
        final r = await db.customSelect('''
          SELECT energyKcal_100g, proteins_100g, carbs_100g, fat_100g, sugars_100g, fiber_100g, salt_100g
          FROM Product WHERE barcode=? LIMIT 1;
        ''', variables: [Variable.withString(input.productBarcode!)]).getSingleOrNull();

        if (r != null) {
          final d = r.data;
          nutr = Nutr100g(
            kcal: d['energyKcal_100g'] as int?,
            protein: (d['proteins_100g'] as num?)?.toDouble(),
            carb: (d['carbs_100g'] as num?)?.toDouble(),
            fat: (d['fat_100g'] as num?)?.toDouble(),
            sugars: (d['sugars_100g'] as num?)?.toDouble(),
            fiber: (d['fiber_100g'] as num?)?.toDouble(),
            salt: (d['salt_100g'] as num?)?.toDouble(),
          );
        }
      } else if (input.customFoodId != null) {
        final r = await db.customSelect('''
          SELECT energyKcal_100g, proteins_100g, carbs_100g, fat_100g, sugars_100g, fiber_100g, salt_100g, gramsPerUnit
          FROM CustomFood WHERE id=? LIMIT 1;
        ''', variables: [Variable.withString(input.customFoodId!)]).getSingleOrNull();
        if (r != null) {
          final d = r.data;
          gramsPerUnit = (d['gramsPerUnit'] as num?)?.toDouble();
          nutr = Nutr100g(
            kcal: d['energyKcal_100g'] as int?,
            protein: (d['proteins_100g'] as num?)?.toDouble(),
            carb: (d['carbs_100g'] as num?)?.toDouble(),
            fat: (d['fat_100g'] as num?)?.toDouble(),
            sugars: (d['sugars_100g'] as num?)?.toDouble(),
            fiber: (d['fiber_100g'] as num?)?.toDouble(),
            salt: (d['salt_100g'] as num?)?.toDouble(),
          );
        }
      }

      // 3) calcular
      final calc = calcPerQuantity(
        unit: input.unit,
        quantity: input.quantity,
        n: nutr,
        gramsPerUnit: gramsPerUnit,
      );

      // 4) inserir item
      final itemId = const Uuid().v4();
      await db.customStatement('''
        INSERT INTO MealItem (id, mealId, productBarcode, customFoodId, unit, quantity, gramsTotal,
                              kcal, protein, carb, fat, sugars, fiber, salt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''', [
        itemId,
        mealId,
        input.productBarcode,
        input.customFoodId,
        input.unit,
        input.quantity,
        calc.gramsTotal,
        calc.kcal,
        calc.protein,
        calc.carb,
        calc.fat,
        calc.sugars,
        calc.fiber,
        calc.salt,
      ]);

      // 5) recalcular totals da meal + daily
      await _recalcMealTotals(mealId);
      await _recalcDailyStats(input.userId, day);
    });
  }

  @override
  Future<void> removeMealItem(String mealItemId) async {
    await db.transaction(() async {
      final info = await db.customSelect('''
        SELECT MealItem.mealId AS mealId, Meal.userId AS userId, Meal.date AS day
        FROM MealItem JOIN Meal ON MealItem.mealId = Meal.id
        WHERE MealItem.id=? LIMIT 1;
      ''', variables: [Variable.withString(mealItemId)]).getSingleOrNull();
      if (info == null) return;
      final r = info.data;
      final mealId = r['mealId'] as String;
      final userId = r['userId'] as String;
      final day = r['day'] as String;

      await db.customStatement('DELETE FROM MealItem WHERE id=?;', [mealItemId]);
      await _recalcMealTotals(mealId);
      await _recalcDailyStats(userId, day);
    });
  }

  Future<String> _ensureMeal(String userId, String dayIso, String type) async {
    final e = await db.customSelect(
      'SELECT id FROM Meal WHERE userId=? AND date=? AND type=? LIMIT 1;',
      variables: [Variable.withString(userId), Variable.withString(dayIso), Variable.withString(type)],
    ).get();
    if (e.isNotEmpty) return e.first.data['id'] as String;

    final id = const Uuid().v4();
    await db.customStatement(
      'INSERT INTO Meal (id, userId, date, type) VALUES (?, ?, ?, ?);',
      [id, userId, dayIso, type],
    );
    return id;
  }

  Future<void> _recalcMealTotals(String mealId) async {
    final rows = await db.customSelect('''
      SELECT 
        COALESCE(SUM(kcal),0) AS kcal,
        COALESCE(SUM(protein),0) AS protein,
        COALESCE(SUM(carb),0) AS carb,
        COALESCE(SUM(fat),0) AS fat
      FROM MealItem WHERE mealId=?;
    ''', variables: [Variable.withString(mealId)]).get();

    final r = rows.first.data;
    await db.customStatement('''
      UPDATE Meal SET totalKcal=?, totalProtein=?, totalCarb=?, totalFat=?, updatedAt=datetime('now')
      WHERE id=?;
    ''', [r['kcal'] ?? 0, r['protein'] ?? 0.0, r['carb'] ?? 0.0, r['fat'] ?? 0.0, mealId]);
  }

  Future<void> _recalcDailyStats(String userId, String dayIso) async {
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
    ''', variables: [Variable.withString(userId), Variable.withString(dayIso)]).get();

    final r = rows.first.data;
    await db.customStatement('''
      INSERT INTO DailyStats (userId, date, kcal, protein, carb, fat, sugars, fiber, salt)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(userId, date) DO UPDATE SET
        kcal=excluded.kcal, protein=excluded.protein, carb=excluded.carb, fat=excluded.fat,
        sugars=excluded.sugars, fiber=excluded.fiber, salt=excluded.salt,
        updatedAt=datetime('now');
    ''', [
      userId,
      dayIso,
      r['kcal'] ?? 0,
      r['protein'] ?? 0.0,
      r['carb'] ?? 0.0,
      r['fat'] ?? 0.0,
      r['sugars'] ?? 0.0,
      r['fiber'] ?? 0.0,
      r['salt'] ?? 0.0,
    ]);
  }
}
