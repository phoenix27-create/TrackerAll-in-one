import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'activity_detector.dart';
import 'browser_location.dart';
import 'partner_service.dart';

enum LocationAccess { granted, denied, deniedForever, serviceOff }

/// Live GPS for the Partner Location tracker (free Spark plan friendly).
///
/// * Every user must allow location (PermissionsFlow asks on first use).
/// * While linked with a partner, the position is written to
///   users/{uid}/live/location – at most every 20 s, or sooner after moving
///   30 m – so the partner sees it live on the map.
/// * Android keeps sharing in the background with a small ongoing
///   notification; iOS uses the background-location mode.
class LocationService {
  LocationService._();
  static final instance = LocationService._();

  final _db = FirebaseFirestore.instance;

  /// My latest position (for the blue dot on the map).
  final myPosition = ValueNotifier<Position?>(null);

  // ---------------------------------------------------------- permission --

  /// Web: the user tapped Allow and the browser agreed. iPhone Safari's
  /// Permissions API keeps answering "prompt" even after that, so this flag
  /// (not the API) decides whether sharing may start.
  bool _webAllowed = false;

  Future<LocationAccess> status() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    return _map(await Geolocator.checkPermission());
  }

  /// Shows the system "Allow location?" prompt when it still can.
  Future<LocationAccess> request() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceOff;
    }
    if (kIsWeb) {
      // Always the real request on the web: it shows the browser prompt when
      // allowed, and only a real "Don't Allow" counts as blocked.
      final ok = await requestBrowserLocation();
      if (ok == true) _webAllowed = true;
      return ok == true ? LocationAccess.granted : LocationAccess.deniedForever;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied ||
        p == LocationPermission.unableToDetermine) {
      p = await Geolocator.requestPermission();
    }
    return _map(p);
  }

  /// Opens the phone settings when the prompt can no longer be shown.
  Future<void> openSettings(LocationAccess a) async {
    if (kIsWeb) return;
    if (a == LocationAccess.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  static LocationAccess _map(LocationPermission p) => switch (p) {
    LocationPermission.always ||
    LocationPermission.whileInUse => LocationAccess.granted,
    LocationPermission.deniedForever => LocationAccess.deniedForever,
    _ => LocationAccess.denied,
  };

  // ------------------------------------------------------------- sharing --

  StreamSubscription<Position>? _sub;
  String? _uid;
  Position? _lastSent;
  DateTime? _lastSentAt;
  String? _lastActivity;

  static const _minInterval = Duration(seconds: 20);
  static const _moveMeters = 30.0;

  // Partner alerts (driving / places / battery) detected on THIS phone.
  final _detector = ActivityDetector();
  String? _partnerId;
  String _myName = '';
  final _battery = Battery();
  StreamSubscription<BatteryState>? _batterySub;
  int? _batteryLevel;
  bool _charging = false;

  /// Starts sharing [uid]'s location while they have a partner.
  /// [profile] is the user's own users/{uid} doc (name, partnerId, places).
  /// No partner = nothing to share, so it stops.
  Future<void> update({
    required String uid,
    required Map<String, dynamic> profile,
  }) async {
    final partnerId = profile['partnerId'] as String?;
    _partnerId = partnerId;
    final n = (profile['name'] as String?)?.trim() ?? '';
    _myName = n.isNotEmpty ? n : 'Your partner';
    _detector.setPlaces(SavedPlace.fromProfile(profile));
    if (partnerId == null) {
      await stop();
      return;
    }
    if (_uid == uid && _sub != null) return;
    await stop();
    if (kIsWeb) {
      // Only a real block stops sharing on the web (see [_webAllowed]).
      if (!_webAllowed && await status() == LocationAccess.deniedForever) {
        return;
      }
    } else if (await status() != LocationAccess.granted) {
      return;
    }
    _uid = uid;
    _startBattery();
    _sub = Geolocator.getPositionStream(locationSettings: _settings())
        .listen(_onPosition, onError: (e) => debugPrint('Location stream: $e'));
    // Send a first fix straight away instead of waiting for movement.
    final first = await _quickFix();
    if (first != null) _onPosition(first);
  }

  /// One-off position for the map when not sharing (e.g. no partner yet).
  Future<void> refreshMine() async {
    final p = await _quickFix();
    if (p != null) myPosition.value = p;
  }

  /// A position without hanging: precise GPS for up to 20 s, then a quick
  /// network-based fix (phones indoors can take very long for precise GPS).
  Future<Position?> _quickFix() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: kIsWeb
            ? WebSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: const Duration(seconds: 20),
                maximumAge: const Duration(seconds: 30),
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 20),
              ),
      );
    } catch (e) {
      debugPrint('Precise fix failed: $e');
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: kIsWeb
            ? WebSettings(
                accuracy: LocationAccuracy.low,
                timeLimit: const Duration(seconds: 15),
                maximumAge: const Duration(minutes: 10),
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.low,
                timeLimit: Duration(seconds: 15),
              ),
      );
    } catch (e) {
      debugPrint('Quick fix failed: $e');
      return null;
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _batterySub?.cancel();
    _batterySub = null;
    _uid = null;
    _lastSent = null;
    _lastSentAt = null;
  }

  LocationSettings _settings() {
    if (kIsWeb) {
      return WebSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        maximumAge: const Duration(seconds: 10),
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          intervalDuration: const Duration(seconds: 15),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Sharing your location',
            notificationText: 'Your partner can see you on the LifeTrack map.',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          activityType: ActivityType.other,
          pauseLocationUpdatesAutomatically: true,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        );
    }
  }

  void _onPosition(Position p) {
    myPosition.value = p;
    final uid = _uid;
    if (uid == null) return;
    final now = DateTime.now();
    final events = _detector.onLocation(
      lat: p.latitude,
      lng: p.longitude,
      speed: p.speed,
      accuracy: p.accuracy,
      at: now,
    );
    _send(events);
    // Upload straight away when driving starts/stops so the map chip is right.
    // Upload straight away when the activity changes (e.g. starts walking).
    final drivingChanged = _detector.activity != _lastActivity;
    final last = _lastSent, lastAt = _lastSentAt;
    if (last != null && lastAt != null) {
      final elapsed = now.difference(lastAt);
      final moved = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        p.latitude,
        p.longitude,
      );
      final due =
          drivingChanged ||
          elapsed >= _minInterval ||
          (moved >= _moveMeters && elapsed >= const Duration(seconds: 5));
      if (!due) return;
    }
    _lastSent = p;
    _lastSentAt = now;
    _lastActivity = _detector.activity;
    _db
        .collection('users')
        .doc(uid)
        .collection('live')
        .doc('location')
        .set({
          'lat': p.latitude,
          'lng': p.longitude,
          'accuracy': p.accuracy,
          'speed': p.speed,
          'heading': p.heading,
          'updatedAt': FieldValue.serverTimestamp(),
          // e.g. 'web-iOS' (iPhone Home Screen app), 'android', 'web-windows'
          'platform': kIsWeb
              ? 'web-${defaultTargetPlatform.name}'
              : defaultTargetPlatform.name,
          'driving': _detector.driving,
          'activity': _detector.activity,
          'battery': ?_batteryLevel,
          'charging': _charging,
        })
        .catchError((Object e) => debugPrint('Location upload failed: $e'));
  }

  // ------------------------------------------------------------- battery --

  void _startBattery() {
    _batterySub?.cancel();
    try {
      _batterySub = _battery.onBatteryStateChanged.listen(
        _onBatteryState,
        onError: (e) => debugPrint('Battery stream: $e'),
      );
    } catch (e) {
      // Some browsers have no Battery API – battery alerts just stay off.
      debugPrint('Battery not available: $e');
    }
    // Seed the current state (first reading never notifies).
    _battery.batteryState.then(_onBatteryState).catchError((Object e) {
      debugPrint('Battery state: $e');
    });
  }

  Future<void> _onBatteryState(BatteryState s) async {
    int level;
    try {
      level = await _battery.batteryLevel;
    } catch (_) {
      return;
    }
    final mode = switch (s) {
      BatteryState.charging ||
      BatteryState.connectedNotCharging => BatteryMode.charging,
      BatteryState.full => BatteryMode.full,
      BatteryState.discharging => BatteryMode.discharging,
      _ => BatteryMode.unknown,
    };
    if (mode == BatteryMode.unknown) return;
    final changed =
        level != _batteryLevel ||
        (mode != BatteryMode.discharging) != _charging;
    _batteryLevel = level;
    _charging = mode != BatteryMode.discharging;
    _send(_detector.onBattery(level: level, mode: mode, at: DateTime.now()));
    // Keep the partner's battery chip fresh without touching updatedAt.
    final uid = _uid;
    if (changed && uid != null && _lastSent != null) {
      _db
          .collection('users')
          .doc(uid)
          .collection('live')
          .doc('location')
          .set({
            'battery': level,
            'charging': _charging,
          }, SetOptions(merge: true))
          .catchError((Object e) => debugPrint('Battery upload failed: $e'));
    }
  }

  void _send(List<ActivityEvent> events) {
    final uid = _uid, partner = _partnerId;
    if (events.isEmpty || uid == null || partner == null) return;
    for (final e in events) {
      PartnerService.instance.notifyActivity(
        myUid: uid,
        myName: _myName,
        partnerUid: partner,
        event: e,
      );
    }
  }
}

