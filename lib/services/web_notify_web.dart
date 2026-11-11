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
