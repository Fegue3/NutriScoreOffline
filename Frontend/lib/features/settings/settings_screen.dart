// lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../core/theme.dart' show AppColors;

/// ---------------------------------------------------------------------------
/// NutriScore — SettingsScreen
/// ---------------------------------------------------------------------------
/// Ecrã principal de **Definições** da app:
///
/// 1. **Secção "Conta"**
///    - Mostra nome e email do utilizador autenticado (via `userRepo.currentUser()`).
///    - Link para o ecrã de edição de utilizador (`/settings/user`) onde se
///      alteram dados biométricos, datas e metas.
///
/// 2. **Secção "Dieta & Objetivos"**
///    - Ação rápida "Definir peso atual":
///      - Abre um bottom sheet para introduzir o peso em kg.
///      - Guarda um registo em `weightRepo` (tabela de logs de peso).
///      - Atualiza também `UserGoals.currentWeightKg` via um statement SQL
///        custom (`di.db.customStatement`), se possível.
///    - Link "Ver progresso de nutrição" que navega para `/weight`
///      (ecrã de evolução do peso / progresso).
///
/// 3. **"Danger Zone"**
///    - Apagar conta: mostra `AlertDialog` de confirmação e chama
///      `userRepo.deleteAccount()`. Em caso de sucesso, faz `go('/')`.
///    - Terminar sessão: chama `userRepo.signOut()` e volta ao root (`'/'`).
///
/// 4. **Secção "Sobre"**
///    - Mostra nome da app, versão e pequeno texto de descrição.
///
/// Integração com DI:
///   - `di.userRepo`         → sessão, dados de utilizador, delete, sign out.
///   - `di.weightRepo`       → logs de peso (para gráficos / histórico).
///   - `di.db.customStatement` → update direto da tabela UserGoals (peso atual).
///
/// UX:
///   - Usa `RefreshIndicator` para permitir "pull to refresh" dos dados
///     de perfil (nome/email).
///   - Feedback de sucesso/erro via SnackBar com helpers `_toastOk` / `_toastErr`.
///   - Layout coerente com o resto da app (cores de `AppColors` e cards suaves).
/// ---------------------------------------------------------------------------

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Estado do [SettingsScreen].
///
/// Responsabilidades:
///  - Carregar dados básicos do perfil (nome, email) com `_bootstrap()`;
///  - Tratar das ações de:
///      * definir peso atual (`_setCurrentWeight`);
///      * apagar conta (`_confirmDeleteAccount`);
///      * terminar sessão (logout);
///  - Construir a árvore de widgets das várias secções de definições.
class _SettingsScreenState extends State<SettingsScreen> {
  /// Indica se o ecrã está a carregar os dados iniciais do utilizador.
  bool _loading = true;

  /// Nome do utilizador, tal como guardado em `UserModel.name`.
  String? _name;

  /// Email do utilizador autenticado (pode ser vazio, dependendo do backend).
  String? _email;

  // ---------------------------------------------------------------------------
  // Ciclo de vida
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // ---------------------------------------------------------------------------
  // LOAD: leitura de perfil (userRepo)
  // ---------------------------------------------------------------------------

  /// Carrega o utilizador atual a partir do `userRepo` e preenche
  /// [_name], [_email] e o flag [`_loading`].
  ///
  /// Chamada:
  ///   - Ao iniciar (em `initState`);
  ///   - Ao fazer pull-to-refresh no `RefreshIndicator`.
  Future<void> _bootstrap() async {
    final u = await di.userRepo.currentUser();
    if (!mounted) return;
    setState(() {
      _name = u?.name ?? 'Utilizador';
      _email = u?.email ?? '';
      _loading = false;
    });
  }

  // =======================================================================
  // Helpers de feedback (SnackBars)
  // =======================================================================

