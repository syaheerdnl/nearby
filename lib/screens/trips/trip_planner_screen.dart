import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/zone.dart';
import '../../providers/zone_provider.dart';
import '../../services/routing_service.dart';
import '../../widgets/map_credit.dart';

/// Pick saved places to visit, get the shortest order (or drag your own),
/// see the route, then hand it to Google Maps for turn-by-turn.
class TripPlannerScreen extends StatefulWidget {
  const TripPlannerScreen({super.key, this.start});

  /// Where the trip starts. Falls back to a fresh GPS fix, then to the first stop.
  final LatLng? start;

  @override
  State<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends State<TripPlannerScreen> {
  final _map = MapController();
  final _routing = RoutingService();
  final List<Zone> _stops = [];
  LatLng? _start;
  RouteResult? _route;
  bool _busy = false;
  String? _error;
  int _routeRequest = 0;

  @override
  void initState() {
    super.initState();
    _start = widget.start;
    if (_start == null) _locate();
  }

  Future<void> _locate() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() => _start = LatLng(pos.latitude, pos.longitude));
      _refreshRoute();
    } catch (_) {
      // No fix: the first stop becomes the start.
    }
  }

  LatLng _point(Zone z) => LatLng(z.latitude, z.longitude);

  /// The route always begins at [_start], or at the first stop without GPS.
  ({LatLng from, List<Zone> visit})? get _legs {
    if (_stops.isEmpty) return null;
    if (_start != null) return (from: _start!, visit: List.of(_stops));
    if (_stops.length < 2) return null;
    return (from: _point(_stops.first), visit: _stops.sublist(1));
  }

  Future<void> _refreshRoute() async {
    final legs = _legs;
    final id = ++_routeRequest;
    if (legs == null || legs.visit.isEmpty) {
      setState(() {
        _route = null;
        _error = null;
        _busy = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r =
          await _routing.route(legs.from, legs.visit.map(_point).toList());
      if (!mounted || id != _routeRequest) return;
      setState(() => _route = r);
      _fit();
    } catch (e) {
      if (!mounted || id != _routeRequest) return;
      setState(() {
        _route = null;
        _error = 'Could not get a route: $e';
      });
    } finally {
      if (mounted && id == _routeRequest) setState(() => _busy = false);
    }
  }

  Future<void> _bestOrder() async {
    final legs = _legs;
    if (legs == null || legs.visit.length < 2) return;
    final id = ++_routeRequest;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _routing.bestOrder(
          legs.from, legs.visit.map(_point).toList());
      if (!mounted || id != _routeRequest) return;
      final reordered = [for (final i in r.order) legs.visit[i]];
      setState(() {
        if (_start == null) {
          final first = _stops.first;
          _stops
            ..clear()
            ..add(first)
            ..addAll(reordered);
        } else {
          _stops
            ..clear()
            ..addAll(reordered);
        }
        _route = r;
      });
      _fit();
    } catch (e) {
      if (!mounted || id != _routeRequest) return;
      setState(() => _error = 'Could not work out an order: $e');
    } finally {
      if (mounted && id == _routeRequest) setState(() => _busy = false);
    }
  }

  void _fit() {
    final points = [
      if (_start != null) _start!,
      ..._stops.map(_point),
      ...?_route?.path,
    ];
    if (points.length < 2) return;
    _map.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.all(48),
      maxZoom: 16,
    ));
  }

  Future<void> _pickStops(List<Zone> zones) async {
    final chosen = await showModalBottomSheet<List<Zone>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StopPicker(zones: zones, selected: _stops),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      // Keep the current order for stops that stay; append new ones.
      _stops.removeWhere((z) => !chosen.any((c) => c.id == z.id));
      for (final z in chosen) {
        if (!_stops.any((s) => s.id == z.id)) _stops.add(z);
      }
    });
    _refreshRoute();
  }

  Future<void> _openInGoogleMaps() async {
    if (_stops.isEmpty) return;
    String ll(LatLng p) =>
        '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';
    // Without GPS the trip starts at stop 1, so that becomes the origin.
    final origin = _start ?? _point(_stops.first);
    final middle = _start == null ? _stops.skip(1).toList() : _stops;
    if (middle.isEmpty) return;
    final destination = _point(middle.last);
    final waypoints = middle
        .sublist(0, middle.length - 1)
        .map((z) => ll(_point(z)))
        .join('|');
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'origin': ll(origin),
      'destination': ll(destination),
      if (waypoints.isNotEmpty) 'waypoints': waypoints,
      'travelmode': 'driving',
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')));
    }
  }

  static String _km(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  static String _mins(double s) {
    final m = (s / 60).round();
    return m < 60 ? '$m min' : '${m ~/ 60} h ${m % 60} min';
  }

  /// Leg that ends at stop [i], if the route has one.
  ({double meters, double seconds})? _legFor(int i) {
    final legs = _route?.legs;
    if (legs == null) return null;
    final li = _start == null ? i - 1 : i;
    return (li >= 0 && li < legs.length) ? legs[li] : null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ZoneProvider>();
    final zones = provider.zones;
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final muted = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    final center = _start ??
        (zones.isNotEmpty
            ? _point(zones.first)
            : const LatLng(AppConstants.fallbackLatitude,
                AppConstants.fallbackLongitude));

    return Scaffold(
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.38,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(initialCenter: center, initialZoom: 14),
                  children: [
                    TileLayer(
                      urlTemplate: AppConstants.tileUrl,
                      userAgentPackageName: AppConstants.userAgentPackageName,
                    ),
                    if (_route != null && _route!.path.length > 1)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: _route!.path,
                          strokeWidth: 4,
                          color: scheme.primary,
                        ),
                      ]),
                    MarkerLayer(markers: [
                      if (_start != null)
                        Marker(
                          point: _start!,
                          width: 18,
                          height: 18,
                          child: Container(
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                            ),
                          ),
                        ),
                      for (var i = 0; i < _stops.length; i++)
                        Marker(
                          point: _point(_stops[i]),
                          width: 24,
                          height: 24,
                          child: _StopNumber(
                              n: i + 1, color: _stops[i].category.color),
                        ),
                    ]),
                    const MapCredit(),
                  ],
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton.filledTonal(
                      style: IconButton.styleFrom(
                          backgroundColor: scheme.surface),
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Material(
              color: scheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  _stops.isEmpty
                                      ? 'Plan a trip'
                                      : '${_stops.length} stop${_stops.length == 1 ? '' : 's'}',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                _route != null
                                    ? '${_km(_route!.distanceMeters)} · about ${_mins(_route!.durationSeconds)}'
                                    : _busy
                                        ? 'Working out the route...'
                                        : (_stops.isEmpty
                                            ? 'Pick where you need to go today'
                                            : (_start == null
                                                ? 'Location off, starting at stop 1'
                                                : ' ')),
                                style: muted,
                              ),
                            ],
                          ),
                        ),
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        TextButton(
                          onPressed: _busy || (_legs?.visit.length ?? 0) < 2
                              ? null
                              : _bestOrder,
                          child: const Text('Shortest order'),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Text(_error!,
                          style: TextStyle(color: scheme.error, fontSize: 13)),
                    ),
                  Expanded(
                    child: zones.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                  'Save a few places first, then plan a trip through them.',
                                  textAlign: TextAlign.center,
                                  style: muted),
                            ),
                          )
                        : ReorderableListView.builder(
                            buildDefaultDragHandles: false,
                            padding: const EdgeInsets.only(top: 6),
                            header: _start == null
                                ? null
                                : _TimelineRow(
                                    marker: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: scheme.primary, width: 2),
                                      ),
                                    ),
                                    lineBelow: _stops.isNotEmpty,
                                    title: 'You',
                                  ),
                            itemCount: _stops.length,
                            onReorder: (oldIndex, newIndex) {
                              setState(() {
                                if (newIndex > oldIndex) newIndex -= 1;
                                _stops.insert(
                                    newIndex, _stops.removeAt(oldIndex));
                              });
                              _refreshRoute();
                            },
                            itemBuilder: (_, i) {
                              final z = _stops[i];
                              final leg = _legFor(i);
                              final todo = provider
                                  .remindersFor(z.id)
                                  .where((r) => r.active)
                                  .length;
                              final parts = <String>[
                                if (leg != null)
                                  '${_km(leg.meters)} · ${_mins(leg.seconds)}',
                                if (todo > 0)
                                  '$todo to remember',
                              ];
                              return _TimelineRow(
                                key: ValueKey(z.id),
                                marker: _StopNumber(
                                    n: i + 1, color: z.category.color),
                                lineBelow: i < _stops.length - 1,
                                title: z.name,
                                subtitle: parts.join(' · '),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Remove stop',
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(Icons.close,
                                          size: 18,
                                          color: scheme.onSurfaceVariant),
                                      onPressed: () {
                                        setState(() => _stops.removeAt(i));
                                        _refreshRoute();
                                      },
                                    ),
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Icon(Icons.drag_handle,
                                            color: scheme.outline),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: zones.isEmpty
                                  ? null
                                  : () => _pickStops(zones),
                              icon: const Icon(Icons.add),
                              label: const Text('Stop'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed:
                                  _stops.isEmpty ? null : _openInGoogleMaps,
                              icon: const Icon(Icons.navigation_outlined),
                              label: const Text('Go in Google Maps'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StopNumber extends StatelessWidget {
  const _StopNumber({required this.n, required this.color});

  final int n;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text('$n',
          style: const TextStyle(
              color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

/// One row of the stop timeline: marker + rail on the left, text, actions.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    super.key,
    required this.marker,
    required this.lineBelow,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final Widget marker;
  final bool lineBelow;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(width: 16),
            SizedBox(
              width: 26,
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  marker,
                  Expanded(
                    child: Container(
                      width: 2,
                      color: lineBelow
                          ? scheme.outline.withValues(alpha: 0.6)
                          : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ),
            if (trailing != null) trailing!,
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _StopPicker extends StatefulWidget {
  const _StopPicker({required this.zones, required this.selected});

  final List<Zone> zones;
  final List<Zone> selected;

  @override
  State<_StopPicker> createState() => _StopPickerState();
}

class _StopPickerState extends State<_StopPicker> {
  late final Set<String> _ids = {for (final z in widget.selected) z.id};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Where are you going?',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final z in widget.zones)
                  CheckboxListTile(
                    value: _ids.contains(z.id),
                    title: Text(z.name),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _ids.add(z.id);
                      } else {
                        _ids.remove(z.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: () => Navigator.pop(
                  context,
                  // Keep the order the user picked them in.
                  [
                    ...widget.selected.where((z) => _ids.contains(z.id)),
                    ...widget.zones.where((z) =>
                        _ids.contains(z.id) &&
                        !widget.selected.any((s) => s.id == z.id)),
                  ]),
              child: Text('Use ${_ids.length} stop${_ids.length == 1 ? '' : 's'}'),
            ),
          ),
        ],
      ),
    );
  }
}
