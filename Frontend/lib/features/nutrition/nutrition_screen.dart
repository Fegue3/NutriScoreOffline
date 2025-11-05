// lib/features/nutrition/nutrition_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart' as di;
import '../../domain/models.dart';
import '../../core/meal_type.dart'; // <- ÚNICA fonte do enum + extensions

/// NutriScore – NutritionScreen

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key});
  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> {
  // ===== Navegação por dia (UI) =====
  int _dayOffset = 0; // 0=Hoje, -1=Ontem, 1=Amanhã…
  int _slideDir = 0;

  // ===== Estado calorias (resumo topo – UI) =====
  final int _fallbackDailyGoal = 2200;
  int get _goal => _dailyGoal > 0 ? _dailyGoal : _fallbackDailyGoal;

  int _dailyGoal = 0;

  MealType _parseMealType(String s) {
    switch (s) {
      case 'BREAKFAST':
        return MealType.breakfast;
      case 'LUNCH':
        return MealType.lunch;
      case 'SNACK':
        return MealType.snack;
      case 'DINNER':
        return MealType.dinner;
      default:
        return MealType.lunch;
    }
  }

  List<MealEntry> _toEntries(List<MealWithItems> meals) {
    final out = <MealEntry>[];
    for (final m in meals) {
      final typ = _parseMealType(m.type);
      for (final it in m.items) {
        out.add(
          MealEntry(
            id: it.id,
            name: (it.name != null && it.name!.trim().isNotEmpty)
                ? it.name!.trim()
                : (it.customFoodId ?? 'Alimento'),
            meal: typ,
            brand: it.brand,
            barcode: it.productBarcode,
            calories: it.kcal,
            protein: it.protein,
            carbs: it.carb,
            fat: it.fat,
            quantityGrams: it.gramsTotal,
            quantityMl: it.unit == 'ML' ? it.quantity : null,
            servings: it.unit == 'PIECE' ? it.quantity : null,
          ),
        );
      }
    }
    return out;
  }

  Future<void> _loadDay() async {
    setState(() {}); // trigger leve de loading
    try {
      final u = await di.di.userRepo.currentUser();
      if (u == null) return;

      // Goal diário
      final goals = await di.di.goalsRepo.getByUser(u.id);
      _dailyGoal = goals?.dailyCalories ?? 0;

      // Refeições do dia
      final dayCanon = DateTime.now().toUtc().add(Duration(days: _dayOffset));
      final meals = await di.di.mealsRepo.getMealsForDay(u.id, dayCanon);
      _entries = _toEntries(meals);
    } catch (_) {
      // opcional: snack/erro
    } finally {
      if (mounted) setState(() {});
    }
  }

  // ===== Estado das refeições (UI local) =====
  List<MealEntry> _entries = const [];

  // Agrupado por tipo (UI):
  List<MealEntry> get _brk =>
      _entries.where((e) => e.meal == MealType.breakfast).toList();
  List<MealEntry> get _lun =>
      _entries.where((e) => e.meal == MealType.lunch).toList();
  List<MealEntry> get _snk =>
      _entries.where((e) => e.meal == MealType.snack).toList();
  List<MealEntry> get _din =>
      _entries.where((e) => e.meal == MealType.dinner).toList();

  int get _consumed {
    int sum = 0;
    for (final e in _entries) {
      final c = e.calories;
      if (c != null) sum += c.round();
    }
    return sum;
  }

  String get _ymd {
    final d = DateTime.now().add(Duration(days: _dayOffset));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  int _sumKcal(Iterable<MealEntry> xs) {
    int s = 0;
    for (final e in xs) {
      if (e.calories != null) s += e.calories!.round();
    }
    return s;
  }

  String _labelFor(BuildContext ctx, int off) {
    if (off == 0) return "Hoje";
    if (off == -1) return "Ontem";
    if (off == 1) return "Amanhã";
    final d = DateTime.now().add(Duration(days: off));
    return MaterialLocalizations.of(ctx).formatMediumDate(d);
  }

  void _go(int delta) {
    if (delta == 0) return;
    setState(() {
      _slideDir = delta > 0 ? 1 : -1;
      _dayOffset += delta;
    });
    _loadDay();
  }

  // ======= NAV: Adicionar alimento (vai para /add-food) =======
  void _openAddFor(MealType meal) {
    context
        .push(
          '/add-food',
          extra: {
            'meal': meal, // <- envia o enum diretamente
            'mealTitle': meal.labelPt, // opcional (UI)
            'dateYmd': _ymd, // YYYY-MM-DD
          },
        )
        .then((_) => _loadDay());
  }

  void _removeEntry(MealEntry e) async {
    try {
      await di.di.mealsRepo.removeMealItem(e.id);
    } catch (_) {
      // opcional: snack erro
    }
    _loadDay();
  }

  // ======= NAV: Detalhe do produto (vai para productDetail) =======
  void _openEntry(MealEntry e) {
    // Base para a UI do detalhe (apenas o "tamanho" da unidade base)
    final String baseQty = (e.quantityGrams != null)
        ? '100 g' // item registado em gramas → base g
        : (e.quantityMl != null)
        ? '100 ml' // item registado em ml → base ml
        : '1 porção'; // senão, assume porção/unidade

    final dayCanon = DateTime.now().toUtc().add(Duration(days: _dayOffset));

    context
        .pushNamed(
          'productDetail',
          extra: {
            'barcode': e.barcode,
            'name': e.name,
            'brand': e.brand,
            'baseQuantityLabel': baseQty,

            // valores para UI (opcional)
            'kcalPerBase': e.calories?.round(),
            'proteinGPerBase': (e.protein ?? 0).toDouble(),
            'carbsGPerBase': (e.carbs ?? 0).toDouble(),
            'fatGPerBase': (e.fat ?? 0).toDouble(),

            // ===== edição =====
            'freezeFromEntry': true,
            'readOnly': false,
            'initialMeal': e.meal,
            'date': dayCanon,

            // para UPDATE correto e prefill do multiplicador
            'existingMealItemId': e.id,
            'initialGrams': e.quantityGrams
                ?.toDouble(), // usado se base for 'g'
            // (se quiseres, podes também enviar 'initialMl' / 'initialServings' mais tarde)
          },
        )
        .then((_) => _loadDay());
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
        foregroundColor: cs.onPrimary,
        title: Text(
          "Diário das Calorias",
          style: tt.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openAddFor(MealType.breakfast),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // ===== HERO VERDE =====
          Container(
            color: cs.primary,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  GestureDetector(
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v > 120) _go(-1);
                      if (v < -120) _go(1);
                    },
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          height: 40,
                          child: _ArrowBtn(
                            icon: Icons.chevron_left_rounded,
                            onTap: () => _go(-1),
                          ),
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, anim) {
                              final begin = Offset((_slideDir) * 0.25, 0);
                              return ClipRect(
                                child: SlideTransition(
                                  position: Tween(
                                    begin: begin,
                                    end: Offset.zero,
                                  ).animate(anim),
                                  child: FadeTransition(
                                    opacity: anim,
                                    child: child,
                                  ),
                                ),
                              );
                            },
                            child: Center(
                              key: ValueKey(_dayOffset),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: const ShapeDecoration(
                                  color: Colors.white,
                                  shape: StadiumBorder(),
                                ),
                                child: Text(
                                  _labelFor(context, _dayOffset),
                                  style: tt.titleMedium?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          height: 40,
                          child: _ArrowBtn(
                            icon: Icons.chevron_right_rounded,
                            onTap: () => _go(1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _CalorieSummaryConnectedCompact(
                    goal: _goal,
                    consumed: _consumed,
                  ),
                ],
              ),
            ),
          ),

          // ===== Conteúdo do dia =====
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                final begin = Offset((_slideDir) * 0.25, 0);
                return ClipRect(
                  child: SlideTransition(
                    position: Tween(
                      begin: begin,
                      end: Offset.zero,
                    ).animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                );
              },
              child: _DayContent(
                key: ValueKey('$_dayOffset-${_entries.length}'),
                brk: _brk,
                lun: _lun,
                snk: _snk,
                din: _din,
                kcalBrk: _sumKcal(_brk),
                kcalLun: _sumKcal(_lun),
                kcalSnk: _sumKcal(_snk),
                kcalDin: _sumKcal(_din),
                onTapAddFood: _openAddFor,
                onRemove: _removeEntry,
                onTapItem: _openEntry,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _BottomActions(
          onOpenNutrition: () => context.pushNamed('nutritionStats'),
        ),
      ),
    );
  }
}

