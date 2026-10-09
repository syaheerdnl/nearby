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

  Zone copyWith({
    String? name,
    double? latitude,
    double? longitude,
    int? radiusMeters,
    TriggerType? triggerType,
    PlaceCategory? category,
    DateTime? updatedAt,
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
      );
}
