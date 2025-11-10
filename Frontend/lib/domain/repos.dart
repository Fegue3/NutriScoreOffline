import 'models.dart';

/// Contratos (interfaces) da **camada de domínio**.
///
/// Objetivo:
/// - Definir as capacidades que a aplicação precisa (sem detalhes de implementação);
/// - Permitir múltiplas implementações (ex.: SQLite vs. híbrido com OFF);
/// - Facilitar *testing* através de *mocks/fakes*.
///
/// Convenções:
/// - Todos os métodos são assíncronos (`Future<...>`);
/// - Comentários documentam parâmetros, formatos (ex.: ISO 8601) e semântica.
/// - Não há dependências de UI ou camadas inferiores aqui (apenas `models.dart`).

// ========================= AUTENTICAÇÃO / UTILIZADOR =========================

/// Operações de sessão e gestão de conta do utilizador.
abstract class UserRepo {
  /// Inicia sessão com [email] e [password].
  ///
  /// Retorna:
  /// - `UserModel` quando as credenciais são válidas;
  /// - `null` se as credenciais estiverem incorretas.
  Future<UserModel?> signIn(String email, String password);

  /// Cria uma conta e devolve o **ID do utilizador**.
  ///
  /// Parâmetros:
  /// - [email] será normalizado (lowercase);
  /// - [password] é armazenada de forma segura na implementação;
  /// - [name] opcional.
  Future<String> signUp(String email, String password, {String? name});

  /// Devolve o utilizador atual (se houver sessão persistida), caso contrário `null`.
  Future<UserModel?> currentUser();

  /// Termina a sessão local (não apaga a conta).
  Future<void> signOut();

  /// Apaga definitivamente a conta local e limpa segredos/sessão associados.
  Future<void> deleteAccount();
}

// =============================== PRODUTOS ====================================

/// Produtos alimentares (catálogo local e/ou origem remota).
abstract class ProductsRepo {
  /// Obtém um produto pelo **código de barras** [barcode].
  ///
  /// Implementações **híbridas** podem:
  /// 1) tentar local primeiro;
  /// 2) se não existir, ir à rede e **cachear**.
  Future<ProductModel?> getByBarcode(String barcode);

  /// Pesquisa por nome/marca/barcode.
  ///
  /// Parâmetros:
  /// - [q] texto de pesquisa;
  /// - [limit] número máximo de resultados (default 50).
  ///
  /// Implementações locais podem aplicar *ranking* (exato > prefixo > palavra > contém).
  Future<List<ProductModel>> searchByName(String q, {int limit = 50});

  /// UPSERT explícito de um [ProductModel] (atualiza por `barcode`).
  Future<void> upsert(ProductModel p);
}

// ================================ REFEIÇÕES =================================

/// Gestão de refeições e respetivos itens.
abstract class MealsRepo {
  /// Devolve as refeições do **dia canónico UTC** [dayUtcCanon] para o [userId],
  /// já com itens e totais agregados.
  Future<List<MealWithItems>> getMealsForDay(String userId, DateTime dayUtcCanon);

  /// Adiciona **ou** atualiza um item de refeição conforme [AddMealItemInput].
  ///
  /// Notas:
  /// - Garante a existência da refeição do dia/tipo;
  /// - Recalcula totais da refeição e das estatísticas diárias.
  Future<void> addOrUpdateMealItem(AddMealItemInput input);

  /// Remove um item de refeição por [mealItemId] e atualiza totais (meal + dia).
  Future<void> removeMealItem(String mealItemId);

  /// Atualiza a **quantidade** (e respetivos totais derivados) de um item.
  ///
  /// Parâmetros:
  /// - [unit] `'GRAM' | 'ML' | 'PIECE'`;
  /// - [quantity] valor na unidade indicada.
  Future<void> updateMealItemQuantity(
    String mealItemId, {
    required String unit,     // 'GRAM' | 'ML' | 'PIECE'
    required double quantity, // ex.: 120.0 (g)
  });
}

// ============================== ESTATÍSTICAS ================================

/// Estatísticas agregadas por dia.
abstract class StatsRepo {
  /// Calcula e **guarda em cache** as estatísticas do dia [dayUtcCanon] para [userId].
  Future<DailyStatsModel> computeDaily(String userId, DateTime dayUtcCanon);

  /// Lê a versão **em cache** (se existir) das estatísticas do dia.
  Future<DailyStatsModel?> getCached(String userId, DateTime dayUtcCanon);

  /// Escreve/atualiza a versão em cache de [DailyStatsModel].
  Future<void> putCached(DailyStatsModel stats);
}

// ================================ PESO ======================================

/// Registos de peso do utilizador.
abstract class WeightRepo {
  /// Adiciona um registo de peso para o [day] (data; formato local), em quilogramas [kg].
  ///
  /// [note] é opcional.
  Future<void> addLog(String userId, DateTime day, double kg, {String? note});

  /// Devolve a série de registos no intervalo `[fromDay, toDay]` (inclusive).
  ///
  /// Implementações podem devolver **todos os registos** por dia ou aplicar
  /// políticas (ex.: último do dia) conforme a camada de apresentação.
  Future<List<WeightLogModel>> getRange(String userId, DateTime fromDay, DateTime toDay);
}

// ================================ METAS =====================================

/// Metas/objetivos do utilizador (perfil nutricional).
abstract class GoalsRepo {
  /// Cria/atualiza (UPSERT) as metas do utilizador.
  ///
  /// Implementações podem calcular valores omissos (ex.: calorias diárias).
  Future<void> upsert(UserGoalsModel model);

  /// Obtém as metas guardadas para o [userId], ou `null` se não existirem.
  Future<UserGoalsModel?> getByUser(String userId);
}

/// ===== NOVOS REPOS =====

// =============================== HISTÓRICO ==================================

/// Histórico de produtos consultados/scaneados.
abstract class HistoryRepo {
  /// Adiciona ao histórico **se** o último registo não for do mesmo barcode
  /// (evita duplicados imediatos).
  Future<void> addIfNotDuplicate(String userId, HistorySnapshot s);

  /// Lista entradas do histórico, com **paginação** e filtro por intervalo opcional.
  ///
  /// Parâmetros:
  /// - [page] página (1-based), default 1;
  /// - [pageSize] itens por página, default 20;
  /// - [fromIso], [toIso] limites ISO 8601 (opcionais).
  Future<List<HistoryEntry>> list(String userId, {int page = 1, int pageSize = 20, String? fromIso, String? toIso});
}

// =============================== FAVORITOS ==================================

/// Favoritos do utilizador.
abstract class FavoritesRepo {
  /// Verifica se o [barcode] está favoritado pelo [userId].
  Future<bool> isFavorited(String userId, String barcode);

  /// Adiciona um favorito.
  Future<void> add(String userId, String barcode);

  /// Remove um favorito.
  Future<void> remove(String userId, String barcode);

  /// Alterna estado de favorito (devolve `true` se ficou favoritado).
  Future<bool> toggle(String userId, String barcode);

  /// Lista favoritos com **paginação** e pesquisa opcional [q] (por nome/marca/barcode).
  Future<List<ProductModel>> list(String userId, {int page = 1, int pageSize = 20, String? q});
}
