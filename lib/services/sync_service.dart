import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../core/supabase_client.dart';
import '../models/zone.dart';
import '../models/zone_reminder.dart';
import 'local_db_service.dart';

/// Reconciles the local sqflite store with Supabase.
///
/// Writes always land locally first with a pending status; [pushPending]
/// sends them up whenever we are online. Failures leave rows pending, so the
/// next call (app start, resume, or the next edit) retries them.
class SyncService {
  SyncService({LocalDbService? local})
      : _local = local ?? LocalDbService.instance;

  final LocalDbService _local;
  bool _pushing = false;
  bool _again = false;

  Future<void> pushPending() async {
    if (supabase.auth.currentUser == null) return;
    if (_pushing) {
      // A push is running; make it go round once more for the new rows.
      _again = true;
      return;
    }
    _pushing = true;
    try {
      do {
        _again = false;
        await _pushOnce();
      } while (_again);
    } finally {
      _pushing = false;
    }
  }

  Future<void> _pushOnce() async {
    {
      // Rows are only marked synced if they weren't edited again while the
      // upload was in flight (matched on updated_at).
      // Zones before reminders: reminders reference zones remotely.
      for (final zone in await _local.zonesWithStatus(SyncStatus.pendingUpsert)) {
        await _try(() async {
          await supabase.from('zones').upsert(zone.toRemote());
          await _local.markZoneSynced(zone.id, zone.updatedAt);
        }, 'upsert zone ${zone.id}');
      }
      for (final r
          in await _local.remindersWithStatus(SyncStatus.pendingUpsert)) {
        await _try(() async {
          await supabase.from('zone_reminders').upsert(r.toRemote());
          await _local.markReminderSynced(r.id, r.updatedAt);
        }, 'upsert reminder ${r.id}');
      }
      for (final r
          in await _local.remindersWithStatus(SyncStatus.pendingDelete)) {
        await _try(() async {
          await supabase.from('zone_reminders').delete().eq('id', r.id);
          await _local.hardDeleteReminder(r.id);
        }, 'delete reminder ${r.id}');
      }
      for (final zone in await _local.zonesWithStatus(SyncStatus.pendingDelete)) {
        await _try(() async {
          await supabase.from('zones').delete().eq('id', zone.id);
          await _local.hardDeleteZone(zone.id);
        }, 'delete zone ${zone.id}');
      }
    }
  }

  /// Pulls the user's rows and merges them in. Local rows with unpushed
  /// changes win; synced local rows missing remotely were deleted elsewhere.
  Future<void> pullRemote() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final zoneRows =
        await supabase.from('zones').select().eq('owner_id', userId);
    final remoteZones = zoneRows.map(Zone.fromRemote).toList();
    final zoneIds = remoteZones.map((z) => z.id).toList();
    final reminderRows = zoneIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await supabase
            .from('zone_reminders')
            .select()
            .inFilter('zone_id', zoneIds);
    final remoteReminders = reminderRows.map(ZoneReminder.fromRemote).toList();

    final zoneStatus = await _local.zoneStatuses();
    for (final zone in remoteZones) {
      final status = zoneStatus[zone.id];
      if (status == null || status == SyncStatus.synced) {
        await _local.saveZone(zone, SyncStatus.synced);
      }
    }
    final remoteZoneIds = zoneIds.toSet();
    for (final entry in zoneStatus.entries) {
      if (entry.value == SyncStatus.synced &&
          !remoteZoneIds.contains(entry.key)) {
        await _local.hardDeleteZone(entry.key);
      }
    }

    final reminderStatus = await _local.reminderStatuses();
    for (final r in remoteReminders) {
      final status = reminderStatus[r.id];
      final parent = zoneStatus[r.zoneId];
      if (parent == SyncStatus.pendingDelete) continue;
      if (status == null || status == SyncStatus.synced) {
        await _local.saveRemoteReminder(r);
      }
    }
    final remoteReminderIds = remoteReminders.map((r) => r.id).toSet();
    for (final entry in reminderStatus.entries) {
      if (entry.value == SyncStatus.synced &&
          !remoteReminderIds.contains(entry.key)) {
        await _local.deleteSyncedReminder(entry.key);
      }
    }
  }

  Future<void> _try(Future<void> Function() action, String label) async {
    try {
      await action();
    } catch (e) {
      debugPrint('Sync: $label failed, will retry later: $e');
    }
  }
}
