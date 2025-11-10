import 'package:flutter/material.dart';
import 'app/di.dart';
import 'app/router/app_router.dart';
import 'core/theme.dart';

/// Ponto de entrada da aplicação NutriScore.
///
/// Passos no arranque:
/// 1) Garante que o Flutter está inicializado (`WidgetsFlutterBinding.ensureInitialized`);
/// 2) Inicializa o contentor de dependências `di.init()` (BD local, repositórios, etc.);
/// 3) Arranca a app com o `runApp`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await di.init();
  runApp(const NutriScoreApp());
}

/// *Root widget* da app NutriScore.
///
/// Responsabilidades:
/// - Construir o `GoRouter` através de `buildAppRouter()` (inclui *guards* de sessão/onboarding);
/// - Fornecer o `ThemeData` central (`NutriTheme.light`);
/// - Usar `MaterialApp.router` com `routerConfig` para navegação declarativa.
class NutriScoreApp extends StatelessWidget {
  const NutriScoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = buildAppRouter(); // se o router usa auth
    return MaterialApp.router(
      title: 'NutriScore',
      debugShowCheckedModeBanner: false,

      // Tema global (cores, tipografia e componentes), ver core/theme.dart
      theme: NutriTheme.light,

      // Configuração do GoRouter (rotas + redireções)
      routerConfig: router,
    );
  }
}
