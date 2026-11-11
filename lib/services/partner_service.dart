import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/format.dart';
import '../features/expense/models.dart';
import 'activity_detector.dart';
import 'notification_service.dart';

/// Partner sharing (works on the free Spark plan – no Cloud Functions).
///
/// Data:
///   users/{uid}.partnerCode      own code while single (e.g. "K7P2QX")
///   users/{uid}.partnerId        partner's uid once connected
///   users/{uid}.partnerSince     timestamp
///   partnerCodes/{code}          { uid }  – lookup table, get-only
///   users/{uid}/inbox/{id}       partner activity (new expense, connected…)
///
/// Connecting is one Firestore transaction that links BOTH users and deletes
/// both codes. Security rules make sure a user can only be linked once and
/// only through a valid code.
class PartnerService {
  PartnerService._();
  static final instance = PartnerService._();

  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);
  CollectionReference<Map<String, dynamic>> get _codes =>
      _db.collection('partnerCodes');

  // No 0/O/1/I/L to avoid confusion when typing.
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static String _newCode() {
    final r = Random.secure();
    return List.generate(
      6,
      (_) => _alphabet[r.nextInt(_alphabet.length)],
    ).join();
  }

  static String normalize(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  // ------------------------------------------------------------- my code --

  bool _ensuring = false;

  /// Gives the user a partner code if they are single and don't have one.
  Future<void> ensureCode(String uid) async {
    if (_ensuring) return;
    _ensuring = true;
    try {
      final me = (await _user(uid).get()).data() ?? {};
      if (me['partnerId'] != null) return;
      final existing = me['partnerCode'] as String?;
      if (existing != null) {
        final c = await _codes.doc(existing).get();
        if (c.exists && c.data()?['uid'] == uid) return;
      }
      for (var attempt = 0; attempt < 6; attempt++) {
        final code = _newCode();
        final created = await _db.runTransaction<bool>((tx) async {
          final ref = _codes.doc(code);
          if ((await tx.get(ref)).exists) return false;
          tx.set(ref, {'uid': uid, 'createdAt': FieldValue.serverTimestamp()});
          tx.set(_user(uid), {'partnerCode': code}, SetOptions(merge: true));
          return true;
        });
        if (created) return;
      }
    } catch (e) {
      debugPrint('ensureCode failed: $e');
    } finally {
      _ensuring = false;
    }
  }

  // ------------------------------------------------------------- connect --

  /// Links the signed-in user ([myUid]) with the owner of [rawCode].
  /// Throws a [PartnerException] with a friendly message.
  Future<void> connect({
    required String myUid,
    required String myName,
    required String rawCode,
  }) async {
    final code = normalize(rawCode);
    if (code.length != 6) {
      throw PartnerException('The code has 6 letters/numbers.');
    }

    final codeSnap = await _codes.doc(code).get();
    if (!codeSnap.exists) {
      throw PartnerException(
        'Code not found. Check it with your partner – it may have changed.',
      );
    }
    final otherUid = codeSnap.data()!['uid'] as String;
    if (otherUid == myUid) {
      throw PartnerException(
        'That is your own code 😄 Ask your partner for theirs.',
      );
    }

    try {
      await _db.runTransaction((tx) async {
        final meSnap = await tx.get(_user(myUid));
        final me = meSnap.data() ?? {};
        if (me['partnerId'] != null) {
          throw PartnerException('You are already connected with a partner.');
        }
        final codeAgain = await tx.get(_codes.doc(code));
        if (!codeAgain.exists) {
          throw PartnerException('This code was just used. Ask for a new one.');
        }

        final since = FieldValue.serverTimestamp();
        // Partner's profile (allowed by rules only while they are single).
        tx.update(_user(otherUid), {
          'partnerId': myUid,
          'partnerSince': since,
          'partnerCode': FieldValue.delete(),
        });
        tx.set(_user(myUid), {
          'partnerId': otherUid,
          'partnerSince': since,
          'partnerCode': FieldValue.delete(),
        }, SetOptions(merge: true));
        tx.delete(_codes.doc(code));
        final myCode = me['partnerCode'] as String?;
        if (myCode != null) tx.delete(_codes.doc(myCode));
      });
    } on PartnerException {
      rethrow;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw PartnerException(
          'This person is already connected with someone else.',
        );
      }
      rethrow;
    }

    await _sendInbox(otherUid, {
      'type': 'connected',
      'from': myUid,
      'fromName': myName,
    });
  }

  // ---------------------------------------------------------- disconnect --
  //
  // Disconnecting needs BOTH people:
  //   1. A taps Disconnect  -> users/A.disconnectRequestedAt is set and B is notified.
  //   2. B taps Confirm     -> both links are cleared in one batch.
  //      (or B taps "Stay connected" / A cancels -> the request is cleared.)
  // Security rules refuse any unlink without the other person's request.

  /// Step 1: ask the partner to confirm the disconnect.
  Future<void> requestDisconnect({
    required String myUid,
    required String myName,
    required String partnerUid,
  }) async {
    await _user(myUid).set({
      'disconnectRequestedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _safeInbox(partnerUid, {
      'type': 'disconnect_request',
      'from': myUid,
      'fromName': myName,
    });
  }

  /// The requester changed their mind.
  Future<void> cancelDisconnect({
    required String myUid,
    required String myName,
    required String partnerUid,
  }) async {
    await _user(myUid).update({'disconnectRequestedAt': null});
    await _safeInbox(partnerUid, {
      'type': 'disconnect_cancel',
      'from': myUid,
      'fromName': myName,
    });
  }

  /// The other person says no: clears their request, stays connected.
  Future<void> declineDisconnect({
    required String myUid,
    required String myName,
    required String partnerUid,
  }) async {
    await _user(partnerUid).update({'disconnectRequestedAt': null});
    await _safeInbox(partnerUid, {
      'type': 'disconnect_declined',
      'from': myUid,
      'fromName': myName,
    });
  }

  /// Step 2: the partner requested it, I confirm. Unlinks both users;
  /// each gets a fresh code.
  Future<void> confirmDisconnect({
    required String myUid,
    required String partnerUid,
  }) async {
    final partner = (await _user(partnerUid).get()).data() ?? {};
    if (partner['disconnectRequestedAt'] == null) {
      throw PartnerException('Your partner has not asked to disconnect.');
    }
    final batch = _db.batch();
    batch.update(_user(partnerUid), {
      'partnerId': null,
      'partnerSince': null,
      'disconnectRequestedAt': null,
    });
    batch.update(_user(myUid), {
      'partnerId': null,
      'partnerSince': null,
      'disconnectRequestedAt': null,
    });
    await batch.commit();
    await ensureCode(myUid);
  }

  Future<void> _safeInbox(String toUid, Map<String, dynamic> data) async {
    try {
      await _sendInbox(toUid, data);
    } catch (e) {
      debugPrint('Partner inbox failed: $e');
    }
  }

  // --------------------------------------------------------------- inbox --

  Stream<List<PartnerActivity>> recentActivity(String uid, {int limit = 3}) =>
      _user(uid)
          .collection('inbox')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(PartnerActivity.fromDoc).toList());

  /// Called after a NEW expense is added. [onYourTracker] = the partner added
  /// it to the receiver's own tracker (otherwise it is the sender's spending).
  Future<void> notifyExpense({
    required String myUid,
    required String myName,
    required String? partnerUid,
    required Expense e,
    bool onYourTracker = false,
  }) async {
    if (partnerUid == null) return;
    await _safeInbox(partnerUid, {
      'type': 'expense',
      'from': myUid,
      'fromName': myName,
      'onYourTracker': onYourTracker,
      'amount': e.amount,
      'category': e.categoryId,
      'payment': e.paymentId,
      'note': e.note,
      'date': Timestamp.fromDate(e.date),
    });
  }

  /// The keep amount was broken – the emergency alert goes to both partners.
  Future<void> notifyAlert({
    required String myUid,
    required String myName,
    required String partnerUid,
    required bool onYourTracker,
    required double remaining,
    required double keep,
    required String month,
  }) => _safeInbox(partnerUid, {
    'type': 'alert',
    'from': myUid,
    'fromName': myName,
    'onYourTracker': onYourTracker,
    'remaining': remaining,
    'keep': keep,
    'month': month,
  });

  /// Live-GPS alert (driving / place / battery) detected on my phone.
  /// Same-type alerts are throttled on the sender by [ActivityDetector].
  Future<void> notifyActivity({
    required String myUid,
    required String myName,
    required String partnerUid,
    required ActivityEvent event,
  }) => _safeInbox(partnerUid, {
    'type': event.type.id,
    'from': myUid,
    'fromName': myName,
    'place': ?event.place,
    'battery': ?event.battery,
  });

  /// The receiver's choices (users/{uid}.locationAlerts), kept up to date by
  /// the home screen. Missing = on.
  Map<String, dynamic> alertPrefs = const {};

  /// Which setting controls each live-GPS alert type.
  static String? prefFor(String type) => switch (type) {
    'driving_start' || 'driving_stop' => 'driving',
    'left_place' || 'arrived_place' => 'places',
    'charging' || 'battery_full' || 'battery_low' => 'battery',
    _ => null,
  };

  bool _wanted(String type) {
    final key = prefFor(type);
    return key == null || alertPrefs[key] != false;
  }

  Future<void> _sendInbox(String toUid, Map<String, dynamic> data) =>
      _user(toUid).collection('inbox').add({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
        'notified': false,
      });

  StreamSubscription? _inboxSub;
  String? _inboxUid;

  /// Shows a device notification for every new partner activity.
  /// Runs while the app is open or in the background; anything that arrived
  /// while it was closed is shown the next time the app opens.
  void listenInbox(String uid) {
    if (kIsWeb || _inboxUid == uid) return;
    _inboxSub?.cancel();
    _inboxUid = uid;
    _inboxSub = _user(uid)
        .collection('inbox')
        .where('notified', isEqualTo: false)
        .snapshots()
        .listen((snap) async {
          for (final d in snap.docs) {
            final a = PartnerActivity.fromDoc(d);
            // Alerts the user switched off are marked as seen silently.
            if (_wanted(a.type)) {
              await NotificationService.instance.showPartner(
                id: 3000 + (d.id.hashCode & 0xFFFF),
                title: a.title,
                body: a.body,
              );
            }
            await d.reference.update({'notified': true});
          }
        }, onError: (e) => debugPrint('Inbox listener: $e'));
  }

  void stopInbox() {
    _inboxSub?.cancel();
    _inboxSub = null;
    _inboxUid = null;
  }
}

