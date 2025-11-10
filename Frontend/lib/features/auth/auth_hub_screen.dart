import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/di.dart';

/// Ecrã “hub” de autenticação.
///
/// Responsabilidades:
/// - Verificar, no arranque, se existe sessão local via `di.userRepo.currentUser()`;
/// - Se **houver** sessão → encaminha diretamente para `/dashboard`;
/// - Se **não houver** sessão → apresenta CTA’s para **Criar conta** ou **Entrar**.
///
/// Notas de UX:
/// - Usa `SafeArea` + `SingleChildScrollView` para comportar-se bem em ecrãs pequenos;
/// - Botões primário (criar conta) e secundário (já tenho conta) com estilos contrastantes;
/// - Texto auxiliar sobre Termos & Privacidade no rodapé.
class AuthHubScreen extends StatefulWidget {
  const AuthHubScreen({super.key});

  @override
  State<AuthHubScreen> createState() => _AuthHubScreenState();
}

class _AuthHubScreenState extends State<AuthHubScreen> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  /// Decide o fluxo inicial:
  /// - se existir utilizador atual guardado (sessão) → `go('/dashboard')`;
  /// - caso contrário, permanece neste ecrã e mostra os botões.
  Future<void> _decide() async {
    final u = await di.userRepo.currentUser();
    if (!mounted) return;
    if (u == null) return; // mostra os botões (novo utilizador / já tenho conta)
    context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Marca / Ilustração
                  Image.asset('assets/utils/icon.png', width: 256, height: 256),
                  const SizedBox(height: 12),
                  Text(
                    'NutriScore',
                    style: tt.headlineSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Alimentação consciente e simples',
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: .70),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Cartão com ações de autenticação
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 10,
                          offset: Offset(0, 4),
                          color: Color(0x14000000),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // CTA principal: criar conta
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => context.go('/signup'),
                            icon: const Icon(Icons.person_add),
                            label: const Text('Sou um novo utilizador'),
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // CTA secundário: já tenho conta
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => context.go('/login'),
                            icon: const Icon(Icons.login),
                            label: const Text('Já tenho conta'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: cs.primary,
                              side: BorderSide(color: cs.primary, width: 2),
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Aviso legal / consentimento
                  Text(
                    'Ao continuar, aceita os Termos & Privacidade',
                    textAlign: TextAlign.center,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: .50),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
