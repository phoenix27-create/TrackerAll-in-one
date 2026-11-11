import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../expense_controller.dart';
import '../forms.dart';
import '../models.dart';
import '../widgets.dart';

class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key, required this.onOpenTab});
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ExpenseController>();
    final s = ctrl.summary;
    if (ctrl.loading) return const Center(child: CircularProgressIndicator());

    final recent = s.expenses.take(6).toList();
    final topCats = s.byCategory.entries.take(4).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
      children: [
        MonthSwitcher(month: ctrl.month, onChanged: ctrl.setMonth),
        const SizedBox(height: 14),
        BalanceCard(s: s),
        BudgetAlertBanner(
          s: s,
          onTap: () => s.status == BudgetStatus.noSalary
              ? showSalarySheet(context, ctrl)
              : onOpenTab(2),
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
                footer:
                    '${s.salaries.length} payment${s.salaries.length == 1 ? '' : 's'}',
                onTap: () => onOpenTab(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TotalCard(
                title: 'Total Expense',
                amount: s.totalExpense,
                color: AppColors.orange,
                icon: Icons.receipt_long_rounded,
                footer:
                    '${s.expenses.length} transaction${s.expenses.length == 1 ? '' : 's'}',
                onTap: () => onOpenTab(1),
              ),
            ),
          ],
        ),
        SectionHeader(
          'Keep goal',
          action: 'Edit',
          onAction: () => showKeepSheet(context, ctrl),
        ),
        _KeepProgressCard(s: s, onTap: () => showKeepSheet(context, ctrl)),
        if (topCats.isNotEmpty) ...[
          SectionHeader(
            'Top spending',
            action: 'View all',
            onAction: () => onOpenTab(2),
          ),
          AppCard(
            child: Column(
              children: [
                for (final e in topCats)
                  _CategoryBar(
                    c: ExpenseCategory.byId(e.key),
                    amount: e.value,
                    total: s.totalExpense,
                  ),
              ],
            ),
          ),
        ],
        SectionHeader(
          'Recent transactions',
          action: 'View all',
          onAction: () => onOpenTab(1),
        ),
        if (recent.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            text: 'No expenses yet this month.\nTap + to add your first one.',
          )
        else
          for (final e in recent)
            ExpenseTile(
              e: e,
              onTap: () => showExpenseSheet(context, ctrl, existing: e),
            ),
      ],
    );
  }
}

/// "You have spent X this month" + split bar (like the 75.78% / 24.22% bar).
class _KeepProgressCard extends StatelessWidget {
  const _KeepProgressCard({required this.s, this.onTap});
  final MonthSummary s;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final total = s.totalSalary;
    final spentPct = total <= 0
        ? 0.0
        : (s.totalExpense / total * 100).clamp(0, 100).toDouble();
    final keepPct = total <= 0
        ? 0.0
        : (s.keepAmount / total * 100).clamp(0, 100).toDouble();
    final keptSoFar = s.remaining.clamp(0, double.infinity);
    final goalProgress = s.keepAmount <= 0
        ? 1.0
        : (keptSoFar / s.keepAmount).clamp(0, 1).toDouble();

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'You want to keep '),
                      TextSpan(
                        text: mmk(s.keepAmount),
                        style: TextStyle(
                          color: AppColors.purple,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: s.isCustomKeep
                            ? ' (your amount)'
                            : ' (auto ${s.settings.keepPercent.round()}%)',
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Split bar: spent | free | keep
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 30,
              child: Row(
                children: [
                  if (spentPct > 0)
                    Expanded(
                      flex: (spentPct * 10).round().clamp(1, 1000),
                      child: Container(
                        color: AppColors.orange,
                        alignment: Alignment.center,
                        child: spentPct > 14
                            ? Text(
                                '${spentPct.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : null,
                      ),
                    ),
                  if (100 - spentPct - keepPct > 0)
                    Expanded(
                      flex: ((100 - spentPct - keepPct) * 10).round().clamp(
                        1,
                        1000,
                      ),
                      child: Container(color: AppColors.bg),
                    ),
                  if (keepPct > 0)
                    Expanded(
                      flex: (keepPct * 10).round().clamp(1, 1000),
                      child: Container(
                        color: s.status == BudgetStatus.danger
                            ? AppColors.red
                            : AppColors.purple,
                        alignment: Alignment.center,
                        child: keepPct > 14
                            ? Text(
                                '${keepPct.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : null,
                      ),
                    ),
                  if (total <= 0)
                    Expanded(child: Container(color: AppColors.bg)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Legend(color: AppColors.orange, text: 'Spent'),
              SizedBox(width: 14),
              _Legend(color: AppColors.bg, text: 'Free to spend'),
              SizedBox(width: 14),
              _Legend(color: AppColors.purple, text: 'Keep'),
            ],
          ),
          Divider(height: 24, color: AppColors.border),
          Row(
            children: [
              Expanded(
                child: Text(
                  s.status == BudgetStatus.danger
                      ? 'Goal broken – only ${mmk(keptSoFar)} left'
                      : 'Goal is safe – ${(goalProgress * 100).round()}% protected',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: s.status == BudgetStatus.danger
                        ? AppColors.red
                        : AppColors.green,
                  ),
                ),
              ),
              Text(
                '${s.daysLeft} days left',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: AppColors.border),
        ),
      ),
      const SizedBox(width: 5),
      Text(text, style: TextStyle(fontSize: 11, color: AppColors.muted)),
    ],
  );
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.c,
    required this.amount,
    required this.total,
  });
  final ExpenseCategory c;
  final double amount;
  final double total;

  @override
  Widget build(BuildContext context) {
    final pct = total <= 0 ? 0.0 : amount / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(c.icon, color: c.color, size: 20),
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
                        c.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      mmk(amount),
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
                    valueColor: AlwaysStoppedAnimation(c.color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 40,
            child: Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
