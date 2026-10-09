import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/constants.dart';

/// A driving route through points in a given order.
class RouteResult {
  const RouteResult({
    required this.path,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.order,
    required this.legs,
  });

  /// One entry per hop, in visiting order: start -> 1st stop, 1st -> 2nd, ...
  final List<({double meters, double seconds})> legs;

  /// Line to draw on the map.
  final List<LatLng> path;
  final double distanceMeters;
  final double durationSeconds;

  /// For [RoutingService.bestOrder]: stop indexes (into the list passed in,
  /// excluding the start) in visiting order. For [RoutingService.route] this
  /// is simply 0..n-1.
  final List<int> order;
}

/// Driving routes from OSRM (router.project-osrm.org).
///
/// The public OSRM server is a free demo: fine for a portfolio app with light
/// use, not for heavy traffic. Swap [_host] for a self-hosted OSRM or move to
/// OpenRouteService if usage grows.
class RoutingService {
  RoutingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _host = 'router.project-osrm.org';

  /// Route through [start] then [stops] exactly in the given order.
  Future<RouteResult> route(LatLng start, List<LatLng> stops) async {
    final json = await _get('/route/v1/driving/${_coords([start, ...stops])}', {
      'overview': 'full',
      'geometries': 'geojson',
    });
    final routes = (json['routes'] as List?) ?? const [];
    if (routes.isEmpty) throw const RoutingException('No route found.');
    final r = routes.first as Map<String, dynamic>;
    return RouteResult(
      path: _path(r['geometry']),
      distanceMeters: (r['distance'] as num).toDouble(),
      durationSeconds: (r['duration'] as num).toDouble(),
      order: List<int>.generate(stops.length, (i) => i),
      legs: _legs(r['legs']),
    );
  }

  /// Shortest order to visit every stop, starting at [start] and ending at
  /// whichever stop is best (no return trip).
  Future<RouteResult> bestOrder(LatLng start, List<LatLng> stops) async {
    final json = await _get('/trip/v1/driving/${_coords([start, ...stops])}', {
      'source': 'first',
      'destination': 'any',
      'roundtrip': 'false',
      'overview': 'full',
      'geometries': 'geojson',
    });
    final trips = (json['trips'] as List?) ?? const [];
    final waypoints = (json['waypoints'] as List?) ?? const [];
    if (trips.isEmpty || waypoints.length != stops.length + 1) {
      throw const RoutingException('Could not work out an order.');
    }
    // waypoints[i] is input point i; waypoint_index is its position in the trip.
    final positions = <int, int>{};
    for (var i = 1; i < waypoints.length; i++) {
      final w = waypoints[i] as Map<String, dynamic>;
      positions[i - 1] = (w['waypoint_index'] as num).toInt();
    }
    final order = positions.keys.toList()
      ..sort((a, b) => positions[a]!.compareTo(positions[b]!));
    final t = trips.first as Map<String, dynamic>;
    return RouteResult(
      path: _path(t['geometry']),
      distanceMeters: (t['distance'] as num).toDouble(),
      durationSeconds: (t['duration'] as num).toDouble(),
      order: order,
      legs: _legs(t['legs']),
    );
  }

  Future<Map<String, dynamic>> _get(
      String path, Map<String, String> query) async {
    final res = await _client
        .get(Uri.https(_host, path, query),
            headers: {'User-Agent': AppConstants.httpUserAgent})
        .timeout(const Duration(seconds: 15));
    Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } on FormatException {
      throw RoutingException('Routing server is busy (${res.statusCode}). Try again.');
    }
    if (res.statusCode != 200 || json['code'] != 'Ok') {
      throw RoutingException(
          (json['message'] as String?) ?? 'Routing failed (${res.statusCode}).');
    }
    return json;
  }

  // OSRM wants lon,lat pairs joined by ';'.
  static String _coords(List<LatLng> points) => points
      .map((p) =>
          '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
      .join(';');

  static List<({double meters, double seconds})> _legs(Object? legs) => [
        for (final l in (legs as List?) ?? const [])
          (
            meters: ((l as Map)['distance'] as num).toDouble(),
            seconds: (l['duration'] as num).toDouble(),
          ),
      ];

  static List<LatLng> _path(Object? geometry) {
    final coords = (geometry as Map?)?['coordinates'] as List? ?? const [];
    return [
      for (final c in coords)
        LatLng(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble()),
    ];
  }
}

class RoutingException implements Exception {
  const RoutingException(this.message);
  final String message;

  @override
  String toString() => message;
}
