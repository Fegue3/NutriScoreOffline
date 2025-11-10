// lib/features/weight/weight_progress_screen.dart
// ignore_for_file: unused_element, unused_element_parameter

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';

import '../../app/di.dart';
import '../../core/widgets/weight_trend_chart.dart';
import '../../core/theme.dart' show AppColors;

/// ---------------------------------------------------------------------------
/// NutriScore — WeightProgressScreen
/// ---------------------------------------------------------------------------
/// Ecrã de **evolução do peso**:
///
/// - Lê os logs de peso do `weightRepo` via DI (`di.weightRepo`);
/// - Permite escolher intervalo (30 / 90 / 180 dias ou 1 ano);
/// - Mostra:
///   - Um gráfico de tendência (reutiliza `WeightTrendCard` do core);
///   - Métricas resumo:
///       * último peso
///       * primeiro registo
///       * variação em kg e em %
///       * média semanal (kg/semana)
///       * nº de registos no período selecionado
///
/// Requisitos de dados:
/// - `di.userRepo.currentUser()` para obter o utilizador atual;
/// - `di.weightRepo.getRange(userId, from, to)` devolve uma lista de objetos
///    que contêm pelo menos `dayIso` (YYYY-MM-DD) e `kg`.
///
/// O ecrã também permite “pull to refresh” (via refresh no AppBar) e mostra
/// mensagens de erro básicas quando algo falha.
/// ---------------------------------------------------------------------------

class WeightProgressScreen extends StatefulWidget {
  const WeightProgressScreen({super.key});

  @override
  State<WeightProgressScreen> createState() => _WeightProgressScreenState();
}

/// Intervalos pré-definidos de dias para o histórico do gráfico.
enum _Range { d30, d90, d180, d365 }

extension on _Range {
  /// Nº de dias que cada intervalo cobre.
  int get days {
    switch (this) {
      case _Range.d30:
        return 30;
      case _Range.d90:
        return 90;
      case _Range.d180:
        return 180;
      case _Range.d365:
        return 365;
    }
  }

  /// Rótulo curto para mostrar nos chips de filtro.
  String get label {
    switch (this) {
      case _Range.d30:
        return '30d';
      case _Range.d90:
        return '90d';
      case _Range.d180:
        return '6m';
      case _Range.d365:
        return '1 ano';
    }
  }
}

/// Ponto de dados de peso na UI.
class _Point {
  final DateTime d;
  final double kg;
  _Point(this.d, this.kg);
}

class _WeightProgressScreenState extends State<WeightProgressScreen> {
  bool _loading = true;
  String? _error;
  _Range _range = _Range.d90;

  List<_Point> _points = [];
  DateTime? _from;
  DateTime? _to;

  // Métricas calculadas
  double? _latest;
  double? _start;
  double? _deltaKg;
  double? _deltaPct;
  double? _perWeek;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  /// Carrega os logs de peso do intervalo atual e calcula as métricas de resumo.
  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final u = await di.userRepo.currentUser();
      if (u == null) {
        throw Exception('Sem sessão local.');
      }

      // Data canónica de hoje em UTC (00:00)
      final now = DateTime.now().toUtc();
      final today = DateTime.utc(now.year, now.month, now.day);
      final from = today.subtract(Duration(days: _range.days));

      final list = await di.weightRepo.getRange(u.id, from, today);

      // Mapear para pontos da UI e ordenar por data
      _points = list
          .map((e) {
            final d = DateTime.parse('${e.dayIso}T00:00:00Z');
            return _Point(d, e.kg);
          })
          .toList()
        ..sort((a, b) => a.d.compareTo(b.d));

      _from = from;
      _to = today;
      _count = _points.length;

      if (_points.isNotEmpty) {
        _latest = _points.last.kg;
        _start = _points.first.kg;
        _deltaKg = _latest! - _start!;
        _deltaPct = _start == 0 ? 0 : (_deltaKg! / _start!) * 100;

        final days = (_to!.difference(_from!).inDays).clamp(1, 99999);
        _perWeek = _deltaKg! / days * 7;
      } else {
        _latest = _start = _deltaKg = _deltaPct = _perWeek = null;
      }
    } catch (e) {
      _error = 'Falha ao carregar o histórico: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Atualiza o intervalo e recarrega os dados.
  void _setRange(_Range r) {
    if (_range == r) return;
    setState(() => _range = r);
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppColors.softOffWhite,
      appBar: AppBar(
        backgroundColor: AppColors.freshGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Evolução do peso',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _fetch,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            // ===== Filtro de intervalo (30d / 90d / 6m / 1 ano) =====
            Center(
              child: _RangeChips(value: _range, onChanged: _setRange),
            ),
            const SizedBox(height: 16),

            // ===== Card do gráfico principal =====
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_error != null)
              Card(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              )
            else
              WeightTrendCard(
                points: _points
                    .map(
                      (p) => WeightPoint(
                        date: p.d,
                        weightKg: p.kg,
                      ),
                    )
                    .toList(),
                height: 320,
                collapseSameDay: false,
              ),
            const SizedBox(height: 16),

            // ===== Métricas resumidas do período =====
            _StatsGrid(
              latest: _latest,
              start: _start,
              deltaKg: _deltaKg,
              deltaPct: _deltaPct,
              perWeek: _perWeek,
              count: _count,
              from: _from,
              to: _to,
            ),
            const SizedBox(height: 16),

            // Dica de interação com o gráfico
            if (!_loading && _error == null && _points.isNotEmpty)
              Text(
                'Dica: toca e arrasta no gráfico para ver valores por dia.',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: .6),
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// WIDGETS AUXILIARES
// ============================================================================

/// Chips de seleção do intervalo de dias.
class _RangeChips extends StatelessWidget {
  final _Range value;
  final ValueChanged<_Range> onChanged;
  const _RangeChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _Range.values.map((r) {
        final selected = r == value;
        return ChoiceChip(
          label: Text(r.label),
          selected: selected,
          labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.charcoal,
            fontWeight: FontWeight.w600,
          ),
          backgroundColor: Colors.white,
          selectedColor: AppColors.freshGreen,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected
                  ? AppColors.freshGreen
                  : Colors.black.withValues(alpha: .08),
            ),
          ),
          onSelected: (_) => onChanged(r),
        );
      }).toList(),
    );
  }
}

