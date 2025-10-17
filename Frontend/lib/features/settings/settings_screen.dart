// lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/di.dart';
import '../../core/theme.dart' show AppColors;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;

  // Perfil
  String? _name;
  String? _email;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final u = await di.userRepo.currentUser();
    if (!mounted) return;
    setState(() {
      _name = u?.name ?? 'Utilizador';
      _email = u?.email ?? '';
      _loading = false;
    });
  }

  // =====================================================================
  // Ações
  // =====================================================================

  void _toastOk(String msg) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: cs.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _toastErr(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

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
      final txt = controller.text.replaceAll(',', '.').trim();
      final kg = double.tryParse(txt);
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
        } catch (_) {/* silencioso */ }

        if (!mounted) return;
        _toastOk('Peso atualizado.');
        await _bootstrap();
      } catch (e) {
        if (!mounted) return;
        _toastErr('Falha ao atualizar: $e');
      }
    }
  }

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
            style: TextButton.styleFrom(foregroundColor: AppColors.ripeRed),
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

  // =====================================================================
  // UI
  // =====================================================================
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
      body: RefreshIndicator(
        onRefresh: _bootstrap,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // ===== CONTA =====
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
                          subtitle: 'Nome, preferências e dados básicos.',
                          onTap: () => context.go('/settings/user'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ===== DIETA & OBJETIVOS =====
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

                  // ===== DANGER ZONE =====
                  const _SectionHeaderDanger('Danger Zone'),
                  _DangerCard(
                    child: Column(
                      children: [
                        _DangerTile(
                          icon: Icons.delete_forever_outlined,
                          title: 'Apagar conta',
                          subtitle: 'Remove todos os teus dados do servidor.',
                          onTap: _confirmDeleteAccount,
                        ),
                        _DangerDivider(),
                        _DangerTile(
                          icon: Icons.logout,
                          title: 'Terminar sessão',
                          onTap: () async {
                            await di.userRepo.signOut();
                            if (!mounted) return;
                            GoRouter.of(context).go('/');
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ===== SOBRE =====
                  const _SectionHeader('Sobre'),
                  const _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AboutRow(name: 'NutriScore', version: 'v1.0.0'),
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
// Widgets / Helpers
// ============================================================================

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

// Título vermelho para a Danger Zone
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

// Card específico vermelho (tinte leve) para a Danger Zone
class _DangerCard extends StatelessWidget {
  final Widget child;
  const _DangerCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ripeRed.withAlpha(16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ripeRed.withAlpha(120), width: 1),
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
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: tt.bodyMedium?.copyWith(color: AppColors.coolGray),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

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
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
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

// Tiles específicos para Danger Zone (vermelhos por defeito)
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
                          color: AppColors.ripeRed.withValues(alpha: 0.85),
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
