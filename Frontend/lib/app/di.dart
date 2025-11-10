/// NutriScore — DI (Injeção de Dependências / Service Locator)
///
/// Ponto central de criação e disponibilização de serviços/repositórios
/// da aplicação. Expõe uma instância global [`di`] com componentes
/// **offline-first** (SQLite) e, opcionalmente, integra fontes **online**.
///
/// ### Responsabilidades
/// - Criar e inicializar:
///   - Base de dados local [`NutriDatabase`] e *seed* inicial;
///   - Camada de segurança [`SecureStore`];
///   - Repositórios locais: utilizadores, produtos, refeições, estatísticas,
///     peso, objetivos, favoritos e histórico;
///   - Infraestrutura online (quando ativa): cliente HTTP, *throttle*,
///     cliente OFF (Open Food Facts), *remote datasource* e *sync queue*;
/// - Fornecer **toggle** de modo online (`enableOnline`) e *switch* dinâmico
///   entre repositório **híbrido** (`ProductsRepoHybrid`) e **só local**
///   (`ProductsRepoSqlite`).
///
/// ### Fluxo típico de uso
/// ```dart
/// // No arranque da app (ex.: main()):
/// await di.init();
///
/// // Em qualquer ponto da app:
/// final meals = await di.mealsRepo.getForDay(DateTime.now());
///
/// // Alternar modo online em runtime (ex.: definições):
/// await di.setOnlineEnabled(false); // passa a usar só SQLite
/// ```
///
/// > Nota: Mantém as screens desacopladas: tudo consome `di.algoRepo` sem
/// > conhecer pormenores de construção/ambiente.
///
/// Autor: Francisco Pereira · Atualizado: 2025-11-10
library;
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

/// Instância global do *service locator* do **NutriScore**.
///
/// Utiliza a classe interna [_DI] para agrupar dependências.
final di = _DI();

/// Registrador/injetor de dependências da app.
///
/// Fornece inicialização assíncrona via [init] e permite alternar o modo
/// **online** em runtime com [setOnlineEnabled]. Os campos *late* são
/// resolvidos durante o [init].
class _DI {
  /// Base de dados local (SQLite via Drift).
  late final NutriDatabase db;

  /// Armazenamento seguro (tokens/segredos).
  late final SecureStore secure;

  /// Repositório de utilizadores (sessão/local).
  late final UserRepo userRepo;

  /// Repositório de produtos.
  ///
  /// **Não `final`** para permitir *hot-swap* entre implementação
  /// **híbrida** (online+cache) e **só local**.
  late ProductsRepo productsRepo;

  /// Repositório de refeições.
  late final MealsRepo mealsRepo;

  /// Repositório de estatísticas.
  late final StatsRepo statsRepo;

  /// Repositório de peso.
  late final WeightRepo weightRepo;

  /// Repositório de objetivos (ex.: meta calórica).
  late final GoalsRepo goalsRepo;

  // NOVOS

  /// Repositório de favoritos.
  late final FavoritesRepo favoritesRepo;

  /// Repositório de histórico de pesquisas/produtos.
  late final HistoryRepo historyRepo;

  // === ONLINE infra (opcional) ===

  /// Cliente HTTP base.
  late final http.Client _httpClient;

  /// Limitador de taxa e concorrência para chamadas de rede.
  late final NetThrottle _throttle;

  /// Cliente para Open Food Facts (usa `kOffBaseUrl` + `kUserAgent`).
  late final OffClient _offClient;

  /// Fonte de dados remota para produtos (OFF).
  late final ProductsRemoteDataSource _remoteDs;

  /// Fila de sincronização/execução concorrente para *fetches*.
  late final SyncQueue _queue;

  /// **Toggle central de modo online**.
  ///
  /// - `true` → usa repositório **híbrido** (offline-first com atualização online);
  /// - `false` → usa **só SQLite** (100% offline).
  ///
  /// Pode futuramente ser lido de `SharedPreferences`/RemoteConfig.
  bool enableOnline = true;

  /// Inicializa a infraestrutura local e (opcionalmente) online.
  ///
  /// Passos:
  /// 1. Cria `SecureStore`;
  /// 2. Instancia `NutriDatabase` e garante *schema/seed* via [LocalBootstrap];
  /// 3. Constrói repositórios locais (incluindo `favoritesRepo` e `historyRepo`);
  /// 4. Prepara camada **online**: `http.Client`, `NetThrottle`, `OffClient`,
  ///    `ProductsRemoteDataSource` e `SyncQueue`;
  /// 5. Decide a implementação de [productsRepo] consoante [enableOnline].
  ///
  /// Lança:
  /// - Propaga exceções de I/O/DB se ocorrerem durante *bootstrap*.
  Future<void> init() async {
    secure = SecureStore();

    db = NutriDatabase();
    await LocalBootstrap(db).ensureSchemaAndSeed();
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

  /// Alterna o modo online em tempo de execução e troca o [productsRepo].
  ///
  /// Parâmetros:
  /// - [value] `true` ativa o repositório híbrido; `false` fixa em SQLite.
  ///
  /// Notas:
  /// - As *screens* não precisam de mudar: continuam a usar `di.productsRepo`;
  /// - Operação síncrona do ponto de vista de troca de instância; qualquer
  ///   *fetch* em curso deverá ser robusto à troca (por design do repositório).
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
