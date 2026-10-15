import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/list_access.dart';
import '../../models/list_item.dart';
import '../../models/owed.dart';
import '../../models/payment_record.dart';
import '../../models/receipt.dart';
import '../../models/shared_list.dart';
import '../../providers/zone_provider.dart';
import '../../services/list_repository.dart';
import '../../services/settlement_repository.dart';
import '../settlement/payment_confirm_screen.dart';
import '../settlement/receipt_upload_screen.dart';
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
  final _settle = SettlementRepository();
  final _add = TextEditingController();
  final _addFocus = FocusNode();

  SharedList? _list;
  List<ListItem> _items = const [];
  List<ListAccessEntry> _access = const [];
  Map<String, String> _names = {};
  // Receipts by item id, payments by receipt id (Phase 3).
  Map<String, Receipt> _receipts = const {};
  Map<String, PaymentRecord> _payments = const {};
  String? _error;
  bool _loading = true;
  RealtimeChannel? _channel;
  Timer? _reloadSoon;
  ZoneProvider? _zones;

  @override
  void initState() {
    super.initState();
    _zones = context.read<ZoneProvider>();
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
    // Items may have changed here: refresh the cached copy that the map
    // badge and the arrival alert read from.
    _zones?.refreshShared();
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
      // Receipts are optional extras: a failure here must not hide the list.
      var receipts = _receipts;
      var payments = _payments;
      try {
        receipts =
            await _settle.receiptsFor(items.where((i) => i.isDone).map((i) => i.id));
        payments =
            await _settle.paymentsFor(receipts.values.map((r) => r.id));
      } catch (e) {
        debugPrint('Load receipts failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _names = {..._names, ...names};
        _receipts = receipts;
        _payments = payments;
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

  /// Receipt screens push a route; reload when they report a change.
  Future<void> _open(Widget screen) async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => screen));
    if (changed == true) await _loadItems();
  }

  /// Display name for someone on this list (the owner's name comes with
  /// the list, everyone else's from the items).
  String _nameOf(String id) {
    final list = _list;
    if (list != null && id == list.ownerId) {
      return id == _repo.me ? 'You' : list.ownerName;
    }
    return _who(id);
  }

  void _payAll(OwedGroup g) => _open(PaymentConfirmScreen(
        entries: g.entries,
        buyerName: _nameOf(g.personId),
        canPay: true,
      ));

  void _itemActions(ListItem item) {
    final list = _list;
    if (list == null) return;
    final me = _repo.me;
    final receipt = _receipts[item.id];
    final paid = receipt == null ? null : _payments[receipt.id];
    final buyer = _who(receipt?.uploadedBy ?? item.claimedBy);
    // The owner buying their own item needs no receipt: nobody owes anybody.
    final iBoughtForSomeone = item.status == ItemStatus.bought &&
        item.claimedBy == me &&
        !list.iOwn;
    final canPay = receipt != null &&
        paid == null &&
        list.iOwn &&
        receipt.uploadedBy != me;
    final receiptActions = <_Action>[
      if (iBoughtForSomeone && paid == null)
        _Action.open(
          Icons.receipt_long_outlined,
          receipt == null ? 'Add receipt' : 'Edit receipt',
          () => _open(ReceiptUploadScreen(item: item, existing: receipt)),
        ),
      if (receipt != null)
        _Action.open(
          canPay ? Icons.payments_outlined : Icons.receipt_outlined,
          canPay ? 'Pay $buyer' : 'View receipt',
          () => _open(PaymentConfirmScreen(
                entries: [(item: item, receipt: receipt)],
                buyerName: buyer,
                canPay: canPay,
                payment: paid,
              )),
        ),
    ];
    if (!list.canEdit && receiptActions.isEmpty) return;
    final settled = item.status == ItemStatus.settled;
    final actions = <_Action>[
      ...receiptActions,
      if (list.canEdit && !settled) ...[
      if (item.status == ItemStatus.open)
        _Action(Icons.front_hand_outlined, "I'll buy this",
            () => _repo.apply(item, ItemAction.claim)),
      if (item.status == ItemStatus.claimed && item.claimedBy == me)
        _Action(Icons.undo, "I can't buy it after all",
            () => _repo.apply(item, ItemAction.unclaim)),
      if (!item.isDone)
        _Action(Icons.check_circle_outline, 'Bought',
            () => _repo.apply(item, ItemAction.bought)),
      // Skip when "I can't buy it after all" is shown: same result. Not once
      // a receipt is in: put the receipt right instead of reopening.
      if (item.status != ItemStatus.open &&
          receipt == null &&
          !(item.status == ItemStatus.claimed && item.claimedBy == me))
        _Action(Icons.replay, 'Put back on the list',
            () => _repo.apply(item, ItemAction.reopen)),
      if (list.iOwn || item.createdBy == me)
        _Action(Icons.delete_outline, 'Delete', () => _repo.deleteItem(item.id)),
      ],
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
            for (final a in actions)
              ListTile(
                leading: Icon(a.icon),
                title: Text(a.label),
                onTap: () {
                  Navigator.pop(ctx);
                  // Opening a screen isn't a save: no error snackbar for it.
                  a.opensScreen ? a.run() : _run(a.run);
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
    // Open + claimed: everything still to buy (the map badge counts open only).
    final toBuy = _items.where((i) => !i.isDone).length;

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
                          '$toBuy to buy',
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
                      _OwedCard(
                        groups: owedByPerson(
                          items: _items,
                          receipts: _receipts,
                          payments: _payments,
                          me: _repo.me,
                          iOwn: list.iOwn,
                          ownerId: list.ownerId,
                        ),
                        iOwn: list.iOwn,
                        nameOf: _nameOf,
                        onPay: _payAll,
                      ),
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
                          receipt: _receipts[i.id],
                          payToMe: list.iOwn &&
                              _receipts[i.id] != null &&
                              _receipts[i.id]!.uploadedBy != _repo.me &&
                              i.status != ItemStatus.settled,
                          onTap: list.canEdit || _receipts[i.id] != null
                              ? () => _itemActions(i)
                              : null,
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

/// One entry in an item's action sheet.
class _Action {
  const _Action(this.icon, this.label, this.run) : opensScreen = false;
  const _Action.open(this.icon, this.label, this.run) : opensScreen = true;
  final IconData icon;
  final String label;
  final Future<void> Function() run;

  /// Navigates to another screen instead of saving a change.
  final bool opensScreen;
}

/// Money still to settle on this list. As the owner: one row per friend you
/// owe, each with Pay / Pay all. As a friend: what the owner owes you.
/// Hidden when nothing is owed.
class _OwedCard extends StatelessWidget {
  const _OwedCard({
    required this.groups,
    required this.iOwn,
    required this.nameOf,
    required this.onPay,
  });
  final List<OwedGroup> groups;
  final bool iOwn;
  final String Function(String id) nameOf;
  final void Function(OwedGroup g) onPay;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    String items(int n) => n == 1 ? '1 item' : '$n items';
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (iOwn)
            Text('You owe',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant)),
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          iOwn
                              ? nameOf(g.personId)
                              : '${nameOf(g.personId)} owes you',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          iOwn
                              ? items(g.entries.length)
                              : '${items(g.entries.length)} · waiting for '
                                  'them to pay',
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Text(formatSen(g.totalSen),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  if (iOwn) ...[
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: () => onPay(g),
                      child: Text(g.entries.length == 1 ? 'Pay' : 'Pay all'),
                    ),
                  ] else
                    const SizedBox(width: 6),
                ],
              ),
            ),
        ],
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
  const _ItemRow({
    required this.item,
    required this.who,
    this.receipt,
    this.payToMe = false,
    this.onTap,
  });
  final ListItem item;
  final String who;
  final Receipt? receipt;

  /// I own the list and this receipt still needs paying.
  final bool payToMe;
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
      ItemStatus.bought => (
          who.isEmpty ? 'Bought' : '$who bought',
          const Color(0xFFE3F4EC),
          const Color(0xFF1F7A55)
        ),
      ItemStatus.settled => (
          'Paid',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant
        ),
    };
    final r = receipt;
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: item.name),
                      if (item.quantity > 1)
                        TextSpan(
                            text: '  x${item.quantity}',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant)),
                    ]),
                    style: TextStyle(
                      fontSize: 15,
                      color: item.isDone ? scheme.onSurfaceVariant : null,
                      decoration:
                          item.isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (r != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 14,
                              color: payToMe
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            payToMe
                                ? '${formatSen(r.amountSen)} · tap to pay'
                                : formatSen(r.amountSen),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight:
                                  payToMe ? FontWeight.w600 : FontWeight.w400,
                              color: payToMe
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
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
