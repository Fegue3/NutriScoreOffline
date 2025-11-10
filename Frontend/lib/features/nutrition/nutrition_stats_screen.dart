// lib/features/nutrition/nutrition_stats_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app/di.dart';
import '../../core/theme.dart' show AppColors;

/// NutriScore — NutritionStatsScreen
///
/// Ecrã de **estatísticas de nutrição** por dia, complementar ao Diário.
///
/// Mostra:
/// - distribuição de calorias por refeição (gráfico circular / “pie”);
/// - totais e metas diárias de calorias;
/// - progresso dos principais macronutrientes:
///   - proteína, hidratos, gordura (com metas derivadas das calorias diárias);
/// - outros nutrientes de saúde pública:
///   - açúcares, fibra, sal (com metas fixas básicas).
///
/// Fontes de dados (através de DI):
/// - `userRepo`  → utilizador atual;
/// - `goalsRepo` → metas diárias (kcal + percentagens de macros);
/// - `statsRepo` → totais agregados de macros e nutrientes por dia;
/// - `mealsRepo` → calorias agregadas por refeição.
///
/// Navegação temporal:
/// - `_dayOffset` controla o dia visível:
///   - `0`  → hoje;
///   - `-1` → ontem;
///   - `1`  → amanhã;
/// - botões de “seta” avançam/recém dias;
/// - `RefreshIndicator` permite voltar a carregar os dados do dia atual.
class NutritionStatsScreen extends StatefulWidget {
  const NutritionStatsScreen({super.key});

  @override
  State<NutritionStatsScreen> createState() => _NutritionStatsScreenState();
}

/// Estado do [NutritionStatsScreen].
///
/// Responsabilidades:
/// - gerir o deslocamento de dia ([ _dayOffset ]);
/// - carregar metas de calorias e macros a partir do `goalsRepo`;
/// - carregar estatísticas de macros e micronutrientes do `statsRepo`;
/// - calcular calorias por refeição recorrendo ao `mealsRepo`;
/// - expor valores agregados para os *cards* de UI:
///   - [_CaloriesMealsPieCard] para o pie das refeições;
///   - [_MacroSectionCard] para barras de progresso de macros/nutrientes.
class _NutritionStatsScreenState extends State<NutritionStatsScreen> {
  /// Offset em dias relativamente a hoje.
  ///
  /// - `0`  → hoje;
  /// - `-1` → ontem;
  /// - `1`  → amanhã.
  int _dayOffset = 0;

  // ---------------------------------------------------------------------------
  // Metas (preenchidas a partir do GoalsRepo)
  // ---------------------------------------------------------------------------

  /// Meta diária de calorias (kcal), vinda de `goalsRepo.dailyCalories`.
  int kcalTarget = 0;

  /// Meta diária de proteína (g), calculada a partir da percentagem
  /// de proteína e da meta de calorias.
  double proteinTargetG = 0;

  /// Meta diária de hidratos de carbono (g), calculada a partir da
  /// percentagem de hidratos e da meta de calorias.
  double carbTargetG = 0;

  /// Meta diária de gordura (g), calculada a partir da percentagem de
  /// gordura e da meta de calorias.
  double fatTargetG = 0;

  /// Limite de referência para açúcares (g) — “regra de bolso”.
  double sugarsTargetG = 50;

  /// Limite de referência para fibra (g) — “regra de bolso”.
  double fiberTargetG = 30;

  /// Limite de referência para sal (g) — “regra de bolso”.
  double saltTargetG = 5;

  // ---------------------------------------------------------------------------
  // Dados do dia (vindos de stats/meals)
  // ---------------------------------------------------------------------------

  /// Mapa com calorias totais por slot de refeição do dia.
  ///
  /// Inicializado a zero para todas as refeições.
  Map<MealSlot, double> _kcalByMeal = const {
    MealSlot.breakfast: 0,
    MealSlot.lunch: 0,
    MealSlot.snack: 0,
    MealSlot.dinner: 0,
  };

  /// Totais diários de macronutrientes (g) e micronutrientes (g).
  double proteinG = 0;
  double carbG = 0;
  double fatG = 0;
  double sugarsG = 0;
  double fiberG = 0;
  double saltG = 0;

  /// Flag de carregamento:
  /// - `true`  → a aguardar dados;
  /// - `false` → dados prontos (ou falha silenciosa).
  bool _loading = true;

  // ---------------------------------------------------------------------------
  // Ciclo de vida
  // ---------------------------------------------------------------------------

  /// Inicializa o estado carregando imediatamente as estatísticas de hoje.
  @override
  void initState() {
    super.initState();
    _loadForOffset(0);
  }

  // ---------------------------------------------------------------------------
  // Helpers de data / navegação
  // ---------------------------------------------------------------------------

