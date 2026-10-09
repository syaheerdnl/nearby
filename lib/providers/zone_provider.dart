import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/place_category.dart';
import '../models/trigger_log_entry.dart';
import '../models/zone.dart';
import '../models/zone_reminder.dart';
import '../services/geofence_service.dart';
import '../services/zone_repository.dart';

/// Zone + reminder state for the UI. Keeps OS geofence registrations in
/// step with the saved zones.
class ZoneProvider extends ChangeNotifier {
  ZoneProvider({ZoneRepository? repository, GeofenceService? geofences})
      : _repo = repository ?? ZoneRepository(),
        _geo = geofences ?? GeofenceService.instance;

  final ZoneRepository _repo;
  final GeofenceService _geo;

  List<Zone> _zones = const [];
  final Map<String, List<ZoneReminder>> _reminders = {};
  Set<String> _registeredIds = const {};
  GeofencePermission _permission = GeofencePermission.denied;
  bool _loading = false;
  bool _syncing = false;
  String? _error;

  List<Zone> get zones => _zones;
  bool get loading => _loading;
  bool get syncing => _syncing;
  String? get error => _error;
  GeofencePermission get permission => _permission;

  List<ZoneReminder> remindersFor(String zoneId) =>
      _reminders[zoneId] ?? const [];
  bool isRegistered(String zoneId) => _registeredIds.contains(zoneId);
  Zone? zoneById(String id) {
    for (final z in _zones) {
      if (z.id == id) return z;
    }
    return null;
  }

  /// Local data first (instant, works offline), then sync, then re-read.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _readLocal();
    } catch (e) {
      _error = 'Could not read saved zones.';
      debugPrint('Load zones failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
    await refresh();
  }

  Future<void> refresh() async {
    _syncing = true;
    notifyListeners();
    try {
      await _repo.refresh();
      _error = null;
    } catch (e) {
      // Offline or Supabase down: keep working from local data.
      debugPrint('Refresh failed: $e');
    }
    try {
      await _readLocal();
      await _syncGeofences();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<GeofencePermission> requestGeofencePermission() async {
    _permission = await _geo.requestPermissions();
    await _syncGeofences();
    notifyListeners();
    return _permission;
  }

  Future<void> checkPermission() async {
    _permission = await _geo.permissionStatus();
    notifyListeners();
  }

  Future<Zone> createZone({
    required String name,
    required double latitude,
    required double longitude,
    required int radiusMeters,
    required TriggerType triggerType,
    required PlaceCategory category,
  }) async {
    final zone = await _repo.createZone(
      name: name,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      triggerType: triggerType,
      category: category,
    );
    await _readLocal();
    await _registerOne(zone);
    notifyListeners();
    return zone;
  }

  Future<void> updateZone(Zone zone) async {
    final updated = await _repo.updateZone(zone);
    await _readLocal();
    await _registerOne(updated);
    notifyListeners();
  }

  Future<void> deleteZone(String id) async {
    await _repo.deleteZone(id);
    await _geo.unregister(id);
    _registeredIds = {..._registeredIds}..remove(id);
    _reminders.remove(id);
    await _readLocal();
    notifyListeners();
  }

  Future<void> addReminder(String zoneId, String title, String? body) async {
    await _repo.addReminder(zoneId: zoneId, title: title, body: body);
    await _readReminders(zoneId);
    notifyListeners();
  }

  Future<void> updateReminder(ZoneReminder reminder) async {
    await _repo.updateReminder(reminder);
    await _readReminders(reminder.zoneId);
    notifyListeners();
  }

  Future<void> deleteReminder(ZoneReminder reminder) async {
    // Drop it from the list first: the swiped Dismissible must leave the
    // tree before anything else rebuilds.
    _reminders[reminder.zoneId] = remindersFor(reminder.zoneId)
        .where((r) => r.id != reminder.id)
        .toList();
    notifyListeners();
    await _repo.deleteReminder(reminder.id);
    await _readReminders(reminder.zoneId);
    notifyListeners();
  }

  Future<void> restoreReminder(ZoneReminder reminder) async {
    await _repo.restoreReminder(reminder);
    await _readReminders(reminder.zoneId);
    notifyListeners();
  }

  Future<List<TriggerLogEntry>> triggerLog(String zoneId) =>
      _repo.triggerLog(zoneId);

  /// Sign-out: stop all geofences and wipe local data.
  Future<void> reset() async {
    await _geo.unregisterAll();
    await _repo.clearLocal();
    _zones = const [];
    _reminders.clear();
    _registeredIds = const {};
    notifyListeners();
  }

  Future<void> _readLocal() async {
    _zones = await _repo.zones();
    for (final z in _zones) {
      await _readReminders(z.id);
    }
  }

  Future<void> _readReminders(String zoneId) async {
    _reminders[zoneId] = await _repo.reminders(zoneId);
  }

  Future<void> _registerOne(Zone zone) async {
    _permission = await _geo.permissionStatus();
    if (_permission == GeofencePermission.denied) return;
    if (await _geo.register(zone)) {
      _registeredIds = {..._registeredIds, zone.id};
    }
  }

  Future<void> _syncGeofences() async {
    _permission = await _geo.permissionStatus();
    if (_permission == GeofencePermission.denied) return;
    await _geo.syncAll(_zones);
    _registeredIds = await _geo.registeredIds();
  }
}
