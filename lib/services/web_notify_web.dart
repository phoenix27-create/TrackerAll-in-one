import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

bool get _supported => globalContext.has('Notification');

/// 'granted' | 'denied' | 'default' | 'unsupported'
///
/// iPhone/iPad: Safari only supports notifications for sites added to the
/// Home Screen (iOS 16.4+), so a normal Safari tab reports 'unsupported'.
String webNotifyStatus() =>
    _supported ? web.Notification.permission : 'unsupported';

/// Shows the browser's "Allow notifications?" prompt. Must be called from a
/// tap (browsers ignore it otherwise).
Future<String> webNotifyRequest() async {
  if (!_supported) return 'unsupported';
  try {
    final r = await web.Notification.requestPermission().toDart;
    return r.toDart;
  } catch (e) {
    debugPrint('Notification permission: $e');
    return web.Notification.permission;
  }
}

web.ServiceWorkerRegistration? _reg;

Future<web.ServiceWorkerRegistration?> _registration() async {
  if (_reg != null) return _reg;
  try {
    if (!web.window.navigator.has('serviceWorker')) return null;
    _reg = await web.window.navigator.serviceWorker
        .register(
          'notify_sw.js'.toJS,
          web.RegistrationOptions(scope: './sw-notify/'),
        )
        .toDart;
  } catch (e) {
    debugPrint('Notification worker: $e');
  }
  return _reg;
}

/// Shows a notification (when permission is granted). Uses the service
/// worker (required on iPhone home-screen apps and Android Chrome) and falls
/// back to `new Notification()` on desktop browsers.
Future<void> webNotifyShow(String title, String body, {String? tag}) async {
  if (webNotifyStatus() != 'granted') return;
  final options = web.NotificationOptions(
    body: body,
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    tag: tag ?? '',
  );
  final reg = await _registration();
  if (reg != null) {
    try {
      await reg.showNotification(title, options).toDart;
      return;
    } catch (e) {
      debugPrint('Worker notification failed: $e');
    }
  }
  try {
    web.Notification(title, options);
  } catch (e) {
    debugPrint('Notification failed: $e');
  }
}

/// Subscribes this browser to Web Push (permission must already be
/// granted). Returns the subscription JSON, or null when not possible
/// (e.g. iPhone Safari tab – only Home Screen apps get push).
Future<String?> webPushSubscribe(String vapidPublicKey) async {
  if (webNotifyStatus() != 'granted') return null;
  final reg = await _registration();
  if (reg == null || !(reg as JSObject).has('pushManager')) return null;
  try {
    // subscribe() needs an active worker; ours lives in its own scope, so
    // `serviceWorker.ready` never resolves – wait for activation instead.
    for (var i = 0; i < 40 && reg.active == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (reg.active == null) return null;
    var sub = await reg.pushManager.getSubscription().toDart;
    sub ??= await reg.pushManager
        .subscribe(
          web.PushSubscriptionOptionsInit(
            userVisibleOnly: true,
            applicationServerKey: _b64UrlDecode(vapidPublicKey).toJS,
          ),
        )
        .toDart;
    final json = (globalContext['JSON'] as JSObject).callMethod<JSString>(
      'stringify'.toJS,
      sub,
    );
    return json.toDart;
  } catch (e) {
    debugPrint('Push subscribe failed: $e');
    return null;
  }
}

Uint8List _b64UrlDecode(String s) {
  var t = s.replaceAll('-', '+').replaceAll('_', '/');
  while (t.length % 4 != 0) {
    t += '=';
  }
  return base64.decode(t);
}

/// Minutes east of UTC (e.g. Myanmar = 390).
int webTzOffset() => DateTime.now().timeZoneOffset.inMinutes;

/// True when opened from the Home Screen icon (installed web app).
bool webIsStandalone() {
  try {
    if (web.window.matchMedia('(display-mode: standalone)').matches) {
      return true;
    }
    // iOS Safari's own flag.
    final nav = web.window.navigator as JSObject;
    return nav.has('standalone') &&
        (nav['standalone'] as JSBoolean?)?.toDart == true;
  } catch (_) {
    return false;
  }
}
