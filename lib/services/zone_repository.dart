import 'dart:async';

import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../core/place_category.dart';
import '../core/supabase_client.dart';
import '../models/trigger_log_entry.dart';
import '../models/zone.dart';
import '../models/zone_reminder.dart';
import 'local_db_service.dart';
import 'sync_service.dart';

/// The only way the UI touches zone data. Hides the local/remote split:
/// every write is saved locally first, then pushed in the background.
class ZoneRepository {
  ZoneRepository({LocalDbService? local, SyncService? sync})
      : _local = local ?? LocalDbService.instance,
        _sync = sync ?? SyncService(local: local);

  final LocalDbService _local;
  final SyncService _sync;
  static const _uuid = Uuid();

  Future<List<Zone>> zones() => _local.zones();

  Future<Zone?> zoneById(String id) => _local.zoneById(id);

  /// Push pending local edits, then pull anything changed elsewhere.
  Future<void> refresh() async {
    await _sync.pushPending();
    await _sync.pullRemote();
  }

  Future<Zone> createZone({
    required String name,
    required double latitude,
    required double longitude,
    required int radiusMeters,
    required TriggerType triggerType,
    required PlaceCategory category,
    bool onceOnly = false,
    int? activeFrom,
    int? activeTo,
  }) async {
    final now = DateTime.now().toUtc();
    final zone = Zone(
      id: _uuid.v4(),
      ownerId: _requireUserId(),
      name: name.trim(),
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      triggerType: triggerType,
      category: category,
      createdAt: now,
      updatedAt: now,
      onceOnly: onceOnly,
      activeFrom: activeFrom,
      activeTo: activeTo,
    );
    await _local.saveZone(zone, SyncStatus.pendingUpsert);
    _pushLater();
    return zone;
  }

  Future<Zone> updateZone(Zone zone) async {
    final updated = zone.copyWith(updatedAt: DateTime.now().toUtc());
    await _local.saveZone(updated, SyncStatus.pendingUpsert);
    _pushLater();
    return updated;
  }

  Future<void> deleteZone(String id) async {
    await _local.markZoneDeleted(id);
    _pushLater();
  }

  Future<List<ZoneReminder>> reminders(String zoneId) =>
      _local.remindersForZone(zoneId);

  Future<ZoneReminder> addReminder({
    required String zoneId,
    required String title,
    String? body,
  }) async {
    final now = DateTime.now().toUtc();
    final trimmedBody = body?.trim();
    final reminder = ZoneReminder(
      id: _uuid.v4(),
      zoneId: zoneId,
      title: title.trim(),
      body: (trimmedBody == null || trimmedBody.isEmpty) ? null : trimmedBody,
      active: true,
      createdAt: now,
      updatedAt: now,
    );
    await _local.saveReminder(reminder, SyncStatus.pendingUpsert);
    _pushLater();
    return reminder;
  }

  Future<ZoneReminder> updateReminder(ZoneReminder reminder) async {
    final updated = reminder.copyWith(updatedAt: DateTime.now().toUtc());
    await _local.saveReminder(updated, SyncStatus.pendingUpsert);
    _pushLater();
    return updated;
  }

  /// Undo for a delete: put the same reminder back.
  Future<void> restoreReminder(ZoneReminder reminder) async {
    await _local.saveReminder(
        reminder.copyWith(updatedAt: DateTime.now().toUtc()),
        SyncStatus.pendingUpsert);
    _pushLater();
  }

  Future<void> deleteReminder(String id) async {
    await _local.markReminderDeleted(id);
    _pushLater();
  }

  Future<List<TriggerLogEntry>> triggerLog(String zoneId) =>
      _local.triggerLog(zoneId);

  Future<void> clearLocal() => _local.clearUserData();

  void _pushLater() => unawaited(_sync.pushPending());

  String _requireUserId() {
    final id = supabase.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Not signed in.');
    }
    return id;
  }
}
