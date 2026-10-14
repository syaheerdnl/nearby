/// `list_items.status`. `settled` means the owner paid the buyer back; it is
/// final (the database rejects any change to a settled item).
enum ItemStatus {
  open,
  claimed,
  bought,
  settled;

  static ItemStatus fromName(String? v) =>
      values.firstWhere((s) => s.name == v, orElse: () => ItemStatus.open);
}

class ListItem {
  const ListItem({
    required this.id,
    required this.listId,
    required this.name,
    required this.quantity,
    required this.status,
    required this.createdBy,
    this.notes,
    this.claimedBy,
  });

  final String id;
  final String listId;
  final String name;
  final int quantity;
  final String? notes;
  final ItemStatus status;
  final String? claimedBy;
  final String createdBy;

  bool get isDone => status == ItemStatus.bought || status == ItemStatus.settled;

  factory ListItem.fromRow(Map<String, dynamic> r) => ListItem(
        id: r['id'] as String,
        listId: r['list_id'] as String,
        name: r['name'] as String,
        quantity: (r['quantity'] as num?)?.toInt() ?? 1,
        notes: r['notes'] as String?,
        status: ItemStatus.fromName(r['status'] as String?),
        claimedBy: r['claimed_by'] as String?,
        createdBy: r['created_by'] as String,
      );

  /// What the row should become when [me] takes [action]. Returns null when
  /// the action makes no sense from the current state.
  static Map<String, Object?>? transition(
      ListItem item, ItemAction action, String me) {
    if (item.status == ItemStatus.settled) return null;
    switch (action) {
      case ItemAction.claim:
        if (item.status != ItemStatus.open) return null;
        return {'status': ItemStatus.claimed.name, 'claimed_by': me};
      case ItemAction.unclaim:
        if (item.status != ItemStatus.claimed || item.claimedBy != me) {
          return null;
        }
        return {'status': ItemStatus.open.name, 'claimed_by': null};
      case ItemAction.bought:
        if (item.isDone) return null;
        // Buying something nobody claimed counts as claiming it too.
        return {'status': ItemStatus.bought.name, 'claimed_by': item.claimedBy ?? me};
      case ItemAction.reopen:
        if (item.status == ItemStatus.open) return null;
        return {'status': ItemStatus.open.name, 'claimed_by': null};
    }
  }
}

enum ItemAction { claim, unclaim, bought, reopen }

/// Items sorted for display: open first, then claimed, then done.
List<ListItem> sortItems(Iterable<ListItem> items) {
  int rank(ListItem i) => switch (i.status) {
        ItemStatus.open => 0,
        ItemStatus.claimed => 1,
        _ => 2,
      };
  final out = items.toList();
  out.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}
