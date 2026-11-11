import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/format.dart';
import '../../services/notification_service.dart';
import '../../services/partner_service.dart';
import '../../services/reminder_service.dart';
import 'expense_repository.dart';
import 'models.dart';

/// Holds the selected month and live data for it.
class ExpenseController extends ChangeNotifier {
  ExpenseController(this.repo, {this.partnerView = false, this.ownerName}) {
    _subscribe();
  }

  final ExpenseRepository repo;

  /// true when the signed-in user is managing their PARTNER's tracker.
  /// Everything works the same: add, edit, delete, keep amount, alerts.
  final bool partnerView;
  final String? ownerName;

  DateTime _month = monthStart(DateTime.now());
  DateTime get month => _month;

  List<Salary> _salaries = [];
  List<Expense> _expenses = [];
  MonthSettings _settings = const MonthSettings();
  bool _loadedSalaries = false, _loadedExpenses = false;
  Object? error;

  bool get loading => !_loadedSalaries || !_loadedExpenses;

  MonthSummary get summary => MonthSummary(
    month: _month,
    salaries: _salaries,
    expenses: _expenses,
    settings: _settings,
  );

  final _subs = <StreamSubscription>[];

  void setMonth(DateTime m) {
    final next = monthStart(m);
    if (next == _month) return;
    _month = next;
    _loadedSalaries = _loadedExpenses = false;
    _salaries = [];
    _expenses = [];
    _settings = const MonthSettings();
    notifyListeners();
    _subscribe();
  }

  void _subscribe() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final from = _month, to = nextMonth(_month);
    _subs.add(
      repo.salariesBetween(from, to).listen((v) {
        _salaries = v;
        _loadedSalaries = true;
        notifyListeners();
      }, onError: _onError),
    );
    _subs.add(
      repo.expensesBetween(from, to).listen((v) {
        _expenses = v;
        _loadedExpenses = true;
        notifyListeners();
      }, onError: _onError),
    );
    _subs.add(
      repo.monthSettings(_month).listen((v) {
        _settings = v;
        notifyListeners();
      }, onError: _onError),
    );
  }

  void _onError(Object e) {
    error = e;
    _loadedSalaries = _loadedExpenses = true;
    notifyListeners();
  }

  /// Saves an expense and returns the resulting status for the expense's month.
  /// Sends a device notification when the keep amount is broken.
  Future<BudgetStatus> saveExpense(Expense e) async {
    final isNew = e.id.isEmpty;
    final me = await _me();
    await repo.saveExpense(
      e,
      extra: partnerView
          ? {'addedBy': me.uid, 'addedByName': me.name}
          : const {},
    );
    // Logged something today -> stop today's "no expense" reminders.
    // (The owner's own device re-syncs when they open the app.)
    if (!partnerView) unawaited(ReminderService.instance.sync(repo.uid));
    final status = await _checkAfterChange(
      e.date,
      editedId: e.id,
      newAmount: e.amount,
    );
    if (isNew) unawaited(_tellOther(me, e, status));
    return status;
  }

  String get _who => ownerName ?? 'Your partner';
  double _lastRemaining = 0;

  Future<BudgetStatus> _checkAfterChange(
    DateTime date, {
    required String editedId,
    required double newAmount,
  }) async {
    // Only the selected month is in memory; compute the projected summary.
    if (monthStart(date) != _month) return BudgetStatus.healthy;
    final others = _expenses.where((x) => x.id != editedId || editedId.isEmpty);
    final total = others.fold<double>(0, (s, x) => s + x.amount) + newAmount;
    final s = summary;
    final remaining = s.totalSalary - total;
    _lastRemaining = remaining;
    BudgetStatus status;
    if (s.totalSalary <= 0) {
      status = BudgetStatus.noSalary;
    } else if (remaining < s.keepAmount) {
      status = BudgetStatus.danger;
    } else if (s.spendableBudget > 0 && total >= s.spendableBudget * 0.8) {
      status = BudgetStatus.warning;
    } else {
      status = BudgetStatus.healthy;
    }

    if (status == BudgetStatus.danger) {
      await NotificationService.instance.show(
        title: partnerView
            ? "⚠️ Emergency: $_who's savings goal broken"
            : '⚠️ Emergency: savings goal broken',
        body:
            '${partnerView ? "$_who's" : 'Your'} balance is ${mmk(remaining)}, below the '
            'keep amount ${mmk(s.keepAmount)} for ${monthLabel(_month)}. '
            'Stop non-essential spending.',
        urgent: true,
      );
    } else if (status == BudgetStatus.warning) {
      await NotificationService.instance.show(
        title: partnerView
            ? "Heads up: 80% of $_who's budget used"
            : 'Heads up: 80% of your budget used',
        body:
            'Only ${mmk(remaining - s.keepAmount)} left to spend before touching '
            'the keep amount.',
      );
    }
    return status;
  }

  /// The signed-in user (the owner, or the partner in [partnerView]).
  Future<_Me> _me() async {
    final u = FirebaseAuth.instance.currentUser;
    final uid = u?.uid ?? repo.uid;
    var name = u?.displayName ?? '';
    String? partnerId;
    try {
      final p =
          (await FirebaseFirestore.instance.collection('users').doc(uid).get())
              .data() ??
          {};
      if ((p['name'] as String?)?.trim().isNotEmpty == true) {
        name = p['name'] as String;
      }
      partnerId = p['partnerId'] as String?;
    } catch (err) {
      debugPrint('load profile failed: $err');
    }
    if (name.isEmpty) name = (u?.email ?? 'Partner').split('@').first;
    return _Me(uid, name, partnerId);
  }

  /// Tells the other person about a new expense (and the alert, if the keep
  /// amount is now broken): the owner when the partner edits their tracker,
  /// the partner when the owner adds to their own tracker.
  Future<void> _tellOther(_Me me, Expense e, BudgetStatus status) async {
    final other = partnerView ? repo.uid : me.partnerId;
    if (other == null) return;
    final svc = PartnerService.instance;
    await svc.notifyExpense(
      myUid: me.uid,
      myName: me.name,
      partnerUid: other,
      e: e,
      onYourTracker: partnerView,
    );
    if (status == BudgetStatus.danger) {
      await svc.notifyAlert(
        myUid: me.uid,
        myName: me.name,
        partnerUid: other,
        onYourTracker: partnerView,
        remaining: _lastRemaining,
        keep: summary.keepAmount,
        month: monthLabel(_month),
      );
    }
  }

  Future<void> deleteExpense(String id) async {
    await repo.deleteExpense(id);
    if (!partnerView) unawaited(ReminderService.instance.sync(repo.uid));
  }

  Future<void> saveSalary(Salary s) => repo.saveSalary(s);
  Future<void> deleteSalary(String id) => repo.deleteSalary(id);

  Future<void> setCustomKeep(double? amount) =>
      repo.setKeep(_month, customKeep: amount);

  Future<void> setKeepPercent(double percent) =>
      repo.setKeep(_month, customKeep: null, keepPercent: percent);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

class _Me {
  _Me(this.uid, this.name, this.partnerId);
  final String uid;
  final String name;
  final String? partnerId;
}
