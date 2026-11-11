/// Asks the browser for location (web only).
///
/// Unlike geolocator's web `requestPermission`, which reports EVERY error as
/// "denied forever", this only treats a real "Don't Allow" as denied. A
/// timeout or "position unavailable" (common on iPhone right after tapping
/// Allow, especially indoors) still means permission was granted.
library;

export 'browser_location_stub.dart'
    if (dart.library.js_interop) 'browser_location_web.dart';
