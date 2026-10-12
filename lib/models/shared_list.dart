import 'list_access.dart';

class SharedList {
  const SharedList({
    required this.id,
    required this.zoneId,
    required this.title,
    required this.zoneName,
    required this.ownerId,
    required this.ownerName,
    this.myPermission,
  });

  final String id;
  final String zoneId;
  final String title;
  final String zoneName;
  final String ownerId;
  final String ownerName;

  /// Null when I own the list.
  final ListPermission? myPermission;

  bool get iOwn => myPermission == null;
  bool get canEdit => iOwn || myPermission == ListPermission.claim;
}

/// A place someone shared with me (claim access), cached on the phone so the
/// geofence callback can alert without a network call.
class SharedPlace {
  const SharedPlace({
    required this.zoneId,
    required this.listId,
    required this.listTitle,
    required this.ownerName,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.openItems,
  });

  final String zoneId;
  final String listId;
  final String listTitle;
  final String ownerName;
  final String name;
  final double latitude;
  final double longitude;
  final int radiusMeters;

  /// Open item lines at last sync, e.g. "Beras 5kg x1".
  final List<String> openItems;

  Map<String, Object?> toLocal() => {
        'zone_id': zoneId,
        'list_id': listId,
        'list_title': listTitle,
        'owner_name': ownerName,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius_meters': radiusMeters,
        'open_items': openItems.join('\n'),
      };

  factory SharedPlace.fromLocal(Map<String, Object?> r) => SharedPlace(
        zoneId: r['zone_id']! as String,
        listId: r['list_id']! as String,
        listTitle: r['list_title']! as String,
        ownerName: r['owner_name']! as String,
        name: r['name']! as String,
        latitude: (r['latitude']! as num).toDouble(),
        longitude: (r['longitude']! as num).toDouble(),
        radiusMeters: (r['radius_meters']! as num).toInt(),
        openItems: ((r['open_items'] as String?) ?? '')
            .split('\n')
            .where((l) => l.isNotEmpty)
            .toList(),
      );
}
