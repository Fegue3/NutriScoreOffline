import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// Ponto de medição de peso (data + valor em kg).
///
/// Representa uma amostra individual usada no gráfico de tendência.
class WeightPoint {
  /// Data/hora do registo.
  final DateTime date;

  /// Peso em quilogramas.
  final double weightKg;

  /// Cria um ponto de peso com [date] e [weightKg].
  const WeightPoint({required this.date, required this.weightKg});
}

/// Ponto preparado especificamente para o gráfico:
/// - [date] representa o dia (normalizado para AAAA-MM-DD, 00:00).
/// - [weightKg] é o peso a apresentar.
/// - [isReal] indica se é um registo real do utilizador (`true`) ou
///   um ponto “virtual” usado apenas para manter a linha contínua (`false`).
class _ChartPoint {
  final DateTime date;
  final double weightKg;
  final bool isReal;

  const _ChartPoint({
    required this.date,
    required this.weightKg,
    required this.isReal,
  });
}

/// NutriScore — Cartão de Tendência de Peso
///
/// Cartão puramente visual que apresenta um **gráfico de linha** com a evolução
/// do peso ao longo do tempo.
///
/// Comportamento:
/// - Ordena todos os registos por data/hora.
/// - Garante **no máximo um ponto por dia**:
///   - Se [collapseSameDay] = `true` → usa a **média diária** dos registos desse dia.
///   - Se [collapseSameDay] = `false` → usa o **último registo do dia**.
/// - Cria um **timeline contínuo dia a dia**:
///   - Se [rangeStart]/[rangeEnd] forem fornecidos, usa esse intervalo
///     (ex.: últimos 30 dias).
///   - Caso contrário, usa do primeiro ao último registo.
///   - Dias sem pesagem usam o **último peso conhecido** (linha horizontal).
///   - Só mostra **dots** nos dias com registo real; dias “preenchidos” não
///     mostram marcador.
/// - O gráfico pode:
///   - ocupar toda a largura sem scroll (`fitToWidth = true`, ideal para
///     ecrãs de resumo, como o WeightProgressScreen);
///   - ou permitir scroll horizontal (`fitToWidth = false`, ideal para
///     dashboards onde queres navegar ao longo do tempo).
class WeightTrendCard extends StatelessWidget {
  /// Cria um cartão com gráfico de tendência do peso.
  const WeightTrendCard({
    super.key,
    required this.points,
    this.title = 'Evolução do peso',
    this.showLegend = true,
    this.height = 240,
    this.collapseSameDay = true,
    this.rangeStart,
    this.rangeEnd,
    this.fitToWidth = false,
  });

  /// Lista de pontos de peso a apresentar (registos “brutos”).
  final List<WeightPoint> points;

  /// Título do cartão.
  final String title;

  /// Exibe uma legenda/ajuda de interação sob o gráfico.
  final bool showLegend;

  /// Altura em pixels reservada ao gráfico.
  final double height;

  /// Define como colapsar múltiplos registos no mesmo dia:
  ///
  /// - `true` → usa a **média diária** dos registos desse dia.
  /// - `false` → usa o **último registo desse dia**.
  ///
  /// Em ambos os casos, o gráfico garante **no máximo um ponto por dia**,
  /// portanto dados do mesmo dia nunca “dão stack”.
  final bool collapseSameDay;

  /// Início do intervalo visível (dia de calendário).
  ///
  /// Se `null`, usa a data do primeiro registo.
  final DateTime? rangeStart;

  /// Fim do intervalo visível (dia de calendário).
  ///
  /// Se `null`, usa a data do último registo.
  final DateTime? rangeEnd;

