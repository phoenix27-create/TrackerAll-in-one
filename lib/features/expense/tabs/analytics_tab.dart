import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../expense_controller.dart';
import '../models.dart';
import '../daily_chart.dart';
import '../widgets.dart';

/// Dashboard: this month's breakdown + a 12-month salary / expense / keep view.
class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});
  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  int _year = DateTime.now().year;
  int _touchedPie = -1;

  Stream<List<Salary>>? _salaries;
  Stream<List<Expense>>? _expenses;
  Stream<Map<String, MonthSettings>>? _settings;
  int? _streamYear;

  void _ensureStreams(ExpenseController ctrl) {
    if (_streamYear == _year) return;
    _streamYear = _year;
    final from = DateTime(_year), to = DateTime(_year + 1);
    _salaries = ctrl.repo.salariesBetween(from, to);
    _expenses = ctrl.repo.expensesBetween(from, to);
    _settings ??= ctrl.repo.allMonthSettings();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ExpenseController>();
    final s = ctrl.summary;
    _ensureStreams(ctrl);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
      children: [
        MonthSwitcher(month: ctrl.month, onChanged: ctrl.setMonth),
        const SizedBox(height: 14),
        _SpendSummary(s: s),
        const SectionHeader('Spending by category'),
        if (s.expenses.isEmpty)
          const EmptyState(
            icon: Icons.pie_chart_outline_rounded,
            text: 'No expenses this month yet.',
          )
        else
          _CategoryPie(
            s: s,
            touched: _touchedPie,
            onTouch: (i) => setState(() => _touchedPie = i),
          ),
        if (s.expenses.isNotEmpty) ...[
          const SectionHeader('Daily spending'),
          DailySpendingChart(s: s),
          const SectionHeader('Payment methods'),
          _PaymentBreakdown(s: s),
        ],
        SectionHeader(
          'Yearly overview',
          action: '$_year  ▾',
          onAction: _pickYear,
        ),
        StreamBuilder<List<Salary>>(
          stream: _salaries,
          builder: (_, sal) => StreamBuilder<List<Expense>>(
            stream: _expenses,
            builder: (_, exp) => StreamBuilder<Map<String, MonthSettings>>(
              stream: _settings,
              builder: (_, set) {
                if (!sal.hasData || !exp.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final months = List.generate(12, (i) {
                  final m = DateTime(_year, i + 1);
                  return MonthSummary(
                    month: m,
                    salaries: sal.data!
                        .where((x) => x.date.month == i + 1)
                        .toList(),
                    expenses: exp.data!
                        .where((x) => x.date.month == i + 1)
                        .toList(),
                    settings: set.data?[monthKey(m)] ?? const MonthSettings(),
                  );
                });
                return Column(
                  children: [
                    _YearChart(months: months),
                    const SectionHeader('Monthly history'),
                    _YearTotals(months: months),
                    const SizedBox(height: 10),
                    for (final m in months.reversed)
                      if (m.totalSalary > 0 || m.totalExpense > 0)
                        _MonthHistoryCard(
                          m: m,
                          onTap: () => ctrl.setMonth(m.month),
                        ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickYear() async {
    final now = DateTime.now().year;
    final y = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var y = now; y >= now - 5; y--)
              ListTile(
                title: Text('$y'),
                trailing: y == _year
                    ? Icon(Icons.check, color: AppColors.purple)
                    : null,
                onTap: () => Navigator.pop(c, y),
              ),
          ],
        ),
      ),
    );
    if (y != null) setState(() => _year = y);
  }
}

// ---------------------------------------------------------------------------

class _SpendSummary extends StatelessWidget {
  const _SpendSummary({required this.s});
  final MonthSummary s;

  @override
  Widget build(BuildContext context) {
    final spentPct = s.totalSalary <= 0
        ? 0.0
        : s.totalExpense / s.totalSalary * 100;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'You have spent '),
                TextSpan(
                  text: mmk(s.totalExpense),
                  style: TextStyle(
                    color: AppColors.orange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: '\nthis month.'),
              ],
            ),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: math.max(1, spentPct.clamp(0, 100).round()),
                child: Container(
                  height: 30,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.purple,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: FittedBox(
                    child: Text(
                      '${spentPct.toStringAsFixed(2)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: math.max(1, (100 - spentPct).clamp(0, 100).round()),
                child: Container(
                  height: 30,
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    child: Text(
                      '${(100 - spentPct).clamp(0, 100).toStringAsFixed(2)}%',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'of total salary ${mmk(s.totalSalary)}',
            style: TextStyle(color: AppColors.muted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _CategoryPie extends StatelessWidget {
  const _CategoryPie({
    required this.s,
    required this.touched,
    required this.onTouch,
  });
  final MonthSummary s;
  final int touched;
  final ValueChanged<int> onTouch;

  @override
  Widget build(BuildContext context) {
    final entries = s.byCategory.entries.toList();
    final total = s.totalExpense;
    return AppCard(
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 46,
                pieTouchData: PieTouchData(
                  touchCallback: (event, resp) {
                    if (!event.isInterestedForInteractions ||
                        resp?.touchedSection == null) {
                      onTouch(-1);
                      return;
                    }
                    onTouch(resp!.touchedSection!.touchedSectionIndex);
                  },
                ),
                sections: [
                  for (var i = 0; i < entries.length; i++)
                    () {
                      final c = ExpenseCategory.byId(entries[i].key);
                      final pct = entries[i].value / total * 100;
                      final isTouched = i == touched;
                      return PieChartSectionData(
                        value: entries[i].value,
                        color: c.color,
                        radius: isTouched ? 64 : 54,
                        title: pct >= 6 ? '${pct.round()}%' : '',
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        badgeWidget: isTouched
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.navy,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  money(entries[i].value),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              )
                            : null,
                        badgePositionPercentageOffset: 1.25,
                      );
                    }(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final e in entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: ExpenseCategory.byId(e.key).color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${ExpenseCategory.byId(e.key).label} · ${compact(e.value)}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentBreakdown extends StatelessWidget {
  const _PaymentBreakdown({required this.s});
  final MonthSummary s;

  @override
  Widget build(BuildContext context) {
    final total = s.totalExpense;
    return AppCard(
      child: Column(
        children: [
          for (final e in s.byPayment.entries)
            () {
              final m = PaymentMethod.byId(e.key);
              final pct = total <= 0 ? 0.0 : e.value / total;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: m.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(m.icon, color: m.color, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  m.label,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                mmk(e.value),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 6,
                              backgroundColor: AppColors.bg,
                              valueColor: AlwaysStoppedAnimation(m.color),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }(),
        ],
      ),
    );
  }
}

class _YearChart extends StatelessWidget {
  const _YearChart({required this.months});
  final List<MonthSummary> months;

  @override
  Widget build(BuildContext context) {
    final maxY = months.fold<double>(
      0,
      (a, m) => math.max(a, math.max(m.totalSalary, m.totalExpense)),
    );
    final top = maxY <= 0 ? 1.0 : maxY * 1.15;
    final thisMonth = monthStart(DateTime.now());
    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 18, 16, 12),
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: top,
                groupsSpace: 10,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: top / 4,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: AppColors.border, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: top / 4,
                      getTitlesWidget: (v, _) => Text(
                        compact(v),
                        style: TextStyle(fontSize: 9.5, color: AppColors.muted),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, _) {
                        final m = months[v.toInt()].month;
                        final current = m == thisMonth;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            shortMonth(m).substring(0, 1),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: current
                                  ? AppColors.purple
                                  : AppColors.muted,
                              fontWeight: current
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.navy,
                    getTooltipItem: (g, _, rod, rodIndex) => BarTooltipItem(
                      '${shortMonth(months[g.x].month)} ${rodIndex == 0 ? 'salary' : 'expense'}\n${mmk(rod.toY)}',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < 12; i++)
                    BarChartGroupData(
                      x: i,
                      barsSpace: 2,
                      barRods: [
                        BarChartRodData(
                          toY: months[i].totalSalary,
                          width: 7,
                          color: AppColors.purple,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        BarChartRodData(
                          toY: months[i].totalExpense,
                          width: 7,
                          color: AppColors.orange,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Dot(color: AppColors.purple, text: 'Salary'),
              SizedBox(width: 18),
              _Dot(color: AppColors.orange, text: 'Expense'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.text});
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(fontSize: 12)),
    ],
  );
}

class _YearTotals extends StatelessWidget {
  const _YearTotals({required this.months});
  final List<MonthSummary> months;

  @override
  Widget build(BuildContext context) {
    final salary = months.fold<double>(0, (a, m) => a + m.totalSalary);
    final expense = months.fold<double>(0, (a, m) => a + m.totalExpense);
    final saved = salary - expense;
    Widget cell(String label, double v, Color c) => Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: AppColors.muted)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                compact(v),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: c,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Row(
      children: [
        cell('Year salary', salary, AppColors.purple),
        const SizedBox(width: 10),
        cell('Year expense', expense, AppColors.orange),
        const SizedBox(width: 10),
        cell('Year saved', saved, saved >= 0 ? AppColors.green : AppColors.red),
      ],
    );
  }
}

class _MonthHistoryCard extends StatelessWidget {
  const _MonthHistoryCard({required this.m, required this.onTap});
  final MonthSummary m;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metGoal = m.remaining >= m.keepAmount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    monthLabel(m.month),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (metGoal ? AppColors.green : AppColors.red)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    metGoal ? 'Goal met' : 'Goal missed',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: metGoal ? AppColors.green : AppColors.red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _HistValue('Salary', m.totalSalary, AppColors.purple),
                _HistValue('Expense', m.totalExpense, AppColors.orange),
                _HistValue('Keep', m.keepAmount, AppColors.purple),
                _HistValue(
                  'Saved',
                  m.remaining,
                  m.remaining >= 0 ? AppColors.green : AppColors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistValue extends StatelessWidget {
  const _HistValue(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10.5, color: AppColors.muted)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            compact(value),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}
