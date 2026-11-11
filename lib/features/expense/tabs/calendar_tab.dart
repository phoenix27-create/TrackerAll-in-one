import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../expense_controller.dart';
import '../forms.dart';
import '../models.dart';
import '../widgets.dart';

/// Calendar to pick a day + that day's expenses.
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key, required this.onDayChanged});
  final ValueChanged<DateTime> onDayChanged;

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  DateTime _selected = DateTime.now();
  CalendarFormat _format = CalendarFormat.week;

  void _select(DateTime d) {
    setState(() => _selected = d);
    // Midday so time zones never push it into another day.
    widget.onDayChanged(DateTime(d.year, d.month, d.day, 12));
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ExpenseController>();
    final s = ctrl.summary;
    final dayExpenses = s.expenses
        .where((e) => sameDay(e.date, _selected))
        .toList();
    final dayTotal = dayExpenses.fold<double>(0, (a, e) => a + e.amount);
    final daily = s.dailyTotals;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: TableCalendar<Expense>(
            firstDay: DateTime(2020),
            lastDay: DateTime(2100),
            focusedDay: _selected,
            calendarFormat: _format,
            availableCalendarFormats: const {
              CalendarFormat.week: 'Week',
              CalendarFormat.month: 'Month',
            },
            onFormatChanged: (f) => setState(() => _format = f),
            startingDayOfWeek: StartingDayOfWeek.monday,
            selectedDayPredicate: (d) => sameDay(d, _selected),
            onDaySelected: (d, _) {
              _select(d);
              if (monthStart(d) != ctrl.month) ctrl.setMonth(d);
            },
            onPageChanged: (focused) {
              // Keep the controller month in sync with what the calendar shows.
              if (monthStart(focused) != ctrl.month) ctrl.setMonth(focused);
              _select(focused);
            },
            eventLoader: (d) => monthStart(d) == ctrl.month
                ? s.expenses.where((e) => sameDay(e.date, d)).toList()
                : const [],
            headerStyle: HeaderStyle(
              titleCentered: true,
              titleTextStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              formatButtonDecoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              formatButtonTextStyle: const TextStyle(fontSize: 12),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(fontSize: 11, color: AppColors.muted),
              weekendStyle: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              selectedDecoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              todayDecoration: BoxDecoration(
                color: AppColors.orangeLight,
                borderRadius: BorderRadius.circular(12),
              ),
              todayTextStyle: TextStyle(
                color: AppColors.orange,
                fontWeight: FontWeight.w600,
              ),
              defaultDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              weekendDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              markerDecoration: BoxDecoration(
                color: AppColors.purple,
                shape: BoxShape.circle,
              ),
              markersMaxCount: 1,
              markerSize: 5,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TotalCard(
                title: 'Total Salary',
                amount: s.totalSalary,
                color: AppColors.purple,
                icon: Icons.account_balance_rounded,
                footer: monthLabel(ctrl.month),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TotalCard(
                title: 'Total Expense',
                amount: s.totalExpense,
                color: AppColors.orange,
                icon: Icons.receipt_long_rounded,
                footer: monthLabel(ctrl.month),
              ),
            ),
          ],
        ),
        SectionHeader(
          sameDay(_selected, DateTime.now()) ? 'Today' : dayLabel(_selected),
          action: 'Total ${mmk(dayTotal)}',
        ),
        if (s.dailyAllowance > 0 && monthStart(_selected) == ctrl.month)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AllowanceHint(
              spent: daily.isEmpty ? 0 : dayTotal,
              allowance: s.dailyAllowance,
            ),
          ),
        if (dayExpenses.isEmpty)
          EmptyState(
            icon: Icons.event_available_rounded,
            text:
                'No expenses on ${shortDay(_selected)}.\nTap + to add one for this day.',
          )
        else
          for (final e in dayExpenses)
            ExpenseTile(
              e: e,
              onTap: () => showExpenseSheet(context, ctrl, existing: e),
            ),
      ],
    );
  }
}

class _AllowanceHint extends StatelessWidget {
  const _AllowanceHint({required this.spent, required this.allowance});
  final double spent;
  final double allowance;

  @override
  Widget build(BuildContext context) {
    final over = spent > allowance;
    return AppCard(
      color: over ? AppColors.redSoft : AppColors.greenSoft,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            over ? Icons.trending_up_rounded : Icons.check_circle_rounded,
            color: over ? AppColors.red : AppColors.green,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              over
                  ? 'Over today\'s safe limit of ${mmk(allowance)}'
                  : 'Safe daily limit: ${mmk(allowance)}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
