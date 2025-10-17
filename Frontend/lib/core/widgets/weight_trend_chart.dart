// lib/core/widgets/weight_trend_chart.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class WeightPoint {
  final DateTime date;
  final double weightKg;
  const WeightPoint({required this.date, required this.weightKg});
}

/// Card de UI PURA:
/// - Se existirem múltiplos registos no mesmo dia, por defeito colapsa para o
///   **último do dia** (consistente com o backend). Pode desligar via flag.
class WeightTrendCard extends StatelessWidget {
  const WeightTrendCard({
    super.key,
    required this.points,
    this.title = 'Evolução do peso',
    this.showLegend = true,
    this.height = 240,
    this.collapseSameDay = true, // <— NOVO
  });

  final List<WeightPoint> points;
  final String title;
  final bool showLegend;
  final double height;
  final bool collapseSameDay; // <— NOVO

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 1) ordena por data/hora
    final sorted = [...points]..sort((a, b) => a.date.compareTo(b.date));

    // 2) (opcional) colapsa para “último do dia”
    final data = collapseSameDay ? _collapseLastOfDay(sorted) : sorted;

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
              child: data.isEmpty
                  ? Center(
                      child: Text(
                        'Sem registos ainda',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: .7),
                          fontSize: 13,
                        ),
                      ),
                    )
                  : _Chart(points: data, cs: cs),
            ),
            if (showLegend && data.isNotEmpty) ...[
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

  /// Agrupa por YYYY-MM-DD e devolve o **último** ponto desse dia (por hora).
  List<WeightPoint> _collapseLastOfDay(List<WeightPoint> pts) {
    final byDay = <String, WeightPoint>{};
    for (final p in pts) {
      final isoDay =
          '${p.date.toUtc().year.toString().padLeft(4, '0')}-'
          '${p.date.toUtc().month.toString().padLeft(2, '0')}-'
          '${p.date.toUtc().day.toString().padLeft(2, '0')}';
      // como está ordenado crescente, cada overwrite mantém o "último" do dia
      byDay[isoDay] = p;
    }
    final keys = byDay.keys.toList()..sort(); // YYYY-MM-DD ordena lexicograficamente
    return [for (final k in keys) byDay[k]!];
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.points, required this.cs});
  final List<WeightPoint> points;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final minY = points.map((e) => e.weightKg).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((e) => e.weightKg).reduce((a, b) => a > b ? a : b);
    final margin = ((maxY - minY).abs() * 0.06).clamp(0.6, 2.0);

    return LineChart(
      LineChartData(
        minY: minY - margin,
        maxY: maxY + margin,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: cs.outline.withValues(alpha: .22), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
              interval: (points.length / 5).clamp(1, 999).toDouble(),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
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
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            tooltipBgColor: cs.surface,
            getTooltipItems: (ts) => ts.map((spot) {
              final i = spot.x.toInt();
              final p = points[i];
              final date =
                  '${p.date.day.toString().padLeft(2, '0')}/${p.date.month.toString().padLeft(2, '0')}/${p.date.year}';
              return LineTooltipItem(
                '$date\n${p.weightKg.toStringAsFixed(1)} kg',
                TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700, fontSize: 12),
              );
            }).toList(),
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
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3.5,
                color: cs.primary,
                strokeWidth: 2,
                strokeColor: cs.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [cs.primary.withValues(alpha: .25), cs.primary.withValues(alpha: .05)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            spots: points
                .asMap()
                .entries
                .map((e) => FlSpot(e.key.toDouble(), e.value.weightKg))
                .toList(),
          ),
        ],
      ),
    );
  }
}
