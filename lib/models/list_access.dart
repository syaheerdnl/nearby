/// 'view' = see items; 'claim' = also claim, mark bought, add items, and
/// get the arrival alert for the place.
enum ListPermission {
  view,
  claim;

  static ListPermission? fromName(String? v) {
    for (final p in values) {
      if (p.name == v) return p;
    }
    return null;
  }
}

class ListAccessEntry {
  const ListAccessEntry({
    required this.friendId,
    required this.username,
    required this.permission,
  });
  final String friendId;
  final String username;
  final ListPermission permission;
}
