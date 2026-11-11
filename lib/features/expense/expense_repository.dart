import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/format.dart';
import 'models.dart';

/// Firestore layout (all private to the signed-in user):
///   users/{uid}/salaries/{id}   amount, source, date, payment
///   users/{uid}/expenses/{id}   amount, category, payment, date, note
///   users/{uid}/months/{yyyy-MM} keepAmount, keepPercent
class ExpenseRepository {
  ExpenseRepository(this.uid, {FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _user =>
      _db.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> get _salaries =>
      _user.collection('salaries');
  CollectionReference<Map<String, dynamic>> get _expenses =>
      _user.collection('expenses');
  CollectionReference<Map<String, dynamic>> get _months =>
      _user.collection('months');

  // ---- range queries (range + orderBy on the same field: no composite index) --

  Stream<List<Expense>> expensesBetween(DateTime from, DateTime to) => _expenses
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .where('date', isLessThan: Timestamp.fromDate(to))
      .orderBy('date', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Expense.fromDoc).toList());

  Stream<List<Salary>> salariesBetween(DateTime from, DateTime to) => _salaries
      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .where('date', isLessThan: Timestamp.fromDate(to))
      .orderBy('date', descending: true)
      .snapshots()
      .map((s) => s.docs.map(Salary.fromDoc).toList());

  Stream<MonthSettings> monthSettings(DateTime month) => _months
      .doc(monthKey(month))
      .snapshots()
      .map((d) => MonthSettings.fromMap(d.data()));

  Stream<Map<String, MonthSettings>> allMonthSettings() =>
      _months.snapshots().map(
        (s) => {for (final d in s.docs) d.id: MonthSettings.fromMap(d.data())},
      );

  // ---- writes ---------------------------------------------------------------

  /// [extra] e.g. {'addedBy': uid, 'addedByName': 'Bob'} when the partner adds it.
  Future<void> saveExpense(
    Expense e, {
    Map<String, dynamic> extra = const {},
  }) => e.id.isEmpty
      ? _expenses.add({
          ...e.toMap(),
          ...extra,
          'createdAt': FieldValue.serverTimestamp(),
        })
      : _expenses.doc(e.id).set(e.toMap(), SetOptions(merge: true));

  Future<void> deleteExpense(String id) => _expenses.doc(id).delete();

  Future<void> saveSalary(Salary s) => s.id.isEmpty
      ? _salaries.add({...s.toMap(), 'createdAt': FieldValue.serverTimestamp()})
      : _salaries.doc(s.id).set(s.toMap(), SetOptions(merge: true));

  Future<void> deleteSalary(String id) => _salaries.doc(id).delete();

  /// [customKeep] null = go back to the automatic suggestion.
  Future<void> setKeep(
    DateTime month, {
    double? customKeep,
    double? keepPercent,
  }) => _months.doc(monthKey(month)).set({
    'keepAmount': customKeep,
    'keepPercent': ?keepPercent,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}
