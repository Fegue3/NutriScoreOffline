/// NutriScore — App Shell (estrutura com Bottom Navigation)
///
/// Envolve as páginas principais da aplicação com:
/// - `Scaffold` e `SafeArea` para respeitar *notches* e barras do sistema;
/// - Barra de navegação inferior (`AppBottomNav`) com 3 tabs:
///   - **Dashboard** (`/dashboard`)
///   - **Diário** (`/diary`)
///   - **Definições** (`/settings`)
///
/// O *tab* ativo é inferido a partir da `location` atual do `GoRouter`.
///
/// Autor: Francisco Pereira · Atualizado: 2025-11-10
library;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/widgets/app_bottom_nav.dart';

/// *Shell* da aplicação que fornece *Bottom Navigation* para as rotas principais.
///
/// Recebe um [child] que é a página ativa conforme a rota atual. O índice do
/// separador selecionado é calculado por `_indexForLocation`, garantindo
/// consistência entre a *URL* e o estado visual da barra de navegação.
///
/// Este *shell* é normalmente utilizado como `ShellRoute` no `app_router.dart`.
class AppShell extends StatelessWidget {
  /// Cria o *AppShell* com o conteúdo [child] a ser apresentado no corpo.
  const AppShell({super.key, required this.child});

  /// Conteúdo atual apresentado no corpo do `Scaffold`.
  final Widget child;

  /// Converte uma localização (path) no índice do separador da *Bottom Nav*.
  ///
  /// Regras:
  /// - `'/dashboard'` → índice **0**
  /// - `'/diary'` → índice **1**
  /// - Qualquer outro path (ex.: `'/settings'`) → índice **2**
  ///
  /// Isto permite que subrotas (ex.: `/dashboard/…`) continuem a ativar o
  /// separador correto através de `startsWith`.
  int _indexForLocation(String l) {
    if (l.startsWith('/dashboard')) return 0;
    if (l.startsWith('/diary')) return 1;
    return 2; // settings
  }

  /// Constrói a estrutura visual com `Scaffold`, `SafeArea` e `AppBottomNav`.
  ///
  /// O `currentIndex` é derivado da `GoRouterState.of(context).uri.path`.
  /// O `onChanged` navega através de `context.go` para as três rotas principais.
  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexForLocation(location);

    return Scaffold(
      body: SafeArea(
        // Mantemos bottom true para evitar sobreposição com a BottomNavigationBar.
        top: false,
        bottom: true,
        child: child,
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: currentIndex,
        onChanged: (i) {
          switch (i) {
            case 0:
              context.go('/dashboard');
              break;
            case 1:
              context.go('/diary');
              break;
            case 2:
              context.go('/settings');
              break;
          }
        },
      ),
    );
  }
}
