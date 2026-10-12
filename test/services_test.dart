import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/services/place_search_service.dart';
import 'package:nearby/services/routing_service.dart';

/// Brute force: cost of the best open path from point 0 through all stops.
double bestCost(List<List<double>> c) {
  final m = c.length - 1;
  var best = double.infinity;
  void go(List<int> path, Set<int> left, double cost) {
    if (cost >= best) return;
    if (left.isEmpty) {
      best = cost;
      return;
    }
    final at = path.isEmpty ? 0 : path.last + 1;
    for (final k in left.toList()) {
      go([...path, k], {...left}..remove(k), cost + c[at][k + 1]);
    }
  }

  go([], {for (var k = 0; k < m; k++) k}, 0);
  return best;
}

double pathCost(List<List<double>> c, List<int> order) {
  var at = 0, total = 0.0;
  for (final k in order) {
    total += c[at][k + 1];
    at = k + 1;
  }
  return total;
}

List<List<double>> randomMatrix(Random r, int n) => List.generate(
    n, (i) => List.generate(n, (j) => i == j ? 0.0 : 60 + r.nextInt(1800).toDouble()));

void main() {
  group('RoutingService.exactOrder (shortest visiting order)', () {
    test('visits every stop exactly once', () {
      final r = Random(1);
      for (var n = 3; n <= 9; n++) {
        final order = RoutingService.exactOrder(randomMatrix(r, n));
        expect(order.toSet(), {for (var k = 0; k < n - 1; k++) k});
        expect(order.length, n - 1);
      }
    });

    test('matches brute force on random asymmetric matrices', () {
      final r = Random(42);
      for (var trial = 0; trial < 40; trial++) {
        final n = 3 + r.nextInt(5); // 2..6 stops
        final c = randomMatrix(r, n);
        expect(pathCost(c, RoutingService.exactOrder(c)),
            closeTo(bestCost(c), 1e-6));
      }
    });

    test('obvious line: visits stops in distance order', () {
      // Start at 0 km, stops at 3, 1, 2 km along one road (seconds = km).
      final pos = [0.0, 3.0, 1.0, 2.0];
      final c = [
        for (final a in pos) [for (final b in pos) (a - b).abs()]
      ];
      expect(RoutingService.exactOrder(c), [1, 2, 0]);
    });

    test('unreachable pair is avoided when another order exists', () {
      const x = 1e12;
      final c = [
        [0.0, 10.0, 10.0],
        [10.0, 0.0, x], // stop 0 -> stop 1 has no road
        [10.0, 10.0, 0.0],
      ];
      expect(RoutingService.exactOrder(c), [1, 0]);
    });
  });

  test('RoutingService.greedyOrder visits every stop once', () {
    final r = Random(7);
    final c = randomMatrix(r, 14);
    final order = RoutingService.greedyOrder(c);
    expect(order.toSet().length, 13);
  });

  test('RoutingService.flattenLonLat reads MultiLineString as lat/lng', () {
    final pts = RoutingService.flattenLonLat([
      [
        [102.10, 2.35],
        [102.11, 2.36],
      ],
      [
        [102.11, 2.36],
        [102.12, 2.37],
      ],
    ]);
    expect(pts.length, 4);
    expect(pts.first.latitude, 2.35);
    expect(pts.first.longitude, 102.10);
    expect(pts.last.latitude, 2.37);
  });

  group('PlaceSearchService parsers', () {
    test('Geoapify autocomplete', () {
      final res = PlaceSearchService.parseGeoapify({
        'results': [
          {
            'name': 'Masjid Al-Sultan Abdullah',
            'address_line1': 'Masjid Al-Sultan Abdullah',
            'address_line2': 'Masjid Tanah, Melaka, Malaysia',
            'lat': 2.3503338,
            'lon': 102.1094493,
          },
          {
            // No name: falls back to address_line1.
            'address_line1': 'Jalan Stadium',
            'address_line2': 'Masjid Tanah, Melaka',
            'lat': 2.35,
            'lon': 102.11,
          },
          {'name': 'Missing coords'},
        ],
      });
      expect(res.length, 2);
      expect(res[0].name, 'Masjid Al-Sultan Abdullah');
      expect(res[0].subtitle, 'Masjid Tanah, Melaka, Malaysia');
      expect(res[0].latitude, 2.3503338);
      expect(res[1].name, 'Jalan Stadium');
    });

    test('Photon GeoJSON, drops "Melaka, Melaka" repeats', () {
      final res = PlaceSearchService.parsePhoton({
        'features': [
          {
            'geometry': {
              'coordinates': [102.25, 2.19]
            },
            'properties': {
              'name': 'AEON Bandaraya Melaka',
              'city': 'Melaka',
              'state': 'Melaka',
            },
          },
        ],
      });
      expect(res.single.name, 'AEON Bandaraya Melaka');
      expect(res.single.subtitle, 'Melaka');
      expect(res.single.longitude, 102.25);
    });
  });
}
