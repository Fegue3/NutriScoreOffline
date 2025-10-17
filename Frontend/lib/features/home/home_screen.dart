// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart' show AppColors;
import '../../app/di.dart';
import '../../domain/models.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _username;
  int _goalKcal = 0;
  int _consumedKcal = 0;

  double _kBreakfast = 0, _kLunch = 0, _kSnack = 0, _kDinner = 0;

  double _proteinG = 0, _carbG = 0, _fatG = 0;
  double _targetProteinG = 0, _targetCarbG = 0, _targetFatG = 0;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final u = await di.userRepo.currentUser();
      if (u == null) {
        setState(() => _loading = false);
        return;
      }
      _username = u.name ?? '';

      final goals = await di.goalsRepo.getByUser(u.id);
      _goalKcal = goals?.dailyCalories ?? 0;

      final now = DateTime.now().toUtc();
      final cached = await di.statsRepo.getCached(u.id, now);
      final stats = cached ?? await di.statsRepo.computeDaily(u.id, now);

      _consumedKcal = stats.kcal;
      _proteinG = stats.protein;
      _carbG = stats.carb;
      _fatG = stats.fat;

      // targets de macros (se tiveres percentagens guardadas, podes calcular no cliente)
      if (_goalKcal > 0) {
        final carbPct = goals?.carbPercent ?? 50;
        final protPct = goals?.proteinPercent ?? 20;
        final fatPct = goals?.fatPercent ?? 30;

        // 4/4/9 kcal/g
        _targetCarbG = (_goalKcal * carbPct / 100.0) / 4.0;
        _targetProteinG = (_goalKcal * protPct / 100.0) / 4.0;
        _targetFatG = (_goalKcal * fatPct / 100.0) / 9.0;
      }

      // kcal por refeição (agregamos Meal.totalKcal por type)
      final meals = await di.mealsRepo.getMealsForDay(u.id, now);
      double b = 0, l = 0, s = 0, d = 0;
      for (final m in meals) {
        switch (m.type) {
          case 'BREAKFAST':
            b += m.totalKcal;
            break;
          case 'LUNCH':
            l += m.totalKcal;
            break;
          case 'SNACK':
            s += m.totalKcal;
            break;
          case 'DINNER':
            d += m.totalKcal;
            break;
        }
      }
      _kBreakfast = b;
      _kLunch = l;
      _kSnack = s;
      _kDinner = d;
    } catch (_) {
      // podes mostrar um toast
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final int remaining = (_goalKcal - _consumedKcal).clamp(0, 1 << 31);
    final double pct = _goalKcal <= 0 ? 0.0 : (_consumedKcal / _goalKcal).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.freshGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Dashboard',
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  // ===== Cumprimento =====
                  Text(
                    (_username == null || _username!.trim().isEmpty)
                        ? 'Olá 👋'
                        : 'Olá, ${_username!.trim()} 👋',
                    style: tt.titleLarge,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 16),

                  // ===== Calorias =====
                  _Card(
                    child: Row(
                      children: [
                        _CaloriesRing(consumed: _consumedKcal, goal: _goalKcal),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Calorias de hoje', style: tt.titleMedium),
                              const SizedBox(height: 8),
                              _kv('Objetivo', '$_goalKcal kcal', tt),
                              _kv('Consumidas', '$_consumedKcal kcal', tt),
                              _kv('Restantes', '$remaining kcal', tt, emphasize: true, color: cs.primary),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(value: pct, minHeight: 8),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ===== Peso (placeholder do teu gráfico) =====
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Evolução do peso', style: tt.titleMedium),
                        const SizedBox(height: 12),
                        Container(
                          height: 160,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Gráfico (UI placeholder)',
                            style: tt.labelLarge?.copyWith(color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ===== Macros =====
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Macros', style: tt.titleMedium),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _MacroCircle(
                                label: 'Proteína',
                                value: _proteinG,
                                target: _targetProteinG,
                                unit: 'g',
                                color: AppColors.leafyGreen,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _MacroCircle(
                                label: 'Hidratos',
                                value: _carbG,
                                target: _targetCarbG,
                                unit: 'g',
                                color: AppColors.warmTangerine,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _MacroCircle(
                                label: 'Gordura',
                                value: _fatG,
                                target: _targetFatG,
                                unit: 'g',
                                color: AppColors.goldenAmber,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ===== Refeições =====
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Refeições', style: tt.titleMedium),
                        const SizedBox(height: 12),
                        _MealRow(icon: Icons.free_breakfast, label: 'Pequeno-almoço', kcal: _kBreakfast),
                        const SizedBox(height: 12),
                        _MealRow(icon: Icons.lunch_dining, label: 'Almoço', kcal: _kLunch),
                        const SizedBox(height: 12),
                        _MealRow(icon: Icons.cookie_outlined, label: 'Lanche', kcal: _kSnack),
                        const SizedBox(height: 12),
                        _MealRow(icon: Icons.dinner_dining, label: 'Jantar', kcal: _kDinner),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _kv(String k, String v, TextTheme tt, {bool emphasize = false, Color? color}) {
    final style = emphasize
        ? tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color, fontFamily: 'RobotoMono')
        : tt.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(k, style: tt.bodyMedium), Text(v, style: style)],
    );
  }
}

// ================== UI building blocks (iguais aos teus) ==================
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(blurRadius: 10, offset: Offset(0, 4), color: Color(0x14000000))],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

class _CaloriesRing extends StatelessWidget {
  final int consumed;
  final int goal;
  const _CaloriesRing({required this.consumed, required this.goal});
  @override
  Widget build(BuildContext context) {
    final double pct = goal <= 0 ? 0.0 : (consumed / goal).clamp(0.0, 1.0);
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 92, height: 92,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: 92, height: 92,
          child: CircularProgressIndicator(
            value: pct, strokeWidth: 12, strokeCap: StrokeCap.round,
            color: cs.primary, backgroundColor: cs.surfaceContainerHighest,
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${(pct * 100).round()}%', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontFamily: 'RobotoMono')),
          const SizedBox(height: 2),
          Text('kcal', style: tt.labelSmall),
        ]),
      ]),
    );
  }
}

