// lib/app/router/app_router.dart
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

GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: '/',

    // ==================== GUARDA GLOBAL ====================
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
      GoRoute(path: '/', builder: (_, __) => const AuthHubScreen()),
      GoRoute(path: '/login', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignUpScreen()),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),

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

      GoRoute(path: '/scan', builder: (_, __) => const ScannerScreen()),

      GoRoute(
        path: '/weight',
        name: 'weight',
        builder: (_, __) => const wp.WeightProgressScreen(),
      ),

      GoRoute(
        path: '/settings/user',
        pageBuilder: (_, __) => const NoTransitionPage(child: EditUserScreen()),
      ),

      // ---------- PRODUCT DETAIL ----------
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

      GoRoute(
        path: '/nutrition/stats',
        name: 'nutritionStats',
        builder: (_, __) => const NutritionStatsScreen(),
      ),

      // ---------- SHELL PRINCIPAL ----------
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (_, __) => const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/diary',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: NutritionScreen()),
          ),
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