  /// Se `true`, o gráfico é **comprimido para caber na largura do cartão**
  /// (sem scroll horizontal). Ideal para ecrãs de resumo por período.
  ///
  /// Se `false` (default), o gráfico pode ter scroll horizontal, com
  /// largura proporcional ao nº de dias.
  final bool fitToWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 1) Ordena por data/hora (crescente).
    final sorted = [...points]..sort((a, b) => a.date.compareTo(b.date));

    if (sorted.isEmpty) {
      return Card(
        elevation: 0,
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outline.withValues(alpha: .15)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'Sem registos ainda',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: .7),
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    // 2) Garante no máximo 1 ponto por dia (média ou último).
    final daily = _collapseByDay(
      sorted,
      useAverage: collapseSameDay,
    );

    // 3) Cria timeline contínuo (com pontos virtuais para dias sem registo),
    //    respeitando o intervalo [rangeStart, rangeEnd] quando fornecido.
    final chartPoints = _buildContinuousTimeline(
      daily,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );

    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline.withValues(alpha: .15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: height,
              child: chartPoints.isEmpty
                  ? Center(
                      child: Text(
                        'Sem registos ainda',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: .7),
                          fontSize: 13,
                        ),
                      ),
                    )
                  : _Chart(
                      points: chartPoints,
                      cs: cs,
                      fitToWidth: fitToWidth,
                    ),
            ),
            if (showLegend && chartPoints.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Toque e arraste para ver valores',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: .6),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Colapsa múltiplos registos no mesmo dia para **um único ponto por dia**.
  ///
  /// - [useAverage] define o modo de colapso:
  ///   - `true` → usa a **média** de [weightKg] nesse dia.
  ///   - `false` → usa o **último registo** desse dia (por ordem cronológica).
  ///
  /// Isto garante que dados do mesmo dia não “fazem stack” no gráfico.
  List<WeightPoint> _collapseByDay(
    List<WeightPoint> pts, {
    required bool useAverage,
  }) {
    if (pts.isEmpty) return const [];

    // Normaliza para data (AAAA-MM-DD) em horário local.
    final Map<DateTime, List<WeightPoint>> byDay = {};

    for (final p in pts) {
      final dayKey = DateTime(p.date.year, p.date.month, p.date.day);
      byDay.putIfAbsent(dayKey, () => []).add(p);
    }

    final days = byDay.keys.toList()..sort((a, b) => a.compareTo(b));

    final List<WeightPoint> result = [];

    for (final d in days) {
      final list = byDay[d]!..sort((a, b) => a.date.compareTo(b.date));

      if (useAverage) {
        // Média diária dos registos desse dia.
        final sum = list.fold<double>(0, (acc, p) => acc + p.weightKg);
        final avg = sum / list.length;
        result.add(
          WeightPoint(
            date: d,
            weightKg: avg,
          ),
        );
      } else {
        // Último registo cronológico desse dia.
        final last = list.last;
        result.add(
          WeightPoint(
            date: d,
            weightKg: last.weightKg,
          ),
        );
      }
    }

    return result;
  }

  DateTime _normalizeDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Constrói um **timeline contínuo dia a dia**.
  ///
  /// - Se [rangeStart]/[rangeEnd] forem fornecidos → usa esse intervalo
  ///   (ex.: últimos 30 dias).
  /// - Caso contrário → vai do primeiro ao último registo.
  ///
  /// Para cada dia do intervalo:
  /// - Se existir registo → usa esse peso (`isReal = true`).
  /// - Caso contrário → usa o **último peso conhecido** (`isReal = false`),
  ///   mantendo a linha contínua.
  List<_ChartPoint> _buildContinuousTimeline(
    List<WeightPoint> dailyPoints, {
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) {
    if (dailyPoints.isEmpty) return const [];

    final sorted = [...dailyPoints]..sort(
        (a, b) => a.date.compareTo(b.date),
      );

    // Mapa dia (data apenas) → peso desse dia.
    final Map<DateTime, double> weightByDay = {
      for (final p in sorted) _normalizeDay(p.date): p.weightKg,
    };

    // Determina o intervalo efetivo da série.
    final DateTime seriesStart = rangeStart != null
        ? _normalizeDay(rangeStart)
        : _normalizeDay(sorted.first.date);

    final DateTime seriesEnd = rangeEnd != null
        ? _normalizeDay(rangeEnd)
        : _normalizeDay(sorted.last.date);

    if (seriesEnd.isBefore(seriesStart)) {
      return const [];
    }

    final List<_ChartPoint> result = [];

    // Primeiro peso conhecido como ponto base da linha.
    double lastKnownWeight = sorted.first.weightKg;

    for (DateTime d = seriesStart;
        !d.isAfter(seriesEnd);
        d = d.add(const Duration(days: 1))) {
      final dayKey = _normalizeDay(d);
      final w = weightByDay[dayKey];

      final isReal = w != null;
      if (w != null) {
        lastKnownWeight = w;
      }

      result.add(
        _ChartPoint(
          date: dayKey,
          weightKg: lastKnownWeight,
          isReal: isReal,
        ),
      );
    }

    return result;
  }
}

/// Gráfico de linha com `fl_chart` para a evolução do peso.
///
/// - Usa [_ChartPoint] para saber se o ponto é real ou “virtual”.
/// - Calcula margens dinâmicas em Y para evitar cortes.
/// - Mostra grades horizontais e eixos com rótulos compactos.
/// - Tooltip com data completa e valor em kg.
/// - Pode ter:
///   - scroll horizontal (`fitToWidth = false`);
///   - ou ocupar toda a largura, sem scroll (`fitToWidth = true`).
/// - Quando há scroll, faz auto-scroll para o fim (últimos registos).
class _Chart extends StatefulWidget {
  const _Chart({
    required this.points,
    required this.cs,
    required this.fitToWidth,
  });

  /// Pontos já pré-processados (timeline contínuo).
  final List<_ChartPoint> points;

  /// Esquema de cores atual da app (theme.dart → colorScheme).
  final ColorScheme cs;

  /// Se `true`, o gráfico é comprimido na largura disponível (sem scroll).
  final bool fitToWidth;

  @override
  State<_Chart> createState() => _ChartState();
}

class _ChartState extends State<_Chart> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // Só faz scroll automático se estivermos em modo scroll.
    if (!widget.fitToWidth) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToEnd();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _Chart oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Se a série mudou e estamos em modo scroll, volta a posicionar no fim.
    if (!widget.fitToWidth &&
        (oldWidget.points.length != widget.points.length ||
            !identical(oldWidget.points, widget.points))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToEnd();
      });
    }
  }

  void _scrollToEnd() {
    if (widget.fitToWidth) return;
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent > 0) {
      _scrollController.jumpTo(maxExtent);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final cs = widget.cs;

    if (points.isEmpty) {
      return const SizedBox.shrink();
    }

    final minY =
        points.map((e) => e.weightKg).reduce((a, b) => a < b ? a : b);
    final maxY =
        points.map((e) => e.weightKg).reduce((a, b) => a > b ? a : b);
    final margin = ((maxY - minY).abs() * 0.06).clamp(0.6, 2.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Quando fitToWidth = true → usamos sempre a largura disponível.
        // Quando false → usamos largura proporcional ao nº de dias,
        // permitindo scroll horizontal.
        const double minWidthPerPoint = 32.0;

        double chartWidth;
        if (widget.fitToWidth || points.length <= 1) {
          chartWidth = constraints.maxWidth;
        } else {
          final rawWidth = points.length * minWidthPerPoint;
          chartWidth =
              rawWidth < constraints.maxWidth ? constraints.maxWidth : rawWidth;
        }

        final chart = SizedBox(
          width: chartWidth,
          child: LineChart(
            LineChartData(
              minY: minY - margin,
              maxY: maxY + margin,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: cs.outline.withValues(alpha: .22),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (v, _) => Text(
                      v.toStringAsFixed(1),
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: .72),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval:
                        (points.length / 5).clamp(1, 999).toDouble(),
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= points.length) {
                        return const SizedBox.shrink();
                      }
                      final d = points[i].date;
                      final label =
                          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: .72),
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  tooltipRoundedRadius: 12,
                  tooltipPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  tooltipBgColor: cs.surface,
                  getTooltipItems: (ts) => ts.map((spot) {
                    final i = spot.x.toInt();
                    if (i < 0 || i >= points.length) {
                      return null;
                    }
                    final p = points[i];
                    final d = p.date;
                    final date =
                        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
                    return LineTooltipItem(
                      '$date\n${p.weightKg.toStringAsFixed(1)} kg',
                      TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    );
                  }).whereType<LineTooltipItem>().toList(),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  barWidth: 3,
                  color: cs.primary,
                  dotData: FlDotData(
                    show: true,
                    // Só mostra dots nos pontos com registo real.
                    checkToShowDot: (spot, _) {
                      final index = spot.x.toInt();
                      if (index < 0 || index >= points.length) {
                        return false;
                      }
                      return points[index].isReal;
                    },
                    getDotPainter: (spot, _, __, ___) {
                      final index = spot.x.toInt();
                      final isReal = index >= 0 &&
                          index < points.length &&
                          points[index].isReal;

                      if (!isReal) {
                        // Ponto virtual → dot invisível.
                        return FlDotCirclePainter(
                          radius: 0,
                          color: Colors.transparent,
                          strokeWidth: 0,
                        );
                      }

                      return FlDotCirclePainter(
                        radius: 3.5,
                        color: cs.primary,
                        strokeWidth: 2,
                        strokeColor: cs.surface,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withValues(alpha: .25),
                        cs.primary.withValues(alpha: .05),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  spots: points
                      .asMap()
                      .entries
                      .map(
                        (e) => FlSpot(
                          e.key.toDouble(),
                          e.value.weightKg,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        );

        if (widget.fitToWidth) {
          // Modo “resumido” → tudo cabe na largura, sem scroll.
          return chart;
        } else {
          // Modo scroll → largura proporcional ao nº de dias.
          return SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: chart,
          );
        }
      },
    );
  }
}
