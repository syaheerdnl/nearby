import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/list_access.dart';
import '../models/list_item.dart';
import '../models/shared_list.dart';
import 'local_db_service.dart';

/// Shared lists live on the server (they're shared, so offline copies would
/// conflict). RLS decides what each user can read or change. The only local
/// copy is [SharedPlace]s, so a friend's phone can alert without a network.
class ListRepository {
  ListRepository({LocalDbService? local})
      : _local = local ?? LocalDbService.instance;

  final LocalDbService _local;

  String get me {
    final id = supabase.auth.currentUser?.id;
    if (id == null) throw const ListException('Not signed in.');
    return id;
  }

  Future<Map<String, String>> _names(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return {};
    final rows =
        await supabase.from('profiles').select('id, username').inFilter('id', list);
    return {for (final r in rows) r['id'] as String: r['username'] as String};
  }

  // ---------- lists ----------

  /// My own list for a zone, if any (one list per place).
  Future<String?> listIdForZone(String zoneId) async {
    final rows = await supabase
        .from('shared_lists')
        .select('id')
        .eq('zone_id', zoneId)
        .order('created_at')
        .limit(1);
    return rows.isEmpty ? null : rows.first['id'] as String;
  }

  Future<String> createList(String zoneId, String title) async {
    final row = await supabase
        .from('shared_lists')
        .insert({'zone_id': zoneId, 'title': title.trim()})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> renameList(String listId, String title) =>
      supabase.from('shared_lists').update({'title': title.trim()}).eq('id', listId);

  Future<void> deleteList(String listId) =>
      supabase.from('shared_lists').delete().eq('id', listId);

  Future<SharedList> getList(String listId) async {
    final l = await supabase
        .from('shared_lists')
        .select('id, zone_id, title, zones(name, owner_id)')
        .eq('id', listId)
        .single();
    final zone = (l['zones'] as Map?) ?? const {};
    final ownerId = zone['owner_id'] as String? ?? '';
    final names = await _names([ownerId]);
    ListPermission? mine;
    if (ownerId != me) {
      final a = await supabase
          .from('list_access')
          .select('permission')
          .eq('list_id', listId)
          .eq('friend_id', me)
          .maybeSingle();
      mine = ListPermission.fromName(a?['permission'] as String?) ??
          ListPermission.view;
    }
    return SharedList(
      id: l['id'] as String,
      zoneId: l['zone_id'] as String,
      title: l['title'] as String,
      zoneName: zone['name'] as String? ?? '',
      ownerId: ownerId,
      ownerName: names[ownerId] ?? '',
      myPermission: mine,
    );
  }

  // ---------- items ----------

  Future<List<ListItem>> items(String listId) async {
    final rows = await supabase
        .from('list_items')
        .select()
        .eq('list_id', listId);
    return sortItems(rows.map(ListItem.fromRow));
  }

  Future<void> addItem(String listId, String name, int quantity) =>
      supabase.from('list_items').insert({
        'list_id': listId,
        'name': name.trim(),
        'quantity': quantity,
        'created_by': me,
      });

  Future<void> apply(ListItem item, ItemAction action) async {
    final change = ListItem.transition(item, action, me);
    if (change == null) return;
    await supabase.from('list_items').update(change).eq('id', item.id);
  }

  Future<void> deleteItem(String itemId) =>
      supabase.from('list_items').delete().eq('id', itemId);

  /// Usernames for ids that appear on items (claimers).
  Future<Map<String, String>> names(Iterable<String> ids) => _names(ids);

  // ---------- access ----------

  Future<List<ListAccessEntry>> access(String listId) async {
    final rows = await supabase
        .from('list_access')
        .select('friend_id, permission')
        .eq('list_id', listId);
    final names = await _names(rows.map((r) => r['friend_id'] as String));
    return [
      for (final r in rows)
        ListAccessEntry(
          friendId: r['friend_id'] as String,
          username: names[r['friend_id']] ?? 'unknown',
          permission: ListPermission.fromName(r['permission'] as String?) ??
              ListPermission.view,
        ),
    ]..sort((a, b) => a.username.compareTo(b.username));
  }

  /// [permission] null removes access.
  Future<void> setAccess(
      String listId, String friendId, ListPermission? permission) async {
    if (permission == null) {
      await supabase
          .from('list_access')
          .delete()
          .eq('list_id', listId)
          .eq('friend_id', friendId);
      return;
    }
    await supabase.from('list_access').upsert(
      {'list_id': listId, 'friend_id': friendId, 'permission': permission.name},
      onConflict: 'list_id,friend_id',
    );
  }

  /// Friend leaves a list someone shared with them.
  Future<void> leave(String listId) => supabase
      .from('list_access')
      .delete()
      .eq('list_id', listId)
      .eq('friend_id', me);

  // ---------- shared with me ----------

  /// Lists others shared with me, with their place. Also refreshes the local
  /// cache the geofence callback reads (claim access only gets alerts).
  Future<List<SharedPlace>> refreshSharedWithMe() async {
    final access = await supabase
        .from('list_access')
        .select('list_id, permission, shared_lists(id, title, zone_id, '
            'zones(id, name, latitude, longitude, radius_meters, owner_id))')
        .eq('friend_id', me);
    final ownerIds = <String>{};
    for (final a in access) {
      final z = (a['shared_lists'] as Map?)?['zones'] as Map?;
      if (z?['owner_id'] is String) ownerIds.add(z!['owner_id'] as String);
    }
    final owners = await _names(ownerIds);
    final listIds = [
      for (final a in access)
        if (a['permission'] == 'claim') a['list_id'] as String,
    ];
    final openByList = <String, List<String>>{};
    if (listIds.isNotEmpty) {
      final items = await supabase
          .from('list_items')
          .select('list_id, name, quantity')
          .inFilter('list_id', listIds)
          .eq('status', 'open');
      for (final i in items) {
        final q = (i['quantity'] as num?)?.toInt() ?? 1;
        openByList
            .putIfAbsent(i['list_id'] as String, () => [])
            .add(q > 1 ? '${i['name']} x$q' : i['name'] as String);
      }
    }
    final places = <SharedPlace>[];
    for (final a in access) {
      if (a['permission'] != 'claim') continue;
      final l = a['shared_lists'] as Map?;
      final z = l?['zones'] as Map?;
      if (l == null || z == null) continue;
      places.add(SharedPlace(
        zoneId: z['id'] as String,
        listId: l['id'] as String,
        listTitle: l['title'] as String,
        ownerName: owners[z['owner_id']] ?? '',
        name: z['name'] as String,
        latitude: (z['latitude'] as num).toDouble(),
        longitude: (z['longitude'] as num).toDouble(),
        radiusMeters: (z['radius_meters'] as num).toInt(),
        openItems: openByList[l['id']] ?? const [],
      ));
    }
    await _local.replaceSharedPlaces(places);
    return places;
  }

  /// All lists shared with me (any permission), for the Home screen.
  Future<List<SharedList>> sharedWithMe() async {
    final access = await supabase
        .from('list_access')
        .select('permission, shared_lists(id, title, zone_id, zones(name, owner_id))')
        .eq('friend_id', me);
    final ownerIds = <String>{
      for (final a in access)
        if (((a['shared_lists'] as Map?)?['zones'] as Map?)?['owner_id']
            is String)
          ((a['shared_lists'] as Map)['zones'] as Map)['owner_id'] as String,
    };
    final owners = await _names(ownerIds);
    return [
      for (final a in access)
        if (a['shared_lists'] is Map)
          SharedList(
            id: (a['shared_lists'] as Map)['id'] as String,
            zoneId: (a['shared_lists'] as Map)['zone_id'] as String,
            title: (a['shared_lists'] as Map)['title'] as String,
            zoneName: (((a['shared_lists'] as Map)['zones'] as Map?)?['name']
                    as String?) ??
                '',
            ownerId: (((a['shared_lists'] as Map)['zones'] as Map?)?['owner_id']
                    as String?) ??
                '',
            ownerName: owners[((a['shared_lists'] as Map)['zones']
                    as Map?)?['owner_id']] ??
                '',
            myPermission: ListPermission.fromName(a['permission'] as String?),
          ),
    ];
  }

  // ---------- realtime ----------

  /// Calls [onChange] whenever an item on [listId] changes.
  /// Deletes can't be filtered server-side (RLS leaves only the id), so
  /// [onDelete] gets every visible delete's id; the screen checks its own.
  RealtimeChannel watch(String listId, void Function() onChange,
      {void Function(String id)? onDelete}) {
    return supabase
        // Unique topic per screen: two screens on one topic would share it.
        .channel('list-items-$listId-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'list_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'list_id',
            value: listId,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'list_items',
          callback: (p) => onDelete?.call('${p.oldRecord['id']}'),
        )
        .subscribe();
  }

  Future<void> unwatch(RealtimeChannel channel) =>
      supabase.removeChannel(channel);
}

class ListException implements Exception {
  const ListException(this.message);
  final String message;
  @override
  String toString() => message;
}