  /// Gera um rótulo amigável para o dia atual de `_dayOffset`.
  ///
  /// Casos especiais:
  /// - `0`  → "Hoje";
  /// - `-1` → "Ontem";
  /// - `1`  → "Amanhã".
  ///
  /// Para outros offsets, usa `MaterialLocalizations.formatMediumDate`
  /// para gerar uma data localizada.
  String _labelFor(BuildContext ctx) {
    if (_dayOffset == 0) return 'Hoje';
    if (_dayOffset == -1) return 'Ontem';
    if (_dayOffset == 1) return 'Amanhã';
    final d = DateTime.now().add(Duration(days: _dayOffset));
    return MaterialLocalizations.of(ctx).formatMediumDate(d);
  }

  /// Soma total de calorias do dia considerando todos os slots de refeição.
  double get _totalKcal =>
      _kcalByMeal.values.fold<double>(0, (a, b) => a + b);

  /// Avança/recuar o dia em [delta] dias.
  ///
  /// - Se [delta] for `0`, não faz nada;
  /// - Caso contrário, delega em [_loadForOffset] com o novo offset.
  void _go(int delta) {
    if (delta == 0) return;
    _loadForOffset(_dayOffset + delta);
  }

  // ---------------------------------------------------------------------------
  // Carregamento de dados
  // ---------------------------------------------------------------------------

