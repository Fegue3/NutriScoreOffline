// lib/features/nutrition/nutrition_stats_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// NutriScore – NutritionStatsScreen (UI puro, sem chamadas a backend)
/// - Pie de calorias por refeição (CustomPaint)
/// - Cartão de macros com progress bars
/// - Dados mock só para demonstrar UI

class NutritionStatsScreen extends StatefulWidget {
  const NutritionStatsScreen({super.key});
  @override
  State<NutritionStatsScreen> createState() => _NutritionStatsScreenState();
}

class _NutritionStatsScreenState extends State<NutritionStatsScreen> {
  int _dayOffset = 0; // 0=hoje, -1=ontem, 1=amanhã…

  // ===== Metas (mock)
  int kcalTarget = 2200;
  double proteinTargetG = 130;
  double carbTargetG = 260;
  double fatTargetG = 70;
  double sugarsTargetG = 50;
  double fiberTargetG = 30;
  double saltTargetG = 5;

  // ===== Dados do dia (mock – variam com offset)
  Map<MealSlot, double> _kcalByMeal = const {
    MealSlot.breakfast: 380,
    MealSlot.lunch: 760,
    MealSlot.snack: 260,
    MealSlot.dinner: 540,
  };

  double proteinG = 95;
  double carbG = 210;
  double fatG = 58;
  double sugarsG = 38;
  double fiberG = 22;
  double saltG = 3.6;

  @override
  void initState() {
    super.initState();
    _applyMockForOffset(0);
  }

  String _labelFor(BuildContext ctx) {
    if (_dayOffset == 0) return 'Hoje';
    if (_dayOffset == -1) return 'Ontem';
    if (_dayOffset == 1) return 'Amanhã';
    final d = DateTime.now().add(Duration(days: _dayOffset));
    return MaterialLocalizations.of(ctx).formatMediumDate(d);
  }

  double get _totalKcal =>
      _kcalByMeal.values.fold<double>(0, (a, b) => a + b);

  void _go(int delta) {
    if (delta == 0) return;
    setState(() {
      _dayOffset += delta;
      _applyMockForOffset(_dayOffset);
    });
  }

