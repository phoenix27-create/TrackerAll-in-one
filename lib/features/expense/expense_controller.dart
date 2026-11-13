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
  ///
  /// Notifications (both people get one):
  ///  * new expense -> "added" message for me, partner inbox for the other;
  ///  * spending above income, or balance below the saving goal -> alert
  ///    for both (every new expense while it stays like that);
  ///  * 80% of the budget used -> heads-up for me.
  Future<BudgetStatus> saveExpense(Expense e) async {
    final isNew = e.id.isEmpty;
    final me = await _me();
    final before = summary;
    await repo.saveExpense(
      e,
      extra: partnerView
          ? {'addedBy': me.uid, 'addedByName': me.name}
          : const {},
    );
    // Logged something today -> stop today's "no expense" reminders.
    // (The owner's own device re-syncs when they open the app.)
    if (!partnerView) unawaited(ReminderService.instance.sync(repo.uid));

    if (isNew) {
      final cat = ExpenseCategory.byId(e.categoryId).label;
      unawaited(
        _showMine(
          title: partnerView
              ? '📝 You added ${mmk(e.amount)} to $_who\'s expenses'
              : '✅ Expense added: ${mmk(e.amount)}',
          body: '$cat • ${PaymentMethod.byId(e.paymentId).label}',
        ),
      );
      unawaited(_toOther(me, (svc, other) => svc.notifyExpense(
            myUid: me.uid,
            myName: me.name,
            partnerUid: other,
            e: e,
            onYourTracker: partnerView,
          )));
    }

    // Only the selected month is in memory.
    if (monthStart(e.date) != _month) return BudgetStatus.healthy;
    // Start from the list as it was BEFORE saving: the live list may
    // already contain the new expense (Firestore updates it instantly).
    final after = _projected(
      expenses: [...before.expenses.where((x) => isNew || x.id != e.id), e],
      from: before,
    );
    await _checkBudget(me, before, after, alwaysAlert: isNew);
    return after.status;
  }

  // ---------------------------------------------------------- salary --

  Future<void> saveSalary(Salary s) async {
    final isNew = s.id.isEmpty;
    final me = await _me();
    final before = summary;
    await repo.saveSalary(s);
    if (isNew) {
      unawaited(
        _showMine(
          title: partnerView
              ? '💵 You added ${mmk(s.amount)} income to $_who\'s tracker'
              : '💵 Income added: ${mmk(s.amount)}',
          body: '${s.source} • ${s.payment.label}',
        ),
      );
      unawaited(_toOther(me, (svc, other) => svc.notifySalary(
            myUid: me.uid,
            myName: me.name,
            partnerUid: other,
            s: s,
            onYourTracker: partnerView,
          )));
    }
    if (monthStart(s.date) != _month) return;
    await _checkBudget(
      me,
      before,
      _projected(
        salaries: [...before.salaries.where((x) => isNew || x.id != s.id), s],
        from: before,
      ),
    );
  }

  Future<void> deleteSalary(String id) async {
    final me = await _me();
    final before = summary;
    await repo.deleteSalary(id);
    await _checkBudget(
      me,
      before,
      _projected(
        salaries: before.salaries.where((x) => x.id != id).toList(),
        from: before,
      ),
    );
  }

  // ------------------------------------------------------ saving goal --

  Future<void> setCustomKeep(double? amount) => _setKeep(
    MonthSettings(customKeep: amount, keepPercent: _settings.keepPercent),
    () => repo.setKeep(_month, customKeep: amount),
  );

  Future<void> setKeepPercent(double percent) => _setKeep(
    MonthSettings(keepPercent: percent),
    () => repo.setKeep(_month, customKeep: null, keepPercent: percent),
  );

  Future<void> _setKeep(MonthSettings next, Future<void> Function() save) async {
    final me = await _me();
    final before = summary;
    await save();
    final after = _projected(settings: next, from: before);
    final goal = after.keepAmount;
    final month = monthLabel(_month);
    unawaited(
      _showMine(
        title: partnerView
            ? '🎯 You set $_who\'s saving goal to ${mmk(goal)}'
            : '🎯 Saving goal set: ${mmk(goal)}',
        body: 'For $month.',
      ),
    );
    unawaited(_toOther(me, (svc, other) => svc.notifyKeep(
          myUid: me.uid,
          myName: me.name,
          partnerUid: other,
          keep: goal,
          month: month,
          onYourTracker: partnerView,
        )));
    await _checkBudget(me, before, after);
  }

  // ---------------------------------------------------------- alerts --

  String get _who => ownerName ?? 'Your partner';

  /// The month after a change: [from] (the data before saving) with the
  /// changed part replaced.
  MonthSummary _projected({
    required MonthSummary from,
    List<Salary>? salaries,
    List<Expense>? expenses,
    MonthSettings? settings,
  }) => MonthSummary(
    month: _month,
    salaries: salaries ?? from.salaries,
    expenses: expenses ?? from.expenses,
    settings: settings ?? from.settings,
  );

  /// Alerts both people when spending is above income or the balance is
  /// below the saving goal. [alwaysAlert] (new expenses): alert on every
  /// expense while it stays like that; otherwise only when it just became so.
  Future<void> _checkBudget(
    _Me me,
    MonthSummary before,
    MonthSummary after, {
    bool alwaysAlert = false,
  }) async {
    final status = after.status;
    final overIncome = after.totalSalary > 0 && after.remaining < 0;
    final wasOver = before.totalSalary > 0 && before.remaining < 0;
    final wasDanger = before.status == BudgetStatus.danger;

    if (status == BudgetStatus.danger &&
        (alwaysAlert || !wasDanger || (overIncome && !wasOver))) {
      final month = monthLabel(_month);
      final spentOf =
          'Spent ${mmk(after.totalExpense)} of ${mmk(after.totalSalary)} '
          'income for $month';
      await NotificationService.instance.show(
        title: overIncome
            ? (partnerView
                  ? '🚨 $_who spent more than their income'
                  : '🚨 You spent more than your income')
            : (partnerView
                  ? '⚠️ $_who has only ${mmk(after.remaining)} left'
                  : '⚠️ Only ${mmk(after.remaining)} left to spend'),
        body: overIncome
            ? '$spentOf (${mmk(-after.remaining)} over). '
                  'Saving goal: ${mmk(after.keepAmount)}.'
            : '$spentOf. That is below the saving goal of '
                  '${mmk(after.keepAmount)}.',
        urgent: overIncome,
      );
      unawaited(_toOther(me, (svc, other) => svc.notifyAlert(
            myUid: me.uid,
            myName: me.name,
            partnerUid: other,
            onYourTracker: partnerView,
            remaining: after.remaining,
            keep: after.keepAmount,
            income: after.totalSalary,
            spent: after.totalExpense,
            month: month,
          )));
    } else if (status == BudgetStatus.warning && alwaysAlert) {
      await NotificationService.instance.show(
        title: partnerView
            ? "Heads up: 80% of $_who's budget used"
            : 'Heads up: 80% of your budget used',
        body:
            'Only ${mmk(after.remaining - after.keepAmount)} left to spend '
            'before touching the saving goal.',
      );
    }
  }

  /// "You added …" confirmation on this device.
  Future<void> _showMine({required String title, required String body}) =>
      NotificationService.instance.show(title: title, body: body);

  /// The other person: the owner when the partner edits their tracker, the
  /// partner when the owner edits their own tracker.
  Future<void> _toOther(
    _Me me,
    Future<void> Function(PartnerService svc, String other) send,
  ) async {
    final other = partnerView ? repo.uid : me.partnerId;
    if (other == null || other == me.uid) return;
    await send(PartnerService.instance, other);
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

  Future<void> deleteExpense(String id) async {
    await repo.deleteExpense(id);
    if (!partnerView) unawaited(ReminderService.instance.sync(repo.uid));
  }

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
