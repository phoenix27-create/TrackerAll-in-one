import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

// ---------------------------------------------------------------------------
// Payment methods (Myanmar wallets + banks)
// ---------------------------------------------------------------------------

class PaymentMethod {
  const PaymentMethod(this.id, this.label, this.baseColor, this.icon);
  final String id;
  final String label;
  final Color baseColor;
  final IconData icon;

  /// Brand colour, lifted in dark mode so dark brands stay visible.
  Color get color => liftForDark(baseColor);

  static const all = <PaymentMethod>[
    PaymentMethod('cash', 'Cash', Color(0xFF22B573), Icons.payments_rounded),
    PaymentMethod(
      'kbzpay',
      'KBZPay',
      Color(0xFF0B4EA2),
      Icons.account_balance_wallet_rounded,
    ),
    PaymentMethod(
      'cbpay',
      'CB Pay',
      Color(0xFFE21B23),
      Icons.account_balance_wallet_rounded,
    ),
    PaymentMethod(
      'yomapay',
      'Yoma Pay',
      Color(0xFF00A3AD),
      Icons.account_balance_wallet_rounded,
    ),
    PaymentMethod(
      'wavepay',
      'WavePay',
      Color(0xFFFFC20E),
      Icons.account_balance_wallet_rounded,
    ),
    PaymentMethod(
      'ayapay',
      'AYA Pay',
      Color(0xFFC8102E),
      Icons.account_balance_wallet_rounded,
    ),
    PaymentMethod(
      'uabpay',
      'UAB Pay',
      Color(0xFF00843D),
      Icons.account_balance_wallet_rounded,
    ),
    PaymentMethod(
      'onepay',
      'OnePay',
      Color(0xFF1E88E5),
      Icons.account_balance_wallet_rounded,
    ),
    PaymentMethod(
      'mytelpay',
      'MyTel Pay',
      Color(0xFFF7931E),
      Icons.account_balance_wallet_rounded,
    ),
    PaymentMethod(
      'mpu',
      'MPU / Debit Card',
      Color(0xFF3949AB),
      Icons.credit_card_rounded,
    ),
    PaymentMethod(
      'visa',
      'Visa / Master',
      Color(0xFF1A1F71),
      Icons.credit_card_rounded,
    ),
    PaymentMethod(
      'bank',
      'Bank Transfer',
      Color(0xFF546E7A),
      Icons.account_balance_rounded,
    ),
    PaymentMethod(
      'other',
      'Other',
      Color(0xFF8E8EA9),
      Icons.more_horiz_rounded,
    ),
  ];

  static PaymentMethod byId(String? id) =>
      all.firstWhere((m) => m.id == id, orElse: () => all.last);
}

// ---------------------------------------------------------------------------
// Expense categories
// ---------------------------------------------------------------------------

class ExpenseCategory {
  const ExpenseCategory(this.id, this.label, this.icon, this.baseColor);
  final String id;
  final String label;
  final IconData icon;
  final Color baseColor;

  Color get color => liftForDark(baseColor);

  static const all = <ExpenseCategory>[
    ExpenseCategory(
      'food',
      'Food & Drinks',
      Icons.restaurant_rounded,
      Color(0xFFFF6B35),
    ),
    ExpenseCategory(
      'shopping',
      'Shopping',
      Icons.shopping_bag_rounded,
      Color(0xFFE91E63),
    ),
    ExpenseCategory(
      'transport',
      'Transport',
      Icons.directions_car_rounded,
      Color(0xFF1E88E5),
    ),
    ExpenseCategory(
      'bills',
      'Bills & Utilities',
      Icons.receipt_long_rounded,
      Color(0xFF00897B),
    ),
    ExpenseCategory(
      'rent',
      'Rent & Home',
      Icons.home_rounded,
      Color(0xFF6D4C41),
    ),
    ExpenseCategory(
      'phone',
      'Phone & Internet',
      Icons.wifi_rounded,
      Color(0xFF5E35B1),
    ),
    ExpenseCategory(
      'health',
      'Healthcare',
      Icons.local_hospital_rounded,
      Color(0xFF7B3FF2),
    ),
    ExpenseCategory(
      'education',
      'Education',
      Icons.school_rounded,
      Color(0xFF3949AB),
    ),
    ExpenseCategory(
      'entertainment',
      'Entertainment',
      Icons.movie_rounded,
      Color(0xFFFB8C00),
    ),
    ExpenseCategory(
      'family',
      'Family & Gifts',
      Icons.card_giftcard_rounded,
      Color(0xFFD81B60),
    ),
    ExpenseCategory(
      'donation',
      'Donation',
      Icons.volunteer_activism_rounded,
      Color(0xFF43A047),
    ),
    ExpenseCategory(
      'other',
      'Other',
      Icons.category_rounded,
      Color(0xFF8E8EA9),
    ),
  ];

  static ExpenseCategory byId(String? id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all.last);
}

// ---------------------------------------------------------------------------
// Firestore documents
// ---------------------------------------------------------------------------

