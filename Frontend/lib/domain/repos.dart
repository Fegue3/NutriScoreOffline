import 'models.dart';

abstract class UserRepo {
  Future<UserModel?> signIn(String email, String password);
  Future<String> signUp(String email, String password, {String? name});
  Future<UserModel?> currentUser();
  Future<void> signOut();
  Future<void> deleteAccount();
}

abstract class ProductsRepo {
  Future<ProductModel?> getByBarcode(String barcode);
  Future<List<ProductModel>> searchByName(String q, {int limit = 50});
  Future<void> upsert(ProductModel p);
}

abstract class MealsRepo {
  Future<List<MealWithItems>> getMealsForDay(String userId, DateTime dayUtcCanon);
  Future<void> addOrUpdateMealItem(AddMealItemInput input);
  Future<void> removeMealItem(String mealItemId);
  Future<void> updateMealItemQuantity(
    String mealItemId, {
    required String unit,     // 'GRAM' | 'ML' | 'PIECE'
    required double quantity, // ex.: 120.0 (g)
  });
}

abstract class StatsRepo {
  Future<DailyStatsModel> computeDaily(String userId, DateTime dayUtcCanon);
  Future<DailyStatsModel?> getCached(String userId, DateTime dayUtcCanon);
  Future<void> putCached(DailyStatsModel stats);
}

abstract class WeightRepo {
  Future<void> addLog(String userId, DateTime day, double kg, {String? note});
  Future<List<WeightLogModel>> getRange(String userId, DateTime fromDay, DateTime toDay);
}

abstract class GoalsRepo {
  Future<void> upsert(UserGoalsModel model);
  Future<UserGoalsModel?> getByUser(String userId);
}

/// ===== NOVOS REPOS =====

abstract class HistoryRepo {
  Future<void> addIfNotDuplicate(String userId, HistorySnapshot s);
  Future<List<HistoryEntry>> list(String userId, {int page = 1, int pageSize = 20, String? fromIso, String? toIso});
}

abstract class FavoritesRepo {
  Future<bool> isFavorited(String userId, String barcode);
  Future<void> add(String userId, String barcode);
  Future<void> remove(String userId, String barcode);
  Future<bool> toggle(String userId, String barcode);
  Future<List<ProductModel>> list(String userId, {int page = 1, int pageSize = 20, String? q});
}
