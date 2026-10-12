import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/list_access.dart';
import '../../models/shared_list.dart';
import '../../providers/friend_provider.dart';
import '../../services/list_repository.dart';
import '../friends/friends_screen.dart';

/// Owner picks which friends see the list and what they can do.
/// Changes save straight away (no Save button to forget).
class ShareListScreen extends StatefulWidget {
  const ShareListScreen({super.key, required this.list});
  final SharedList list;

  @override
  State<ShareListScreen> createState() => _ShareListScreenState();
}

class _ShareListScreenState extends State<ShareListScreen> {
  final _repo = ListRepository();
  Map<String, ListPermission> _perm = {};
  final Set<String> _saving = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // FriendProvider.load notifies listeners: not during the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final friends = context.read<FriendProvider>();
    try {
      await friends.load();
      final access = await _repo.access(widget.list.id);
      if (!mounted) return;
      setState(() =>
          _perm = {for (final a in access) a.friendId: a.permission});
    } catch (e) {
      debugPrint('Load sharing failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(String friendId, ListPermission? p) async {
    final before = _perm[friendId];
    setState(() {
      _saving.add(friendId);
      if (p == null) {
        _perm.remove(friendId);
      } else {
        _perm[friendId] = p;
      }
    });
    try {
      await _repo.setAccess(widget.list.id, friendId, p);
    } catch (e) {
      debugPrint('Set access failed: $e');
      if (!mounted) return;
      setState(() {
        if (before == null) {
          _perm.remove(friendId);
        } else {
          _perm[friendId] = before;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't change sharing. Check your connection.")));
    } finally {
      if (mounted) setState(() => _saving.remove(friendId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final friends = context.watch<FriendProvider>().friends;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Share list')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              children: [
                Text(
                  'People who can buy also get the alert when they reach '
                  '${widget.list.zoneName}.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                if (friends.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add friends first, then share with them.',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const FriendsScreen())),
                          child: const Text('Find friends'),
                        ),
                      ],
                    ),
                  ),
                for (final f in friends)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('@${f.username}',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                        if (_saving.contains(f.userId))
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox.square(
                                dimension: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        SegmentedButton<int>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                              visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(value: 0, label: Text('Off')),
                            ButtonSegment(value: 1, label: Text('View')),
                            ButtonSegment(value: 2, label: Text('Can buy')),
                          ],
                          selected: {
                            switch (_perm[f.userId]) {
                              null => 0,
                              ListPermission.view => 1,
                              ListPermission.claim => 2,
                            }
                          },
                          onSelectionChanged: (s) => _set(
                            f.userId,
                            switch (s.first) {
                              1 => ListPermission.view,
                              2 => ListPermission.claim,
                              _ => null,
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Text('View: see items and who is buying.\n'
                    'Can buy: also add items, claim and mark bought, and get '
                    'the arrival alert.',
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ],
            ),
    );
  }
}
