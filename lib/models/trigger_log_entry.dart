import '../core/constants.dart';

/// Local-only record of every geofence event, so trigger latency can be
/// measured on real devices (CLAUDE.md Phase 1 step 7).
class TriggerLogEntry {
  const TriggerLogEntry({
    required this.id,
    required this.zoneId,
    required this.event,
    required this.firedAt,
    required this.latitude,
    required this.longitude,
    required this.notified,
  });

  final int id;
  final String zoneId;
  final TriggerType event;
  final DateTime firedAt;
  final double? latitude;
  final double? longitude;

  /// False when the zone had no active reminders, so nothing was shown.
  final bool notified;

  factory TriggerLogEntry.fromLocal(Map<String, Object?> row) =>
      TriggerLogEntry(
        id: row['id']! as int,
        zoneId: row['zone_id']! as String,
        event: TriggerType.fromName(row['event']! as String),
        firedAt: DateTime.parse(row['fired_at']! as String),
        latitude: (row['latitude'] as num?)?.toDouble(),
        longitude: (row['longitude'] as num?)?.toDouble(),
        notified: (row['notified'] as int? ?? 0) == 1,
      );
}