class _MacroCircle extends StatelessWidget {
  final String label;
  final double value;
  final double target;
  final String unit;
  final Color color;
  const _MacroCircle({required this.label, required this.value, required this.target, required this.unit, required this.color});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final bool hasTarget = target > 0;
    final double pct = hasTarget ? (value / target).clamp(0.0, 1.0) : 0.0;

    final circle = SizedBox(
      width: 96, height: 96,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: 96, height: 96,
          child: CircularProgressIndicator(
            value: 1, strokeWidth: 12, strokeCap: StrokeCap.round,
            valueColor: AlwaysStoppedAnimation<Color>(cs.surfaceContainerHighest), backgroundColor: Colors.transparent,
          ),
        ),
        SizedBox(
          width: 96, height: 96,
          child: CircularProgressIndicator(
            value: pct, strokeWidth: 12, strokeCap: StrokeCap.round,
            valueColor: AlwaysStoppedAnimation<Color>(color), backgroundColor: Colors.transparent,
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${value.toStringAsFixed(0)} $unit', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, fontFamily: 'RobotoMono')),
          Text(hasTarget ? 'Alvo ${target.toStringAsFixed(0)}' : 'sem alvo', style: tt.labelSmall),
        ]),
      ]),
    );

    return Column(mainAxisSize: MainAxisSize.min, children: [circle, const SizedBox(height: 8), Text(label, style: tt.bodyMedium)]);
  }
}

class _MealRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double kcal;
  const _MealRow({required this.icon, required this.label, required this.kcal});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final double barPct = kcal <= 0 ? 0.0 : (kcal / 800).clamp(0.0, 1.0);
    final row = Row(children: [
      Icon(icon, color: cs.primary),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: tt.bodyLarge, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: barPct, minHeight: 10, color: AppColors.warmTangerine, backgroundColor: cs.surfaceContainerHighest),
          ),
        ]),
      ),
      const SizedBox(width: 12),
      Text('${kcal.round()} kcal', style: tt.titleSmall?.copyWith(fontFamily: 'RobotoMono')),
    ]);
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: row);
  }
}
