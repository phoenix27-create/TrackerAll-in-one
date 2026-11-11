/// 'granted' | 'denied' | 'default' | 'unsupported'
String webNotifyStatus() => 'unsupported';

Future<String> webNotifyRequest() async => 'unsupported';

Future<void> webNotifyShow(String title, String body, {String? tag}) async {}

/// True when running as an installed home-screen app (PWA).
bool webIsStandalone() => false;
