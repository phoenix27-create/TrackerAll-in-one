import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/activity_detector.dart';
import '../../services/route_service.dart';
import 'location_alerts_sheet.dart';
import '../profile/profile_screen.dart';

const _pink = Color(0xFFE91E63);
const _blue = Color(0xFF1E88E5);
const _live = Color(0xFF16A34A);

/// Live map of the partner's GPS position (OpenStreetMap – free, no API key).
class PartnerMapScreen extends StatelessWidget {
  const PartnerMapScreen({
    super.key,
    required this.myUid,
    required this.partnerId,
  });
  final String myUid;
  final String? partnerId;

  @override
  Widget build(BuildContext context) {
    final pid = partnerId;
    if (pid == null) return const _NoPartner();
    return StreamBuilder<Map<String, dynamic>>(
      stream: AuthService.instance.profile(pid),
      builder: (_, snap) => _PartnerMap(
        myUid: myUid,
        partnerId: pid,
        partner: snap.data ?? const {},
      ),
    );
  }
}

class _NoPartner extends StatelessWidget {
  const _NoPartner();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Partner Location')),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: _pink.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: _pink,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Connect with your partner first',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Use "Connect with partner" on the main menu with your partner\'s code. '
              'Then you can see each other live on the map.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _pink),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.link_rounded),
              label: const Text('Go to main menu'),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================

class _PartnerMap extends StatefulWidget {
  const _PartnerMap({
    required this.myUid,
    required this.partnerId,
    required this.partner,
  });
  final String myUid;
  final String partnerId;
  final Map<String, dynamic> partner;

  @override
  State<_PartnerMap> createState() => _PartnerMapState();
}

class _PartnerMapState extends State<_PartnerMap> {
  final _map = MapController();
  late final Stream<SharedLocation?> _loc = SharedLocation.watch(
    widget.partnerId,
  );
  bool _ready = false;
  bool _follow = true; // keep the camera on the partner until the user drags
  bool _centredOnce = false;
  Timer? _tick;

  // ------------------------------------------------------- directions --
  bool _directions = false;
  TravelMode _mode = TravelMode.car;
  RouteResult? _route;
  bool _routing = false;
  String? _routeError;
  LatLng? _routedFrom, _routedTo;
  DateTime? _routedAt;

  void _openDirections() {
    setState(() {
      _directions = true;
      _follow = false;
      _route = null;
      _routeError = null;
      _routedFrom = _routedTo = null;
    });
    LocationService.instance.refreshMine();
  }

  void _closeDirections() => setState(() {
    _directions = false;
    _route = null;
    _routeError = null;
  });