  /// Mostra um `SnackBar` verde/positivo com a mensagem [msg].
  void _toastOk(String msg) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: cs.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  /// Mostra um `SnackBar` vermelho/erro com a mensagem [msg].
  void _toastErr(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // =======================================================================
  // Ações principais
  // =======================================================================

  /// Abre um bottom sheet para o utilizador introduzir o peso atual em kg.
  ///
  /// Fluxo:
  ///   1. Mostra o formulário com campo de texto numérico;
  ///   2. Se o utilizador confirmar, valida o valor (0 < kg <= 400);
  ///   3. Lê o utilizador atual via `userRepo.currentUser()`;
  ///   4. Cria log do dia corrente em `weightRepo` (com data "canon" UTC 00:00);
  ///   5. Tenta também atualizar `UserGoals.currentWeightKg` via statement
  ///      SQL direto sobre a BD local (`di.db.customStatement`);
  ///   6. Mostra mensagem de sucesso e refaz `_bootstrap()` para refletir
  ///      possíveis alterações de peso relacionado com metas.
  Future<void> _setCurrentWeight() async {
    final controller = TextEditingController(text: '');

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final insets = MediaQuery.of(ctx).viewInsets;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + insets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Definir peso atual',
                style: Theme.of(ctx).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Peso (kg)',
                  hintText: 'Ex.: 72.5',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (ok == true) {
      // Converte texto para double (aceita vírgula ou ponto).
      final txt = controller.text.replaceAll(',', '.').trim();
      final kg = double.tryParse(txt);

      // Validação simples de faixa plausível de peso.
      if (kg == null || kg <= 0 || kg > 400) {
        _toastErr('Peso inválido.');
        return;
      }

      try {
        final u = await di.userRepo.currentUser();
        if (u == null) throw 'Sem sessão local.';

        // 1) cria log do dia corrente (UTC 00:00)
        final now = DateTime.now().toUtc();
        final day = DateTime.utc(now.year, now.month, now.day);
        await di.weightRepo.addLog(u.id, day, kg, note: 'settings');

        // 2) (opcional) atualiza currentWeightKg em UserGoals se existir
        try {
          await di.db.customStatement(
            'UPDATE UserGoals SET currentWeightKg=?, updatedAt=datetime(\'now\') WHERE userId=?;',
            [kg, u.id],
          );
        } catch (_) {
          // silencioso; se falhar, pelo menos o log de peso fica guardado
        }

        if (!mounted) return;
        _toastOk('Peso atualizado.');
        await _bootstrap();
      } catch (e) {
        if (!mounted) return;
        _toastErr('Falha ao atualizar: $e');
      }
    }
  }

  /// Confirma com o utilizador se pretende realmente apagar a conta.
  ///
  /// - Mostra um `AlertDialog` com texto de aviso;
  /// - Se confirmar:
  ///   - Chama `userRepo.deleteAccount()` (responsável por limpar dados
  ///     locais e remotos);
  ///   - Mostra toast de sucesso e redireciona para `'/'` (e.g. ecrã de login);
  /// - Se falhar, mostra toast de erro com mensagem técnica.
  Future<void> _confirmDeleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apagar conta'),
        content: const Text(
          'Isto é definitivo. Queres mesmo apagar a tua conta e todos os dados locais?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.ripeRed,
            ),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await di.userRepo.deleteAccount();
        if (!mounted) return;
        _toastOk('Conta apagada.');
        GoRouter.of(context).go('/');
      } catch (e) {
        _toastErr('Falha ao apagar conta: $e');
      }
    }
  }

  // =======================================================================
  // BUILD
  // =======================================================================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.softOffWhite,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        title: Text(
          'Definições',
          style: tt.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),

      /// Conteúdo dentro de um `RefreshIndicator` para permitir
      /// "pull to refresh" (reload de nome/email).
      body: RefreshIndicator(
        onRefresh: _bootstrap,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // ===========================================================
                  // SECÇÃO: CONTA
                  // ===========================================================
                  const _SectionHeader('Conta'),
                  _Card(
                    child: Column(
                      children: [
                        _ProfileRow(
                          title: _name ?? (_email ?? 'Utilizador'),
                          subtitle: _name != null && _name!.isNotEmpty
                              ? (_email ?? '')
                              : '',
                        ),
                        const SizedBox(height: 8),
                        _DividerSoft(),
                        _Tile(
                          icon: Icons.manage_accounts_outlined,
                          iconBg: AppColors.freshGreen.withAlpha(24),
                          iconColor: AppColors.freshGreen,
                          title: 'Editar informações do utilizador',
                          subtitle:
                              'Nome, preferências e dados básicos.',
                          onTap: () => context.go('/settings/user'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ===========================================================
                  // SECÇÃO: DIETA & OBJETIVOS
                  // ===========================================================
                  const _SectionHeader('Dieta & Objetivos'),
                  _Card(
                    child: Column(
                      children: [
                        _Tile(
                          icon: Icons.monitor_weight_outlined,
                          iconBg: AppColors.freshGreen.withAlpha(24),
                          iconColor: AppColors.freshGreen,
                          title: 'Definir peso atual',
                          onTap: _setCurrentWeight,
                        ),
                        _DividerSoft(),
                        _Tile(
                          icon: Icons.bar_chart_outlined,
                          iconBg: AppColors.freshGreen.withAlpha(24),
                          iconColor: AppColors.freshGreen,
                          title: 'Ver progresso de nutrição',
                          onTap: () => context.push('/weight'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ===========================================================
                  // SECÇÃO: DANGER ZONE
                  // ===========================================================
                  const _SectionHeaderDanger('Danger Zone'),
                  _DangerCard(
                    child: Column(
                      children: [
                        _DangerTile(
                          icon: Icons.delete_forever_outlined,
                          title: 'Apagar conta',
                          subtitle:
                              'Remove todos os teus dados do servidor.',
                          onTap: _confirmDeleteAccount,
                        ),
                        _DangerDivider(),
                        _DangerTile(
                          icon: Icons.logout,
                          title: 'Terminar sessão',
                          onTap: () async {
                            await di.userRepo.signOut();
                            if (!context.mounted) return;
                            GoRouter.of(context).go('/');
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ===========================================================
                  // SECÇÃO: SOBRE
                  // ===========================================================
                  const _SectionHeader('Sobre'),
                  const _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AboutRow(
                          name: 'NutriScore',
                          version: 'v1.0.0',
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Aplicação para escolhas alimentares conscientes.\n'
                          'Área 2 – Segurança Alimentar e Agricultura Sustentável.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ============================================================================
// Widgets auxiliares (seções, cards e tiles)
// ============================================================================

/// Cabeçalho de secção normal (ex.: "Conta", "Dieta & Objetivos", "Sobre").
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: tt.headlineMedium?.copyWith(
          color: AppColors.charcoal,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Cabeçalho específico para a "Danger Zone" (texto vermelho).
class _SectionHeaderDanger extends StatelessWidget {
  final String title;
  const _SectionHeaderDanger(this.title);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: tt.headlineMedium?.copyWith(
          color: AppColors.ripeRed,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Card genérico verde-claro usado nas secções normais.
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSage,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

/// Card com styling vermelho (tinte leve) para a *Danger Zone*.
class _DangerCard extends StatelessWidget {
  final Widget child;
  const _DangerCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ripeRed.withAlpha(16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.ripeRed.withAlpha(120),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

/// Linha de perfil com avatar circular + nome + email.
class _ProfileRow extends StatelessWidget {
  final String title;
  final String subtitle;
  const _ProfileRow({required this.title, this.subtitle = ''});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.freshGreen.withAlpha(40),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            (title.isNotEmpty ? title[0] : 'U').toUpperCase(),
            style: tt.titleLarge?.copyWith(
              color: AppColors.freshGreen,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tt.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: tt.bodyMedium?.copyWith(
                    color: AppColors.coolGray,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tile genérico para itens de definições “normais”.
class _Tile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _Tile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.bodyLarge?.copyWith(
                      color: AppColors.charcoal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: tt.bodyMedium?.copyWith(
                          color: AppColors.coolGray,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black26),
          ],
        ),
      ),
    );
  }
}

/// Tile específico para ações perigosas (apagar conta, logout, etc.).
class _DangerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _DangerTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.ripeRed.withAlpha(22),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: AppColors.ripeRed),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.bodyLarge?.copyWith(
                      color: AppColors.ripeRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: tt.bodyMedium?.copyWith(
                          color:
                              AppColors.ripeRed.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black26),
          ],
        ),
      ),
    );
  }
}

/// Divider vermelho suave para separar ações dentro da *Danger Zone*.
class _DangerDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 12,
      thickness: 1,
      color: AppColors.ripeRed.withValues(alpha: 0.25),
    );
  }
}

/// Divider cinzento muito suave para separar tiles normais.
class _DividerSoft extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 12,
      thickness: 1,
      color: Colors.black12.withValues(alpha: 0.06),
    );
  }
}

/// Linha da secção "Sobre": nome da app + versão.
class _AboutRow extends StatelessWidget {
  final String name;
  final String version;
  const _AboutRow({required this.name, required this.version});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Text(version, style: tt.bodyMedium),
      ],
    );
  }
}