/// Card alternativo de gráfico (não usado diretamente, mas mantido como
/// exemplo isolado de fl_chart com linha).
class _ChartCard extends StatelessWidget {
  final bool loading;
  final String? error;
  final List<_Point> points;
  final double height;

  const _ChartCard({
    required this.loading,
    required this.error,
    required this.points,
    this.height = 320,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outline.withValues(alpha: .12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: height,
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : (error != null)
                  ? Center(
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: .7),
                          fontSize: 13,
                        ),
                      ),
                    )
                  : (points.isEmpty
                      ? Center(
                          child: Text(
                            'Sem registos ainda',
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: .7),
                              fontSize: 13,
                            ),
                          ),
                        )
                      : _LineChart(points: points)),
        ),
      ),
    );
  }
}

/// Implementação pura de `fl_chart` para uma linha de tendência de peso.
///
/// (Atualmente não usada diretamente porque a app usa `WeightTrendCard`, mas
/// pode servir de fallback ou exemplo futuro.)
class _LineChart extends StatelessWidget {
  final List<_Point> points;
  const _LineChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final minY =
        points.map((e) => e.kg).reduce((a, b) => a < b ? a : b).toDouble();
    final maxY =
        points.map((e) => e.kg).reduce((a, b) => a > b ? a : b).toDouble();
    final margin = ((maxY - minY).abs() * 0.06).clamp(0.6, 2.0);

    return LineChart(
      LineChartData(
        minY: minY - margin,
        maxY: maxY + margin,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: cs.outline.withValues(alpha: .18),
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
              interval: (points.length / 5).clamp(1, 999).toDouble(),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length) return const SizedBox();
                final d = points[i].d;
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
            tooltipBgColor: Colors.white,
            getTooltipItems: (spots) => spots.map((s) {
              final i = s.x.toInt();
              final p = points[i];
              final date =
                  '${p.d.day.toString().padLeft(2, '0')}/${p.d.month.toString().padLeft(2, '0')}/${p.d.year}';
              return LineTooltipItem(
                '$date\n${p.kg.toStringAsFixed(1)} kg',
                TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            barWidth: 3,
            color: AppColors.freshGreen,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3.5,
                color: AppColors.freshGreen,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  AppColors.freshGreen.withValues(alpha: .25),
                  AppColors.freshGreen.withValues(alpha: .05),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            spots: points
                .asMap()
                .entries
                .map((e) => FlSpot(e.key.toDouble(), e.value.kg))
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// Grelha de métricas resumo do período de peso selecionado.
class _StatsGrid extends StatelessWidget {
  final double? latest, start, deltaKg, deltaPct, perWeek;
  final int count;
  final DateTime? from, to;

  const _StatsGrid({
    required this.latest,
    required this.start,
    required this.deltaKg,
    required this.deltaPct,
    required this.perWeek,
    required this.count,
    required this.from,
    required this.to,
  });

  Color _deltaColor() {
    if (deltaKg == null) return AppColors.coolGray;
    // Não assumimos objetivo (perder/ganhar); só destacamos em verde
    // quando |delta| > 0.1 kg.
    return (deltaKg!.abs() > 0.1) ? AppColors.freshGreen : AppColors.coolGray;
  }

  IconData _trendIcon() {
    if (deltaKg == null) return Icons.remove_rounded;
    if (deltaKg! > 0) return Icons.trending_up_rounded;
    if (deltaKg! < 0) return Icons.trending_down_rounded;
    return Icons.remove_rounded;
  }

  String _fmt(double? v, {int dec = 1, String suffix = ''}) {
    if (v == null) return '—';
    return '${v.toStringAsFixed(dec)}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final rangeStr = (from != null && to != null)
        ? '${from!.day.toString().padLeft(2, '0')}/${from!.month.toString().padLeft(2, '0')} – '
          '${to!.day.toString().padLeft(2, '0')}/${to!.month.toString().padLeft(2, '0')}'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rangeStr.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Período: $rangeStr',
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF666666)),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Último peso',
                value: _fmt(latest, suffix: ' kg'),
                icon: Icons.monitor_weight_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'Primeiro registo',
                value: _fmt(start, suffix: ' kg'),
                icon: Icons.flag_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Variação',
                value:
                    '${_fmt(deltaKg, suffix: ' kg')}  (${_fmt(deltaPct, dec: 1, suffix: '%')})',
                icon: _trendIcon(),
                valueColor: _deltaColor(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'Média semanal',
                value: _fmt(perWeek, suffix: ' kg/sem'),
                icon: Icons.calendar_view_week_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _MetricCard(
          title: 'Registos no período',
          value: '$count',
          icon: Icons.timeline_rounded,
          wide: true,
        ),
      ],
    );
  }
}

/// Card compacto para uma métrica (título + valor + ícone).
class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final bool wide;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    this.valueColor,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.lightSage,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0x1A4CAF6D), // FreshGreen com opacidade
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.freshGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    ' ',
                    style: TextStyle(fontSize: 0), // spacing fix mínimo
                  ),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: valueColor ?? AppColors.charcoal,
                    ),
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