/// A partner's last shared position.
class SharedLocation {
  SharedLocation({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.speed,
    required this.updatedAt,
    this.battery,
    this.charging = false,
    this.driving = false,
    this.activity,
    this.platform = '',
  });

  final double lat, lng, accuracy, speed;
  final DateTime? updatedAt;
  final int? battery;
  final bool charging, driving;

  /// 'still' | 'walking' | 'running' | 'driving' (null = older app version).
  final String? activity;

  /// e.g. 'web-iOS', 'android', 'web-windows'.
  final String platform;

  /// iPhone/iPad web app: Safari never shares battery with websites.
  bool get isIosWeb => platform == 'web-iOS';

  static SharedLocation? fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    if (m == null || m['lat'] == null || m['lng'] == null) return null;
    return SharedLocation(
      lat: (m['lat'] as num).toDouble(),
      lng: (m['lng'] as num).toDouble(),
      accuracy: (m['accuracy'] as num?)?.toDouble() ?? 0,
      speed: (m['speed'] as num?)?.toDouble() ?? 0,
      updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
      battery: (m['battery'] as num?)?.round(),
      charging: m['charging'] == true,
      driving: m['driving'] == true,
      activity: m['activity'] as String?,
      platform: m['platform'] as String? ?? '',
    );
  }

  static Stream<SharedLocation?> watch(String uid) => FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('live')
      .doc('location')
      .snapshots()
      .map(fromDoc);
}
