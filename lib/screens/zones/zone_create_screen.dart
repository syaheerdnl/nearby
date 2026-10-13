import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/place_category.dart';
import '../../models/zone.dart';
import '../../providers/zone_provider.dart';
import '../../services/geofence_service.dart';
import '../../widgets/zone_pin_marker.dart';
import '../../widgets/map_credit.dart';
import '../../widgets/app_tile_layer.dart';

/// Create a zone at [initialPoint], or edit [existing].
/// The pin stays in the middle of the map; moving the map moves the place.
/// Pops with the saved [Zone].
class ZoneCreateScreen extends StatefulWidget {
  const ZoneCreateScreen({
    super.key,
    this.initialPoint,
    this.initialName,
    this.existing,
  }) : assert(initialPoint != null || existing != null);

  final LatLng? initialPoint;

  /// Prefilled from a search result.
  final String? initialName;
  final Zone? existing;

  @override
  State<ZoneCreateScreen> createState() => _ZoneCreateScreenState();
}

class _ZoneCreateScreenState extends State<ZoneCreateScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _map = MapController();
  late LatLng _point;
  late double _radius;
  late TriggerType _trigger;
  late PlaceCategory _category;
  late bool _onceOnly;
  // Active window in minutes after midnight; null = any time.
  TimeOfDay? _from;
  TimeOfDay? _to;
  bool _saving = false;

  static TimeOfDay _tod(int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60);
  static int _min(TimeOfDay t) => t.hour * 60 + t.minute;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final z = widget.existing;
    _point = z != null ? LatLng(z.latitude, z.longitude) : widget.initialPoint!;
    _radius = (z?.radiusMeters ?? AppConstants.defaultRadiusMeters).toDouble();
    _trigger = z?.triggerType ?? TriggerType.enter;
    _category = z?.category ?? _guessCategory(widget.initialName);
    _onceOnly = z?.onceOnly ?? false;
    if (z != null && z.hasActiveWindow) {
      _from = _tod(z.activeFrom!);
      _to = _tod(z.activeTo!);
    }
    final suggested = widget.initialName ?? '';
    _name.text = z?.name ??
        (suggested.length > 60 ? suggested.substring(0, 60) : suggested);
  }

  /// Best guess from a search result name; the user can change it.
  static PlaceCategory _guessCategory(String? name) {
    final n = (name ?? '').toLowerCase();
    bool has(List<String> words) => words.any(n.contains);
    if (has(['masjid', 'surau', 'mosque'])) return PlaceCategory.masjid;
    if (has(['sekolah', 'school', 'universiti', 'university', 'kolej',
      'college', 'tadika'])) {
      return PlaceCategory.school;
    }
    if (has(['mart', 'tesco', 'lotus', 'mydin', 'giant', 'aeon', 'econsave',
      'kedai', 'pasar', 'market', 'shop', 'mall', 'farmasi', 'pharmacy'])) {
      return PlaceCategory.shop;
    }
    if (has(['pejabat', 'office', 'kilang', 'factory'])) {
      return PlaceCategory.work;
    }
    if (has(['rumah', 'home'])) return PlaceCategory.home;
    return PlaceCategory.other;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Zoom so the whole circle fits the map area.
  double get _zoom {
    if (_radius <= 150) return 16.5;
    if (_radius <= 300) return 15.5;
    if (_radius <= 600) return 14.5;
    return 13.8;
  }

  Future<bool> _explainAndAskPermission(ZoneProvider zones) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Allow location'),
        content: const Text(
          'Nearby checks your places on the phone itself, even when the app '
          'is closed. On the next screens, allow location and then choose '
          '"Allow all the time".',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue')),
        ],
      ),
    );
    if (go != true) return false;
    final result = await zones.requestGeofencePermission();
    return result == GeofencePermission.granted;
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final zones = context.read<ZoneProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await zones.checkPermission();
      if (zones.permission != GeofencePermission.granted) {
        final granted = await _explainAndAskPermission(zones);
        if (!granted) {
          messenger.showSnackBar(const SnackBar(
              content: Text('Saved, but paused until location is allowed '
                  'all the time.')));
        }
      }
      final Zone saved;
      if (_editing) {
        saved = widget.existing!.copyWith(
          name: _name.text.trim(),
          latitude: _point.latitude,
          longitude: _point.longitude,
          radiusMeters: _radius.round(),
          triggerType: _trigger,
          category: _category,
          onceOnly: _onceOnly,
          activeFrom: _from == null ? null : _min(_from!),
          activeTo: _to == null ? null : _min(_to!),
          clearActiveWindow: _from == null,
        );
        await zones.updateZone(saved);
      } else {
        saved = await zones.createZone(
          name: _name.text,
          latitude: _point.latitude,
          longitude: _point.longitude,
          radiusMeters: _radius.round(),
          triggerType: _trigger,
          category: _category,
          onceOnly: _onceOnly,
          activeFrom: _from == null ? null : _min(_from!),
          activeTo: _to == null ? null : _min(_to!),
        );
      }
      HapticFeedback.lightImpact();
      nav.pop(saved);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Could not save the place: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    final mapHeight = MediaQuery.of(context).size.height * 0.34;

    return Scaffold(
      body: Column(
        children: [
          SizedBox(
            height: mapHeight,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _point,
                    initialZoom: _zoom,
                    onPositionChanged: (camera, hasGesture) {
                      if (hasGesture) setState(() => _point = camera.center);
                    },
                  ),
                  children: [
                    const AppTileLayer(),
                    CircleLayer(circles: [
                      CircleMarker(
                        point: _point,
                        radius: _radius,
                        useRadiusInMeter: true,
                        color: _category.color.withValues(alpha: 0.12),
                        borderColor: _category.color,
                        borderStrokeWidth: 1.5,
                      ),
                    ]),
                    const MapCredit(),
                  ],
                ),
                // Fixed pin in the middle: the map moves under it.
                IgnorePointer(
                  child: Center(
                    child: ZonePinMarker(category: _category, size: 32),
                  ),
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
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(_editing ? 'Edit place' : 'New place',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('Move the map to adjust', style: label),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Name', style: label),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                        hintText: 'Rumah, 99 Speedmart, Masjid...',
                        counterText: '',
                      ),
                      textCapitalization: TextCapitalization.words,
                      maxLength: 60,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Give this place a name'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text('What is it', style: label),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in PlaceCategory.values)
                          _TypeChip(
                            category: c,
                            selected: _category == c,
                            onTap: () => setState(() => _category = c),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Remind me when I', style: label),
                    const SizedBox(height: 8),
                    for (final t in TriggerType.values)
                      _TriggerOption(
                        trigger: t,
                        selected: _trigger == t,
                        onTap: () => setState(() => _trigger = t),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('Area', style: label),
                        const Spacer(),
                        Text('${_radius.round()} m',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Slider(
                      value: _radius,
                      min: AppConstants.minRadiusMeters.toDouble(),
                      max: AppConstants.maxRadiusMeters.toDouble(),
                      divisions: (AppConstants.maxRadiusMeters -
                              AppConstants.minRadiusMeters) ~/
                          50,
                      onChanged: (v) => setState(() => _radius = v),
                      onChangeEnd: (_) => _map.move(_point, _zoom),
                    ),
                    Text(
                      'Phones check places roughly, so 150 m or more works best.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    Text('How often', style: label),
                    const SizedBox(height: 8),
                    _ChoiceCard(
                      title: 'Every time',
                      hint: 'Good for Home, Office',
                      selected: !_onceOnly,
                      onTap: () => setState(() => _onceOnly = false),
                    ),
                    _ChoiceCard(
                      title: 'Just once',
                      hint: 'Reminders turn off after the first alert',
                      selected: _onceOnly,
                      onTap: () => setState(() => _onceOnly = true),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: Text('Only between these times',
                                style: label)),
                        Switch(
                          value: _from != null,
                          onChanged: (on) => setState(() {
                            if (on) {
                              _from = const TimeOfDay(hour: 8, minute: 0);
                              _to = const TimeOfDay(hour: 22, minute: 0);
                            } else {
                              _from = null;
                              _to = null;
                            }
                          }),
                        ),
                      ],
                    ),
                    if (_from != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _TimeBox(
                              label: 'From',
                              time: _from!,
                              onPick: (t) => setState(() => _from = t),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _TimeBox(
                              label: 'Until',
                              time: _to!,
                              onPick: (t) => setState(() => _to = t),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Arrive outside these hours and Nearby stays quiet. "
                        "It doesn't remind you later.",
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : Text(_editing ? 'Save changes' : 'Save'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final PlaceCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? category.color : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
            color: selected ? category.color : scheme.outline.withValues(alpha: 0.7)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(category.icon,
                  size: 17, color: selected ? Colors.white : category.color),
              const SizedBox(width: 6),
              Text(category.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: selected ? Colors.white : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}


/// One tappable card per trigger (Arrive / Leave / Stay a while).
class _TriggerOption extends StatelessWidget {
  const _TriggerOption({
    required this.trigger,
    required this.selected,
    required this.onTap,
  });

  final TriggerType trigger;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, title, hint) = switch (trigger) {
      TriggerType.enter => (Icons.login, 'Arrive', 'As soon as I get there'),
      TriggerType.exit => (Icons.logout, 'Leave', 'When I head out'),
      TriggerType.dwell => (
          Icons.schedule,
          'Stay a while',
          'After ${AppConstants.dwellDelay.inMinutes} minutes there'
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.4 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.surface
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon,
                      size: 19,
                      color:
                          selected ? scheme.primary : scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                      Text(hint,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Two-option card (How often).
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.4 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                      Text(hint,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tappable time field (From / Until).
class _TimeBox extends StatelessWidget {
  const _TimeBox({required this.label, required this.time, required this.onPick});
  final String label;
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final t = await showTimePicker(context: context, initialTime: time);
          if (t != null) onPick(t);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              Text(time.format(context),
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
