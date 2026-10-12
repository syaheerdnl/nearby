import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/place_category.dart';
import '../../models/zone.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zone_provider.dart';
import '../../services/geofence_service.dart';
import '../../services/local_db_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/category_badge.dart';
import '../../widgets/place_preview_card.dart';
import '../../widgets/place_search_bar.dart';
import '../../widgets/zone_pin_marker.dart';
import '../onboarding/battery_optimization_screen.dart';
import '../trips/trip_planner_screen.dart';
import 'zone_create_screen.dart';
import 'zone_detail_screen.dart';

class ZoneMapScreen extends StatefulWidget {
  const ZoneMapScreen({super.key});

  @override
  State<ZoneMapScreen> createState() => _ZoneMapScreenState();
}

class _ZoneMapScreenState extends State<ZoneMapScreen>
    with WidgetsBindingObserver {
  static const _batteryShownKey = 'battery_screen_shown';
  final _map = MapController();
  bool _locating = false;
  bool _centeredOnZones = false;
  LatLng? _me;
  PlaceCategory? _filter;

  /// Pin tapped on the map; shows the preview card instead of the list.
  String? _selectedId;

  /// Receives zone ids from the notification "Done" isolate.
  final _donePort = ReceivePort();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _centerOnMeIfAllowed();
    NotificationService.instance.pendingZoneId.addListener(_openFromNotification);
    // Cold start: the id may already be waiting.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openFromNotification());
    IsolateNameServer.removePortNameMapping(kDonePortName);
    IsolateNameServer.registerPortWithName(_donePort.sendPort, kDonePortName);
    _donePort.listen((_) {
      if (mounted) context.read<ZoneProvider>().refresh();
    });
  }

  /// Tapped reminder notification -> that place's detail screen.
  void _openFromNotification() {
    final pending = NotificationService.instance.pendingZoneId;
    final id = pending.value;
    if (id == null || !mounted) return;
    pending.value = null;
    // Drop anything stacked on top (another place, the trip planner) so
    // back always returns to the map.
    Navigator.of(context).popUntil((r) => r.isFirst);
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ZoneDetailScreen(zoneId: id)));
    // Reminders may have been switched off by "Done" while we were away.
    context.read<ZoneProvider>().refresh();
  }

  @override
  void dispose() {
    NotificationService.instance.pendingZoneId
        .removeListener(_openFromNotification);
    IsolateNameServer.removePortNameMapping(kDonePortName);
    _donePort.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Push queued edits and pick up permission changes made in Settings.
      context.read<ZoneProvider>().refresh();
    }
  }

  /// Only uses location if it was already granted. Never prompts on open.
  Future<void> _centerOnMeIfAllowed() async {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse) {
      await _goToMe(prompt: false);
    }
  }

  Future<void> _goToMe({bool prompt = true}) async {
    if (!mounted) return;
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && prompt) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (prompt && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Location is off for Nearby. You can still '
                  'search or tap the map.')));
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final here = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _me = here);
      _map.move(here, 16);
    } catch (_) {
      if (prompt && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get your location.')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _addZoneAt(LatLng point, {String? name}) async {
    final created = await Navigator.of(context).push<Zone>(
      MaterialPageRoute(
          builder: (_) =>
              ZoneCreateScreen(initialPoint: point, initialName: name)),
    );
    if (created == null || !mounted) return;
    await _maybeShowBatteryScreen();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ZoneDetailScreen(zoneId: created.id)));
  }

  /// Once, after the very first zone (CLAUDE.md section 6 step 3).
  Future<void> _maybeShowBatteryScreen() async {
    final db = LocalDbService.instance;
    if (await db.getMeta(_batteryShownKey) == '1') return;
    await db.setMeta(_batteryShownKey, '1');
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const BatteryOptimizationScreen()));
  }

  void _openZone(Zone z) {
    setState(() => _selectedId = null);
    _map.move(LatLng(z.latitude, z.longitude), 16);
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ZoneDetailScreen(zoneId: z.id)));
  }

  void _selectZone(Zone z) {
    setState(() => _selectedId = z.id);
    // Keep the pin above the card: aim a little below it.
    final zoom = _map.camera.zoom < 15 ? 15.0 : _map.camera.zoom;
    _map.move(LatLng(z.latitude - 0.0012 * (16 / zoom), z.longitude), zoom);
  }

  Future<void> _directionsTo(Zone z) async {
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination':
          '${z.latitude.toStringAsFixed(6)},${z.longitude.toStringAsFixed(6)}',
      'travelmode': 'driving',
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')));
    }
  }

  Future<void> _signOut() async {
    final zones = context.read<ZoneProvider>();
    final auth = context.read<AuthProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'Reminders stop on this phone until you sign in again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    await zones.reset();
    await auth.signOut();
  }

  void _accountMenu() {
    final auth = context.read<AuthProvider>();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(auth.email ?? 'Signed in'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.battery_saver_outlined),
              title: const Text('Battery settings'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const BatteryOptimizationScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () {
                Navigator.pop(ctx);
                _signOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ZoneProvider>();
    final auth = context.watch<AuthProvider>();
    final all = provider.zones;
    final zones =
        _filter == null ? all : all.where((z) => z.category == _filter).toList();
    final usedCategories = {for (final z in all) z.category}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final scheme = Theme.of(context).colorScheme;
    final selected =
        _selectedId == null ? null : provider.zoneById(_selectedId!);

    // Zones load after the map is built: jump to them once if we don't know
    // where the user is.
    if (!_centeredOnZones && _me == null && all.isNotEmpty) {
      _centeredOnZones = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _map.move(LatLng(all.first.latitude, all.first.longitude), 15);
        }
      });
    }
    final center = _me ??
        (all.isNotEmpty
            ? LatLng(all.first.latitude, all.first.longitude)
            : const LatLng(
                AppConstants.fallbackLatitude, AppConstants.fallbackLongitude));
    final email = auth.email ?? '';
    final initial = email.isEmpty ? '?' : email.substring(0, 1).toUpperCase();

    return Scaffold(
      // Keep the FABs still when the search keyboard opens.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: center,
              initialZoom: all.isEmpty && _me == null ? 13 : 15,
              // With a card open, a map tap just closes it.
              onTap: (_, point) {
                if (_selectedId != null) {
                  setState(() => _selectedId = null);
                } else {
                  _addZoneAt(point);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: AppConstants.tileUrl,
                userAgentPackageName: AppConstants.userAgentPackageName,
              ),
              CircleLayer(
                circles: [
                  for (final z in zones)
                    CircleMarker(
                      point: LatLng(z.latitude, z.longitude),
                      radius: z.radiusMeters.toDouble(),
                      useRadiusInMeter: true,
                      color: z.category.color.withValues(alpha: 0.12),
                      borderColor: z.category.color,
                      borderStrokeWidth: 1.5,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (_me != null)
                    Marker(
                      point: _me!,
                      width: 30,
                      height: 30,
                      child: Center(
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                  color: scheme.primary.withValues(alpha: 0.18),
                                  spreadRadius: 7),
                            ],
                          ),
                        ),
                      ),
                    ),
                  for (final z in zones)
                    Marker(
                      point: LatLng(z.latitude, z.longitude),
                      width: ZonePinMarker.width,
                      height: ZonePinMarker.height,
                      child: ZonePinMarker(
                        category: z.category,
                        label: z.name,
                        count: provider
                            .remindersFor(z.id)
                            .where((r) => r.active)
                            .length,
                        selected: z.id == _selectedId,
                        onTap: () => _selectZone(z),
                      ),
                    ),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PlaceSearchBar(
                    hintText: 'Search a place',
                    biasPoint: () => _me ?? _map.camera.center,
                    trailing: GestureDetector(
                      onTap: _accountMenu,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        child: Text(initial,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    onSelected: (place) {
                      final point = LatLng(place.latitude, place.longitude);
                      _map.move(point, 16);
                      _addZoneAt(point, name: place.name);
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _MapChip(
                          icon: Icons.route_outlined,
                          label: 'Plan trip',
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      TripPlannerScreen(start: _me))),
                        ),
                        if (usedCategories.length > 1)
                          for (final c in usedCategories)
                            _MapChip(
                              label: c.label,
                              selected: _filter == c,
                              onTap: () => setState(
                                  () => _filter = _filter == c ? null : c),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Banner(provider: provider),
                ],
              ),
            ),
          ),
          if (selected != null)
            Positioned(
              left: 10,
              right: 10,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 12),
                child: PlacePreviewCard(
                  zone: selected,
                  reminders: provider.remindersFor(selected.id),
                  distanceMeters: _me == null
                      ? null
                      : Geolocator.distanceBetween(_me!.latitude,
                          _me!.longitude, selected.latitude, selected.longitude),
                  onToggleDone: (r, done) =>
                      provider.updateReminder(r.copyWith(active: !done)),
                  onDirections: () => _directionsTo(selected),
                  onOpen: () => _openZone(selected),
                  onClose: () => setState(() => _selectedId = null),
                ),
              ),
            )
          else
          DraggableScrollableSheet(
            initialChildSize: 0.34,
            minChildSize: 0.12,
            maxChildSize: 0.75,
            snap: true,
            snapSizes: const [0.12, 0.34, 0.75],
            builder: (context, scroll) => Material(
              color: scheme.surface,
              clipBehavior: Clip.antiAlias,
              elevation: 3,
              shadowColor: Colors.black45,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: _ZoneList(
                scroll: scroll,
                zones: zones,
                provider: provider,
                me: _me,
                filtered: _filter != null,
                onOpen: _openZone,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: selected != null
          ? null
          : Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height * 0.34 - 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.small(
              heroTag: 'me',
              backgroundColor: scheme.surface,
              foregroundColor: scheme.onSurface,
              onPressed: _locating ? null : _goToMe,
              child: _locating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.extended(
              heroTag: 'add',
              onPressed: () => _addZoneAt(_map.camera.center),
              icon: const Icon(Icons.add),
              label: const Text('Place'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapChip extends StatelessWidget {
  const _MapChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? scheme.primary : scheme.surface,
        elevation: 1,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 16,
                      color: selected ? scheme.onPrimary : scheme.onSurface),
                  const SizedBox(width: 5),
                ],
                Text(label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: selected ? scheme.onPrimary : scheme.onSurface,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.provider});

  final ZoneProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (provider.zones.isNotEmpty &&
        provider.permission != GeofencePermission.granted) {
      return Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.location_off_outlined,
                  size: 18, color: scheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Reminders are paused. Allow location "all the time".',
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onErrorContainer),
                ),
              ),
              TextButton(
                onPressed: provider.requestGeofencePermission,
                child: const Text('Allow'),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _ZoneList extends StatelessWidget {
  const _ZoneList({
    required this.scroll,
    required this.zones,
    required this.provider,
    required this.me,
    required this.filtered,
    required this.onOpen,
  });

  final ScrollController scroll;
  final List<Zone> zones;
  final ZoneProvider provider;
  final LatLng? me;
  final bool filtered;
  final ValueChanged<Zone> onOpen;

  static String _km(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reminderCount = zones
        .map((z) => provider.remindersFor(z.id).where((r) => r.active).length)
        .fold<int>(0, (a, b) => a + b);

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Your places',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${zones.length} · $reminderCount reminders',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(AppConstants.mapAttribution,
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
        ),
        if (provider.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(provider.error!,
                style: TextStyle(color: scheme.error)),
          ),
        if (zones.isEmpty && !provider.loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              filtered
                  ? 'No places of this type.'
                  : 'Nothing saved yet. Search for a place above, or tap '
                      'anywhere on the map.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        for (final z in zones) ...[
          const Divider(),
          _ZoneRow(
            zone: z,
            subtitle: _subtitle(z),
            trailing: _trailing(context, z),
            onTap: () => onOpen(z),
          ),
        ],
      ],
    );
  }

  String _subtitle(Zone z) {
    final active = provider.remindersFor(z.id).where((r) => r.active).toList();
    if (active.isEmpty) return '${z.triggerType.short} · nothing yet';
    final titles = active.map((r) => r.title).join(', ');
    return '${z.triggerType.short} · $titles';
  }

  Widget _trailing(BuildContext context, Zone z) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    final active = provider.remindersFor(z.id).any((r) => r.active);
    Widget dotLabel(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(t, style: style),
          ],
        );
    if (provider.permission != GeofencePermission.granted ||
        !provider.isRegistered(z.id)) {
      return dotLabel(scheme.error, 'Paused');
    }
    if (!active) return dotLabel(scheme.outline, 'Quiet');
    if (me != null) {
      final d = Geolocator.distanceBetween(
          me!.latitude, me!.longitude, z.latitude, z.longitude);
      return Text(_km(d), style: style);
    }
    return dotLabel(const Color(0xFF2F8A3E), 'On');
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.zone,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final Zone zone;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            CategoryBadge(category: zone.category),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(zone.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}
