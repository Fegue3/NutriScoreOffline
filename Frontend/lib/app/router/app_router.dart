// lib/app/router/app_router.dart
import 'package:flutter/foundation.dart';
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

GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: '/',

    // 👇 NOVO: guard global
    redirect: (context, state) async {
      final loc = state.matchedLocation;
      final public = {'/', '/login', '/signup'};

      final user = await di.di.userRepo.currentUser(); // sessão local (SecureStore)
      if (user == null) {
        // bloqueia páginas do app sem sessão
        if (!public.contains(loc)) return '/';
        return null;
      }

      // sessão existe → ver se já completou onboarding
      final rows = await di.di.db
          .customSelect(
            'SELECT onboardingCompleted FROM User WHERE id=? LIMIT 1;',
            variables: [Variable.withString(user.id)],
          )
          .get();

      final done = rows.isNotEmpty && (rows.first.data['onboardingCompleted'] == 1);

      // se não fez onboarding, força o fluxo
      if (!done && loc != '/onboarding') return '/onboarding';

      // se já fez, evita páginas públicas
      if (done && public.contains(loc)) return '/dashboard';

      return null; // segue normal
    },

    routes: [
      GoRoute(path: '/', builder: (_, __) => const AuthHubScreen()),
      GoRoute(path: '/login', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignUpScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),

      GoRoute(path: '/add-food', builder: (_, __) => const AddFoodScreen()),
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
            readOnly: m['readOnly'] == true,
            freezeFromEntry: m['freezeFromEntry'] == true,
          );
        },
      ),

      GoRoute(
        path: '/nutrition/stats',
        name: 'nutritionStats',
        builder: (_, __) => const NutritionStatsScreen(),
      ),

      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (_, __) => const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/diary',
            pageBuilder: (_, __) => const NoTransitionPage(child: NutritionScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, __) => const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
    ],
  );
}