  /// Carrega metas e estatísticas para o dia correspondente ao offset [off].
  ///
  /// Fluxo:
  /// 1. Atualiza `_dayOffset` e liga `_loading = true` com `setState`;
  /// 2. Obtém o utilizador atual via `userRepo.currentUser()`:
  ///    - se `null`, desliga apenas `_loading`;
  /// 3. Lê metas em `goalsRepo.getByUser(u.id)`:
  ///    - preenche [kcalTarget];
  ///    - se `kcalTarget > 0`, calcula metas de macros:
  ///      - proteína/hidratos: `4 kcal/g`;
  ///      - gordura: `9 kcal/g`;
  ///    - se não houver metas, zera alvos de macros;
  /// 4. Calcula a data canónica do dia (UTC + offset);
  /// 5. Lê estatísticas do `statsRepo`:
  ///    - tenta `getCached` primeiro;
  ///    - se `null`, calcula com `computeDaily`;
  /// 6. Atualiza totais de macros e nutrientes (g);
  /// 7. Lê refeições do `mealsRepo` e agrega calorias por tipo;
  /// 8. Finalmente, desliga `_loading` (se montado).
  Future<void> _loadForOffset(int off) async {
    setState(() {
      _dayOffset = off;
      _loading = true;
    });

    try {
      final u = await di.userRepo.currentUser();
      if (u == null) {
        setState(() => _loading = false);
        return;
      }

      // ---- metas (GoalsRepo)
      final goals = await di.goalsRepo.getByUser(u.id);
      kcalTarget = goals?.dailyCalories ?? 0;

      if (kcalTarget > 0) {
        final carbPct = (goals?.carbPercent ?? 50).toDouble();
        final protPct = (goals?.proteinPercent ?? 20).toDouble();
        final fatPct = (goals?.fatPercent ?? 30).toDouble();

        // 4 kcal/g (carb/prot), 9 kcal/g (fat)
        carbTargetG = (kcalTarget * carbPct / 100.0) / 4.0;
        proteinTargetG = (kcalTarget * protPct / 100.0) / 4.0;
        fatTargetG = (kcalTarget * fatPct / 100.0) / 9.0;
      } else {
        // se não houver dailyCalories ainda, zera os alvos de macros
        carbTargetG = 0;
        proteinTargetG = 0;
        fatTargetG = 0;
      }

      // ---- stats do dia (StatsRepo)
      final day = DateTime.now().toUtc().add(Duration(days: _dayOffset));
      final cached = await di.statsRepo.getCached(u.id, day);
      final stats = cached ?? await di.statsRepo.computeDaily(u.id, day);

      proteinG = stats.protein;
      carbG = stats.carb;
      fatG = stats.fat;
      sugarsG = stats.sugars;
      fiberG = stats.fiber;
      saltG = stats.salt;

      // ---- kcal por refeição (MealsRepo)
      final meals = await di.mealsRepo.getMealsForDay(u.id, day);
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
      _kcalByMeal = {
        MealSlot.breakfast: b,
        MealSlot.lunch: l,
        MealSlot.snack: s,
        MealSlot.dinner: d,
      };
    } catch (_) {
      // opcional: log/snack de erro
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Construção do UI
  // ---------------------------------------------------------------------------

  /// Constrói toda a estrutura de UI:
  ///
  /// - `AppBar` com título "Nutrição";
  /// - cabeçalho roxo/verde com navegação entre dias;
  /// - `RefreshIndicator` para recarregar estatísticas do dia atual;
  /// - lista com dois *cards* principais:
  ///   - [_CaloriesMealsPieCard] → distribuição de calorias por refeição;
  ///   - [_MacroSectionCard]     → barras de progresso de macros/nutrientes.
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
        onRefresh: () => _loadForOffset(_dayOffset),
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
                      style: ButtonStyle(
                        backgroundColor:
                            const WidgetStatePropertyAll<Color>(Colors.white),
                        foregroundColor:
                            WidgetStatePropertyAll<Color>(cs.primary),
                        elevation: const WidgetStatePropertyAll<double>(0),
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
                      style: ButtonStyle(
                        backgroundColor:
                            const WidgetStatePropertyAll<Color>(Colors.white),
                        foregroundColor:
                            WidgetStatePropertyAll<Color>(cs.primary),
                        elevation: const WidgetStatePropertyAll<double>(0),
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

/// Slot de refeição para agregação de calorias no gráfico de pie.
///
/// Representa as quatro refeições principais do dia:
/// - [MealSlot.breakfast] → pequeno-almoço;
/// - [MealSlot.lunch]     → almoço;
/// - [MealSlot.snack]     → lanche;
/// - [MealSlot.dinner]    → jantar.
enum MealSlot { breakfast, lunch, snack, dinner }

/// Extensão de conveniência para obter o rótulo PT de cada [MealSlot].
extension MealSlotLabel on MealSlot {
  /// Rótulo de UI para o slot de refeição:
  /// - "Pequeno-almoço", "Almoço", "Lanche", "Jantar".
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

/// Card com o gráfico circular de **calorias por refeição**.
///
/// Mostra:
/// - pie principal desenhado por [_MealsPie] / [_PiePainter];
/// - legenda com:
///   - rótulo de refeição;
///   - calorias por refeição;
///   - percentagem da refeição face ao total;
/// - totais e meta de calorias na parte inferior.
class _CaloriesMealsPieCard extends StatelessWidget {
  /// Mapa de calorias por refeição.
  final Map<MealSlot, double> kcalByMeal;

  /// Total de calorias do dia.
  final double totalKcal;

  /// Meta diária de calorias.
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

    // Filtra apenas slots com valor > 0 para mostrar no gráfico/legenda.
    final entries = MealSlot.values
        .map((s) => MapEntry(s, kcalByMeal[s] ?? 0))
        .where((e) => e.value > 0)
        .toList(growable: false);

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
                // Gráfico circular
                Expanded(
                  flex: 11,
                  child: Center(
                    child: SizedBox(
                      width: 160,
                      height: 160,
                      child: _MealsPie(
                        data: entries,
                        palette: const [
                          AppColors.freshGreen,
                          AppColors.leafyGreen,
                          AppColors.warmTangerine,
                          AppColors.goldenAmber,
                        ],
                        background: cs.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ),
                // Legenda e totais
                Expanded(
                  flex: 13,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ...entries.asMap().entries.map((kv) {
                        final idx = kv.key;
                        final e = kv.value;
                        final Color color = const [
                          AppColors.freshGreen,
                          AppColors.leafyGreen,
                          AppColors.warmTangerine,
                          AppColors.goldenAmber,
                        ][idx % 4];

                        final int pct = totalKcal <= 0
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

/// Wrapper que configura o [CustomPaint] para o pie de refeições.
///
/// Recebe:
/// - [data]: lista de (slot, kcal) já filtrados;
/// - [palette]: paleta de cores usada ciclicamente;
/// - [background]: cor da “trilha” de fundo.
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
    final double sum = data.fold<double>(0, (a, b) => a + b.value);
    return CustomPaint(
      painter: _PiePainter(
        values: data.map((e) => e.value).toList(growable: false),
        colors: List<Color>.generate(
          data.length,
          (i) => palette[i % palette.length],
          growable: false,
        ),
        background: background,
        sum: sum,
      ),
    );
  }
}

/// *CustomPainter* responsável por desenhar o pie de refeições.
///
/// Estratégia:
/// - desenha primeiro um círculo de “trilha” a `360º` com a cor [background];
/// - se [sum] ≤ 0, pára aqui (sem dados);
/// - caso contrário, desenha segmentos de arco em volta, um por valor,
///   com largura constante e cores vindas de [colors].
class _PiePainter extends CustomPainter {
  /// Valores numéricos de cada fatia (ex.: kcal por refeição).
  final List<double> values;

  /// Cores usadas para cada fatia (mesmo comprimento de [values]).
  final List<Color> colors;

  /// Soma total dos valores (usada para calcular a percentagem).
  final double sum;

  /// Cor de fundo da trilha do gráfico.
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

    // Largura da “linha” do pie e raio efetivo.
    final railStroke = radius * 0.30;
    final arcRadius = radius * 0.72;

    // Trilha de fundo (círculo completo).
    final bgPaint = Paint()
      ..color = background
      ..style = PaintingStyle.stroke
      ..strokeWidth = railStroke
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: arcRadius),
      -math.pi / 2,
      math.pi * 2,
      false,
      bgPaint,
    );

    if (sum <= 0) return;

    // Fatias de dados.
    double start = -math.pi / 2;
    for (int i = 0; i < values.length; i++) {
      final double v = values[i] <= 0 ? 0.0 : values[i];
      final double sweep = (v / sum) * (math.pi * 2);
      if (sweep <= 0) continue;

      final p = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = railStroke
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: arcRadius),
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

/// Card com o resumo de calorias e barras de progresso de macros/nutrientes.
///
/// Conteúdo:
/// - chips de calorias:
///   - “kcal usados”;
///   - “meta kcal”;
/// - secção de macros principais:
///   - proteína, hidratos, gordura;
/// - secção de “outros nutrientes” com limites mais gerais:
///   - açúcares, fibra, sal.
///
/// Cada linha de nutriente é renderizada por [meter], que:
/// - mostra um `LinearProgressIndicator` proporcional ao valor/target;
/// - apresenta o valor atual e o alvo em texto.
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

    /// Constrói uma linha de “medidor” (barra + valores) para um nutriente.
    ///
    /// Parâmetros:
    /// - [title]  → rótulo do nutriente (ex.: "Proteína");
    /// - [value]  → valor atual em gramas;
    /// - [target] → meta em gramas (evita 0 → assume 1 para não dividir por 0);
    /// - [color]  → cor da barra de progresso (default: `primary`);
    /// - [unit]   → unidade de texto (por omissão `'g'`).
    Widget meter({
      required String title,
      required double value,
      required double target,
      Color? color,
      String unit = 'g',
    }) {
      final double v =
          value.isFinite ? value.clamp(0, double.infinity) : 0.0;
      final double t = (target.isFinite && target > 0) ? target : 1.0;

      final double pct = v / t;
      final double clampedPct = pct < 0
          ? 0.0
          : (pct > 1.0)
              ? 1.0
              : pct;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tt.labelLarge),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: clampedPct,
              minHeight: 10,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor:
                  AlwaysStoppedAnimation<Color>(color ?? cs.primary),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${v.toStringAsFixed(0)} $unit',
                style:
                    tt.labelSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Text(
                'alvo ${t.toStringAsFixed(0)} $unit',
                style:
                    tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===== Cabeçalho calorias em LINHAS =====
          Text('Calorias', style: tt.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip(
                '$kcalUsed kcal usados',
                AppColors.freshGreen,
                Colors.white,
              ),
              const SizedBox(width: 8),
              _chip(
                'meta $kcalTarget kcal',
                Theme.of(context).colorScheme.surfaceContainerHighest,
                cs.onSurface,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ===== Macros principais — cada um numa linha =====
          meter(
            title: 'Proteína',
            value: proteinG,
            target: proteinTargetG,
            color: AppColors.leafyGreen,
          ),
          const SizedBox(height: 12),
          meter(
            title: 'Hidratos',
            value: carbG,
            target: carbTargetG,
            color: AppColors.warmTangerine,
          ),
          const SizedBox(height: 12),
          meter(
            title: 'Gordura',
            value: fatG,
            target: fatTargetG,
            color: AppColors.goldenAmber,
          ),

          const SizedBox(height: 20),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 12),

          // ===== Outros nutrientes — cada um numa linha =====
          meter(
            title: 'Açúcares',
            value: sugarsG,
            target: sugarsTargetG == 0 ? 1 : sugarsTargetG,
            color: AppColors.goldenAmber,
          ),
          const SizedBox(height: 12),
          meter(
            title: 'Fibra',
            value: fiberG,
            target: fiberTargetG == 0 ? 1 : fiberTargetG,
            color: AppColors.leafyGreen,
          ),
          const SizedBox(height: 12),
          meter(
            title: 'Sal',
            value: saltG,
            target: saltTargetG == 0 ? 1 : saltTargetG,
            unit: 'g',
            color: AppColors.warmTangerine,
          ),
        ],
      ),
    );
  }

  /// Constrói um pequeno *chip* visual com texto.
  ///
  /// Parâmetros:
  /// - [text] → conteúdo textual (ex.: "kcal usados");
  /// - [bg]   → cor de fundo do chip;
  /// - [fg]   → cor do texto.
  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const ShapeDecoration(
        shape: StadiumBorder(),
        color: Colors.transparent,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: fg,
          ),
        ),
      ),
    );
  }
}
