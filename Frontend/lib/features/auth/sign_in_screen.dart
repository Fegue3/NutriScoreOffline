// lib/features/auth/sign_in_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/di.dart';

/// Ecrã de **autenticação – Entrar**.
///
/// Responsabilidades:
/// - Apresentar um formulário simples com *email* e *palavra-passe*;
/// - Validar campos localmente (form `FormState`);
/// - Invocar `di.userRepo.signIn(...)`;
/// - Exibir feedback de erro via `SnackBar`;
/// - Redirecionar para `/dashboard` em caso de sucesso.
///
/// Acessibilidade / UX:
/// - Campos com `labelText` e `hintText`;
/// - Botão para mostrar/ocultar a palavra-passe;
/// - Estado de carregamento (desativa o botão e mostra *spinner*).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  /// *Key* do formulário para validações/saves.
  final _formKey = GlobalKey<FormState>();

  /// Controlador do campo de email.
  final _email = TextEditingController();

  /// Controlador do campo de palavra-passe.
  final _password = TextEditingController();

  /// Indica se está a decorrer o *submit* (bloqueia UI).
  bool _loading = false;

  /// Controla a visibilidade da palavra-passe.
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Submete o formulário:
  /// 1) Valida os campos;
  /// 2) Chama `userRepo.signIn`;
  /// 3) Mostra `SnackBar` em caso de erro;
  /// 4) Faz `go('/dashboard')` no sucesso.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    String? error;
    try {
      final u = await di.userRepo.signIn(_email.text, _password.text);
      if (u == null) {
        error = 'Credenciais inválidas.';
      }
    } catch (e) {
      debugPrint('SignIn error: $e');
      error = 'Erro a autenticar.';
    }

    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    // sucesso
    GoRouter.of(context).go('/dashboard');
  }

  /// Constrói a decoração base dos `TextFormField` deste ecrã.
  ///
  /// Parâmetros:
  /// - [label] Texto do *label* (obrigatório);
  /// - [hint]  Texto de ajuda (opcional);
  /// - [suffix] Ícone/ação à direita (opcional), p.ex. *toggle* da palavra-passe.
  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    Widget? suffix,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: tt.bodyMedium,
      hintStyle: tt.bodyMedium?.copyWith(
        color: cs.onSurface.withValues(alpha: .60),
      ),
      filled: true,
      fillColor: cs.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: cs.outline.withValues(alpha: .50),
          width: 1,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: cs.outline.withValues(alpha: .50),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: suffix,
    );
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
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo + títulos
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      children: [
                        Image.asset(
                          'assets/utils/icon.png',
                          width: 256,
                          height: 256,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Entrar',
                          style: tt.headlineSmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bem-vindo de volta',
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurface.withValues(alpha: .70),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Card do formulário
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
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Campo de email
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: _inputDecoration(
                              label: 'Email',
                              hint: 'nome@dominio.com',
                            ),
                            validator: (v) =>
                                (v == null || !v.contains('@')) ? 'Email inválido' : null,
                          ),

                          const SizedBox(height: 16),

                          // Campo de palavra-passe
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: _inputDecoration(
                              label: 'Palavra-passe',
                              suffix: IconButton(
                                onPressed: () => setState(() => _obscure = !_obscure),
                                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                                color: cs.outline,
                              ),
                            ),
                            validator: (v) =>
                                (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                          ),

                          const SizedBox(height: 18),

                          // Botão Entrar
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _loading ? null : _submit,
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
                              child: _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Entrar'),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Link para criar conta
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Ainda não tem conta?',
                                style: tt.bodyMedium?.copyWith(
                                  color: cs.onSurface.withValues(alpha: .80),
                                ),
                              ),
                              const SizedBox(width: 10),
                              TextButton(
                                onPressed: () => context.go('/signup'),
                                style: TextButton.styleFrom(
                                  foregroundColor: cs.secondary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  textStyle: tt.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                child: const Text('Criar conta'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Versão / rodapé
                  Text(
                    'NutriScore • v0.1',
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