class PartnerException implements Exception {
  PartnerException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PartnerActivity {
  PartnerActivity({
    required this.type,
    required this.fromName,
    required this.createdAt,
    this.amount = 0,
    this.categoryId,
    this.paymentId,
    this.note = '',
    this.onYourTracker = false,
    this.remaining = 0,
    this.keep = 0,
    this.month = '',
    this.place,
    this.battery,
  });

  final String type;
  final String fromName;
  final DateTime createdAt;
  final double amount;
  final String? categoryId;
  final String? paymentId;
  final String note;
  final bool onYourTracker;
  final double remaining;
  final double keep;
  final String month;
  final String? place;
  final int? battery;

  factory PartnerActivity.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return PartnerActivity(
      type: m['type'] as String? ?? 'expense',
      fromName: (m['fromName'] as String?)?.trim().isNotEmpty == true
          ? m['fromName'] as String
          : 'Your partner',
      createdAt: (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      categoryId: m['category'] as String?,
      paymentId: m['payment'] as String?,
      note: m['note'] as String? ?? '',
      onYourTracker: m['onYourTracker'] == true,
      remaining: (m['remaining'] as num?)?.toDouble() ?? 0,
      keep: (m['keep'] as num?)?.toDouble() ?? 0,
      month: m['month'] as String? ?? '',
      place: m['place'] as String?,
      battery: (m['battery'] as num?)?.round(),
    );
  }

  String get firstName => fromName.split(' ').first;

  String get placeName => switch (place) {
    'home' => 'Home',
    'work' => 'Work',
    final p? => p,
    null => 'a saved place',
  };
  String get placeEmoji => place == 'work' ? '💼' : '🏠';
  String get _pct => battery == null ? '' : ' ($battery%)';

  String get title => switch (type) {
    'connected' => '💞 $fromName connected with you',
    'alert' =>
      onYourTracker
          ? '⚠️ Emergency: your savings goal is broken'
          : "⚠️ Emergency: $firstName's savings goal is broken",
    'disconnect_request' => '💔 $firstName wants to disconnect',
    'disconnect_cancel' => '💞 $firstName cancelled the disconnect request',
    'disconnect_declined' => '💞 $firstName wants to stay connected',
    'driving_start' => '🚗 $firstName started driving',
    'driving_stop' => '🅿️ $firstName stopped driving',
    'left_place' => '$placeEmoji $firstName left $placeName',
    'arrived_place' => '$placeEmoji $firstName arrived at $placeName',
    'charging' => "⚡ $firstName's phone is charging$_pct",
    'battery_full' => "🔋 $firstName's phone is fully charged",
    'battery_low' => "🪫 $firstName's battery is low$_pct",
    _ =>
      onYourTracker
          ? '📝 $firstName added ${mmk(amount)} to your expenses'
          : '💑 $firstName spent ${mmk(amount)}',
  };

  String get body {
    switch (type) {
      case 'connected':
        return 'You can now see and manage each other\'s expenses.';
      case 'alert':
        final whose = onYourTracker ? 'Your' : "$firstName's";
        return '$whose balance is ${mmk(remaining)}, below the keep amount ${mmk(keep)}'
            '${month.isEmpty ? '' : ' for $month'}. Stop non-essential spending.';
      case 'disconnect_request':
        return 'Open LifeTrack to confirm, or choose to stay connected.';
      case 'disconnect_cancel':
      case 'disconnect_declined':
        return 'You are still connected.';
      case 'driving_start':
        return 'Open Partner Location to follow $firstName live.';
      case 'driving_stop':
        return '$firstName has parked or reached the destination.';
      case 'left_place':
        return '$firstName is on the way. Tap to see where.';
      case 'arrived_place':
        return '$firstName is at $placeName now.';
      case 'charging':
      case 'battery_full':
        return 'Location sharing keeps going.';
      case 'battery_low':
        return 'Location sharing may stop soon if the phone turns off.';
    }
    final cat = ExpenseCategory.byId(categoryId).label;
    final pay = PaymentMethod.byId(paymentId).label;
    return note.isNotEmpty ? '$note • $cat • $pay' : '$cat • paid with $pay';
  }

  String get shortText => switch (type) {
    'connected' => '$firstName connected with you',
    'alert' =>
      onYourTracker
          ? 'Your keep amount was broken'
          : "$firstName's keep amount was broken",
    'disconnect_request' => '$firstName asked to disconnect',
    'disconnect_cancel' => '$firstName cancelled the disconnect',
    'disconnect_declined' => '$firstName wants to stay connected',
    'driving_start' => '$firstName started driving',
    'driving_stop' => '$firstName stopped driving',
    'left_place' => '$firstName left $placeName',
    'arrived_place' => '$firstName arrived at $placeName',
    'charging' => "$firstName's phone is charging$_pct",
    'battery_full' => "$firstName's phone is fully charged",
    'battery_low' => "$firstName's battery is low$_pct",
    _ =>
      onYourTracker
          ? '$firstName added ${mmk(amount)} (${ExpenseCategory.byId(categoryId).label}) for you'
          : '$firstName spent ${mmk(amount)} on ${ExpenseCategory.byId(categoryId).label}',
  };

  bool get isUrgent =>
      type == 'alert' || type == 'disconnect_request' || type == 'battery_low';
}
