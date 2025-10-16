// lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// usa as variáveis do teu theme.dart
import '../../core/theme.dart' show AppColors;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // ===== Dados mock (só UI) =====
  final String _username = 'Joana';
  final int _goalKcal = 2200;
  final int _consumedKcal = 1435;

  // kcal por refeição (mock)
  final double _kBreakfast = 320, _kLunch = 610, _kSnack = 180, _kDinner = 325;

  // macros consumidas (mock)
  final double _proteinG = 82, _carbG = 156, _fatG = 41;

  // metas/limites (mock)
  final double _targetProteinG = 120, _targetCarbG = 240, _targetFatG = 70;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final int remaining =
        (_goalKcal - _consumedKcal).clamp(0, 1 << 31); // continua a ser int
    final double pct =
        _goalKcal <= 0 ? 0.0 : (_consumedKcal / _goalKcal).clamp(0.0, 1.0);

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

      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          // ===== Cumprimento =====
          Text(
            (_username == null || _username.trim().isEmpty)
                ? 'Olá 👋'
                : 'Olá, ${_username.trim()} 👋',
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
                      _kv(
                        'Restantes',
                        '$remaining kcal',
                        tt,
                        emphasize: true,
                        color: cs.primary,
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ===== Peso (placeholder gráfico só UI) =====
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

          // ===== Macros (3 círculos) =====
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
                _MealRow(
                  icon: Icons.free_breakfast,
                  label: 'Pequeno-almoço',
                  kcal: _kBreakfast,
                ),
                const SizedBox(height: 12),
                _MealRow(
                  icon: Icons.lunch_dining,
                  label: 'Almoço',
                  kcal: _kLunch,
                ),
                const SizedBox(height: 12),
                _MealRow(
                  icon: Icons.cookie_outlined,
                  label: 'Lanche',
                  kcal: _kSnack,
                ),
                const SizedBox(height: 12),
                _MealRow(
                  icon: Icons.dinner_dining,
                  label: 'Jantar',
                  kcal: _kDinner,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _kv(
    String k,
    String v,
    TextTheme tt, {
    bool emphasize = false,
    Color? color,
  }) {
    final style = emphasize
        ? tt.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
            fontFamily: 'RobotoMono',
          )
        : tt.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: tt.bodyMedium),
        Text(v, style: style),
      ],
    );
  }
}

// ================== UI building blocks ==================

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
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 4),
            color: Color(0x14000000),
          ),
        ],
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
      width: 92,
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: CircularProgressIndicator(
              value: pct,
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              color: cs.primary,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(pct * 100).round()}%',
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'RobotoMono',
                ),
              ),
              const SizedBox(height: 2),
              Text('kcal', style: tt.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

// ===== Macros em círculos =====
class _MacroCircle extends StatelessWidget {
  final String label;
  final double value; // consumido em g
  final double target; // alvo em g
  final String unit;
  final Color color;

  const _MacroCircle({
    required this.label,
    required this.value,
    required this.target,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final bool hasTarget = target > 0;
    final double pct = hasTarget ? (value / target).clamp(0.0, 1.0) : 0.0;

    final circle = SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              valueColor:
                  AlwaysStoppedAnimation<Color>(cs.surfaceContainerHighest),
              backgroundColor: Colors.transparent,
            ),
          ),
          SizedBox(
            width: 96,
            height: 96,
            child: CircularProgressIndicator(
              value: pct,
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              backgroundColor: Colors.transparent,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${value.toStringAsFixed(0)} $unit',
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'RobotoMono',
                ),
              ),
              Text(
                hasTarget ? 'Alvo ${target.toStringAsFixed(0)}' : 'sem alvo',
                style: tt.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle,
        const SizedBox(height: 8),
        Text(label, style: tt.bodyMedium),
      ],
    );
  }
}

class _MealRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double kcal;
  const _MealRow({
    required this.icon,
    required this.label,
    required this.kcal,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final double barPct =
        kcal <= 0 ? 0.0 : (kcal / 800).clamp(0.0, 1.0); // escala visual

    final row = Row(
      children: [
        Icon(icon, color: cs.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: tt.bodyLarge, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: barPct,
                  minHeight: 10,
                  color: AppColors.warmTangerine,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '${kcal.round()} kcal',
          style: tt.titleSmall?.copyWith(fontFamily: 'RobotoMono'),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: row,
    );
  }
}
