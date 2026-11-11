import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import 'models.dart';

/// "<  November 2026  >" switcher.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({
    super.key,
    required this.month,
    required this.onChanged,
  });
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final isCurrent = monthStart(DateTime.now()) == month;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => onChanged(prevMonth(month)),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: month,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  initialDatePickerMode: DatePickerMode.year,
                  helpText: 'Pick any day in the month',
                );
                if (picked != null) onChanged(monthStart(picked));
              },
              child: Column(
                children: [
                  Text(
                    monthLabel(month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (!isCurrent)
                    Text(
                      'tap to pick • not current month',
                      style: TextStyle(fontSize: 10, color: AppColors.muted),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => onChanged(nextMonth(month)),
          ),
        ],
      ),
    );
  }
}

/// Dark card – "Remaining balance" (like the Total Balance card in the design).
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.s});
  final MonthSummary s;

  @override
  Widget build(BuildContext context) {
    final danger = s.status == BudgetStatus.danger;
    return AppCard(
      padding: const EdgeInsets.all(20),
      gradient: LinearGradient(
        colors: danger
            ? const [Color(0xFF8E1B1B), Color(0xFF4A0E0E)]
            : [AppColors.navy, AppColors.navyDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Remaining balance',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              _StatusPill(status: s.status),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              mmk(s.remaining),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: s.spentRatio,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(
                danger ? const Color(0xFFFF8A80) : AppColors.orange,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            s.totalSalary > 0
                ? '${(s.spentRatio * 100).toStringAsFixed(1)}% of salary spent'
                : 'Add your salary to start',
            style: const TextStyle(color: Colors.white60, fontSize: 11.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Mini(label: 'Keep goal', value: mmk(s.keepAmount)),
              _Mini(
                label: 'Safe to spend',
                value: mmk(s.safeToSpend < 0 ? 0 : s.safeToSpend),
              ),
              _Mini(label: 'Per day', value: mmk(s.dailyAllowance)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (status) {
      BudgetStatus.healthy => ('On track', AppColors.green),
      BudgetStatus.warning => ('Careful', AppColors.amber),
      BudgetStatus.danger => ('Emergency', AppColors.red),
      BudgetStatus.noSalary => ('No salary', AppColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Purple "Total Salary" / orange "Total Expense" cards from the design.
class TotalCard extends StatelessWidget {
  const TotalCard({
    super.key,
    required this.title,
    required this.amount,
    required this.color,
    required this.icon,
    required this.footer,
    this.onTap,
  });
  final String title;
  final double amount;
  final Color color;
  final IconData icon;
  final String footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: color,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ),
              const Icon(
                Icons.more_vert_rounded,
                color: Colors.white70,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              money(amount),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Text(
            'MMK',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  footer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Red/amber banner shown when the keep amount is broken / nearly broken.
class BudgetAlertBanner extends StatelessWidget {
  const BudgetAlertBanner({super.key, required this.s, this.onTap});
  final MonthSummary s;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (s.status == BudgetStatus.healthy) return const SizedBox.shrink();
    final (bg, fg, icon, title, body) = switch (s.status) {
      BudgetStatus.danger => (
        AppColors.redSoft,
        AppColors.red,
        Icons.warning_amber_rounded,
        'Emergency: below your keep amount',
        'You are ${mmk(s.keepAmount - s.remaining)} under your goal of '
            '${mmk(s.keepAmount)}. Pause non-essential spending.',
      ),
      BudgetStatus.warning => (
        AppColors.amberSoft,
        AppColors.amberInk,
        Icons.info_outline_rounded,
        'Careful: 80% of budget used',
        'Only ${mmk(s.safeToSpend)} left before you touch your keep amount.',
      ),
      _ => (
        AppColors.purpleLight,
        AppColors.purple,
        Icons.add_card_rounded,
        'Add your salary for ${monthLabel(s.month)}',
        'Enter every salary/income you get this month so we can plan your savings.',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: AppCard(
        color: bg,
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: TextStyle(fontSize: 12, color: AppColors.text),
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

/// A row in a transaction list.
class ExpenseTile extends StatelessWidget {
  const ExpenseTile({super.key, required this.e, this.onTap});
  final Expense e;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = e.category;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: c.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(c.icon, color: c.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.note.isNotEmpty ? e.note : c.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      PaymentDot(method: e.payment),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          (e.note.isNotEmpty
                                  ? '${e.payment.label} • ${c.label}'
                                  : e.payment.label) +
                              (e.addedByName != null
                                  ? ' • by ${e.addedByName}'
                                  : ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '-${money(e.amount)}',
                  style: TextStyle(
                    color: AppColors.red,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  shortDay(e.date),
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PaymentDot extends StatelessWidget {
  const PaymentDot({super.key, required this.method, this.size = 9});
  final PaymentMethod method;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: method.color, shape: BoxShape.circle),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.muted.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Full-screen emergency alert after an expense breaks the keep amount.
/// [ownerName] is set when it is the partner's tracker.
Future<void> showEmergencyDialog(
  BuildContext context,
  MonthSummary s, {
  String? ownerName,
}) {
  final whose = ownerName != null ? "$ownerName's" : 'Your';
  final wants = ownerName != null ? 'they want' : 'you want';
  return showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: AppColors.raised,
      icon: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.redSoft,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.warning_amber_rounded,
          color: AppColors.red,
          size: 40,
        ),
      ),
      title: Text(
        'Emergency budget alert',
        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.red),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$whose balance (${mmk(s.remaining)}) is below the amount $wants to keep '
            '(${mmk(s.keepAmount)}) for ${monthLabel(s.month)}.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Short by ${mmk(s.keepAmount - s.remaining)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.red,
            minimumSize: const Size(200, 48),
          ),
          onPressed: () => Navigator.pop(c),
          child: const Text('I understand'),
        ),
      ],
    ),
  );
}
