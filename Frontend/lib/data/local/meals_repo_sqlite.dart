import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models.dart';
import '../../domain/repos.dart';
import 'db.dart';
import 'utils/dates.dart';
import 'utils/food_calc.dart';

class MealsRepoSqlite implements MealsRepo {
  final NutriDatabase db;
  MealsRepoSqlite(this.db);

  @override
  Future<List<MealWithItems>> getMealsForDay(
    String userId,
    DateTime dayUtcCanon,
  ) async {
    final day = canonDayUtcIso(dayUtcCanon);

    // 1) buscar as meals do dia
    final meals = await db
        .customSelect(
          '''
    SELECT id, type, date,
           COALESCE(totalKcal,0)   AS totalKcal,
           COALESCE(totalProtein,0) AS totalProtein,
           COALESCE(totalCarb,0)    AS totalCarb,
           COALESCE(totalFat,0)     AS totalFat
    FROM Meal
    WHERE userId=? AND date=?
    ORDER BY type;
  ''',
          variables: [Variable.withString(userId), Variable.withString(day)],
        )
        .get();

    // 2) para cada meal, trazer items já com nome (product/custom) e marca
    final result = <MealWithItems>[];
    for (final m in meals) {
      final mid = m.data['id'] as String;

      final items = await db
          .customSelect(
            '''
      SELECT
        mi.id, mi.mealId, mi.productBarcode, mi.customFoodId,
        mi.unit, mi.quantity, mi.gramsTotal,
        mi.kcal, mi.protein, mi.carb, mi.fat, mi.sugars, mi.fiber, mi.salt,

        -- valores vindos das tabelas de origem
        p.name  AS productName,
        p.brand AS productBrand,
        cf.name AS customName,
        cf.brand AS customBrand
      FROM MealItem mi
      LEFT JOIN Product    p  ON p.barcode = mi.productBarcode
      LEFT JOIN CustomFood cf ON cf.id     = mi.customFoodId
      WHERE mi.mealId=?
      ORDER BY mi.position NULLS LAST, mi.id;
    ''',
            variables: [Variable.withString(mid)],
          )
          .get();

      final parsedItems = items.map((row) {
        final r = row.data;

        // Nome: preferir o do produto; se não houver, usar o do custom
        final String? resolvedName =
            (r['productName'] as String?) ?? (r['customName'] as String?);

        // Marca só existe para products (custom não tem)
        final String? resolvedBrand = r['productBrand'] as String?;

        return MealItemModel(
          id: r['id'] as String,
          mealId: r['mealId'] as String,
          productBarcode: r['productBarcode'] as String?,
          customFoodId: r['customFoodId'] as String?,
          name: resolvedName?.trim(),
          brand: resolvedBrand?.trim(),
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

      result.add(
        MealWithItems(
          id: mid,
          type: m.data['type'] as String,
          dateIso: m.data['date'] as String,
          totalKcal: (m.data['totalKcal'] as int?) ?? 0,
          protein: (m.data['totalProtein'] as num?)?.toDouble() ?? 0.0,
          carb: (m.data['totalCarb'] as num?)?.toDouble() ?? 0.0,
          fat: (m.data['totalFat'] as num?)?.toDouble() ?? 0.0,
          items: parsedItems,
        ),
      );
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
        final r = await db
            .customSelect(
              '''
          SELECT energyKcal_100g, proteins_100g, carbs_100g, fat_100g, sugars_100g, fiber_100g, salt_100g
          FROM Product WHERE barcode=? LIMIT 1;
        ''',
              variables: [Variable.withString(input.productBarcode!)],
            )
            .getSingleOrNull();

        if (r != null) {
          final d = r.data;
          nutr = Nutr100g(
            kcal: (d['energyKcal_100g'] as num?)?.toInt(),
            protein: (d['proteins_100g'] as num?)?.toDouble(),
            carb: (d['carbs_100g'] as num?)?.toDouble(),
            fat: (d['fat_100g'] as num?)?.toDouble(),
            sugars: (d['sugars_100g'] as num?)?.toDouble(),
            fiber: (d['fiber_100g'] as num?)?.toDouble(),
            salt: (d['salt_100g'] as num?)?.toDouble(),
          );
        }
      } else if (input.customFoodId != null) {
        final r = await db
            .customSelect(
              '''
          SELECT energyKcal_100g, proteins_100g, carbs_100g, fat_100g, sugars_100g, fiber_100g, salt_100g, gramsPerUnit
          FROM CustomFood WHERE id=? LIMIT 1;
        ''',
              variables: [Variable.withString(input.customFoodId!)],
            )
            .getSingleOrNull();
        if (r != null) {
          final d = r.data;
          gramsPerUnit = (d['gramsPerUnit'] as num?)?.toDouble();
          nutr = Nutr100g(
            kcal: (d['energyKcal_100g'] as num?)?.toInt(),
            protein: (d['proteins_100g'] as num?)?.toDouble(),
            carb: (d['carbs_100g'] as num?)?.toDouble(),
            fat: (d['fat_100g'] as num?)?.toDouble(),
            sugars: (d['sugars_100g'] as num?)?.toDouble(),
            fiber: (d['fiber_100g'] as num?)?.toDouble(),
            salt: (d['salt_100g'] as num?)?.toDouble(),
          );
        }
      }

      // 3) calcular totais pela quantidade
      final calc = calcPerQuantity(
        unit: input.unit,
        quantity: input.quantity,
        n: nutr,
        gramsPerUnit: gramsPerUnit,
      );

      // 4) inserir item
      final itemId = const Uuid().v4();
      await db.customStatement(
        '''
        INSERT INTO MealItem (id, mealId, productBarcode, customFoodId, unit, quantity, gramsTotal,
                              kcal, protein, carb, fat, sugars, fiber, salt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''',
        [
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
        ],
      );

      // 5) recalcular totals da meal + daily
      await _recalcMealTotals(mealId);
      await _recalcDailyStats(input.userId, day);
    });
  }

  @override
  Future<void> removeMealItem(String mealItemId) async {
    await db.transaction(() async {
      final info = await db
          .customSelect(
            '''
        SELECT MealItem.mealId AS mealId, Meal.userId AS userId, Meal.date AS day
        FROM MealItem JOIN Meal ON MealItem.mealId = Meal.id
        WHERE MealItem.id=? LIMIT 1;
      ''',
            variables: [Variable.withString(mealItemId)],
          )
          .getSingleOrNull();
      if (info == null) return;
      final r = info.data;
      final mealId = r['mealId'] as String;
      final userId = r['userId'] as String;
      final day = r['day'] as String;

      await db.customStatement('DELETE FROM MealItem WHERE id=?;', [
        mealItemId,
      ]);
      await _recalcMealTotals(mealId);
      await _recalcDailyStats(userId, day);
    });
  }

  Future<String> _ensureMeal(String userId, String dayIso, String type) async {
    final e = await db
        .customSelect(
          'SELECT id FROM Meal WHERE userId=? AND date=? AND type=? LIMIT 1;',
          variables: [
            Variable.withString(userId),
            Variable.withString(dayIso),
            Variable.withString(type),
          ],
        )
        .get();
    if (e.isNotEmpty) return e.first.data['id'] as String;

    final id = const Uuid().v4();
    await db.customStatement(
      'INSERT INTO Meal (id, userId, date, type) VALUES (?, ?, ?, ?);',
      [id, userId, dayIso, type],
    );
    return id;
  }

  @override
  Future<void> updateMealItemQuantity(
    String mealItemId, {
    required String unit,
    required double quantity,
  }) async {
    await db.transaction(() async {
      // 1) contexto do item (para recalcular e atualizar totals)
      final info = await db
          .customSelect(
            '''
      SELECT mi.mealId, mi.productBarcode, mi.customFoodId,
             m.userId, m.date AS dayIso
      FROM MealItem mi
      JOIN Meal m ON m.id = mi.mealId
      WHERE mi.id = ?
      LIMIT 1;
      ''',
            variables: [Variable.withString(mealItemId)],
          )
          .getSingleOrNull();

      if (info == null) return;
      final d = info.data;
      final mealId = d['mealId'] as String;
      final userId = d['userId'] as String;
      final dayIso = d['dayIso'] as String;
      final productBarcode = d['productBarcode'] as String?;
      final customFoodId = d['customFoodId'] as String?;

      // 2) nutrimentos base (100 g) da fonte
      Nutr100g nutr = const Nutr100g();
      double? gramsPerUnit;

      if (productBarcode != null) {
        final r = await db
            .customSelect(
              '''
        SELECT energyKcal_100g, proteins_100g, carbs_100g, fat_100g,
               sugars_100g, fiber_100g, salt_100g
        FROM Product WHERE barcode=? LIMIT 1;
        ''',
              variables: [Variable.withString(productBarcode)],
            )
            .getSingleOrNull();

        if (r != null) {
          final x = r.data;
          nutr = Nutr100g(
            kcal: (x['energyKcal_100g'] as num?)?.toInt(),
            protein: (x['proteins_100g'] as num?)?.toDouble(),
            carb: (x['carbs_100g'] as num?)?.toDouble(),
            fat: (x['fat_100g'] as num?)?.toDouble(),
            sugars: (x['sugars_100g'] as num?)?.toDouble(),
            fiber: (x['fiber_100g'] as num?)?.toDouble(),
            salt: (x['salt_100g'] as num?)?.toDouble(),
          );
        }
      } else if (customFoodId != null) {
        final r = await db
            .customSelect(
              '''
        SELECT energyKcal_100g, proteins_100g, carbs_100g, fat_100g,
               sugars_100g, fiber_100g, salt_100g, gramsPerUnit
        FROM CustomFood WHERE id=? LIMIT 1;
        ''',
              variables: [Variable.withString(customFoodId)],
            )
            .getSingleOrNull();

        if (r != null) {
          final x = r.data;
          gramsPerUnit = (x['gramsPerUnit'] as num?)?.toDouble();
          nutr = Nutr100g(
            kcal: (x['energyKcal_100g'] as num?)?.toInt(),
            protein: (x['proteins_100g'] as num?)?.toDouble(),
            carb: (x['carbs_100g'] as num?)?.toDouble(),
            fat: (x['fat_100g'] as num?)?.toDouble(),
            sugars: (x['sugars_100g'] as num?)?.toDouble(),
            fiber: (x['fiber_100g'] as num?)?.toDouble(),
            salt: (x['salt_100g'] as num?)?.toDouble(),
          );
        }
      }

      // 3) recalcular com a nova quantidade
      final calc = calcPerQuantity(
        unit: unit,
        quantity: quantity,
        n: nutr,
        gramsPerUnit: gramsPerUnit,
      );

      // 4) atualizar o item
      await db.customStatement(
        '''
      UPDATE MealItem
      SET unit=?, quantity=?, gramsTotal=?,
          kcal=?, protein=?, carb=?, fat=?, sugars=?, fiber=?, salt=? 
      WHERE id=?;
      ''',
        [
          unit,
          quantity,
          calc.gramsTotal,
          calc.kcal,
          calc.protein,
          calc.carb,
          calc.fat,
          calc.sugars,
          calc.fiber,
          calc.salt,
          mealItemId,
        ],
      );

      // 5) recalcular totais
      await _recalcMealTotals(mealId);
      await _recalcDailyStats(userId, dayIso);
    });
  }

  Future<void> _recalcMealTotals(String mealId) async {
    final rows = await db
        .customSelect(
          '''
      SELECT 
        COALESCE(SUM(kcal),0) AS kcal,
        COALESCE(SUM(protein),0) AS protein,
        COALESCE(SUM(carb),0) AS carb,
        COALESCE(SUM(fat),0) AS fat
      FROM MealItem WHERE mealId=?;
    ''',
          variables: [Variable.withString(mealId)],
        )
        .get();

    final r = rows.first.data;
    await db.customStatement(
      '''
      UPDATE Meal SET totalKcal=?, totalProtein=?, totalCarb=?, totalFat=?, updatedAt=datetime('now')
      WHERE id=?;
    ''',
      [
        r['kcal'] ?? 0,
        r['protein'] ?? 0.0,
        r['carb'] ?? 0.0,
        r['fat'] ?? 0.0,
        mealId,
      ],
    );
  }

  Future<void> _recalcDailyStats(String userId, String dayIso) async {
    final rows = await db
        .customSelect(
          '''
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
    ''',
          variables: [Variable.withString(userId), Variable.withString(dayIso)],
        )
        .get();

    final r = rows.first.data;
    await db.customStatement(
      '''
      INSERT INTO DailyStats (userId, date, kcal, protein, carb, fat, sugars, fiber, salt)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(userId, date) DO UPDATE SET
        kcal=excluded.kcal, protein=excluded.protein, carb=excluded.carb, fat=excluded.fat,
        sugars=excluded.sugars, fiber=excluded.fiber, salt=excluded.salt,
        updatedAt=datetime('now');
    ''',
      [
        userId,
        dayIso,
        r['kcal'] ?? 0,
        r['protein'] ?? 0.0,
        r['carb'] ?? 0.0,
        r['fat'] ?? 0.0,
        r['sugars'] ?? 0.0,
        r['fiber'] ?? 0.0,
        r['salt'] ?? 0.0,
      ],
    );
  }
}
