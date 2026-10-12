import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/list_access.dart';
import '../../models/list_item.dart';
import '../../models/shared_list.dart';
import '../../providers/zone_provider.dart';
import '../../services/list_repository.dart';
import 'share_list_screen.dart';

/// One shared list, the same screen for the owner and for friends. Changes
/// from other phones arrive live (Supabase Realtime on list_items).
class SharedListScreen extends StatefulWidget {
  const SharedListScreen({super.key, required this.listId});
  final String listId;

  @override
  State<SharedListScreen> createState() => _SharedListScreenState();
}

class _SharedListScreenState extends State<SharedListScreen> {
  final _repo = ListRepository();
  final _add = TextEditingController();
  final _addFocus = FocusNode();

  SharedList? _list;
  List<ListItem> _items = const [];
  List<ListAccessEntry> _access = const [];
  Map<String, String> _names = {};
  String? _error;
  bool _loading = true;
  RealtimeChannel? _channel;
  Timer? _reloadSoon;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _repo.watch(widget.listId, _scheduleReload, onDelete: (id) {
      if (_items.any((i) => i.id == id)) _scheduleReload();
    });
  }

  // Several rows can change at once: reload once.
  void _scheduleReload() {
    _reloadSoon?.cancel();
    _reloadSoon = Timer(const Duration(milliseconds: 300), _loadItems);
  }

  @override
  void dispose() {
    _reloadSoon?.cancel();
    final c = _channel;
    if (c != null) _repo.unwatch(c);
    _add.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.getList(widget.listId);
      final access = await _repo.access(widget.listId);
      if (!mounted) return;
      setState(() {
        _list = list;
        _access = access;
        _error = null;
      });
      await _loadItems();
    } catch (e) {
      debugPrint('Load list failed: $e');
      if (mounted) {
        setState(() => _error = 'Could not open this list. It may have been '
            'removed, or you are offline.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadItems() async {
    try {
      final items = await _repo.items(widget.listId);
      final ids = {
        for (final i in items) ...[
          if (i.claimedBy != null) i.claimedBy!,
          i.createdBy,
        ],
      }..removeAll(_names.keys);
      final names = ids.isEmpty ? const <String, String>{} : await _repo.names(ids);
      if (!mounted) return;
      setState(() {
        _items = items;
        _names = {..._names, ...names};
      });
    } catch (e) {
      debugPrint('Load items failed: $e');
    }
  }

  Future<bool> _run(Future<void> Function() action) async {
    try {
      await action();
      await _loadItems();
      return true;
    } catch (e) {
      debugPrint('List action failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Couldn't save that. Check your connection.")));
      }
      return false;
    }
  }

  Future<void> _addItem() async {
    final raw = _add.text.trim();
    if (raw.isEmpty) return;
    // "Telur x30" or "Telur 30x" sets the quantity.
    final m = RegExp(r'^(.*?)\s*(?:x\s*(\d{1,3})|(\d{1,3})\s*x)$',
            caseSensitive: false)
        .firstMatch(raw);
    final name = (m?.group(1)?.trim().isNotEmpty ?? false) ? m!.group(1)!.trim() : raw;
    final qty = int.tryParse(m?.group(2) ?? m?.group(3) ?? '') ?? 1;
    _add.clear();
    _addFocus.requestFocus();
    await _run(() => _repo.addItem(widget.listId, name, qty.clamp(1, 999)));
  }

  String _who(String? id) {
    if (id == null) return '';
    if (id == _repo.me) return 'You';
    return _names[id] ?? '';
  }

  void _itemActions(ListItem item) {
    final list = _list;
    if (list == null || !list.canEdit) return;
    final me = _repo.me;
    final actions = <(IconData, String, Future<void> Function())>[
      if (item.status == ItemStatus.open)
        (Icons.front_hand_outlined, "I'll buy this",
            () => _repo.apply(item, ItemAction.claim)),
      if (item.status == ItemStatus.claimed && item.claimedBy == me)
        (Icons.undo, "I can't buy it after all",
            () => _repo.apply(item, ItemAction.unclaim)),
      if (!item.isDone)
        (Icons.check_circle_outline, 'Bought',
            () => _repo.apply(item, ItemAction.bought)),
      if (item.status != ItemStatus.open)
        (Icons.replay, 'Put back on the list',
            () => _repo.apply(item, ItemAction.reopen)),
      if (list.iOwn || item.createdBy == me)
        (Icons.delete_outline, 'Delete', () => _repo.deleteItem(item.id)),
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(item.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: item.quantity > 1 ? Text('x${item.quantity}') : null,
            ),
            const Divider(height: 1),
            for (final (icon, label, run) in actions)
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () {
                  Navigator.pop(ctx);
                  _run(run);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this list?'),
        content: const Text("You won't see it or get alerts for this place."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final zones = context.read<ZoneProvider>();
    final nav = Navigator.of(context);
    if (!await _run(() => _repo.leave(widget.listId))) return;
    await zones.refresh();
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = _list;
    final open = _items.where((i) => !i.isDone).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(list?.title ?? 'List'),
        actions: [
          if (list != null && list.iOwn)
            TextButton.icon(
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Share'),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ShareListScreen(list: list)));
                if (mounted) _load();
              },
            ),
          if (list != null && !list.iOwn)
            IconButton(
                tooltip: 'Leave list',
                icon: const Icon(Icons.logout),
                onPressed: _leave),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
                    children: [
                      Text(
                        [
                          list!.zoneName,
                          if (!list.iOwn) 'from ${list.ownerName}',
                          '$open open',
                        ].join(' · '),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      _Members(
                        owner: list.iOwn ? 'You' : list.ownerName,
                        access: _access,
                        myId: _repo.me,
                      ),
                      if (!list.canEdit)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('You can view this list.',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant)),
                        ),
                      const SizedBox(height: 8),
                      if (_items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text('Nothing on the list yet.',
                              style:
                                  TextStyle(color: scheme.onSurfaceVariant)),
                        ),
                      for (final i in _items)
                        _ItemRow(
                          item: i,
                          who: _who(i.claimedBy),
                          onTap: list.canEdit ? () => _itemActions(i) : null,
                        ),
                      if (list.canEdit) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _add,
                          focusNode: _addFocus,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _addItem(),
                          decoration: InputDecoration(
                            hintText: 'Add item (e.g. Telur x30)',
                            suffixIcon: IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: _addItem),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _Members extends StatelessWidget {
  const _Members({required this.owner, required this.access, required this.myId});
  final String owner;
  final List<ListAccessEntry> access;
  final String myId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final names = [
      owner,
      for (final a in access) a.friendId == myId ? 'You' : a.username,
    ];
    return Text(
      access.isEmpty ? 'Only you · tap Share to add family' : names.join(', '),
      style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.who, this.onTap});
  final ListItem item;
  final String who;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (item.status) {
      ItemStatus.open => ('Open', scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      ItemStatus.claimed => (
          who == 'You' ? "You're buying" : '$who buying',
          const Color(0xFFFFF3E0),
          const Color(0xFFB45309)
        ),
      _ => (
          who.isEmpty ? 'Bought' : '$who bought',
          const Color(0xFFE3F4EC),
          const Color(0xFF1F7A55)
        ),
    };
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: item.name),
                  if (item.quantity > 1)
                    TextSpan(
                        text: '  x${item.quantity}',
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ]),
                style: TextStyle(
                  fontSize: 15,
                  color: item.isDone ? scheme.onSurfaceVariant : null,
                  decoration: item.isDone ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}
