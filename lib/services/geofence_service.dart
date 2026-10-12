import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants.dart';
import '../models/shared_list.dart';
import '../models/zone.dart';
import 'local_db_service.dart';
import 'notification_service.dart';

/// Runs in a background isolate started by the OS when a geofence fires,
/// even if the app is fully closed. Keep it short: read local data, show
/// one notification, log the event. No network calls here.
@pragma('vm:entry-point')
Future<void> onGeofenceEvent(GeofenceCallbackParams params) async {
  final event = switch (params.event) {
    GeofenceEvent.enter => TriggerType.enter,
    GeofenceEvent.exit => TriggerType.exit,
    GeofenceEvent.dwell => TriggerType.dwell,
  };
  final now = DateTime.now().toUtc();
  final db = LocalDbService.instance;
  final notifications = NotificationService.instance;
  await notifications.init();

  for (final fence in params.geofences) {
    try {
      if (fence.id.startsWith(kSharedFencePrefix)) {
        await _onSharedPlace(fence.id, event, now, db, notifications);
        continue;
      }
      final zone = await db.zoneById(fence.id);
      if (zone == null) continue;

      // Some devices deliver the same transition twice in a row (iOS after
      // a reboot, some OEM builds on Android). Ignore repeats within 60 s.
      final last = await db.triggerLog(zone.id, limit: 1);
      if (last.isNotEmpty &&
          last.first.event == event &&
          now.difference(last.first.firedAt).inSeconds < 60) {
        continue;
      }

      final reminders = await db.remindersForZone(zone.id, activeOnly: true);
      // Outside the place's active hours: log the visit, stay quiet.
      final inWindow = zone.isActiveAt(DateTime.now());
      final notify = reminders.isNotEmpty && inWindow;
      if (notify) {
        await notifications.showZoneReminder(
          id: zone.id.hashCode & 0x7fffffff,
          title: _titleFor(event, zone.name),
          body: reminders
              .map((r) => r.body == null ? '• ${r.title}' : '• ${r.title}: ${r.body}')
              .join('\n'),
          zoneId: zone.id,
        );
      }
      // "Just once": switch the reminders off now they've been shown.
      if (notify && zone.onceOnly) await db.turnOffReminders(zone.id);
      // Grepped by tools/geofence_test.sh to measure trigger latency.
      debugPrint('NEARBY_GEOFENCE event=${event.name} zone="${zone.name}" '
          'notified=$notify inWindow=$inWindow once=${zone.onceOnly}');
      await db.logTrigger(
        zoneId: zone.id,
        event: event,
        firedAt: now,
        latitude: params.location?.latitude,
        longitude: params.location?.longitude,
        notified: notify,
      );
    } catch (e) {
      debugPrint('Geofence callback failed for ${fence.id}: $e');
    }
  }
}

/// Geofence ids for places friends shared with me: "s:<zone id>".
const String kSharedFencePrefix = 's:';

/// A friend's place: alert with the open items from the last sync.
Future<void> _onSharedPlace(String fenceId, TriggerType event, DateTime now,
    LocalDbService db, NotificationService notifications) async {
  final place =
      await db.sharedPlace(fenceId.substring(kSharedFencePrefix.length));
  if (place == null || event != TriggerType.enter) return;
  final last = await db.triggerLog(fenceId, limit: 1);
  if (last.isNotEmpty && now.difference(last.first.firedAt).inSeconds < 60) {
    return;
  }
  final notify = place.openItems.isNotEmpty;
  if (notify) {
    final who = place.ownerName.isEmpty ? '' : ' (${place.ownerName})';
    await notifications.showZoneReminder(
      id: fenceId.hashCode & 0x7fffffff,
      title: "You're at ${place.name}",
      body: '${place.listTitle}$who: ${place.openItems.length} open\n'
          '${place.openItems.map((i) => '• $i').join('\n')}',
      payload: '$kListPayloadPrefix${place.listId}',
      withDone: false,
    );
  }
  debugPrint('NEARBY_GEOFENCE event=enter zone="${place.name}" '
      'notified=$notify shared=true');
  await db.logTrigger(
    zoneId: fenceId,
    event: event,
    firedAt: now,
    latitude: null,
    longitude: null,
    notified: notify,
  );
}

String _titleFor(TriggerType event, String zoneName) => switch (event) {
      TriggerType.enter => "You're at $zoneName",
      TriggerType.exit => 'Leaving $zoneName',
      TriggerType.dwell => 'Still at $zoneName',
    };

enum GeofencePermission { granted, foregroundOnly, denied }

