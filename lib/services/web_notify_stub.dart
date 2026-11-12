/// 'granted' | 'denied' | 'default' | 'unsupported'
String webNotifyStatus() => 'unsupported';

Future<String> webNotifyRequest() async => 'unsupported';

Future<void> webNotifyShow(String title, String body, {String? tag}) async {}

/// True when running as an installed home-screen app (PWA).
bool webIsStandalone() => false;

/// Web Push subscription as JSON ({endpoint, keys: {p256dh, auth}}), or null.
Future<String?> webPushSubscribe(String vapidPublicKey) async => null;

/// Minutes east of UTC (e.g. Myanmar = 390).
int webTzOffset() => DateTime.now().timeZoneOffset.inMinutes;
