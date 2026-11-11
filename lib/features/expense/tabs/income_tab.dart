import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../expense_controller.dart';
import '../forms.dart';
import '../models.dart';
import '../widgets.dart';

/// Salaries of the month (multiple allowed) + keep amount settings.
class IncomeTab extends StatelessWidget {
  const IncomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ExpenseController>();
    final s = ctrl.summary;
    if (ctrl.loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
      children: [
        MonthSwitcher(month: ctrl.month, onChanged: ctrl.setMonth),
        const SizedBox(height: 14),
        AppCard(
          padding: const EdgeInsets.all(20),
          gradient: LinearGradient(
            colors: [AppColors.purple, Color(0xFF9D6BFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total salary this month',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  mmk(s.totalSalary),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.salaries.isEmpty
                    ? 'No salary added yet'
                    : s.salaries.map((x) => money(x.amount)).join(' + '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 42,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.purple,
                    minimumSize: const Size(0, 42),
                  ),
                  onPressed: () => showSalarySheet(context, ctrl),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add salary / income'),
                ),
              ),
            ],
          ),
        ),
        const SectionHeader('Salary payments'),
        if (s.salaries.isEmpty)
          const EmptyState(
            icon: Icons.payments_outlined,
            text:
                'Add each salary you receive this month.\n'
                'e.g. 10,000 + 20,000 + 30,000 = 60,000 MMK',
          )
        else
          for (final x in s.salaries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                padding: const EdgeInsets.all(12),
                onTap: () => showSalarySheet(context, ctrl, existing: x),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.purpleLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.account_balance_rounded,
                        color: AppColors.purple,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            x.source,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              PaymentDot(method: x.payment),
                              const SizedBox(width: 5),
                              Text(
                                '${x.payment.label} • ${shortDay(x.date)}',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '+${money(x.amount)}',
                      style: TextStyle(
                        color: AppColors.green,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        SectionHeader(
          'Keep amount',
          action: 'Change',
          onAction: () => showKeepSheet(context, ctrl),
        ),
        AppCard(
          onTap: () => showKeepSheet(context, ctrl),
          child: Column(
            children: [
              _Row(
                'Mode',
                s.isCustomKeep
                    ? 'My own amount'
                    : 'Auto (${s.settings.keepPercent.round()}% of salary)',
              ),
              _Row('Suggested by system', mmk(s.suggestedKeep)),
              _Row(
                'Amount to keep',
                mmk(s.keepAmount),
                bold: true,
                color: AppColors.purple,
              ),
              Divider(height: 22, color: AppColors.border),
              _Row('Salary − expense', mmk(s.remaining)),
              _Row('Spendable budget', mmk(s.spendableBudget)),
              _Row(
                'Safe to spend now',
                mmk(s.safeToSpend),
                bold: true,
                color: s.safeToSpend < 0 ? AppColors.red : AppColors.green,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SmartTip(s: s),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    ),
  );
}

/// Plain-language advice from the numbers.
class _SmartTip extends StatelessWidget {
  const _SmartTip({required this.s});
  final MonthSummary s;

  @override
  Widget build(BuildContext context) {
    final String tip;
    switch (s.status) {
      case BudgetStatus.noSalary:
        tip =
            'Start by adding your salary. We will suggest keeping 20% '
            '(50% needs, 30% wants, 20% savings).';
      case BudgetStatus.danger:
        tip =
            'You are ${mmk(s.keepAmount - s.remaining)} below your goal. '
            'Try to avoid shopping & entertainment until next salary, or lower your keep amount.';
      case BudgetStatus.warning:
        tip =
            'You can spend about ${mmk(s.dailyAllowance)} per day for the next '
            '${s.daysLeft} days and still keep ${mmk(s.keepAmount)}.';
      case BudgetStatus.healthy:
        tip =
            'Great job! Spend up to ${mmk(s.dailyAllowance)} per day and you will '
            'finish the month with at least ${mmk(s.keepAmount)}.';
    }
    return AppCard(
      color: AppColors.orangeLight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_rounded, color: AppColors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tip,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