  void _setMode(TravelMode m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _route = null;
      _routedFrom = _routedTo = null;
    });
  }

  /// Re-route when either person moved > 150 m (at most every 30 s).
  void _maybeRoute(LatLng? from, LatLng? to) {
    if (!_directions || _routing || from == null || to == null) return;
    if (_routeError != null && _routedTo != null) return; // wait for Retry
    const d = Distance();
    final first = _routedFrom == null || _routedTo == null;
    if (!first) {
      final moved = d(from, _routedFrom!) > 150 || d(to, _routedTo!) > 150;
      final waited =
          DateTime.now().difference(_routedAt!) > const Duration(seconds: 30);
      if (!moved || !waited) return;
    }
    _routing = true;
    _routedFrom = from;
    _routedTo = to;
    _routedAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadRoute(from, to, fit: first),
    );
  }

  Future<void> _loadRoute(LatLng from, LatLng to, {bool fit = false}) async {
    if (mounted) setState(() => _routeError = null);
    try {
      final r = await RouteService.instance.fastest(from, to, _mode);
      if (!mounted || !_directions) return;
      setState(() => _route = r);
      if (fit && _ready) {
        _map.fitCamera(
          CameraFit.coordinates(
            coordinates: r.points.length > 1 ? r.points : [from, to],
            padding: const EdgeInsets.fromLTRB(50, 120, 50, 330),
            maxZoom: 17,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _routeError = e.toString());
    } finally {
      _routing = false;
    }
  }

  void _retryRoute() => setState(() {
    _routeError = null;
    _routedFrom = _routedTo = null;
  });

  Future<void> _navigate(LatLng to) async {
    final ok = await RouteService.instance.startNavigation(to, _mode);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps.')),
      );
    }
  }

  static const _defaultCenter = LatLng(16.8409, 96.1735); // Yangon

  @override
  void initState() {
    super.initState();
    LocationService.instance.refreshMine();
    // Refresh "updated x min ago".
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _name {
    final n = (widget.partner['name'] as String?)?.trim();
    if (n != null && n.isNotEmpty) return n.split(' ').first;
    return (widget.partner['email'] as String? ?? 'Partner').split('@').first;
  }

  void _goTo(LatLng p, {double zoom = 16}) {
    if (_ready) _map.move(p, zoom);
  }

  void _fitBoth(LatLng a, LatLng b) {
    if (!_ready) return;
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [a, b],
        padding: const EdgeInsets.fromLTRB(60, 140, 60, 300),
        maxZoom: 17,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SharedLocation?>(
      stream: _loc,
      builder: (context, snap) {
        final loc = snap.data;
        final partnerPt = loc == null ? null : LatLng(loc.lat, loc.lng);
        if (partnerPt != null &&
            _ready &&
            !_directions &&
            (_follow || !_centredOnce)) {
          _centredOnce = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _goTo(
                partnerPt,
                zoom: _map.camera.zoom < 13 ? 16 : _map.camera.zoom,
              );
            }
          });
        }

        return ValueListenableBuilder<Position?>(
          valueListenable: LocationService.instance.myPosition,
          builder: (context, me, _) {
            final mePt = me == null ? null : LatLng(me.latitude, me.longitude);
            _maybeRoute(mePt, partnerPt);
            final route = _directions ? _route : null;
            return Scaffold(
              body: Stack(
                children: [
                  FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: partnerPt ?? mePt ?? _defaultCenter,
                      initialZoom: partnerPt != null || mePt != null ? 16 : 6,
                      minZoom: 3,
                      maxZoom: 19,
                      onMapReady: () => setState(() => _ready = true),
                      onPositionChanged: (_, hasGesture) {
                        if (hasGesture && _follow) {
                          setState(() => _follow = false);
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.lifetrack.life_tracker',
                        // Dark mode: invert the map tiles (flutter_map helper).
                        tileBuilder: AppColors.isDark
                            ? darkModeTileBuilder
                            : null,
                        maxZoom: 19,
                      ),
                      if (loc != null && partnerPt != null && loc.accuracy > 0)
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: partnerPt,
                              radius: loc.accuracy.clamp(5, 500).toDouble(),
                              useRadiusInMeter: true,
                              color: _pink.withValues(alpha: 0.12),
                              borderColor: _pink.withValues(alpha: 0.35),
                              borderStrokeWidth: 1,
                            ),
                          ],
                        ),
                      if (route != null)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: route.points,
                              strokeWidth: 6,
                              color: _blue,
                              borderStrokeWidth: 2.5,
                              borderColor: Colors.white,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (mePt != null)
                            Marker(
                              point: mePt,
                              width: 26,
                              height: 26,
                              child: const _MeDot(),
                            ),
                          if (partnerPt != null)
                            Marker(
                              point: partnerPt,
                              width: 64,
                              height:
                                  70, // 58 avatar + 12 tip -> tip on the point
                              alignment: Alignment.topCenter,
                              child: _PartnerPin(
                                profile: widget.partner,
                                name: _name,
                              ),
                            ),
                        ],
                      ),
                      const SimpleAttributionWidget(
                        source: Text('OpenStreetMap contributors'),
                        alignment: Alignment.topRight,
                      ),
                    ],
                  ),
                  // ------------------------------------------------ top bar --
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                      child: Row(
                        children: [
                          _MapButton(
                            icon: Icons.arrow_back_rounded,
                            onTap: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              height: 46,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              alignment: Alignment.centerLeft,
                              decoration: _floating,
                              child: Text(
                                "$_name's location",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Alerts (driving / places / battery) and My places.
                          _MapButton(
                            icon: Icons.notifications_active_rounded,
                            onTap: () => showLocationAlertsSheet(
                              context,
                              myUid: widget.myUid,
                              partnerName: _name,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // --------------------------------------------- bottom card --
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14 + webBottomGap,
                    child: SafeArea(
                      top: false,
                      child: _directions
                          ? _DirectionsCard(
                              name: _name,
                              mode: _mode,
                              route: route,
                              error: mePt == null
                                  ? 'Finding your location… make sure location is on.'
                                  : partnerPt == null
                                  ? '$_name has no location yet.'
                                  : _routeError,
                              loading: route == null && _routeError == null,
                              onMode: _setMode,
                              onRetry: _retryRoute,
                              onClose: _closeDirections,
                              onStart: partnerPt == null
                                  ? null
                                  : () => _navigate(partnerPt),
                            )
                          : _InfoCard(
                              onDirections: partnerPt == null
                                  ? null
                                  : _openDirections,
                              name: _name,
                              profile: widget.partner,
                              loc: loc,
                              loading:
                                  snap.connectionState ==
                                  ConnectionState.waiting,
                              me: me,
                              following: _follow,
                              onPartner: partnerPt == null
                                  ? null
                                  : () {
                                      setState(() => _follow = true);
                                      _goTo(partnerPt);
                                    },
                              onMe: mePt == null
                                  ? null
                                  : () {
                                      setState(() => _follow = false);
                                      _goTo(mePt);
                                    },
                              onBoth: partnerPt == null || mePt == null
                                  ? null
                                  : () {
                                      setState(() => _follow = false);
                                      _fitBoth(partnerPt, mePt);
                                    },
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

BoxDecoration get _floating => BoxDecoration(
  color: AppColors.card,
  borderRadius: BorderRadius.circular(16),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.12),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ],
);

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.card,
    borderRadius: BorderRadius.circular(16),
    elevation: 3,
    shadowColor: Colors.black26,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SizedBox(width: 46, height: 46, child: Icon(icon)),
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.name,
    required this.profile,
    required this.loc,
    required this.loading,
    required this.me,
    required this.following,
    required this.onPartner,
    required this.onMe,
    required this.onBoth,
    required this.onDirections,
  });

  final String name;
  final Map<String, dynamic> profile;
  final SharedLocation? loc;
  final bool loading;
  final Position? me;
  final bool following;
  final VoidCallback? onPartner, onMe, onBoth, onDirections;

  @override
  Widget build(BuildContext context) {
    final l = loc;
    final updated = l?.updatedAt;
    final age = updated == null ? null : DateTime.now().difference(updated);
    final isLive = age != null && age.inMinutes < 2;

    String? distance;
    if (l != null && me != null) {
      final m = Geolocator.distanceBetween(
        me!.latitude,
        me!.longitude,
        l.lat,
        l.lng,
      );
      distance = m < 1000
          ? '${m.round()} m away'
          : '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)} km away';
    }
    final moving = l != null && l.speed > 1; // m/s
    final speed = moving ? '${(l.speed * 3.6).round()} km/h' : null;

    // Is the partner at one of their saved places (Home / Work)?
    String? atPlace;
    if (l != null) {
      for (final p in SavedPlace.fromProfile(profile)) {
        if (ActivityDetector.distance(p.lat, p.lng, l.lat, l.lng) <= p.radius) {
          atPlace = p.id;
          break;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _floating.copyWith(borderRadius: BorderRadius.circular(22)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Avatar(profile: profile, name: name, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (l == null)
                      Text(
                        loading ? 'Finding $name…' : 'No location yet',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12.5,
                        ),
                      )
                    else
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isLive ? _live : AppColors.muted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isLive ? 'Live now' : 'Last seen ${_ago(age)}',
                              style: TextStyle(
                                color: isLive ? _live : AppColors.muted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (l == null && !loading) ...[
            const SizedBox(height: 10),
            Text(
              '$name hasn\'t shared a location yet. It appears as soon as $name opens '
              'LifeTrack with location allowed.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          if (distance != null || speed != null || l != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (l != null && l.driving)
                  _Chip(
                    icon: Icons.directions_car_rounded,
                    text: 'Driving',
                    color: _blue,
                  ),
                if (atPlace != null)
                  _Chip(
                    icon: atPlace == 'work'
                        ? Icons.work_rounded
                        : Icons.home_rounded,
                    text: atPlace == 'work' ? 'At Work' : 'At Home',
                    color: _live,
                  ),
                if (l?.battery != null)
                  _Chip(
                    icon: l!.charging
                        ? Icons.battery_charging_full_rounded
                        : _batteryIcon(l.battery!),
                    text: '${l.battery}%${l.charging ? ' · charging' : ''}',
                    color: l.charging
                        ? _live
                        : (l.battery! <= 15 ? AppColors.red : null),
                  ),
                if (distance != null)
                  _Chip(icon: Icons.straighten_rounded, text: distance),
                if (speed != null)
                  _Chip(icon: Icons.speed_rounded, text: speed),
                if (l != null && l.accuracy > 0)
                  _Chip(
                    icon: Icons.gps_fixed_rounded,
                    text: '±${l.accuracy.round()} m',
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.person_pin_circle_rounded,
                  label: name,
                  color: _pink,
                  selected: following,
                  onTap: onPartner,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.my_location_rounded,
                  label: 'Me',
                  color: _blue,
                  onTap: onMe,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.zoom_out_map_rounded,
                  label: 'Both',
                  color: AppColors.purple,
                  onTap: onBoth,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: onDirections,
            icon: const Icon(Icons.directions_rounded),
            label: Text('Get directions to $name'),
          ),
        ],
      ),
    );
  }

  static String _ago(Duration? d) {
    if (d == null) return 'a while ago';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

/// Directions panel: travel mode, fastest route time & distance, arrival
/// time, and "Start navigation" (Google Maps, live traffic, turn-by-turn).
class _DirectionsCard extends StatelessWidget {
  const _DirectionsCard({
    required this.name,
    required this.mode,
    required this.route,
    required this.error,
    required this.loading,
    required this.onMode,
    required this.onRetry,
    required this.onClose,
    required this.onStart,
  });

  final String name;
  final TravelMode mode;
  final RouteResult? route;
  final String? error;
  final bool loading;
  final ValueChanged<TravelMode> onMode;
  final VoidCallback onRetry, onClose;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final r = route;
    final arrive = r == null
        ? null
        : TimeOfDay.fromDateTime(r.arrival).format(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _floating.copyWith(borderRadius: BorderRadius.circular(22)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_rounded, color: _blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Directions to $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final m in TravelMode.values) ...[
                Expanded(
                  child: ChoiceChip(
                    showCheckmark: false,
                    selected: m == mode,
                    onSelected: (_) => onMode(m),
                    selectedColor: _blue.withValues(alpha: 0.15),
                    avatar: Icon(
                      m.icon,
                      size: 18,
                      color: m == mode ? _blue : AppColors.muted,
                    ),
                    label: Text(m.label),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: m == mode ? _blue : AppColors.muted,
                    ),
                  ),
                ),
                if (m != TravelMode.values.last) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (error != null)
            Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(error!, style: const TextStyle(fontSize: 13)),
                ),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            )
          else if (r == null || loading)
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  'Finding the fastest route…',
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  r.durationText,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: _live,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '(${r.distanceText})',
                    style: TextStyle(fontSize: 15, color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Fastest ${mode.label.toLowerCase()} route'
              '${r.options > 1 ? ' of ${r.options} options' : ''} • arrive about $arrive',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
            const SizedBox(height: 2),
            Text(
              'Updates automatically if you or $name move.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: onStart,
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('Start navigation'),
          ),
          const SizedBox(height: 4),
          Text(
            'Opens Google Maps with live traffic and turn-by-turn voice guidance.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

IconData _batteryIcon(int level) => level <= 15
    ? Icons.battery_alert_rounded
    : level <= 50
    ? Icons.battery_3_bar_rounded
    : level <= 80
    ? Icons.battery_5_bar_rounded
    : Icons.battery_full_rounded;

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;

  /// Optional status colour (icon + text); default is muted.
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.bg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color ?? AppColors.muted),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: color != null ? FontWeight.w600 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final c = enabled ? color : AppColors.muted;
    return Material(
      color: selected ? c : c.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(icon, size: 20, color: selected ? Colors.white : c),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : c,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.profile,
    required this.name,
    required this.size,
  });
  final Map<String, dynamic> profile;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photo = profile['usePhoto'] != false
        ? profile['photoUrl'] as String?
        : null;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: avatarColorOf(profile),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        image: photo != null
            ? DecorationImage(image: NetworkImage(photo), fit: BoxFit.cover)
            : null,
      ),
      child: photo == null
          ? Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.4,
              ),
            )
          : null,
    );
  }
}

/// Avatar pin for the partner; its tip sits on the position.
class _PartnerPin extends StatelessWidget {
  const _PartnerPin({required this.profile, required this.name});
  final Map<String, dynamic> profile;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _pink,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _pink.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _Avatar(profile: profile, name: name, size: 52),
        ),
        CustomPaint(size: const Size(16, 12), painter: _TipPainter()),
      ],
    );
  }
}

class _TipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = _pink);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _blue.withValues(alpha: 0.2),
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: _blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
    ),
  );
}
