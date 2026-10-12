import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../core/place_category.dart';
import '../../models/zone.dart';
import '../../providers/auth_provider.dart';
import '../../providers/zone_provider.dart';
import '../shell/shell_nav.dart';
import '../zones/zone_detail_screen.dart';

/// Overview tab: closest place, category shortcuts into the map, all places.
/// Distances are straight-line from the last GPS fix (no API calls).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Position? _me;

  static const _tiles = [
    PlaceCategory.home,
    PlaceCategory.shop,
    PlaceCategory.masjid,
    PlaceCategory.school,
  ];

  @override
  void initState() {
    super.initState();
    _locate();
  }

  /// Never prompts: only uses location if it was already granted.
  Future<void> _locate() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) setState(() => _me = last);
      final now = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      if (mounted) setState(() => _me = now);
    } catch (_) {
      // No fix: list stays unsorted and without distances.
    }
  }

  double? _distance(Zone z) => _me == null
      ? null
      : Geolocator.distanceBetween(
          _me!.latitude, _me!.longitude, z.latitude, z.longitude);

  static String _fmt(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  void _open(Zone z) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ZoneDetailScreen(zoneId: z.id)));

  void _allCategories() {
    final nav = context.read<ShellNav>();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in PlaceCategory.values)
              ListTile(
                leading: Icon(c.icon, color: c.color),
                title: Text(c.label),
                onTap: () {
                  Navigator.pop(ctx);
                  nav.openMap(category: c);
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
    final nav = context.read<ShellNav>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    int active(Zone z) =>
        provider.remindersFor(z.id).where((r) => r.active).length;

    final zones = List.of(provider.zones);
    if (_me != null) {
      zones.sort((a, b) => _distance(a)!.compareTo(_distance(b)!));
    }
    // Hero: closest place that still has something to remember, else closest.
    final hero = zones.where((z) => active(z) > 0).firstOrNull ??
        zones.firstOrNull;
    final name = auth.displayName ?? 'there';

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          await provider.refresh();
          await _locate();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.primary,
                  child: Text(name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hello,',
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                    Text(name,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Search lives on the map; this just takes you there.
            Material(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => nav.openMap(),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(children: [
                    Icon(Icons.search, size: 20, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Text('Search places',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _HeroCard(
              zone: hero,
              subtitle: hero == null
                  ? 'Save a place and Nearby reminds you when you get there.'
                  : [
                      '${active(hero)} reminder${active(hero) == 1 ? '' : 's'}',
                      if (_distance(hero) != null) '${_fmt(_distance(hero)!)} away',
                    ].join(' · '),
              onTap: hero == null ? () => nav.openMap() : () => _open(hero),
              actionLabel: hero == null ? 'Add a place' : 'Plan a trip',
              onAction: hero == null
                  ? () => nav.openMap()
                  : () => nav.goTo(ShellNav.trips),
            ),
            const SizedBox(height: 18),
            _SectionHeader(
                title: 'Categories', action: 'See all', onAction: _allCategories),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final c in _tiles) ...[
                  Expanded(
                    child: _CategoryTile(
                        category: c, onTap: () => nav.openMap(category: c)),
                  ),
                  if (c != _tiles.last) const SizedBox(width: 10),
                ],
              ],
            ),
            const SizedBox(height: 18),
            _SectionHeader(
                title: 'Your places',
                action: 'Map',
                onAction: () => nav.openMap()),
            const SizedBox(height: 10),
            if (zones.isEmpty && !provider.loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Nothing saved yet.',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            for (final z in zones)
              _PlaceCard(
                zone: z,
                subtitle: [
                  z.triggerType.short,
                  '${z.radiusMeters} m',
                  if (_distance(z) != null) '${_fmt(_distance(z)!)} away',
                ].join(' · '),
                count: active(z),
                onTap: () => _open(z),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.title, required this.action, required this.onAction});
  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const Spacer(),
        GestureDetector(
          onTap: onAction,
          child: Text(action,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary)),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.zone,
    required this.subtitle,
    required this.onTap,
    required this.actionLabel,
    required this.onAction,
  });

  final Zone? zone;
  final String subtitle;
  final VoidCallback onTap;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            // Drawn map hint on the right: a few roads and the place ring.
            Positioned.fill(
              child: CustomPaint(painter: _MiniMapPainter()),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(zone == null ? 'Get started' : 'Closest place',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 190,
                    child: Text(zone?.name ?? 'Add your first place',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            height: 1.2,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 190,
                    child: Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12.5)),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.white,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: onAction,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(actionLabel,
                              style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right,
                              size: 18, color: scheme.primary),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;
    final x0 = size.width - 150;
    canvas
      ..drawLine(Offset(x0, size.height * 0.3),
          Offset(size.width, size.height * 0.45), road)
      ..drawLine(Offset(x0 + 40, 0), Offset(x0 + 70, size.height), road)
      ..drawLine(Offset(x0 + 110, 0), Offset(x0 + 120, size.height), road);
    final c = Offset(x0 + 88, size.height * 0.5);
    canvas
      ..drawCircle(c, 34, Paint()..color = Colors.white.withValues(alpha: 0.14))
      ..drawCircle(
          c,
          34,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2)
      ..drawCircle(c, 7, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});
  final PlaceCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 58,
            decoration: BoxDecoration(
              color: category.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Icon(category.icon, color: category.color)),
          ),
          const SizedBox(height: 6),
          Text(category.label,
              style: TextStyle(fontSize: 12, color: scheme.onSurface)),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.zone,
    required this.subtitle,
    required this.count,
    required this.onTap,
  });

  final Zone zone;
  final String subtitle;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = zone.category;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: c.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(c.icon, color: c.color, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(zone.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '$count',
                        style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    TextSpan(
                        text: count == 1 ? '\nreminder' : '\nreminders',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 11)),
                  ]),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
