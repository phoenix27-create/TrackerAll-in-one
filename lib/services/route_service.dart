import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

enum TravelMode {
  car('Car', Icons.directions_car_rounded, 'routed-car', 'driving'),
  bike('Bike', Icons.pedal_bike_rounded, 'routed-bike', 'bicycling'),
  foot('Walk', Icons.directions_walk_rounded, 'routed-foot', 'walking');

  const TravelMode(this.label, this.icon, this.server, this.googleMode);
  final String label;
  final IconData icon;
  final String server; // routing.openstreetmap.de profile
  final String googleMode; // Google Maps travelmode
}

class RouteResult {
  RouteResult({
    required this.points,
    required this.meters,
    required this.seconds,
    required this.options,
  });
  final List<LatLng> points;
  final double meters;
  final double seconds;

  /// How many routes were compared (the fastest one is returned).
  final int options;

  String get distanceText => meters < 1000
      ? '${meters.round()} m'
      : '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} km';

  String get durationText {
    final m = (seconds / 60).round();
    if (m < 1) return '1 min';
    if (m < 60) return '$m min';
    final h = m ~/ 60, r = m % 60;
    return r == 0 ? '$h h' : '$h h $r min';
  }

  DateTime get arrival =>
      DateTime.now().add(Duration(seconds: seconds.round()));
}

class RouteException implements Exception {
  RouteException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Directions on the free OpenStreetMap routing servers (OSRM by FOSSGIS),
/// no API key or billing. Asks for alternative routes and keeps the FASTEST.
/// "Start navigation" hands over to Google Maps for turn-by-turn with live traffic.
class RouteService {
  RouteService._();
  static final instance = RouteService._();

  Future<RouteResult> fastest(LatLng from, LatLng to, TravelMode mode) async {
    final uri = Uri.parse(
      'https://routing.openstreetmap.de/${mode.server}/route/v1/driving/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson&alternatives=3&steps=false',
    );
    final http.Response res;
    try {
      res = await http.get(uri).timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Route request failed: $e');
      throw RouteException(
        'No internet connection, or the route server is busy. Try again.',
      );
    }
    if (res.statusCode != 200) {
      throw RouteException(
        'Route server error (${res.statusCode}). Try again in a moment.',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = (body['routes'] as List?) ?? const [];
    if (body['code'] != 'Ok' || routes.isEmpty) {
      throw RouteException(
        'No ${mode.label.toLowerCase()} route found to your partner.',
      );
    }
    // Pick the quickest of the alternatives.
    final best = routes.cast<Map<String, dynamic>>().reduce(
      (a, b) => (a['duration'] as num) <= (b['duration'] as num) ? a : b,
    );
    final coords = (best['geometry']['coordinates'] as List)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
    return RouteResult(
      points: coords,
      meters: (best['distance'] as num).toDouble(),
      seconds: (best['duration'] as num).toDouble(),
      options: routes.length,
    );
  }

  /// Opens turn-by-turn navigation (Google Maps app, or Google Maps on the web).
  Future<bool> startNavigation(LatLng to, TravelMode mode) {
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${to.latitude},${to.longitude}',
      'travelmode': mode.googleMode,
      'dir_action': 'navigate',
    });
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