/// Registers one OS geofence per zone (geofence id = zone id).
///
/// OEM note: on Vivo/iQOO (OriginOS/FuntouchOS), Xiaomi and Oppo the OS may
/// kill the background receiver unless the app is exempt from battery
/// optimisation and allowed to run in the background. Registration itself
/// still succeeds, so a "registered" fence is not proof it will fire. See
/// BatteryOptimizationScreen.
class GeofenceService {
  GeofenceService._();
  static final GeofenceService instance = GeofenceService._();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await NativeGeofenceManager.instance.initialize();
    _initialized = true;
  }

  Future<GeofencePermission> permissionStatus() async {
    final fg = await Permission.location.status;
    if (!fg.isGranted) return GeofencePermission.denied;
    final bg = await Permission.locationAlways.status;
    return bg.isGranted
        ? GeofencePermission.granted
        : GeofencePermission.foregroundOnly;
  }

  /// Asks for location, then "allow all the time", then notifications.
  /// On Android 11+ the second step opens a system page where the user must
  /// pick "Allow all the time" themselves.
  Future<GeofencePermission> requestPermissions() async {
    final fg = await Permission.location.request();
    if (!fg.isGranted) return GeofencePermission.denied;
    final bg = await Permission.locationAlways.request();
    await NotificationService.instance.requestPermission();
    return bg.isGranted
        ? GeofencePermission.granted
        : GeofencePermission.foregroundOnly;
  }

  Future<Set<String>> registeredIds() async {
    try {
      await init();
      return (await NativeGeofenceManager.instance.getRegisteredGeofenceIds())
          .toSet();
    } catch (e) {
      debugPrint('Reading registered geofences failed: $e');
      return <String>{};
    }
  }

  /// Makes the OS registrations match [zones]: removes stale ones and adds
  /// missing ones. Existing fences are left alone so Android dwell timers
  /// are not reset on every app resume; edits go through [register].
  /// Returns false if permission is missing (zones stay saved, just silent).
  Future<bool> syncAll(List<Zone> zones,
      {List<SharedPlace> shared = const []}) async {
    if (await permissionStatus() == GeofencePermission.denied) return false;
    await init();
    final wanted = {
      for (final z in zones) z.id,
      for (final p in shared) '$kSharedFencePrefix${p.zoneId}',
    };
    final current = await registeredIds();
    for (final id in current) {
      if (!wanted.contains(id)) await unregister(id);
    }
    var ok = true;
    for (final zone in zones) {
      if (!current.contains(zone.id)) {
        ok = await register(zone) && ok;
      }
    }
    // Shared places are few and can move or resize on the owner's side
    // without us knowing, so re-register them each sync.
    for (final p in shared) {
      ok = await _registerShared(p) && ok;
    }
    return ok;
  }

  Future<bool> _registerShared(SharedPlace p) async {
    final id = '$kSharedFencePrefix${p.zoneId}';
    try {
      await NativeGeofenceManager.instance.removeGeofenceById(id);
    } catch (_) {}
    try {
      await NativeGeofenceManager.instance.createGeofence(
        Geofence(
          id: id,
          location: Location(latitude: p.latitude, longitude: p.longitude),
          radiusMeters: p.radiusMeters.toDouble(),
          triggers: {GeofenceEvent.enter},
          iosSettings: const IosGeofenceSettings(initialTrigger: false),
          androidSettings: const AndroidGeofenceSettings(
            initialTriggers: <GeofenceEvent>{},
          ),
        ),
        onGeofenceEvent,
      );
      return true;
    } on NativeGeofenceException catch (e) {
      debugPrint('Register shared $id failed: ${e.code} ${e.message}');
      return false;
    }
  }

  Future<bool> register(Zone zone) async {
    try {
      await init();
      // Replace any old registration so radius/trigger edits take effect.
      await NativeGeofenceManager.instance.removeGeofenceById(zone.id);
    } catch (_) {
      // Not registered yet; fine.
    }
    try {
      await NativeGeofenceManager.instance
          .createGeofence(_toGeofence(zone), onGeofenceEvent);
      return true;
    } on NativeGeofenceException catch (e) {
      debugPrint('Register ${zone.id} failed: ${e.code} ${e.message}');
      return false;
    }
  }

  Future<void> unregister(String zoneId) async {
    try {
      await init();
      await NativeGeofenceManager.instance.removeGeofenceById(zoneId);
    } catch (e) {
      debugPrint('Unregister $zoneId failed: $e');
    }
  }

  Future<void> unregisterAll() async {
    try {
      await init();
      await NativeGeofenceManager.instance.removeAllGeofences();
    } catch (e) {
      debugPrint('Unregister all failed: $e');
    }
  }

  Geofence _toGeofence(Zone zone) {
    var event = switch (zone.triggerType) {
      TriggerType.enter => GeofenceEvent.enter,
      TriggerType.exit => GeofenceEvent.exit,
      TriggerType.dwell => GeofenceEvent.dwell,
    };
    // iOS has no dwell; fall back to enter there.
    if (Platform.isIOS && event == GeofenceEvent.dwell) {
      event = GeofenceEvent.enter;
    }
    return Geofence(
      id: zone.id,
      location: Location(latitude: zone.latitude, longitude: zone.longitude),
      radiusMeters: zone.radiusMeters.toDouble(),
      triggers: {event},
      iosSettings: const IosGeofenceSettings(initialTrigger: false),
      androidSettings: const AndroidGeofenceSettings(
        // Don't fire just because you're already inside when you save it.
        initialTriggers: <GeofenceEvent>{},
        loiteringDelay: AppConstants.dwellDelay,
      ),
    );
  }
}
