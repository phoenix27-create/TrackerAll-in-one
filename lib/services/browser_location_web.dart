import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// true  = allowed (even if no position yet)
/// false = the user or the browser blocked location
/// null  = geolocation not supported
Future<bool?> requestBrowserLocation() {
  final geo = web.window.navigator.geolocation;
  final done = Completer<bool?>();
  geo.getCurrentPosition(
    ((web.GeolocationPosition _) {
      if (!done.isCompleted) done.complete(true);
    }).toJS,
    ((web.GeolocationPositionError e) {
      // 1 = PERMISSION_DENIED. 2 (unavailable) and 3 (timeout) mean the
      // permission was given but no fix arrived yet.
      if (!done.isCompleted) done.complete(e.code != 1);
    }).toJS,
    web.PositionOptions(
      enableHighAccuracy: false,
      timeout: 15000,
      maximumAge: 600000,
    ),
  );
  return done.future;
}
