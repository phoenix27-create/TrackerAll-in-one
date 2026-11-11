import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import 'models.dart';

enum _Range {
  w1('1W', 7),
  w2('2W', 14),
  m1('1M', 31);

  const _Range(this.label, this.days);
  final String label;
  final int days;
}

/// Smooth area line of daily spending (stock-chart style): hero total with
/// a vs-limit badge, 1W / 2W / 1M range chips, a dashed daily-limit line,
/// red dots on over-limit days, and a crosshair tooltip on touch.
class DailySpendingChart extends StatefulWidget {
  const DailySpendingChart({super.key, required this.s});
  final MonthSummary s;

  @override
  State<DailySpendingChart> createState() => _DailyChartState();
}

class _DailyChartState extends State<DailySpendingChart> {
  _Range _range = _Range.m1;

  static Color get _line => AppColors.orange;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final daily = s.dailyTotals;
    final now = DateTime.now();
    final isCurrent = s.month.year == now.year && s.month.month == now.month;
    // Last day to show: today for this month, else the month's last day.
    // (or later, if something is already logged on a future date).
    var lastSpend = 0;
    for (var i = 0; i < daily.length; i++) {
      if (daily[i] > 0) lastSpend = i + 1;
    }
    final lastDay = isCurrent ? math.max(now.day, lastSpend) : daily.length;
    final firstDay = _range == _Range.m1
        ? 1
        : math.max(1, lastDay - _range.days + 1);
    final days = [for (var d = firstDay; d <= lastDay; d++) d];
    final values = [for (final d in days) daily[d - 1]];

    final limit = s.spendableBudget > 0
        ? s.spendableBudget / daily.length
        : 0.0;
    final total = values.fold<double>(0, (a, b) => a + b);
    final avg = days.isEmpty ? 0.0 : total / days.length;
    final overDays = limit > 0 ? values.where((v) => v > limit).length : 0;
    final maxY = math.max(values.fold<double>(0, math.max), limit);
    final top = maxY <= 0 ? 1.0 : maxY * 1.35;

    // Badge: average per day vs the ideal daily limit.
    final diffPct = limit > 0 ? (avg - limit) / limit * 100 : null;
    final over = (diffPct ?? 0) > 0;

