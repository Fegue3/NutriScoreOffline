// lib/app/di.dart
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
import '../data/local/favorites_repo_sqlite.dart';
import '../data/local/history_repo_sqlite.dart';

// === ONLINE ===
import 'package:http/http.dart' as http;
import '../data/online/config.dart';
import '../data/online/net_throttle.dart';
import '../data/online/off_client.dart';
import '../data/online/products_remote_datasource.dart';
import '../data/online/products_repo_hybrid.dart';
import '../data/online/sync_queue.dart';

final di = _DI();

class _DI {
  late final NutriDatabase db;
  late final SecureStore secure;

  late final UserRepo userRepo;
  late ProductsRepo productsRepo; // nota: não final para conseguirmos trocar
  late final MealsRepo mealsRepo;
  late final StatsRepo statsRepo;
  late final WeightRepo weightRepo;
  late final GoalsRepo goalsRepo;

  // NOVOS
  late final FavoritesRepo favoritesRepo;
  late final HistoryRepo historyRepo;

  // === ONLINE infra (opcional) ===
  late final http.Client _httpClient;
  late final NetThrottle _throttle;
  late final OffClient _offClient;
  late final ProductsRemoteDataSource _remoteDs;
  late final SyncQueue _queue;

  // Toggle central (podes ler de SharedPrefs/RemoteConfig no futuro)
  // true -> usa repositório híbrido (offline-first + online); false -> só SQLite
  bool enableOnline = true;

  Future<void> init() async {
    secure = SecureStore();

    db = NutriDatabase();
    await LocalBootstrap(db).ensureSchemaAndSeed();

    // novos repos primeiro (para injeção)
    historyRepo = HistoryRepoSqlite(db);
    favoritesRepo = FavoritesRepoSqlite(db);

    userRepo = UserRepoSqlite(db, secure);

    // === camada online (opcional) ===
    _httpClient = http.Client();
    _throttle = NetThrottle(
      searchBucket: TokenBucket(
        capacity: kRateSearchPerMinute,
        refillEvery: const Duration(minutes: 1),
      ),
      productBucket: TokenBucket(
        capacity: kRateProductPerMinute,
        refillEvery: const Duration(minutes: 1),
      ),
      maxConcurrent: kMaxConcurrentRequests,
    );
    _offClient = OffClient(_httpClient); // usa kOffBaseUrl + kUserAgent
    _remoteDs = ProductsRemoteDataSource(client: _offClient, throttle: _throttle);
    _queue = SyncQueue(concurrency: kMaxConcurrentRequests);

    // === Escolha do repo de produtos ===
    if (enableOnline) {
      // HÍBRIDO: lê local, atualiza a cache com OFF quando possível
      productsRepo = ProductsRepoHybrid(db: db, remote: _remoteDs, queue: _queue);
    } else {
      // SÓ OFFLINE: mantém exatamente o teu repositório atual
      productsRepo = ProductsRepoSqlite(db);
    }

    mealsRepo = MealsRepoSqlite(db);
    statsRepo = StatsRepoSqlite(db);
    weightRepo = WeightRepoSqlite(db);
    goalsRepo = GoalsRepoSqlite(db);
  }

  // Se quiseres alternar em runtime (ex.: “Modo offline” num toggle de settings):
  Future<void> setOnlineEnabled(bool value) async {
    enableOnline = value;
    if (enableOnline) {
      productsRepo = ProductsRepoHybrid(db: db, remote: _remoteDs, queue: _queue);
    } else {
      productsRepo = ProductsRepoSqlite(db);
    }
    // Não é preciso mexer nas screens, elas continuam a pedir ao di.productsRepo
  }
}