class Expense {
  Expense({
    required this.id,
    required this.amount,
    required this.categoryId,
    required this.paymentId,
    required this.date,
    this.note = '',
    this.addedByName,
  });

  final String id;
  final double amount;
  final String categoryId;
  final String paymentId;
  final DateTime date;
  final String note;

  /// Set when the partner added this expense (shown as "by Bob").
  final String? addedByName;

  ExpenseCategory get category => ExpenseCategory.byId(categoryId);
  PaymentMethod get payment => PaymentMethod.byId(paymentId);

  factory Expense.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Expense(
      id: d.id,
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      categoryId: m['category'] as String? ?? 'other',
      paymentId: m['payment'] as String? ?? 'cash',
      date: (m['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      note: m['note'] as String? ?? '',
      addedByName: m['addedByName'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'amount': amount,
    'category': categoryId,
    'payment': paymentId,
    'date': Timestamp.fromDate(date),
    'note': note,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class Salary {
  Salary({
    required this.id,
    required this.amount,
    required this.source,
    required this.date,
    this.paymentId = 'bank',
  });

  final String id;
  final double amount;
  final String source;
  final DateTime date;
  final String paymentId;

  PaymentMethod get payment => PaymentMethod.byId(paymentId);

  factory Salary.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Salary(
      id: d.id,
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      source: m['source'] as String? ?? 'Salary',
      date: (m['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      paymentId: m['payment'] as String? ?? 'bank',
    );
  }

  Map<String, dynamic> toMap() => {
    'amount': amount,
    'source': source,
    'date': Timestamp.fromDate(date),
    'payment': paymentId,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// Per-month settings stored at users/{uid}/months/{yyyy-MM}.
class MonthSettings {
  const MonthSettings({this.customKeep, this.keepPercent = 20});

  /// Amount the user explicitly wants to keep (null = use auto suggestion).
  final double? customKeep;

  /// Percentage of salary used for the automatic keep suggestion.
  final double keepPercent;

  factory MonthSettings.fromMap(Map<String, dynamic>? m) => MonthSettings(
    customKeep: (m?['keepAmount'] as num?)?.toDouble(),
    keepPercent: (m?['keepPercent'] as num?)?.toDouble() ?? 20,
  );
}

enum BudgetStatus { noSalary, healthy, warning, danger }

/// All the numbers the expense screens need for one month.
class MonthSummary {
  MonthSummary({
    required this.month,
    required this.salaries,
    required this.expenses,
    required this.settings,
  });

  final DateTime month;
  final List<Salary> salaries;
  final List<Expense> expenses;
  final MonthSettings settings;

  double get totalSalary => salaries.fold(0, (s, e) => s + e.amount);
  double get totalExpense => expenses.fold(0, (s, e) => s + e.amount);

  /// Salary minus expense (what is left in hand).
  double get remaining => totalSalary - totalExpense;

  /// Auto suggestion: keepPercent of salary (default 20% – the 50/30/20 rule).
  double get suggestedKeep => totalSalary * settings.keepPercent / 100;

  bool get isCustomKeep => settings.customKeep != null;

  /// The amount the user should keep this month.
  double get keepAmount => settings.customKeep ?? suggestedKeep;

  /// Money that can still be spent without touching the keep amount.
  double get safeToSpend => remaining - keepAmount;

  /// Total spendable budget for the month (salary minus keep).
  double get spendableBudget => totalSalary - keepAmount;

  double get spentRatio => totalSalary <= 0
      ? 0
      : (totalExpense / totalSalary).clamp(0, 1).toDouble();

  int get daysLeft {
    final now = DateTime.now();
    final last = DateTime(month.year, month.month + 1, 0);
    if (now.isAfter(last)) return 0;
    if (now.isBefore(month)) return last.day;
    return last.day - now.day + 1;
  }

  /// How much can be spent per day for the rest of the month.
  double get dailyAllowance =>
      daysLeft <= 0 || safeToSpend <= 0 ? 0 : safeToSpend / daysLeft;

  BudgetStatus get status {
    if (totalSalary <= 0) return BudgetStatus.noSalary;
    if (remaining < keepAmount) return BudgetStatus.danger;
    // Warning when 80% of the spendable budget is used.
    if (spendableBudget > 0 && totalExpense >= spendableBudget * 0.8) {
      return BudgetStatus.warning;
    }
    return BudgetStatus.healthy;
  }

  Map<String, double> get byCategory {
    final map = <String, double>{};
    for (final e in expenses) {
      map[e.categoryId] = (map[e.categoryId] ?? 0) + e.amount;
    }
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  Map<String, double> get byPayment {
    final map = <String, double>{};
    for (final e in expenses) {
      map[e.paymentId] = (map[e.paymentId] ?? 0) + e.amount;
    }
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  /// Expense total per day of month (index 0 = day 1).
  List<double> get dailyTotals {
    final days = DateTime(month.year, month.month + 1, 0).day;
    final list = List<double>.filled(days, 0);
    for (final e in expenses) {
      list[e.date.day - 1] += e.amount;
    }
    return list;
  }
}
