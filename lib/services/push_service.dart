import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'web_notify.dart';

/// Web Push: notifications that arrive even when the app is CLOSED
/// (iPhone: Home Screen app, iOS 16.4+; Android Chrome; desktop browsers).
///
/// * Each device saves its push subscription in users/{uid}/push/{id}.
/// * Alerts are sent through the Netlify function `/.netlify/functions/push`
///   (free; no Firebase Blaze plan needed). It checks the sender is the user
///   or their partner, then pushes to every device of the receiver.
/// * Expense reminders are pushed by the scheduled `reminders` function.
class PushService {
  PushService._();
  static final instance = PushService._();

  /// Public half of the VAPID key pair (same as netlify/lib/push.mjs).
  static const vapidPublicKey =
      'BPk1a2hD1lm_Mdt_KQQTvDyS9ISDBOsQcvl9NYJbeC5OzhxO_-qz8uPYa1s7HTgmnvQKLXHg-vOj4PqqgXX1fOU';

  /// True once this device is subscribed (it will get pushes when closed).
  bool get active => _docId != null;

  String? _docId;
  String? _uid;

  CollectionReference<Map<String, dynamic>> _subs(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('push');

  /// Subscribes this browser and saves it for [uid]. Safe to call often.
  Future<void> register(String uid) async {
    if (!kIsWeb) return; // native apps use local notifications
    try {
      final json = await webPushSubscribe(vapidPublicKey);
      if (json == null) return;
      final m = jsonDecode(json) as Map<String, dynamic>;
      final endpoint = m['endpoint'] as String?;
      final keys = m['keys'] as Map<String, dynamic>?;
      if (endpoint == null || keys == null) return;
      final id = _hash(endpoint);
      await _subs(uid).doc(id).set({
        'endpoint': endpoint,
        'p256dh': keys['p256dh'],
        'auth': keys['auth'],
        'tzOffset': webTzOffset(),
        'platform': 'web-${defaultTargetPlatform.name}',
        'standalone': webIsStandalone(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _docId = id;
      _uid = uid;
    } catch (e) {
      debugPrint('Push register failed: $e');
    }
  }

  /// Stops pushes to this device (on sign-out), so the next person who signs
  /// in here does not get the previous user's notifications.
  Future<void> unregister() async {
    final id = _docId, uid = _uid;
    _docId = null;
    _uid = null;
    if (id == null || uid == null) return;
    try {
      await _subs(uid).doc(id).delete();
    } catch (e) {
      debugPrint('Push unregister failed: $e');
    }
  }

  /// Asks the server to push a notification to [to] (yourself or your
  /// partner). Returns how many devices got it (0 when not set up).
  Future<int> send({
    required String to,
    required String type,
    required String title,
    required String body,
    String? inboxId,
  }) async {
    if (!kIsWeb) return 0; // native build has no server URL yet
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return 0;
      final res = await http
          .post(
            Uri.base.resolve('/.netlify/functions/push'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'to': to,
              'type': type,
              'title': title,
              'body': body,
              'inboxId': ?inboxId,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        debugPrint('Push send ${res.statusCode}: ${res.body}');
        return 0;
      }
      return (jsonDecode(res.body)['sent'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('Push send failed: $e');
      return 0;
    }
  }

  /// Short stable id for a subscription endpoint (FNV-1a, 64-bit).
  static String _hash(String s) {
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final c in utf8.encode(s)) {
      h = ((h ^ BigInt.from(c)) * prime) & mask;
    }
    return h.toRadixString(16);
  }
}
