import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../models/place_result.dart';

/// Place search on OpenStreetMap data.
///
/// With a Geoapify key ([Env.useGeoapify]) it uses Geoapify Autocomplete.
/// Without one it falls back to the public Photon server (photon.komoot.io),
/// which is a shared demo: development only, keep requests light.
class PlaceSearchService {
  PlaceSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _photonHost = 'photon.komoot.io';
  static const _geoapifyHost = 'api.geoapify.com';

  /// [nearLat]/[nearLng] bias results towards that point (usually the user).
  Future<List<PlaceResult>> search(
    String query, {
    double? nearLat,
    double? nearLng,
    int limit = 8,
  }) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    return Env.useGeoapify
        ? _geoapify(q, nearLat, nearLng, limit)
        : _photon(q, nearLat, nearLng, limit);
  }

  /// Geoapify's proximity `bias` alone is weak (a search near KLCC for
  /// "Pavilion" ranked Penang, Iraq and the UK first). So with a location we
  /// ask for places within [nearbyRadiusM] first, and only widen to the
  /// biased worldwide search when that finds fewer than [minNearby].
  /// Usually 1 credit per search, 2 when little is nearby.
  static const nearbyRadiusM = 50000;
  static const minNearby = 3;

  Future<List<PlaceResult>> _geoapify(
    String q,
    double? lat,
    double? lng,
    int limit,
  ) async {
    Uri uri({
      bool nearbyOnly = false,
    }) => Uri.https(_geoapifyHost, '/v1/geocode/autocomplete', {
      'text': q,
      'limit': '$limit',
      'format': 'json',
      if (lat != null && lng != null) ...{
        if (nearbyOnly)
          'filter':
              'circle:${lng.toStringAsFixed(5)},${lat.toStringAsFixed(5)},$nearbyRadiusM',
        'bias': 'proximity:${lng.toStringAsFixed(5)},${lat.toStringAsFixed(5)}',
      },
      'apiKey': Env.geoapifyKey,
    });

    if (lat == null || lng == null) return parseGeoapify(await _getJson(uri()));

    final nearby = parseGeoapify(await _getJson(uri(nearbyOnly: true)));
    if (nearby.length >= minNearby) return nearby;
    final wider = parseGeoapify(await _getJson(uri()));
    return mergeResults(nearby, wider, limit);
  }

  /// [first] then [second], skipping places already listed (same name within
  /// about 100 m), capped at [limit].
  @visibleForTesting
  static List<PlaceResult> mergeResults(
    List<PlaceResult> first,
    List<PlaceResult> second,
    int limit,
  ) {
    String key(PlaceResult r) =>
        '${r.name.toLowerCase()}|'
        '${r.latitude.toStringAsFixed(3)},${r.longitude.toStringAsFixed(3)}';
    final seen = <String>{};
    final out = <PlaceResult>[];
    for (final r in [...first, ...second]) {
      if (out.length >= limit) break;
      if (seen.add(key(r))) out.add(r);
    }
    return out;
  }

  /// Geoapify Autocomplete (format=json) body -> results.
  @visibleForTesting
  static List<PlaceResult> parseGeoapify(Map<String, dynamic> body) {
    final results = (body['results'] as List?) ?? const [];
    final out = <PlaceResult>[];
    for (final r in results.whereType<Map<String, dynamic>>()) {
      final la = r['lat'], lo = r['lon'];
      if (la is! num || lo is! num) continue;
      String? s(String key) {
        final v = r[key];
        return v is String && v.trim().isNotEmpty ? v.trim() : null;
      }

      final name = s('name') ?? s('address_line1');
      if (name == null) continue;
      var subtitle = s('address_line2') ?? '';
      if (subtitle.isEmpty || subtitle == name) {
        subtitle = [s('city'), s('state')].whereType<String>().join(', ');
      }
      out.add(
        PlaceResult(
          name: name,
          subtitle: subtitle,
          latitude: la.toDouble(),
          longitude: lo.toDouble(),
        ),
      );
    }
    return out;
  }

  Future<List<PlaceResult>> _photon(
    String q,
    double? nearLat,
    double? nearLng,
    int limit,
  ) async {
    final uri = Uri.https(_photonHost, '/api/', {
      'q': q,
      'limit': '$limit',
      if (nearLat != null && nearLng != null) ...{
        'lat': nearLat.toStringAsFixed(5),
        'lon': nearLng.toStringAsFixed(5),
      },
    });
    return parsePhoton(await _getJson(uri));
  }

  /// Photon GeoJSON body -> results.
  @visibleForTesting
  static List<PlaceResult> parsePhoton(Map<String, dynamic> body) {
    final features = (body['features'] as List?) ?? const [];
    return features
        .whereType<Map<String, dynamic>>()
        .map(_toResult)
        .whereType<PlaceResult>()
        .toList();
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final res = await _client
        .get(uri, headers: AppConstants.httpHeaders)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw PlaceSearchException('Search failed (${res.statusCode}).');
    }
    try {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw const PlaceSearchException('Search failed. Try again.');
    }
  }

  static PlaceResult? _toResult(Map<String, dynamic> feature) {
    final coords = (feature['geometry'] as Map?)?['coordinates'] as List?;
    final props =
        (feature['properties'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    if (coords == null || coords.length < 2) return null;

    String? s(String key) {
      final v = props[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final street = [
      s('housenumber'),
      s('street'),
    ].whereType<String>().join(' ');
    final name = s('name') ?? (street.isNotEmpty ? street : null);
    if (name == null) return null;
    final parts = <String>[
      if (street.isNotEmpty && street != name) street,
      ...[s('district'), s('city'), s('state')].whereType<String>(),
    ];
    // Drop repeats like "Melaka, Melaka".
    final seen = <String>{};
    final subtitle = parts.where((p) => seen.add(p.toLowerCase())).join(', ');

    return PlaceResult(
      name: name,
      subtitle: subtitle,
      latitude: (coords[1] as num).toDouble(),
      longitude: (coords[0] as num).toDouble(),
    );
  }
}

class PlaceSearchException implements Exception {
  const PlaceSearchException(this.message);
  final String message;

  @override
  String toString() => message;
}
