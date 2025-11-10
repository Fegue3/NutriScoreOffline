import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Slots de refeição suportados na app NutriScore.
///
/// Usados para agrupar a ingestão calórica por refeição no dia.
enum MealSlot { breakfast, lunch, snack, dinner }

/// Extensões utilitárias para [MealSlot].
extension MealSlotX on MealSlot {
  /// Rótulo curto em PT-PT para apresentação em UI/legendas.
  String get label {
    switch (this) {
      case MealSlot.breakfast:
        return 'Peq-almoço';
      case MealSlot.lunch:
        return 'Almoço';
      case MealSlot.snack:
        return 'Lanche';
      case MealSlot.dinner:
        return 'Jantar';
    }
  }
}

/// **Pie/Donut chart** da distribuição de calorias por refeição.
///
/// Apresenta um *donut* (via `fl_chart`) com 4 segmentos (Peq-almoço, Almoço,
/// Lanche, Jantar) e uma legenda compacta com valores absolutos (`kcal`) e
/// percentagens relativas ao total do dia.
///
/// ### Propriedades
/// - [kcalByMeal]: mapa `MealSlot → kcal` (valores negativos são tratados como 0);
/// - [totalKcal]: se > 0, é usado como total (em vez de somar o mapa);
/// - [goalKcal]: meta diária de calorias, para mostrar `% do objetivo` no centro;
/// - [padding]: espaçamento interno do cartão (default `16`);
/// - [chartSize]: largura/altura do *donut* em px (default `160`).
///
/// ### Estados vazios
/// Quando o total é 0, renderiza um segmento neutro e centra o texto **"Sem calorias"**.
///
/// ### Acessibilidade
/// - Usa ícone/legenda textual por refeição, não depende só da cor.
/// - Dígitos com *tabular figures* para alinhamento consistente.
class CaloriesMealsPie extends StatelessWidget {
  /// Calorias por [MealSlot]. Valores `null`/ausentes assumem 0.
  final Map<MealSlot, double> kcalByMeal;

  /// Total de calorias do dia. Se `> 0`, tem precedência sobre a soma de [kcalByMeal].
  final double totalKcal;

  /// Meta de calorias do dia. Quando definida, mostra o progresso em `%` no centro.
  final double? goalKcal;

  /// Espaçamento interno do cartão.
  final EdgeInsetsGeometry padding;

  /// Tamanho do *donut* (largura = altura).
  final double chartSize;

  /// Cria um gráfico de distribuição de calorias por refeição.
  const CaloriesMealsPie({
    super.key,
    required this.kcalByMeal,
    this.totalKcal = 0,
    this.goalKcal,
    this.padding = const EdgeInsets.all(16),
    this.chartSize = 160,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Paleta por slot (derivada do ColorScheme atual).
    final colors = <MealSlot, Color>{
      MealSlot.breakfast: cs.primary,
      MealSlot.lunch: cs.tertiary,
      MealSlot.snack: cs.secondary,
      MealSlot.dinner: cs.error,
    };

    // Valores normalizados por slot.
    final values =
        MealSlot.values.map((m) => (kcalByMeal[m] ?? 0).toDouble()).toList();

    // Total seguro: usa totalKcal se fornecido; caso contrário, soma do mapa.
    final sum =
        (totalKcal > 0 ? totalKcal : values.fold<double>(0, (a, b) => a + b))
            .toDouble();
    final isEmpty = sum <= 0.0001;
    final safeSum = isEmpty ? 1.0 : sum;

    // Secções do gráfico (1 neutra se vazio).
    final sections = isEmpty
        ? <PieChartSectionData>[
            PieChartSectionData(
              color: cs.surfaceContainerHighest,
              value: 1,
              radius: 18,
              showTitle: false,
            ),
          ]
        : MealSlot.values.map((slot) {
            final v = (kcalByMeal[slot] ?? 0).toDouble();
            return PieChartSectionData(
              color: colors[slot],
              value: v <= 0 ? 0.0001 : v,
              radius: 18,
              showTitle: false,
            );
          }).toList();

    // Estilo monoespaçado para números (alinhamento estável).
    final mono = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
    );

    return Card(
      color: theme.cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Distribuição das Calorias', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                // DONUT
                SizedBox(
                  width: chartSize,
                  height: chartSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sections: sections,
                          startDegreeOffset: -90,
                          centerSpaceRadius: chartSize * 0.38,
                          sectionsSpace: isEmpty ? 0 : 2,
                          pieTouchData: PieTouchData(enabled: !isEmpty),
                        ),
                        swapAnimationDuration: const Duration(milliseconds: 1200),
                        swapAnimationCurve: Curves.easeOutCubic,
                      ),
                      // Centro (total e progresso vs meta)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isEmpty)
                            Text('Sem calorias',
                                style: theme.textTheme.labelMedium)
                          else
                            Text('${sum.toStringAsFixed(0)} kcal',
                                style: mono),
                          if (!isEmpty && goalKcal != null && goalKcal! > 0)
                            Text(
                              '${((sum / goalKcal!).clamp(0, 1) * 100).round()}% do objetivo',
                              style: theme.textTheme.labelSmall,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // LEGENDA (compacta: slot, kcal e %)
                Expanded(
                  child: Column(
                    children: MealSlot.values.map((slot) {
                      final v = (kcalByMeal[slot] ?? 0).toDouble();
                      final pct = (v / safeSum) * 100.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4), // era 6
                        child: Row(
                          children: [
                            _LegendDot(
                              color: (isEmpty ? cs.surfaceContainerHighest : colors[slot])!,
                              size: 8, // era 12
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                slot.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${v.toStringAsFixed(0)} kcal · ${pct.toStringAsFixed(0)}%',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pequeno marcador colorido para a legenda do gráfico.
///
/// Mostra um quadrado com cantos ligeiramente arredondados.
class _LegendDot extends StatelessWidget {
  /// Cor do marcador (geralmente a mesma da fatia correspondente).
  final Color color;

  /// Tamanho do lado do marcador em px.
  final double size;

  /// Cria um ponto de legenda com [color] e [size] opcionais.
  const _LegendDot({required this.color, this.size = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
