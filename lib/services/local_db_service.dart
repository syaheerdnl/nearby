import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../models/trigger_log_entry.dart';
import '../models/zone.dart';
import '../models/zone_reminder.dart';

/// sqflite store. Mirrors `zones` / `zone_reminders` plus a local
/// `sync_status` column, a trigger log and a small key-value table.
///
/// Also opened from the geofence background isolate, so keep it free of
/// Flutter UI imports.
class LocalDbService {
  LocalDbService._();
  static final LocalDbService instance = LocalDbService._();

  static const _dbName = 'nearby.db';
  static const _dbVersion = 2;

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute(
              "ALTER TABLE zones ADD COLUMN category TEXT NOT NULL DEFAULT 'other'");
        }
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE zones (
            id TEXT PRIMARY KEY,
            owner_id TEXT NOT NULL,
            name TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            radius_meters INTEGER NOT NULL,
            trigger_type TEXT NOT NULL,
            category TEXT NOT NULL DEFAULT 'other',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'pending_upsert'
          )''');
        await db.execute('''
          CREATE TABLE zone_reminders (
            id TEXT PRIMARY KEY,
            zone_id TEXT NOT NULL REFERENCES zones(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            body TEXT,
            active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'pending_upsert'
          )''');
        await db.execute('''
          CREATE TABLE trigger_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            zone_id TEXT NOT NULL,
            event TEXT NOT NULL,
            fired_at TEXT NOT NULL,
            latitude REAL,
            longitude REAL,
            notified INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE app_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )''');
      },
    );
  }

  // Update-then-insert. ConflictAlgorithm.replace would delete the old row
  // first, and the ON DELETE CASCADE would wipe that zone's reminders.
  Future<void> _upsert(String table, Map<String, Object?> row) async {
    final database = await db;
    final updated = await database
        .update(table, row, where: 'id = ?', whereArgs: [row['id']]);
    if (updated == 0) {
      await database.insert(table, row);
    }
  }

  // ---------- zones ----------

  Future<List<Zone>> zones() async {
    final rows = await (await db).query(
      'zones',
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.pendingDelete.value],
      orderBy: 'created_at ASC',
    );
    return rows.map(Zone.fromLocal).toList();
  }

  Future<Zone?> zoneById(String id) async {
    final rows =
        await (await db).query('zones', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Zone.fromLocal(rows.first);
  }

  Future<void> saveZone(Zone zone, SyncStatus status) =>
      _upsert('zones', zone.toLocal(status));

  Future<List<Zone>> zonesWithStatus(SyncStatus status) async {
    final rows = await (await db)
        .query('zones', where: 'sync_status = ?', whereArgs: [status.value]);
    return rows.map(Zone.fromLocal).toList();
  }

  Future<Map<String, SyncStatus>> zoneStatuses() async {
    final rows = await (await db).query('zones', columns: ['id', 'sync_status']);
    return {
      for (final r in rows)
        r['id']! as String: SyncStatus.fromValue(r['sync_status'] as String?),
    };
  }

  /// Marks the zone for remote deletion. Its reminders go now: the remote
  /// foreign key cascades them, so they never need pushing.
  Future<void> markZoneDeleted(String id) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete('zone_reminders', where: 'zone_id = ?', whereArgs: [id]);
      await txn.update(
        'zones',
        {'sync_status': SyncStatus.pendingDelete.value},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> hardDeleteZone(String id) async {
    await (await db).delete('zones', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markZoneSynced(String id, DateTime updatedAt) async {
    await (await db).update('zones', {'sync_status': SyncStatus.synced.value},
        where: 'id = ? AND updated_at = ? AND sync_status = ?',
        whereArgs: [
          id,
          updatedAt.toUtc().toIso8601String(),
          SyncStatus.pendingUpsert.value,
        ]);
  }

  // ---------- reminders ----------

  Future<List<ZoneReminder>> remindersForZone(String zoneId,
      {bool activeOnly = false}) async {
    final where = StringBuffer('zone_id = ? AND sync_status != ?');
    final args = <Object?>[zoneId, SyncStatus.pendingDelete.value];
    if (activeOnly) {
      where.write(' AND active = 1');
    }
    final rows = await (await db).query(
      'zone_reminders',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'created_at ASC',
    );
    return rows.map(ZoneReminder.fromLocal).toList();
  }

  Future<void> saveReminder(ZoneReminder reminder, SyncStatus status) =>
      _upsert('zone_reminders', reminder.toLocal(status));

  Future<List<ZoneReminder>> remindersWithStatus(SyncStatus status) async {
    final rows = await (await db).query('zone_reminders',
        where: 'sync_status = ?', whereArgs: [status.value]);
    return rows.map(ZoneReminder.fromLocal).toList();
  }

  Future<Map<String, SyncStatus>> reminderStatuses() async {
    final rows =
        await (await db).query('zone_reminders', columns: ['id', 'sync_status']);
    return {
      for (final r in rows)
        r['id']! as String: SyncStatus.fromValue(r['sync_status'] as String?),
    };
  }

  Future<void> markReminderDeleted(String id) async {
    await (await db).update(
        'zone_reminders', {'sync_status': SyncStatus.pendingDelete.value},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> hardDeleteReminder(String id) async {
    await (await db).delete('zone_reminders', where: 'id = ?', whereArgs: [id]);
  }

  /// Pull merge. Only overwrites rows that are still synced (or new), checked
  /// inside SQL, so a local edit made mid-pull (e.g. "Done" from the
  /// notification isolate) is never clobbered.
  Future<void> saveRemoteReminder(ZoneReminder reminder) async {
    final database = await db;
    final row = reminder.toLocal(SyncStatus.synced);
    final n = await database.update('zone_reminders', row,
        where: 'id = ? AND sync_status = ?',
        whereArgs: [reminder.id, SyncStatus.synced.value]);
    if (n == 0) {
      await database.insert('zone_reminders', row,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Pull cleanup: drop a reminder deleted remotely, unless edited locally.
  Future<void> deleteSyncedReminder(String id) async {
    await (await db).delete('zone_reminders',
        where: 'id = ? AND sync_status = ?',
        whereArgs: [id, SyncStatus.synced.value]);
  }

  Future<void> markReminderSynced(String id, DateTime updatedAt) async {
    await (await db).update(
        'zone_reminders', {'sync_status': SyncStatus.synced.value},
        where: 'id = ? AND updated_at = ? AND sync_status = ?',
        whereArgs: [
          id,
          updatedAt.toUtc().toIso8601String(),
          SyncStatus.pendingUpsert.value,
        ]);
  }

  /// "Done" from a notification: switch off every active reminder at this
  /// place and queue them for sync. Returns how many were turned off.
  Future<int> turnOffReminders(String zoneId) async {
    final active = await remindersForZone(zoneId, activeOnly: true);
    final now = DateTime.now().toUtc();
    for (final r in active) {
      await saveReminder(
          r.copyWith(active: false, updatedAt: now), SyncStatus.pendingUpsert);
    }
    return active.length;
  }

  // ---------- trigger log ----------

  Future<void> logTrigger({
    required String zoneId,
    required TriggerType event,
    required DateTime firedAt,
    required double? latitude,
    required double? longitude,
    required bool notified,
  }) async {
    await (await db).insert('trigger_log', {
      'zone_id': zoneId,
      'event': event.name,
      'fired_at': firedAt.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'notified': notified ? 1 : 0,
    });
  }

  Future<List<TriggerLogEntry>> triggerLog(String zoneId,
      {int limit = 20}) async {
    final rows = await (await db).query(
      'trigger_log',
      where: 'zone_id = ?',
      whereArgs: [zoneId],
      orderBy: 'fired_at DESC',
      limit: limit,
    );
    return rows.map(TriggerLogEntry.fromLocal).toList();
  }

  // ---------- app meta ----------

  Future<String?> getMeta(String key) async {
    final rows = await (await db)
        .query('app_meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    await (await db).insert('app_meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// On sign-out: drop everything that belongs to the account.
  Future<void> clearUserData() async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete('zone_reminders');
      await txn.delete('zones');
      await txn.delete('trigger_log');
    });
  }
}
