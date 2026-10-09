import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../models/place_result.dart';

/// Place search on OpenStreetMap data via Photon (photon.komoot.io).
///
/// Free, no key. It is a shared public server: keep requests light (the UI
/// debounces typing) and always send a User-Agent that identifies the app.
class PlaceSearchService {
  PlaceSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _host = 'photon.komoot.io';

  /// [nearLat]/[nearLng] bias results towards that point (usually the user).
  Future<List<PlaceResult>> search(
    String query, {
    double? nearLat,
    double? nearLng,
    int limit = 8,
  }) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    final uri = Uri.https(_host, '/api/', {
      'q': q,
      'limit': '$limit',
      if (nearLat != null && nearLng != null) ...{
        'lat': nearLat.toStringAsFixed(5),
        'lon': nearLng.toStringAsFixed(5),
      },
    });
    final res = await _client
        .get(uri, headers: {'User-Agent': AppConstants.httpUserAgent})
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw PlaceSearchException('Search failed (${res.statusCode}).');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final features = (body['features'] as List?) ?? const [];
    return features
        .whereType<Map<String, dynamic>>()
        .map(_toResult)
        .whereType<PlaceResult>()
        .toList();
  }

  PlaceResult? _toResult(Map<String, dynamic> feature) {
    final coords = (feature['geometry'] as Map?)?['coordinates'] as List?;
    final props = (feature['properties'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    if (coords == null || coords.length < 2) return null;

    String? s(String key) {
      final v = props[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final street = [s('housenumber'), s('street')].whereType<String>().join(' ');
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
