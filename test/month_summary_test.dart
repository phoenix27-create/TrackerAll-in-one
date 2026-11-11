import 'package:flutter_test/flutter_test.dart';
import 'package:life_tracker/features/expense/models.dart';

Salary sal(double a) =>
    Salary(id: '', amount: a, source: 'Salary', date: DateTime(2026, 11, 1));
Expense exp(
  double a, {
  int day = 5,
  String cat = 'food',
  String pay = 'cash',
}) => Expense(
  id: '',
  amount: a,
  categoryId: cat,
  paymentId: pay,
  date: DateTime(2026, 11, day),
);

void main() {
  final month = DateTime(2026, 11);

  test('multiple salaries are combined', () {
    final s = MonthSummary(
      month: month,
      salaries: [sal(10000), sal(20000), sal(30000)],
      expenses: [],
      settings: const MonthSettings(),
    );
    expect(s.totalSalary, 60000);
    expect(s.suggestedKeep, 12000); // 20% auto
    expect(s.keepAmount, 12000);
    expect(s.status, BudgetStatus.healthy);
  });

  test(
    'custom keep amount overrides suggestion; danger when balance below keep',
    () {
      final s = MonthSummary(
        month: month,
        salaries: [sal(100000)],
        expenses: [exp(50000), exp(25000, day: 6)],
        settings: const MonthSettings(customKeep: 30000),
      );
      expect(s.totalExpense, 75000);
      expect(s.remaining, 25000);
      expect(s.keepAmount, 30000);
      expect(s.safeToSpend, -5000);
      expect(s.status, BudgetStatus.danger);
    },
  );

  test('warning at 80% of spendable budget', () {
    final s = MonthSummary(
      month: month,
      salaries: [sal(100000)],
      expenses: [exp(65000)], // spendable = 80,000; 80% = 64,000
      settings: const MonthSettings(),
    );
    expect(s.status, BudgetStatus.warning);
  });

  test('no salary status and breakdowns', () {
    final s = MonthSummary(
      month: month,
      salaries: [],
      expenses: [
        exp(1000, cat: 'food', pay: 'kbzpay'),
        exp(3000, cat: 'transport', pay: 'kbzpay'),
      ],
      settings: const MonthSettings(),
    );
    expect(s.status, BudgetStatus.noSalary);
    expect(s.byCategory.keys.first, 'transport');
    expect(s.byPayment['kbzpay'], 4000);
    expect(s.dailyTotals[4], 4000);
    expect(s.dailyTotals.length, 30);
  });
}
