/// Browser notifications (web only): permission + showing a notification.
/// On Android / iOS apps these are no-ops (flutter_local_notifications is used).
library;

export 'web_notify_stub.dart'
    if (dart.library.js_interop) 'web_notify_web.dart';
