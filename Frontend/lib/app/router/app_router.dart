/// NutriScore — Router da Aplicação
///
/// Define a árvore de navegação usando `go_router`, incluindo:
/// - Guarda global de autenticação e onboarding;
/// - Rotas públicas (auth) e privadas (dashboard, diário, definições);
/// - Passagem segura de parâmetros via `state.extra` para ecrãs como *Add Food*
///   e *Product Detail* com parsing robusto (tipos `MealType`, `DateTime` e numéricos).
///
/// ### Boas práticas adotadas
/// - **Redireções defensivas**: previnem acesso a rotas privadas sem sessão ou sem
///   onboarding concluído.
/// - **Compatibilidade de parâmetros**: aceita múltiplas chaves para o mesmo
///   semântico (ex.: `meal`, `initialMeal`, `selectedMealDb`, etc.), reduzindo assim
///   acoplamento entre módulos.
/// - **Conversões seguras**: funções auxiliares locais (`asInt`, `asDouble`) e
///   `DateTime.tryParse` para evitar falhas.
///
/// ### Exemplos de navegação
/// ```dart
/// // Enviar para Add Food com refeição e data:
/// context.goNamed('addFood', extra: {
///   'meal': MealType.lunch,
///   'dateYmd': '2025-11-10',
/// });
///
/// // Abrir Product Detail com dados pré-preenchidos:
/// context.goNamed('productDetail', extra: {
///   'barcode': '5601234567890',
///   'name': 'Iogurte Natural',
///   'brand': 'Marca X',
///   'baseQuantityLabel': '100 g',
///   'kcalPerBase': 60,
///   'proteinGPerBase': 5.1,
///   'carbsGPerBase': 3.4,
///   'fatGPerBase': 2.0,
///   'nutriScore': 'A',
///   'meal': 'LUNCH',
///   'dateYmd': '2025-11-10',
/// });
/// ```
///
/// > Nota: este router é a *fonte única de verdade* para caminhos de UI.
/// > Evita-se duplicação de *strings* de rotas noutros ficheiros.
///
/// Autor: Francisco Pereira · Atualizado: 2025-11-10
library;
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' show Variable;
import '../../app/di.dart' as di;

// AUTH
import '../../features/auth/auth_hub_screen.dart';
import '../../features/auth/sign_in_screen.dart';
import '../../features/auth/sign_up_screen.dart';
import '../../features/auth/onboarding_screen.dart';

// APP
import '../../features/home/home_screen.dart';
import '../../features/nutrition/nutrition_screen.dart';
import '../../features/nutrition/add_food_screen.dart';
import '../../features/nutrition/product_detail_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/edit_user_screen.dart';
import '../../features/nutrition/nutrition_stats_screen.dart';
import '../../features/weight/weight_progress_screen.dart' as wp;
import '../../features/scanner/scanner_screen.dart';
import '../app_shell.dart';
import '../../core/meal_type.dart';

