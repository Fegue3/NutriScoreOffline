class UserModel {
  final String id;
  final String email;
  final String? name;
  const UserModel({required this.id, required this.email, this.name});
}

class UserGoalsModel {
  final String userId;
  final String sex; // 'MALE' | 'FEMALE' | 'OTHER'
  final DateTime? dateOfBirth;
  final int heightCm;
  final double currentWeightKg;
  final double targetWeightKg;
  final DateTime? targetDate;
  final String activityLevel; // 'sedentary' | 'light' | 'moderate' | 'active' | 'very_active'

  final int? dailyCalories;
  final int? carbPercent;
  final int? proteinPercent;
  final int? fatPercent;

  const UserGoalsModel({
    required this.userId,
    required this.sex,
    required this.dateOfBirth,
    required this.heightCm,
    required this.currentWeightKg,
    required this.targetWeightKg,
    required this.targetDate,
    required this.activityLevel,
    this.dailyCalories,
    this.carbPercent,
    this.proteinPercent,
    this.fatPercent,
  });
}


class ProductModel {
  final String id;
  final String barcode;
  final String name;
  final int? energyKcal100g;
  final double? protein100g, carb100g, fat100g, sugars100g, fiber100g, salt100g;
  const ProductModel({
    required this.id,
    required this.barcode,
    required this.name,
    this.energyKcal100g,
    this.protein100g,
    this.carb100g,
    this.fat100g,
    this.sugars100g,
    this.fiber100g,
    this.salt100g,
  });
}

class MealWithItems {
  final String id;
  final String type; // BREAKFAST/LUNCH/DINNER/SNACK
  final String dateIso; // dia canónico
  final int totalKcal;
  final double protein, carb, fat;
  final List<MealItemModel> items;
  const MealWithItems({
    required this.id,
    required this.type,
    required this.dateIso,
    required this.totalKcal,
    required this.protein,
    required this.carb,
    required this.fat,
    required this.items,
  });
}

class MealItemModel {
  final String id;
  final String mealId;
  final String? productBarcode;
  final String? customFoodId;
  final String unit; // GRAM/ML/PIECE
  final double quantity;
  final double? gramsTotal;
  final int? kcal;
  final double? protein, carb, fat, sugars, fiber, salt;
  const MealItemModel({
    required this.id,
    required this.mealId,
    this.productBarcode,
    this.customFoodId,
    required this.unit,
    required this.quantity,
    this.gramsTotal,
    this.kcal,
    this.protein,
    this.carb,
    this.fat,
    this.sugars,
    this.fiber,
    this.salt,
  });
}

class DailyStatsModel {
  final String userId;
  final String dateIso;
  final int kcal;
  final double protein, carb, fat, sugars, fiber, salt;
  const DailyStatsModel({
    required this.userId,
    required this.dateIso,
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
    required this.sugars,
    required this.fiber,
    required this.salt,
  });
}

class WeightLogModel {
  final String dayIso; // YYYY-MM-DD
  final double kg;
  const WeightLogModel({required this.dayIso, required this.kg});
}

class AddMealItemInput {
  final String userId;
  final DateTime dayUtcCanon; // 00:00 UTC
  final String mealType; // 'BREAKFAST' | 'LUNCH' | 'DINNER' | 'SNACK'
  final String? productBarcode;
  final String? customFoodId;
  final String unit; // 'GRAM' | 'ML' | 'PIECE'
  final double quantity;
  const AddMealItemInput({
    required this.userId,
    required this.dayUtcCanon,
    required this.mealType,
    this.productBarcode,
    this.customFoodId,
    required this.unit,
    required this.quantity,
  });
}
