import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
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

/// Driving routes.
///
/// With a Geoapify key ([Env.useGeoapify]) it uses Geoapify Routing and Route
/// Matrix. Without one it falls back to the public OSRM demo server
/// (router.project-osrm.org): development only, not for real traffic.
class RoutingService {
  RoutingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _host = 'router.project-osrm.org';
  static const _geoapifyHost = 'api.geoapify.com';

  /// Brute-force (Held-Karp) the visiting order up to this many stops; above
  /// it, nearest-neighbour. 10 stops is ~100k states, instant on a phone.
  static const _exactOrderLimit = 10;

  /// Route through [start] then [stops] exactly in the given order.
  Future<RouteResult> route(LatLng start, List<LatLng> stops) async {
    if (Env.useGeoapify) return _geoapifyRoute(start, stops);
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
    if (Env.useGeoapify) return _geoapifyBestOrder(start, stops);
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

  // ---------- Geoapify ----------

  Future<RouteResult> _geoapifyRoute(
      LatLng start, List<LatLng> stops, {List<int>? order}) async {
    final points = [start, ...stops];
    final uri = Uri.https(_geoapifyHost, '/v1/routing', {
      'waypoints': points
          .map((p) =>
              '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}')
          .join('|'),
      'mode': 'drive',
      'apiKey': Env.geoapifyKey,
    });
    final res = await _client
        .get(uri, headers: {'User-Agent': AppConstants.httpUserAgent})
        .timeout(const Duration(seconds: 15));
    final json = _decode(res);
    final features = (json['features'] as List?) ?? const [];
    if (features.isEmpty) throw const RoutingException('No route found.');
    final f = features.first as Map<String, dynamic>;
    final props = (f['properties'] as Map?)?.cast<String, dynamic>() ?? {};
    return RouteResult(
      path: flattenLonLat((f['geometry'] as Map?)?['coordinates']),
      distanceMeters: (props['distance'] as num? ?? 0).toDouble(),
      durationSeconds: (props['time'] as num? ?? 0).toDouble(),
      order: order ?? List<int>.generate(stops.length, (i) => i),
      legs: [
        for (final l in (props['legs'] as List?) ?? const [])
          (
            meters: ((l as Map)['distance'] as num? ?? 0).toDouble(),
            seconds: (l['time'] as num? ?? 0).toDouble(),
          ),
      ],
    );
  }

  /// Road travel times between every pair (one Route Matrix call), then the
  /// best open path from [start] through all stops, then one route call.
  Future<RouteResult> _geoapifyBestOrder(
      LatLng start, List<LatLng> stops) async {
    if (stops.length < 2) return _geoapifyRoute(start, stops);
    final points = [start, ...stops];
    final locs = [
      for (final p in points)
        {
          'location': [p.longitude, p.latitude]
        }
    ];
    final res = await _client
        .post(
          Uri.https(_geoapifyHost, '/v1/routematrix',
              {'apiKey': Env.geoapifyKey}),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': AppConstants.httpUserAgent,
          },
          body: jsonEncode({'mode': 'drive', 'sources': locs, 'targets': locs}),
        )
        .timeout(const Duration(seconds: 20));
    final json = _decode(res);
    final rows = (json['sources_to_targets'] as List?) ?? const [];
    final n = points.length;
    // cost[i][j]: seconds from point i to point j; unreachable = huge.
    const unreachable = 1e12;
    final cost = List.generate(n, (_) => List<double>.filled(n, unreachable));
    for (final row in rows) {
      for (final cell in (row as List)) {
        if (cell is! Map) continue;
        final c = cell;
        final i = (c['source_index'] as num?)?.toInt();
        final j = (c['target_index'] as num?)?.toInt();
        final t = c['time'] as num?;
        if (i != null && j != null && i < n && j < n && t != null) {
          cost[i][j] = t.toDouble();
        }
      }
    }
    final order = stops.length <= _exactOrderLimit
        ? exactOrder(cost)
        : greedyOrder(cost);
    final ordered = [for (final i in order) stops[i]];
    return _geoapifyRoute(start, ordered, order: order);
  }

  /// Held-Karp over stops 1..n-1 (index 0 is the start), open path.
  /// Returns stop indexes (0-based into stops) in visiting order.
  @visibleForTesting
  static List<int> exactOrder(List<List<double>> cost) {
    final m = cost.length - 1; // number of stops
    final full = 1 << m;
    final dp = List.generate(full, (_) => List<double>.filled(m, double.infinity));
    final parent = List.generate(full, (_) => List<int>.filled(m, -1));
    for (var k = 0; k < m; k++) {
      dp[1 << k][k] = cost[0][k + 1];
    }
    for (var mask = 1; mask < full; mask++) {
      for (var last = 0; last < m; last++) {
        final cur = dp[mask][last];
        if ((mask & (1 << last)) == 0 || cur == double.infinity) continue;
        for (var next = 0; next < m; next++) {
          if ((mask & (1 << next)) != 0) continue;
          final nm = mask | (1 << next);
          final v = cur + cost[last + 1][next + 1];
          if (v < dp[nm][next]) {
            dp[nm][next] = v;
            parent[nm][next] = last;
          }
        }
      }
    }
    var best = 0;
    for (var k = 1; k < m; k++) {
      if (dp[full - 1][k] < dp[full - 1][best]) best = k;
    }
    final order = <int>[];
    var mask = full - 1;
    var cur = best;
    while (cur != -1) {
      order.add(cur);
      final prev = parent[mask][cur];
      mask &= ~(1 << cur);
      cur = prev;
    }
    return order.reversed.toList();
  }

  /// Nearest unvisited stop each time. Used only for very long trips.
  @visibleForTesting
  static List<int> greedyOrder(List<List<double>> cost) {
    final m = cost.length - 1;
    final left = {for (var k = 0; k < m; k++) k};
    final order = <int>[];
    var at = 0; // matrix index of current point
    while (left.isNotEmpty) {
      final next = left.reduce(
          (a, b) => cost[at][a + 1] <= cost[at][b + 1] ? a : b);
      order.add(next);
      left.remove(next);
      at = next + 1;
    }
    return order;
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on Object {
      throw RoutingException('Routing server is busy (${res.statusCode}). Try again.');
    }
    if (res.statusCode != 200) {
      throw RoutingException((json['message'] as String?) ??
          'Routing failed (${res.statusCode}).');
    }
    return json;
  }

  /// GeoJSON LineString / MultiLineString coordinates ([lon, lat]) -> points.
  @visibleForTesting
  static List<LatLng> flattenLonLat(Object? coords) {
    final out = <LatLng>[];
    void walk(Object? node) {
      if (node is! List || node.isEmpty) return;
      if (node.length >= 2 && node[0] is num && node[1] is num) {
        out.add(LatLng((node[1] as num).toDouble(), (node[0] as num).toDouble()));
        return;
      }
      for (final child in node) {
        walk(child);
      }
    }

    walk(coords);
    return out;
  }

  // ---------- OSRM (fallback) ----------

  Future<Map<String, dynamic>> _get(
      String path, Map<String, String> query) async {
    final res = await _client
        .get(Uri.https(_host, path, query),
            headers: {'User-Agent': AppConstants.httpUserAgent})
        .timeout(const Duration(seconds: 15));
    Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } on Object {
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
