import '../domain/repos.dart';
import '../data/local/db.dart';
import '../data/local/bootstrap.dart';
import '../data/local/secure_store.dart';
import '../data/local/user_repo_sqlite.dart';
import '../data/local/products_repo_sqlite.dart';
import '../data/local/meals_repo_sqlite.dart';
import '../data/local/stats_repo_sqlite.dart';
import '../data/local/weight_repo_sqlite.dart';
import '../data/local/goals_repo_sqlite.dart';
import '../domain/repos.dart' show GoalsRepo;

final di = _DI();

class _DI {
  late final NutriDatabase db;
  late final SecureStore secure;

  late final UserRepo userRepo;
  late final ProductsRepo productsRepo;
  late final MealsRepo mealsRepo;
  late final StatsRepo statsRepo;
  late final WeightRepo weightRepo;
  late final GoalsRepo goalsRepo;

  Future<void> init() async {
    secure = SecureStore();

    db = NutriDatabase();
    await LocalBootstrap(db).ensureSchemaAndSeed();

    userRepo = UserRepoSqlite(db, secure);
    productsRepo = ProductsRepoSqlite(db);
    mealsRepo = MealsRepoSqlite(db);
    statsRepo = StatsRepoSqlite(db);
    weightRepo = WeightRepoSqlite(db);
    goalsRepo = GoalsRepoSqlite(db);
  }
}