  void _applyMockForOffset(int off) {
    final mod = (off % 4).abs();

    final base = {
      0: const {
        MealSlot.breakfast: 380.0,
        MealSlot.lunch: 760.0,
        MealSlot.snack: 260.0,
        MealSlot.dinner: 540.0,
      },
      1: const {
        MealSlot.breakfast: 420.0,
        MealSlot.lunch: 690.0,
        MealSlot.snack: 190.0,
        MealSlot.dinner: 610.0,
      },
      2: const {
        MealSlot.breakfast: 310.0,
        MealSlot.lunch: 840.0,
        MealSlot.snack: 220.0,
        MealSlot.dinner: 520.0,
      },
      3: const {
        MealSlot.breakfast: 360.0,
        MealSlot.lunch: 720.0,
        MealSlot.snack: 300.0,
        MealSlot.dinner: 480.0,
      },
    }[mod]!;

    _kcalByMeal = base;

    final macroBase = [
      (protein: 95.0, carb: 210.0, fat: 58.0, sugars: 38.0, fiber: 22.0, salt: 3.6),
      (protein: 102.0, carb: 198.0, fat: 62.0, sugars: 41.0, fiber: 25.0, salt: 4.1),
      (protein: 87.0, carb: 232.0, fat: 66.0, sugars: 36.0, fiber: 28.0, salt: 3.3),
      (protein: 110.0, carb: 188.0, fat: 54.0, sugars: 34.0, fiber: 26.0, salt: 4.4),
    ][mod];

    proteinG = macroBase.protein;
    carbG = macroBase.carb;
    fatG = macroBase.fat;
    sugarsG = macroBase.sugars;
    fiberG = macroBase.fiber;
    saltG = macroBase.salt;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        title: Text(
          'Nutrição',
          style: tt.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          return;
        },
        child: Column(
          children: [
            // ===== HERO – navegação por dia =====
            Container(
              color: cs.primary,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    IconButton.filled(
                      onPressed: () => _go(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: cs.primary,
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: const ShapeDecoration(
                          color: Colors.white,
                          shape: StadiumBorder(),
                        ),
                        child: Center(
                          child: Text(
                            _labelFor(context),
                            style: tt.titleMedium?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () => _go(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: cs.primary,
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ===== Conteúdo =====
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _CaloriesMealsPieCard(
                    kcalByMeal: _kcalByMeal,
                    totalKcal: _totalKcal,
                    goalKcal: kcalTarget.toDouble(),
                  ),
                  const SizedBox(height: 16),

                  _MacroSectionCard(
                    kcalUsed: _totalKcal.round(),
                    kcalTarget: kcalTarget,
                    proteinG: proteinG,
                    proteinTargetG: proteinTargetG,
                    carbG: carbG,
                    carbTargetG: carbTargetG,
                    fatG: fatG,
                    fatTargetG: fatTargetG,
                    sugarsG: sugarsG,
                    fiberG: fiberG,
                    saltG: saltG,
                    sugarsTargetG: sugarsTargetG,
                    fiberTargetG: fiberTargetG,
                    saltTargetG: saltTargetG,
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

/* ============================ MODELOS LOCAIS ============================ */

enum MealSlot { breakfast, lunch, snack, dinner }

extension MealSlotLabel on MealSlot {
  String get label {
    switch (this) {
      case MealSlot.breakfast:
        return 'Pequeno-almoço';
      case MealSlot.lunch:
        return 'Almoço';
      case MealSlot.snack:
        return 'Lanche';
      case MealSlot.dinner:
        return 'Jantar';
    }
  }
}

/* ============================ PIE DE REFEIÇÕES ============================ */

class _CaloriesMealsPieCard extends StatelessWidget {
  final Map<MealSlot, double> kcalByMeal;
  final double totalKcal;
  final double goalKcal;

  const _CaloriesMealsPieCard({
    required this.kcalByMeal,
    required this.totalKcal,
    required this.goalKcal,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final entries = MealSlot.values
        .map((s) => MapEntry(s, kcalByMeal[s] ?? 0))
        .where((e) => e.value > 0)
        .toList();

    return Container(
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
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('Calorias por refeição', style: tt.titleMedium),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1.6,
            child: Row(
              children: [
                // Pie
                Expanded(
                  flex: 11,
                  child: Center(
                    child: SizedBox(
                      width: 160,
                      height: 160,
                      child: _MealsPie(
                        data: entries,
                        palette: [
                          cs.primary,
                          cs.tertiary,
                          cs.secondary,
                          cs.error,
                        ],
                        background: cs.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ),
                // Legenda
                Expanded(
                  flex: 13,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ...entries.asMap().entries.map((kv) {
                        final idx = kv.key;
                        final e = kv.value;
                        final color = [
                          cs.primary,
                          cs.tertiary,
                          cs.secondary,
                          cs.error,
                        ][idx % 4];
                        final pct = totalKcal <= 0
                            ? 0
                            : ((e.value / totalKcal) * 100).round();
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  e.key.label,
                                  style: tt.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${e.value.round()} kcal',
                                style: tt.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$pct%',
                                style: tt.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      Divider(color: cs.outlineVariant),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Total', style: tt.bodyMedium),
                          ),
                          Text(
                            '${totalKcal.round()} kcal',
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Meta', style: tt.bodyMedium),
                          ),
                          Text(
                            '${goalKcal.round()} kcal',
                            style: tt.titleSmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MealsPie extends StatelessWidget {
  final List<MapEntry<MealSlot, double>> data;
  final List<Color> palette;
  final Color background;

  const _MealsPie({
    required this.data,
    required this.palette,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    final sum = data.fold<double>(0, (a, b) => a + b.value);
    return CustomPaint(
      painter: _PiePainter(
        values: data.map((e) => e.value).toList(),
        colors: List.generate(
          data.length,
          (i) => palette[i % palette.length],
        ),
        background: background,
        sum: sum,
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double sum;
  final Color background;
  _PiePainter({
    required this.values,
    required this.colors,
    required this.sum,
    required this.background,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2;

    final bgPaint = Paint()
      ..color = background
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.30
      ..strokeCap = StrokeCap.butt;

    // trilho
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.72),
      -math.pi / 2,
      math.pi * 2,
      false,
      bgPaint,
    );

    double start = -math.pi / 2;
    for (int i = 0; i < values.length; i++) {
      // ---- FIX 1: garantir double
      final double sweep =
          sum <= 0 ? 0.0 : ((values[i] / sum) * (math.pi * 2)).toDouble();

      final p = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.30
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.72),
        start,
        sweep,
        false,
        p,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.sum != sum ||
        oldDelegate.background != background;
  }
}

/* ============================ CARD DE MACROS ============================ */

class _MacroSectionCard extends StatelessWidget {
  final int kcalUsed;
  final int kcalTarget;

  final double proteinG;
  final double proteinTargetG;

  final double carbG;
  final double carbTargetG;

  final double fatG;
  final double fatTargetG;

  final double sugarsG;
  final double fiberG;
  final double saltG;

  final double sugarsTargetG;
  final double fiberTargetG;
  final double saltTargetG;

  const _MacroSectionCard({
    required this.kcalUsed,
    required this.kcalTarget,
    required this.proteinG,
    required this.proteinTargetG,
    required this.carbG,
    required this.carbTargetG,
    required this.fatG,
    required this.fatTargetG,
    required this.sugarsG,
    required this.fiberG,
    required this.saltG,
    required this.sugarsTargetG,
    required this.fiberTargetG,
    required this.saltTargetG,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget meter({
      required String title,
      required double value,
      required double target,
      Color? color,
      String unit = 'g',
    }) {
      final v = value.clamp(0, double.infinity);
      final t = target <= 0 ? 1 : target;

      // ---- FIX 2: clamp devolve num; força double
      final double pct = (v / t).clamp(0.0, 1.0) as double;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tt.labelLarge),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color ?? cs.primary),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${v.toStringAsFixed(0)} $unit',
                style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Text(
                'alvo ${t.toStringAsFixed(0)} $unit',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 4),
            color: Color(0x14000000),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Cabeçalho calorias
          Row(
            children: [
              Expanded(child: Text('Calorias', style: tt.titleMedium)),
              _chip('$kcalUsed kcal usados', cs.primary, Colors.white),
              const SizedBox(width: 8),
              _chip('meta $kcalTarget kcal', cs.surfaceContainerHighest, cs.onSurface),
            ],
          ),
          const SizedBox(height: 16),

          // Macros principais
          Row(
            children: [
              Expanded(
                child: meter(
                  title: 'Proteína',
                  value: proteinG,
                  target: proteinTargetG,
                  color: const Color(0xFF66BB6A), // Leafy Green
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: meter(
                  title: 'Hidratos',
                  value: carbG,
                  target: carbTargetG,
                  color: const Color(0xFFFF8A4C), // Warm Tangerine
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: meter(
                  title: 'Gordura',
                  value: fatG,
                  target: fatTargetG,
                  color: const Color(0xFFFFC107), // Golden Amber
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 12),

          // Outros nutrientes
          Row(
            children: [
              Expanded(
                child: meter(
                  title: 'Açúcares',
                  value: sugarsG,
                  target: sugarsTargetG == 0 ? 1 : sugarsTargetG,
                  color: const Color(0xFFFFC107),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: meter(
                  title: 'Fibra',
                  value: fiberG,
                  target: fiberTargetG == 0 ? 1 : fiberTargetG,
                  color: const Color(0xFF66BB6A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: meter(
                  title: 'Sal',
                  value: saltG,
                  target: saltTargetG == 0 ? 1 : saltTargetG,
                  unit: 'g',
                  color: const Color(0xFFFF8A4C),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)
            .copyWith(color: fg),
      ),
    );
  }
}
