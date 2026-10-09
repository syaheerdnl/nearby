import '../core/constants.dart';

/// Something to remember at a zone. Column names match `public.zone_reminders`.
class ZoneReminder {
  const ZoneReminder({
    required this.id,
    required this.zoneId,
    required this.title,
    required this.body,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String zoneId;
  final String title;
  final String? body;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  ZoneReminder copyWith({
    String? title,
    String? body,
    bool clearBody = false,
    bool? active,
    DateTime? updatedAt,
  }) {
    return ZoneReminder(
      id: id,
      zoneId: zoneId,
      title: title ?? this.title,
      body: clearBody ? null : (body ?? this.body),
      active: active ?? this.active,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toRemote() => {
        'id': id,
        'zone_id': zoneId,
        'title': title,
        'body': body,
        'active': active,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory ZoneReminder.fromRemote(Map<String, dynamic> row) => ZoneReminder(
        id: row['id'] as String,
        zoneId: row['zone_id'] as String,
        title: row['title'] as String,
        body: row['body'] as String?,
        active: row['active'] as bool? ?? true,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  Map<String, Object?> toLocal(SyncStatus status) => {
        'id': id,
        'zone_id': zoneId,
        'title': title,
        'body': body,
        'active': active ? 1 : 0,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'sync_status': status.value,
      };

  factory ZoneReminder.fromLocal(Map<String, Object?> row) => ZoneReminder(
        id: row['id']! as String,
        zoneId: row['zone_id']! as String,
        title: row['title']! as String,
        body: row['body'] as String?,
        active: (row['active'] as int? ?? 1) == 1,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );
}