/* ============================ MODELOS (UI) ============================ */

class MealEntry {
  final String id;
  final String name;
  final String? brand;
  final String? barcode;
  final MealType meal; // <- do core
  final num? calories;
  final num? protein;
  final num? carbs;
  final num? fat;
  final num? quantityGrams;
  final num? quantityMl;
  final num? servings;

  const MealEntry({
    required this.id,
    required this.name,
    required this.meal,
    this.brand,
    this.barcode,
    this.calories,
    this.protein,
    this.carbs,
    this.fat,
    this.quantityGrams,
    this.quantityMl,
    this.servings,
  });
}

/* ============================ AUXILIARES ============================ */

class _ArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ArrowBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton.filled(
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: cs.onPrimary.withValues(alpha: .90),
        foregroundColor: cs.primary,
        padding: EdgeInsets.zero,
      ),
      icon: Icon(icon, size: 26),
    );
  }
}

/* ============================ DIA ============================ */

class _DayContent extends StatelessWidget {
  final List<MealEntry> brk, lun, snk, din;
  final int kcalBrk, kcalLun, kcalSnk, kcalDin;
  final void Function(MealType meal) onTapAddFood;
  final void Function(MealEntry e) onRemove;
  final void Function(MealEntry e) onTapItem;

  const _DayContent({
    super.key,
    required this.brk,
    required this.lun,
    required this.snk,
    required this.din,
    required this.kcalBrk,
    required this.kcalLun,
    required this.kcalSnk,
    required this.kcalDin,
    required this.onTapAddFood,
    required this.onRemove,
    required this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return ScrollConfiguration(
      behavior: const _BounceScrollBehavior(),
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
        children: [
          _MealSection(
            title: "Pequeno-almoço",
            calories: kcalBrk,
            items: brk,
            onAddTap: () => onTapAddFood(MealType.breakfast),
            onRemove: onRemove,
            initiallyExpanded: brk.isNotEmpty,
            onTapItem: onTapItem,
          ),
          const SizedBox(height: 16),
          _MealSection(
            title: "Almoço",
            calories: kcalLun,
            items: lun,
            onAddTap: () => onTapAddFood(MealType.lunch),
            onRemove: onRemove,
            initiallyExpanded: lun.isNotEmpty,
            onTapItem: onTapItem,
          ),
          const SizedBox(height: 16),
          _MealSection(
            title: "Lanche",
            calories: kcalSnk,
            items: snk,
            onAddTap: () => onTapAddFood(MealType.snack),
            onRemove: onRemove,
            initiallyExpanded: snk.isNotEmpty,
            onTapItem: onTapItem,
          ),
          const SizedBox(height: 16),
          _MealSection(
            title: "Jantar",
            calories: kcalDin,
            items: din,
            onAddTap: () => onTapAddFood(MealType.dinner),
            onRemove: onRemove,
            initiallyExpanded: din.isNotEmpty,
            onTapItem: onTapItem,
          ),
          const SizedBox(height: 16),
          const _WaterCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _BounceScrollBehavior extends ScrollBehavior {
  const _BounceScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child; // sem glow
  }
}

/* ============================ CALORIE SUMMARY ============================ */

class _CalorieSummaryConnectedCompact extends StatelessWidget {
  final int goal;
  final int consumed;
  const _CalorieSummaryConnectedCompact({
    required this.goal,
    required this.consumed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final remaining = goal - consumed;
    final ok = remaining >= 0;
    final onP = cs.onPrimary;
    final dividerColor = onP.withValues(alpha: .22);

    Widget seg({
      required String label,
      required String value,
      Color? valueColor,
    }) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: onP.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelSmall?.copyWith(
                    color: onP,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: tt.titleMedium?.copyWith(
                    color: valueColor ?? onP,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 70,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: onP.withValues(alpha: .14),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 10,
                      offset: Offset(0, 4),
                      color: Color(0x22000000),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                seg(label: "Meta", value: "$goal kcal"),
                seg(label: "Consumidas", value: "$consumed kcal"),
                seg(
                  label: "Restantes",
                  value: "${remaining.abs()} kcal",
                  valueColor: ok ? onP : cs.error,
                ),
              ],
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _VerticalDividersPainter(
                  color: dividerColor,
                  count: 2,
                  topPad: 8,
                  bottomPad: 8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerticalDividersPainter extends CustomPainter {
  final Color color;
  final int count;
  final double topPad;
  final double bottomPad;
  const _VerticalDividersPainter({
    required this.color,
    this.count = 2,
    this.topPad = 10,
    this.bottomPad = 10,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (var i = 1; i <= count; i++) {
      final x = size.width * i / (count + 1);
      final alignedX = x.floorToDouble() + 0.5;
      canvas.drawLine(
        Offset(alignedX, topPad),
        Offset(alignedX, size.height - bottomPad),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VerticalDividersPainter old) =>
      old.color != color ||
      old.count != count ||
      old.topPad != topPad ||
      old.bottomPad != bottomPad;
}

/* ============================ MEAL CARD ============================ */

class _MealSection extends StatefulWidget {
  final String title;
  final int calories;
  final List<MealEntry> items;
  final VoidCallback? onAddTap;
  final void Function(MealEntry e)? onRemove;
  final bool initiallyExpanded;
  final void Function(MealEntry e)? onTapItem;

  const _MealSection({
    required this.title,
    required this.calories,
    required this.items,
    this.onAddTap,
    this.onRemove,
    this.initiallyExpanded = false,
    this.onTapItem,
  });

  @override
  State<_MealSection> createState() => _MealSectionState();
}

class _MealSectionState extends State<_MealSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant _MealSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.items.isNotEmpty && widget.items.isNotEmpty) {
      _expanded = true;
    }
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            offset: Offset(0, 6),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // HEADER
            Material(
              color: cs.primary,
              child: InkWell(
                onTap: _toggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: tt.titleLarge?.copyWith(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: ShapeDecoration(
                          color: cs.onPrimary.withValues(alpha: 0.15),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          "${widget.calories} kcal",
                          style: tt.titleMedium?.copyWith(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 160),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: cs.onPrimary,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // BODY
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: _expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: _MealItemsList(
                  items: widget.items,
                  onRemove: widget.onRemove,
                  onTapItem: widget.onTapItem,
                ),
              ),
              secondChild: const SizedBox.shrink(),
            ),

            // divisor
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 1,
              color: Colors.black.withValues(alpha: _expanded ? 0.0 : 0.06),
            ),

            // FOOTER (Adicionar alimento)
            Material(
              color: Colors.white,
              child: InkWell(
                onTap: widget.onAddTap,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Text(
                      "Adicionar alimento",
                      style: tt.titleMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealItemsList extends StatelessWidget {
  final List<MealEntry> items;
  final void Function(MealEntry e)? onRemove;
  final void Function(MealEntry e)? onTapItem;
  const _MealItemsList({required this.items, this.onRemove, this.onTapItem});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (items.isEmpty) {
      return Center(
        child: Text(
          "Sem itens adicionados.",
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurface.withValues(alpha: .7),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Column(
      children: items.map((e) {
        final kcal = (e.calories ?? 0).round();

        // Subtítulo: marca • barcode
        final subtitleParts = <String>[];
        if ((e.brand ?? '').isNotEmpty) subtitleParts.add(e.brand!);
        final bc = e.barcode?.trim();
        if (bc != null && bc.isNotEmpty) subtitleParts.add(bc);

        // Quantidade human friendly
        String? qtyLabel;
        if (e.quantityGrams != null) {
          qtyLabel = '${e.quantityGrams!.round()} g';
        } else if (e.quantityMl != null) {
          qtyLabel = '${e.quantityMl!.round()} ml';
        } else if (e.servings != null) {
          qtyLabel = (e.servings! % 1 == 0)
              ? '${e.servings!.toInt()} porção(ões)'
              : '${e.servings!.toStringAsFixed(1)} porções';
        }

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onTapItem?.call(e),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Texto
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // NOME
                      Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitleParts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitleParts.join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      if (qtyLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            qtyLabel,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),

                // badge kcal
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: ShapeDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    "$kcal kcal",
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // remover
                IconButton(
                  tooltip: 'Remover',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  iconSize: 22,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  onPressed: (onRemove == null) ? null : () => onRemove!(e),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/* ============================ ÁGUA + AÇÕES ============================ */

class _WaterCard extends StatefulWidget {
  const _WaterCard();
  @override
  State<_WaterCard> createState() => _WaterCardState();
}

class _WaterCardState extends State<_WaterCard> {
  int ml = 0;
  final int goal = 2000;
  bool _expanded = true;

  void _toggle() => setState(() => _expanded = !_expanded);
  void _applyDelta(int delta) =>
      setState(() => ml = (ml + delta).clamp(0, 40000));

  Future<void> _openCustomAmountSheet() async {
    final res = await showModalBottomSheet<_CustomAmountResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _CustomAmountSheet(),
    );
    if (res != null && res.valueMl > 0) {
      _applyDelta(res.isSubtract ? -res.valueMl : res.valueMl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final progress = (ml / goal).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 6,
            offset: Offset(0, 3),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Material(
              color: cs.primary,
              child: InkWell(
                onTap: _toggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Água",
                          style: tt.titleLarge?.copyWith(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: ShapeDecoration(
                          color: cs.onPrimary.withValues(alpha: 0.15),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          "${ml ~/ 100}dl / ${goal ~/ 100}dl",
                          style: tt.titleMedium?.copyWith(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 160),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: cs.onPrimary,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: _expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        backgroundColor: cs.outlineVariant.withValues(
                          alpha: .4,
                        ),
                        valueColor: AlwaysStoppedAnimation(cs.primary),
                      ),
                    ),
                  ],
                ),
              ),
              secondChild: const SizedBox.shrink(),
            ),
            Material(
              color: Colors.white,
              child: InkWell(
                onTap: _openCustomAmountSheet,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Text(
                      "Adicionar água",
                      style: tt.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomAmountSheet extends StatefulWidget {
  const _CustomAmountSheet();
  @override
  State<_CustomAmountSheet> createState() => _CustomAmountSheetState();
}

class _CustomAmountSheetState extends State<_CustomAmountSheet> {
  final _controller = TextEditingController(text: "250");
  String _unit = "ml";
  bool _subtract = false;

  int get _valueMl {
    final raw = int.tryParse(_controller.text.trim()) ?? 0;
    switch (_unit) {
      case "dl":
        return raw * 100;
      case "L":
      case "l":
        return raw * 1000;
      default:
        return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: inset + 16,
        top: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Adicionar água",
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Quantidade",
                    hintText: "ex.: 350",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButtonHideUnderline(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<String>(
                    value: _unit,
                    items: const [
                      DropdownMenuItem(value: "ml", child: Text("ml")),
                      DropdownMenuItem(value: "dl", child: Text("dl")),
                      DropdownMenuItem(value: "L", child: Text("L")),
                    ],
                    onChanged: (v) => setState(() => _unit = v ?? "ml"),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text("Somar")),
              ButtonSegment(value: true, label: Text("Subtrair")),
            ],
            selected: {_subtract},
            onSelectionChanged: (s) => setState(() => _subtract = s.first),
            style: ButtonStyle(
              side: WidgetStatePropertyAll(BorderSide(color: cs.primary)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(
                _CustomAmountResult(valueMl: _valueMl, isSubtract: _subtract),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 14),
                foregroundColor: Colors.white,
              ),
              child: const Text("Aplicar"),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomAmountResult {
  final int valueMl;
  final bool isSubtract;
  const _CustomAmountResult({required this.valueMl, required this.isSubtract});
}

class _BottomActions extends StatelessWidget {
  final VoidCallback? onOpenNutrition;
  const _BottomActions({this.onOpenNutrition});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TonalPill(
            icon: Icons.pie_chart_outline_rounded,
            label: "Nutrição",
            onTap: onOpenNutrition,
          ),
        ),
      ],
    );
  }
}

class _TonalPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _TonalPill({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(0, 4),
            color: Color(0x12000000),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: cs.onSurface.withValues(alpha: .85)),
            const SizedBox(width: 8),
            Text(
              label,
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
