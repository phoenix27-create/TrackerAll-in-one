import 'dart:math' as math;

/// What the partner gets notified about.
enum AlertType {
  drivingStart('driving_start'),
  drivingStop('driving_stop'),
  leftPlace('left_place'),
  arrivedPlace('arrived_place'),
  charging('charging'),
  batteryFull('battery_full'),
  batteryLow('battery_low');

  const AlertType(this.id);

  /// Stored as the inbox item's `type`.
  final String id;
}

class ActivityEvent {
  const ActivityEvent(this.type, {this.place, this.battery});
  final AlertType type;

  /// 'home' / 'work' for place events.
  final String? place;

  /// Battery % for battery events.
  final int? battery;

  @override
  String toString() =>
      '${type.id}${place != null ? '($place)' : ''}${battery != null ? '[$battery%]' : ''}';
}

/// A place the user saved (Home / Work) – stored on users/{uid}.places.
class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.lat,
    required this.lng,
    this.radius = 150,
  });
  final String id;
  final double lat, lng;

  /// Metres. Inside = within radius; outside = beyond radius + [_hysteresis].
  final double radius;

  static List<SavedPlace> fromProfile(Map<String, dynamic>? profile) {
    final raw = profile?['places'];
    if (raw is! Map) return const [];
    return [
      for (final e in raw.entries)
        if (e.value is Map &&
            (e.value as Map)['lat'] is num &&
            (e.value as Map)['lng'] is num)
          SavedPlace(
            id: e.key as String,
            lat: ((e.value as Map)['lat'] as num).toDouble(),
            lng: ((e.value as Map)['lng'] as num).toDouble(),
            radius: (((e.value as Map)['radius'] as num?) ?? 150).toDouble(),
          ),
    ];
  }
}

enum BatteryMode { charging, full, discharging, unknown }

/// Turns raw GPS fixes and battery readings into a few meaningful events.
/// Pure Dart (no plugins) so it can be unit-tested.
///
/// * Driving starts after two fixes faster than ~22 km/h, and stops after
///   4 minutes without moving faster than ~9 km/h (traffic lights don't count).
/// * Place events use a 60 m buffer so GPS jitter at the edge doesn't flap,
///   and ignore inaccurate fixes (> 100 m).
/// * Battery: charging started, fully charged, and low (≤ 15 %, once per
///   discharge – re-armed after charging or rising above 25 %).
/// * The same event can't repeat within 2 minutes.
class ActivityDetector {
  static const driveStartSpeed = 6.0; // m/s ≈ 22 km/h
  static const driveKeepSpeed = 2.5; // m/s ≈ 9 km/h
  static const driveStopAfter = Duration(minutes: 4);
  static const _hysteresis = 60.0;
  static const _maxAccuracy = 100.0;
  static const _cooldown = Duration(minutes: 2);
  static const lowBattery = 15;

  List<SavedPlace> places = const [];

  bool driving = false;
  int _fastFixes = 0;
  DateTime? _lastFastAt;
  double? _lastLat, _lastLng;
  DateTime? _lastAt;
  final _inside = <String, bool>{};

  BatteryMode? _battery;
  bool _lowSent = false;
  final _lastEmit = <String, DateTime>{};

  void setPlaces(List<SavedPlace> p) {
    places = p;
    // Forget states of removed/moved places; they are re-learned silently.
    _inside.removeWhere((id, _) => !p.any((x) => x.id == id));
  }

  List<ActivityEvent> onLocation({
    required double lat,
    required double lng,
    required double speed,
    required double accuracy,
    required DateTime at,
  }) {
    final out = <ActivityEvent>[];

    // ---- speed: device speed, or computed from the previous fix ----------
    var v = speed.isFinite && speed > 0 ? speed : 0.0;
    if (v == 0 && _lastAt != null) {
      final dt = at.difference(_lastAt!).inMilliseconds / 1000;
      if (dt >= 3 && dt <= 120) {
        v = distance(_lastLat!, _lastLng!, lat, lng) / dt;
      }
    }
    _lastLat = lat;
    _lastLng = lng;
    _lastAt = at;

    // ---- driving ---------------------------------------------------------
    if (!driving) {
      _fastFixes = v >= driveStartSpeed ? _fastFixes + 1 : 0;
      if (_fastFixes >= 2) {
        driving = true;
        _lastFastAt = at;
        _emit(out, const ActivityEvent(AlertType.drivingStart), at);
      }
    } else {
      if (v >= driveKeepSpeed) {
        _lastFastAt = at;
      } else if (at.difference(_lastFastAt!) >= driveStopAfter) {
        driving = false;
        _fastFixes = 0;
        _emit(out, const ActivityEvent(AlertType.drivingStop), at);
      }
    }

    // ---- places ----------------------------------------------------------
    if (accuracy <= _maxAccuracy) {
      for (final p in places) {
        final d = distance(p.lat, p.lng, lat, lng);
        final isIn = d <= p.radius;
        final isOut = d > p.radius + _hysteresis;
        final was = _inside[p.id];
        if (was == null) {
          // First fix: learn where we are without notifying.
          if (isIn || isOut) _inside[p.id] = isIn;
        } else if (was && isOut) {
          _inside[p.id] = false;
          _emit(out, ActivityEvent(AlertType.leftPlace, place: p.id), at);
        } else if (!was && isIn) {
          _inside[p.id] = true;
          _emit(out, ActivityEvent(AlertType.arrivedPlace, place: p.id), at);
        }
      }
    }
    return out;
  }

  List<ActivityEvent> onBattery({
    required int level,
    required BatteryMode mode,
    required DateTime at,
  }) {
    final out = <ActivityEvent>[];
    final prev = _battery;
    _battery = mode;
    if (mode == BatteryMode.charging || level > 25) _lowSent = false;

    if (prev != null && prev != mode) {
      if (mode == BatteryMode.charging && prev != BatteryMode.full) {
        _emit(out, ActivityEvent(AlertType.charging, battery: level), at);
      } else if (mode == BatteryMode.full) {
        _emit(out, ActivityEvent(AlertType.batteryFull, battery: level), at);
      }
    }
    if (mode == BatteryMode.discharging && level <= lowBattery && !_lowSent) {
      _lowSent = true;
      _emit(out, ActivityEvent(AlertType.batteryLow, battery: level), at);
    }
    return out;
  }

  void _emit(List<ActivityEvent> out, ActivityEvent e, DateTime at) {
    final key = '${e.type.id}:${e.place ?? ''}';
    final last = _lastEmit[key];
    if (last != null && at.difference(last) < _cooldown) return;
    _lastEmit[key] = at;
    out.add(e);
  }

  /// Great-circle distance in metres.
  static double distance(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(a));
  }
}