/// Constrói e devolve o `GoRouter` principal do **NutriScore**.
///
/// Responsabilidades:
/// - Definir `initialLocation` e a *guarda global* (`redirect`) para sessão e onboarding;
/// - Declarar todas as rotas de nível de app, incluindo *shell* com *Bottom Nav*;
/// - Fornecer `name` para rotas chave (ex.: `'addFood'`, `'productDetail'`,
///   `'nutritionStats'`, `'weight'`) para navegação por nome.
///
/// Retorna:
/// - Instância configurada de [GoRouter] pronta a ser passada ao `MaterialApp.router`.
GoRouter buildAppRouter() {
  return GoRouter(
    /// **Rota inicial**:
    /// - '/' abre o *AuthHub* quando não existe sessão;
    /// - A guarda global pode redirecionar para `/onboarding` ou `/dashboard`.
    initialLocation: '/',

    // ==================== GUARDA GLOBAL ====================
    /// **Guarda Global (redirect)** — aplica regras de:
    /// 1) **Sessão**: impede acesso a rotas privadas sem utilizador local;
    /// 2) **Onboarding**: obriga a concluir onboarding antes de entrar no app shell;
    /// 3) **Rotas públicas**: se já logado e onboarding feito, evita voltar a '/', '/login', '/signup'.
    ///
    /// Fluxo:
    /// - Lê utilizador atual de `userRepo.currentUser()`;
    /// - Se não existir, permite apenas `{ '/', '/login', '/signup' }`;
    /// - Se existir, verifica a flag `onboardingCompleted` na tabela `User` (via `drift`);
    /// - Redireciona para `/onboarding` se incompleto, ou para `/dashboard` se tentar ir a rotas públicas.
    redirect: (context, state) async {
      final loc = state.matchedLocation;
      final public = {'/', '/login', '/signup'};

      final user = await di.di.userRepo.currentUser(); // sessão local
      if (user == null) {
        if (!public.contains(loc)) return '/';
        return null;
      }

      // onboarding completo?
      final rows = await di.di.db
          .customSelect(
            'SELECT onboardingCompleted FROM User WHERE id=? LIMIT 1;',
            variables: [Variable.withString(user.id)],
          )
          .get();

      final done =
          rows.isNotEmpty && (rows.first.data['onboardingCompleted'] == 1);

      if (!done && loc != '/onboarding') return '/onboarding';
      if (done && public.contains(loc)) return '/dashboard';

      return null;
    },

    // ==================== ROTAS ====================
    routes: [
      /// **/** — Hub de autenticação.
      ///
      /// Estado: *pública* (acessível sem sessão). Pode ser redirecionada pela guarda.
      GoRoute(path: '/', builder: (_, __) => const AuthHubScreen()),

      /// **/login** — Ecrã de autenticação (credenciais).
      ///
      /// Estado: *pública*.
      GoRoute(path: '/login', builder: (_, __) => const SignInScreen()),

      /// **/signup** — Ecrã de registo de conta.
      ///
      /// Estado: *pública*.
      GoRoute(path: '/signup', builder: (_, __) => const SignUpScreen()),

      /// **/onboarding** — Passos iniciais do utilizador.
      ///
      /// Redirecionada pela guarda até `onboardingCompleted == true`.
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),

      /// **/add-food** *(name: 'addFood')* — Ecrã para registar alimento/refeição.
      ///
      /// `state.extra` (Map opcional) — chaves aceites:
      /// - **Refeição** (`MealType` ou `String`):
      ///   - `'meal' | 'initialMeal' | 'initialMealDb' | 'initialMealTitle' | 'selectedMealDb' | 'selectedMealTitle' | 'mealTitle'`
      ///   - Strings aceitam `'BREAKFAST'|'LUNCH'|'SNACK'|'DINNER'` ou rótulos PT (via `MealTypeX.fromPt`).
      /// - **Data**:
      ///   - `'dateYmd'` ou `'selectedDateYmd'` no formato ISO (`yyyy-MM-dd`) para `DateTime.tryParse`.
      ///
      /// Exemplo:
      /// ```dart
      /// context.goNamed('addFood', extra: {
      ///   'meal': MealType.dinner,
      ///   'dateYmd': '2025-11-10',
      /// });
      /// ```
      GoRoute(
        path: '/add-food',
        name: 'addFood',
        builder: (_, state) {
          final extra = state.extra;

          MealType? meal;
          DateTime? selectedDate;

          if (extra is Map) {
            // aceita várias chaves possíveis
            final dynamic m =
                extra['meal'] ??
                extra['initialMeal'] ??
                extra['initialMealDb'] ??
                extra['initialMealTitle'] ??
                extra['selectedMealDb'] ??
                extra['selectedMealTitle'] ??
                extra['mealTitle'];

            if (m is MealType) {
              meal = m;
            } else if (m is String && m.trim().isNotEmpty) {
              final s = m.trim();
              // tenta pelos valores da DB primeiro…
              switch (s.toUpperCase()) {
                case 'BREAKFAST':
                  meal = MealType.breakfast;
                  break;
                case 'LUNCH':
                  meal = MealType.lunch;
                  break;
                case 'SNACK':
                  meal = MealType.snack;
                  break;
                case 'DINNER':
                  meal = MealType.dinner;
                  break;
                default:
                  // …senão tenta o rótulo PT ("Almoço", "Jantar", etc.)
                  meal = MealTypeX.fromPt(s);
              }
            }

            final ymd =
                (extra['dateYmd'] ?? extra['selectedDateYmd']) as String?;
            if (ymd != null && ymd.isNotEmpty) {
              selectedDate = DateTime.tryParse(ymd);
            }
          }

          return AddFoodScreen(initialMeal: meal, selectedDate: selectedDate);
        },
      ),

      /// **/scan** — Ecrã do leitor de código de barras/QR.
      ///
      /// Uso: iniciar pesquisa de produto (ex.: Open Food Facts) e pré-preencher detalhes.
      GoRoute(path: '/scan', builder: (_, __) => const ScannerScreen()),

      /// **/weight** *(name: 'weight')* — Progresso de peso.
      ///
      /// Mostra histórico e evolução (tendências).
      GoRoute(
        path: '/weight',
        name: 'weight',
        builder: (_, __) => const wp.WeightProgressScreen(),
      ),

      /// **/settings/user** — Edição de perfil do utilizador.
      ///
      /// Usa `NoTransitionPage` para transição instantânea.
      GoRoute(
        path: '/settings/user',
        pageBuilder: (_, __) => const NoTransitionPage(child: EditUserScreen()),
      ),

      // ---------- PRODUCT DETAIL ----------
      /// **/product-detail** *(name: 'productDetail')* — Detalhe de produto alimentar.
      ///
      /// Aceita um `Map` em `state.extra` com:
      /// - **Identificação**: `barcode`, `name`, `brand`, `origin`
      /// - **Base**: `baseQuantityLabel` (ex.: `'100 g'`)
      /// - **Nutrição por base** (int/double ou string numérica):
      ///   `kcalPerBase`, `proteinGPerBase`, `carbsGPerBase`, `fatGPerBase`,
      ///   `saltGPerBase`, `sugarsGPerBase`, `satFatGPerBase`, `fiberGPerBase`,
      ///   `sodiumGPerBase`
      /// - **NutriScore**: `nutriScore` (string `'A'..'E'`)
      /// - **Contexto de adição**:
      ///   - Refeição: `meal` (enum) ou strings `'BREAKFAST'|'LUNCH'|'SNACK'|'DINNER'`
      ///     ou rótulo PT (via `MealTypeX.fromPt`)
      ///   - Data: `dateYmd`/`selectedDateYmd` (ISO) **ou** `date`/`selectedDate` (`DateTime`/`String`)
      /// - **Flags**:
      ///   - `readOnly`: `true` para modo somente leitura
      ///   - `freezeFromEntry`: `true` para fixar valores vindos de registo
      /// - **Outros**:
      ///   - `initialGrams`: quantidade inicial em gramas
      ///   - `existingMealItemId`: id de item já registado (edição)
      ///
      /// Conversões robustas:
      /// - `asInt`/`asDouble` aceitam `int`, `double`, `num` ou `String` numérica.
      GoRoute(
        name: 'productDetail',
        path: '/product-detail',
        builder: (_, state) {
          final m = (state.extra as Map?) ?? const {};

          int? asInt(Object? v) {
            if (v is int) return v;
            if (v is num) return v.toInt();
            if (v is String) return int.tryParse(v);
            return null;
          }

          double? asDouble(Object? v) {
            if (v is double) return v;
            if (v is num) return v.toDouble();
            if (v is String) return double.tryParse(v);
            return null;
          }

          // ---- MEAL (enum direto, string DB ou label PT) ----
          MealType? meal;
          final dynMeal =
              m['meal'] ??
              m['initialMeal'] ??
              m['selectedMealDb'] ??
              m['initialMealDb'] ??
              m['selectedMealTitle'] ??
              m['initialMealTitle'];
          if (dynMeal is MealType) {
            meal = dynMeal;
          } else if (dynMeal is String && dynMeal.trim().isNotEmpty) {
            final s = dynMeal.trim();
            switch (s.toUpperCase()) {
              case 'BREAKFAST':
                meal = MealType.breakfast;
                break;
              case 'LUNCH':
                meal = MealType.lunch;
                break;
              case 'SNACK':
                meal = MealType.snack;
                break;
              case 'DINNER':
                meal = MealType.dinner;
                break;
              default:
                meal = MealTypeX.fromPt(s);
            }
          }

          // ---- DATE: aceita dateYmd OU DateTime direto ('date' / 'selectedDate') ----
          DateTime? date;
          final ymd = (m['dateYmd'] ?? m['selectedDateYmd']) as String?;
          if (ymd != null && ymd.isNotEmpty) {
            date = DateTime.tryParse(ymd);
          }
          if (date == null) {
            final dynDate = m['date'] ?? m['selectedDate'];
            if (dynDate is DateTime) {
              date = dynDate;
            } else if (dynDate is String) {
              date = DateTime.tryParse(dynDate);
            }
          }

          return ProductDetailScreen(
            barcode: m['barcode']?.toString(),
            name: m['name']?.toString(),
            brand: m['brand']?.toString(),
            origin: m['origin']?.toString(),
            baseQuantityLabel: m['baseQuantityLabel']?.toString(),
            kcalPerBase: asInt(m['kcalPerBase']),
            proteinGPerBase: asDouble(m['proteinGPerBase']),
            carbsGPerBase: asDouble(m['carbsGPerBase']),
            fatGPerBase: asDouble(m['fatGPerBase']),
            saltGPerBase: asDouble(m['saltGPerBase']),
            sugarsGPerBase: asDouble(m['sugarsGPerBase']),
            satFatGPerBase: asDouble(m['satFatGPerBase']),
            fiberGPerBase: asDouble(m['fiberGPerBase']),
            sodiumGPerBase: asDouble(m['sodiumGPerBase']),
            nutriScore: m['nutriScore']?.toString(),
            initialMeal: meal,
            date: date,
            readOnly: m['readOnly'] == true,
            freezeFromEntry: m['freezeFromEntry'] == true,

            initialGrams: (m['initialGrams'] as num?)?.toDouble(),
            existingMealItemId: m['existingMealItemId'] as String?,
          );
        },
      ),

      /// **/nutrition/stats** *(name: 'nutritionStats')* — Estatísticas agregadas de nutrição.
      ///
      /// Exibe métricas e tendências (ex.: semana/mês).
      GoRoute(
        path: '/nutrition/stats',
        name: 'nutritionStats',
        builder: (_, __) => const NutritionStatsScreen(),
      ),

      // ---------- SHELL PRINCIPAL ----------
      /// **Shell principal (AppShell)** — engloba rotas com navegação inferior.
      ///
      /// Filhos:
      /// - `/dashboard` — Home;
      /// - `/diary` — Diário alimentar;
      /// - `/settings` — Definições.
      ///
      /// Usa `NoTransitionPage` para UX fluida entre tabs.
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          /// **/dashboard** — Ecrã inicial (Home).
          GoRoute(
            path: '/dashboard',
            pageBuilder: (_, __) => const NoTransitionPage(child: HomeScreen()),
          ),

          /// **/diary** — Diário alimentar (lista de entradas por dia).
          GoRoute(
            path: '/diary',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: NutritionScreen()),
          ),

          /// **/settings** — Definições gerais da aplicação.
          GoRoute(
            path: '/settings',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
    ],
  );
}
