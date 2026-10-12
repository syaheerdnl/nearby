import '../core/constants.dart';
import '../core/place_category.dart';

/// A place the user cares about. Column names match `public.zones`.
class Zone {
  const Zone({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.triggerType,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    this.onceOnly = false,
    this.activeFrom,
    this.activeTo,
  });

  final String id;
  final String ownerId;
  final String name;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final TriggerType triggerType;
  final PlaceCategory category;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// After the first alert, switch this place's reminders off.
  final bool onceOnly;

  /// Quiet outside this window. Minutes after local midnight; both null =
  /// any time. from > to wraps past midnight.
  final int? activeFrom;
  final int? activeTo;

  bool get hasActiveWindow => activeFrom != null && activeTo != null;

  /// Whether an alert may show at [localTime].
  bool isActiveAt(DateTime localTime) => !hasActiveWindow ||
      minuteInWindow(
          localTime.hour * 60 + localTime.minute, activeFrom!, activeTo!);

  /// [m] inside [from, to] (inclusive start, exclusive end); wraps midnight
  /// when from > to. from == to means all day.
  static bool minuteInWindow(int m, int from, int to) {
    if (from == to) return true;
    return from < to ? (m >= from && m < to) : (m >= from || m < to);
  }

  Zone copyWith({
    String? name,
    double? latitude,
    double? longitude,
    int? radiusMeters,
    TriggerType? triggerType,
    PlaceCategory? category,
    DateTime? updatedAt,
    bool? onceOnly,
    int? activeFrom,
    int? activeTo,
    bool clearActiveWindow = false,
  }) {
    return Zone(
      id: id,
      ownerId: ownerId,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      triggerType: triggerType ?? this.triggerType,
      category: category ?? this.category,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      onceOnly: onceOnly ?? this.onceOnly,
      activeFrom: clearActiveWindow ? null : (activeFrom ?? this.activeFrom),
      activeTo: clearActiveWindow ? null : (activeTo ?? this.activeTo),
    );
  }

  /// Supabase row. `location` is left out: a trigger fills it from lat/lng.
  Map<String, Object?> toRemote() => {
        'id': id,
        'owner_id': ownerId,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius_meters': radiusMeters,
        'trigger_type': triggerType.name,
        'category': category.name,
        'once_only': onceOnly,
        'active_from': activeFrom,
        'active_to': activeTo,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory Zone.fromRemote(Map<String, dynamic> row) => Zone(
        id: row['id'] as String,
        ownerId: row['owner_id'] as String,
        name: row['name'] as String,
        latitude: (row['latitude'] as num).toDouble(),
        longitude: (row['longitude'] as num).toDouble(),
        radiusMeters: (row['radius_meters'] as num).toInt(),
        triggerType: TriggerType.fromName(row['trigger_type'] as String),
        category: PlaceCategory.fromName(row['category'] as String?),
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        onceOnly: row['once_only'] as bool? ?? false,
        activeFrom: (row['active_from'] as num?)?.toInt(),
        activeTo: (row['active_to'] as num?)?.toInt(),
      );

  /// sqflite row (dates as ISO strings).
  Map<String, Object?> toLocal(SyncStatus status) => {
        'id': id,
        'owner_id': ownerId,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius_meters': radiusMeters,
        'trigger_type': triggerType.name,
        'category': category.name,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'once_only': onceOnly ? 1 : 0,
        'active_from': activeFrom,
        'active_to': activeTo,
        'sync_status': status.value,
      };

  factory Zone.fromLocal(Map<String, Object?> row) => Zone(
        id: row['id']! as String,
        ownerId: row['owner_id']! as String,
        name: row['name']! as String,
        latitude: (row['latitude']! as num).toDouble(),
        longitude: (row['longitude']! as num).toDouble(),
        radiusMeters: (row['radius_meters']! as num).toInt(),
        triggerType: TriggerType.fromName(row['trigger_type']! as String),
        category: PlaceCategory.fromName(row['category'] as String?),
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
        onceOnly: (row['once_only'] as num? ?? 0) == 1,
        activeFrom: (row['active_from'] as num?)?.toInt(),
        activeTo: (row['active_to'] as num?)?.toInt(),
      );
}
