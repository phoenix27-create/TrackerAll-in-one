import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

/// "No expense today?" reminders, every 3 hours, as local scheduled
/// notifications (works on the free Spark plan, no server needed).
///
/// * Slots: 09:00, 12:00, 15:00, 18:00, 21:00 – for today and the next 6 days,
///   so the user is reminded even if they don't open the app for a while.
/// * Once an expense is logged for a day, that day's remaining reminders are
///   cancelled. [sync] is called on app start / resume and after every save.
/// * Every reminder uses a different message.
/// * Can be switched off in Profile (users/{uid}.expenseReminders).
class ReminderService {
  ReminderService._();
  static final instance = ReminderService._();

  static const slots = [9, 12, 15, 18, 21];
  static const daysAhead = 7;
  static const _baseId = 2000;

  static Iterable<int> get _allIds sync* {
    for (var d = 0; d < daysAhead; d++) {
      for (var s = 0; s < slots.length; s++) {
        yield _baseId + d * 10 + s;
      }
    }
  }

  static const _messages = <(String, String)>[
    (
      'No expense cost for today? 🤔',
      'Tap to log what you spent today and keep your budget on track.',
    ),
    (
      'Spent anything yet today? 💸',
      'Even a small tea shop bill counts. Add it now in 5 seconds.',
    ),
    (
      'Your wallet misses you 👛',
      'Nothing logged today. Did you pay with Cash, KBZPay or WavePay?',
    ),
    (
      'Quick check-in ⏰',
      'Log today\'s expenses so your savings goal stays safe.',
    ),
    ('Lunch, taxi, top-up? 🍜🚕', 'Don\'t forget to record today\'s spending.'),
    (
      'Keep your streak going 🔥',
      'Add today\'s expenses and see how much you can still spend.',
    ),
    (
      'Budget buddy here 🤝',
      'Your expense tracker is empty for today. Want to fill it in?',
    ),
    (
      'Little costs add up 📈',
      'Record today\'s spending before you forget the details.',
    ),
    (
      'Did today cost nothing? 😮',
      'If you spent money, add it now. If not, great job saving!',
    ),
    ('Evening money check 🌙', 'Take a minute to log what you spent today.'),
    (
      'Protect your keep amount 🛡️',
      'Logging every expense helps you avoid the emergency alert.',
    ),
    ('Hey, quick reminder! ✍️', 'Open LifeTrack and add today\'s expenses.'),
    (
      'Know where your money went 🔍',
      'Nothing recorded today yet. Add your expenses now.',
    ),
    (
      'Small habit, big savings 💰',
      'Log today\'s spending – it only takes a moment.',
    ),
    (
      'Mingalarbar! 🙏',
      'How much did you spend today? Add it to your tracker.',
    ),
  ];

  /// Re-plans all reminders for [uid]. Safe to call often.
  Future<void> sync(String uid) async {
    if (kIsWeb) return;
    try {
      final ns = NotificationService.instance;
      await ns.cancelIds(_allIds);

      final db = FirebaseFirestore.instance;
      final profile = await db.collection('users').doc(uid).get();
      if (profile.data()?['expenseReminders'] == false) return;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final loggedToday = await _hasExpense(db, uid, today);

      for (var d = 0; d < daysAhead; d++) {
        if (d == 0 && loggedToday) continue;
        final day = today.add(Duration(days: d));
        for (var s = 0; s < slots.length; s++) {
          final when = DateTime(day.year, day.month, day.day, slots[s]);
          if (!when.isAfter(now)) continue;
          // Rotate messages so consecutive reminders are never the same.
          final (title, body) =
              _messages[(day.day * slots.length + s) % _messages.length];
          await ns.scheduleReminder(
            id: _baseId + d * 10 + s,
            when: when,
            title: title,
            body: body,
          );
        }
      }
    } catch (e) {
      debugPrint('Reminder sync failed: $e');
    }
  }

  Future<void> cancelAll() => NotificationService.instance.cancelIds(_allIds);

  Future<bool> _hasExpense(
    FirebaseFirestore db,
    String uid,
    DateTime day,
  ) async {
    final snap = await db
        .collection('users')
        .doc(uid)
        .collection('expenses')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(day))
        .where(
          'date',
          isLessThan: Timestamp.fromDate(day.add(const Duration(days: 1))),
        )
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }
}