    final labelEvery = switch (days.length) {
      <= 7 => 1,
      <= 14 => 2,
      _ => 5,
    };

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------------------------------------------- hero + badge --
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mmk(total),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Avg ${mmk(avg)} / day · ${days.length} day${days.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (diffPct != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: (over ? AppColors.red : AppColors.green).withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        over
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 14,
                        color: over ? AppColors.red : AppColors.green,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${diffPct.abs().toStringAsFixed(diffPct.abs() < 10 ? 1 : 0)}% '
                        '${over ? 'over' : 'under'} limit',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: over ? AppColors.red : AppColors.green,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // ------------------------------------------------ range chips --
          Row(
            children: [
              for (final r in _Range.values) ...[
                _RangeChip(
                  label: r.label,
                  selected: r == _range,
                  onTap: () => setState(() => _range = r),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 14),
          // ------------------------------------------------------ chart --
          SizedBox(
            height: 190,
            child: LineChart(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              LineChartData(
                minX: days.length == 1
                    ? days.first - 1.0
                    : days.first.toDouble(),
                maxX: days.length == 1
                    ? days.first + 1.0
                    : days.last.toDouble(),
                minY: 0,
                maxY: top,
                clipData: const FlClipData.all(),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: top / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.border.withValues(alpha: 0.7),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (limit > 0)
                      HorizontalLine(
                        y: limit,
                        color: AppColors.muted.withValues(alpha: 0.8),
                        strokeWidth: 1.2,
                        dashArray: [5, 4],
                      ),
                  ],
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  leftTitles: const AxisTitles(),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: top / 4,
                      getTitlesWidget: (v, meta) => v == meta.max
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                compact(v),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 1,
                      getTitlesWidget: (v, meta) {
                        final d = v.round();
                        if (v != d || (d - days.first) % labelEvery != 0) {
                          return const SizedBox.shrink();
                        }
                        final date = DateTime(s.month.year, s.month.month, d);
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            days.length <= 7 ? _weekday(date) : '$d',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.muted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  getTouchedSpotIndicator: (bar, indexes) => [
                    for (final _ in indexes)
                      TouchedSpotIndicatorData(
                        FlLine(
                          color: _line.withValues(alpha: 0.5),
                          strokeWidth: 1.2,
                          dashArray: [4, 3],
                        ),
                        FlDotData(
                          getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                            radius: 5,
                            color: _line,
                            strokeWidth: 2.5,
                            strokeColor: AppColors.card,
                          ),
                        ),
                      ),
                  ],
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.navy,
                    tooltipBorderRadius: BorderRadius.circular(12),
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    maxContentWidth: 230,
                    getTooltipItems: (spots) => [
                      for (final sp in spots) _tooltip(sp, daily, limit),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < days.length; i++)
                        FlSpot(days[i].toDouble(), values[i]),
                    ],
                    isCurved: true,
                    curveSmoothness: 0.3,
                    preventCurveOverShooting: true,
                    color: _line,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    // Mark only the days over the limit.
                    dotData: FlDotData(
                      show: limit > 0,
                      checkToShowDot: (spot, _) => spot.y > limit,
                      getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                        radius: 4,
                        color: AppColors.red,
                        strokeWidth: 2,
                        strokeColor: AppColors.card,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _line.withValues(alpha: 0.32),
                          _line.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Legend (the limit label lives here so it never hits the line).
          Wrap(
            spacing: 14,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (limit > 0)
                _LegendItem(
                  mark: const _DashMark(),
                  text: 'Daily limit ${mmk(limit)}',
                ),
              if (overDays > 0)
                _LegendItem(
                  mark: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  text: 'Over limit ($overDays day${overDays == 1 ? '' : 's'})',
                ),
            ],
          ),
        ],
      ),
    );
  }

  LineTooltipItem _tooltip(LineBarSpot sp, List<double> daily, double limit) {
    final d = sp.x.round();
    final date = DateTime(widget.s.month.year, widget.s.month.month, d);
    final prev = d >= 2 ? daily[d - 2] : null;
    String change = '';
    Color changeColor = Colors.white70;
    if (prev != null) {
      final diff = sp.y - prev;
      if (prev > 0) {
        final pct = diff / prev * 100;
        change =
            '${diff >= 0 ? '+' : '−'}${compact(diff.abs())} '
            '(${pct >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(pct.abs() < 10 ? 1 : 0)}%) vs prev day';
      } else {
        change = diff > 0
            ? '+${compact(diff)} vs prev day'
            : 'Same as prev day';
      }
      changeColor = diff > 0
          ? const Color(0xFFFF8A80)
          : diff < 0
          ? const Color(0xFF69F0AE)
          : Colors.white70;
    }
    return LineTooltipItem(
      '${dayLabel(date)}\n',
      const TextStyle(
        color: Colors.white70,
        fontSize: 10.5,
        fontWeight: FontWeight.w500,
      ),
      textAlign: TextAlign.left,
      children: [
        TextSpan(
          text: mmk(sp.y),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (limit > 0 && sp.y > limit)
          const TextSpan(
            text: '  over limit',
            style: TextStyle(
              color: Color(0xFFFF8A80),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (change.isNotEmpty)
          TextSpan(
            text: '\n$change',
            style: TextStyle(
              color: changeColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  static String _weekday(DateTime d) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.mark, required this.text});
  final Widget mark;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      mark,
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
    ],
  );
}

class _DashMark extends StatelessWidget {
  const _DashMark();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 3; i++)
        Container(
          width: 4,
          height: 1.6,
          margin: const EdgeInsets.only(right: 2),
          color: AppColors.muted,
        ),
    ],
  );
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (AppColors.isDark ? AppColors.purple : AppColors.navy)
              : AppColors.bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }
}
