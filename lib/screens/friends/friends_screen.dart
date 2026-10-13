import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../models/friend.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_provider.dart';

/// Find people by username, answer requests, see friends.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<ProfileHit> _hits = const [];
  bool _searching = false;
  int _searchId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<FriendProvider>().load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _hits = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final id = ++_searchId;
    setState(() => _searching = true);
    try {
      final hits = await context.read<FriendProvider>().search(q);
      if (!mounted || id != _searchId) return;
      setState(() => _hits = hits);
    } catch (_) {
      if (mounted && id == _searchId) setState(() => _hits = const []);
    } finally {
      if (mounted && id == _searchId) setState(() => _searching = false);
    }
  }

  void _toast(String? error, String ok) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error ?? ok)));
  }

  Future<void> _invite() async {
    final me = context.read<AuthProvider>().displayName ?? '';
    final text = 'Add me on Nearby so we can share errand lists. '
        'My username is @$me (Profile > Friends > search).';
    final uri = Uri.https('wa.me', '/', {'text': text});
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _toast('Could not open WhatsApp.', '');
  }

  Future<void> _confirmRemove(Friend f) async {
    final label = switch (f.state) {
      FriendState.accepted => 'Remove @${f.username} from friends?',
      FriendState.incoming => 'Decline @${f.username}?',
      FriendState.outgoing => 'Cancel your request to @${f.username}?',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<FriendProvider>().remove(f);
    if (mounted) _toast(err, 'Done.');
  }

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FriendProvider>();
    final scheme = Theme.of(context).colorScheme;
    final searching = _query.text.trim().length >= 2;

    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: RefreshIndicator(
        onRefresh: fp.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: [
            TextField(
              controller: _query,
              onChanged: _onQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Find by username',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            if (searching) ...[
              if (!_searching && _hits.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No one with that username.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              for (final h in _hits)
                _PersonCard(
                  username: h.username,
                  subtitle: switch (fp.stateOf(h.userId)) {
                    FriendState.accepted => 'Already friends',
                    FriendState.outgoing => 'Request sent',
                    FriendState.incoming => 'Wants to add you',
                    null => null,
                  },
                  action: fp.stateOf(h.userId) == null
                      ? _Pill(
                          label: 'Add',
                          onTap: () async {
                            final err = await fp.sendRequest(h.userId);
                            if (mounted) _toast(err, 'Request sent.');
                          })
                      : null,
                ),
            ] else ...[
              _InviteCard(onTap: _invite),
              if (fp.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child:
                      Text(fp.error!, style: TextStyle(color: scheme.error)),
                ),
              if (fp.incoming.isNotEmpty) ...[
                const _Label('Requests'),
                for (final f in fp.incoming)
                  _PersonCard(
                    username: f.username,
                    subtitle: 'Wants to add you',
                    onLongPress: () => _confirmRemove(f),
                    action: _Pill(
                        label: 'Accept',
                        onTap: () async {
                          final err = await fp.accept(f);
                          if (mounted) _toast(err, 'You are now friends.');
                        }),
                  ),
              ],
              const _Label('Your friends'),
              if (fp.friends.isEmpty && !fp.loading)
                Text('No friends yet. Search a username above, or invite '
                    'someone on WhatsApp.',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              for (final f in fp.friends)
                _PersonCard(
                  username: f.username,
                  onLongPress: () => _confirmRemove(f),
                ),
              for (final f in fp.outgoing)
                _PersonCard(
                  username: f.username,
                  subtitle: 'Request sent',
                  faded: true,
                  onLongPress: () => _confirmRemove(f),
                ),
              if (fp.friends.isNotEmpty || fp.outgoing.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Long-press someone to remove them.',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      );
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF1F7A55);
    return Material(
      color: const Color(0xFFE7F7EE),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Row(children: [
            Icon(Icons.chat_outlined, color: green),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card is light in both themes, so the title needs a
                  // fixed dark colour (the theme default turns white in dark mode).
                  Text('Invite on WhatsApp',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: AppTheme.ink)),
                  Text('Sends your username so they can add you',
                      style: TextStyle(fontSize: 12, color: green)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: const StadiumBorder(),
        ),
        onPressed: onTap,
        child: Text(label),
      );
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.username,
    this.subtitle,
    this.action,
    this.faded = false,
    this.onLongPress,
  });

  final String username;
  final String? subtitle;
  final Widget? action;
  final bool faded;
  final VoidCallback? onLongPress;

  static const _colors = [
    Color(0xFF3D3AA8),
    Color(0xFF0F766E),
    Color(0xFFB45309),
    Color(0xFF7C3AED),
    Color(0xFFC2410C),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _colors[username.hashCode.abs() % _colors.length];
    return Opacity(
      opacity: faded ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  child: Text(username.substring(0, 1).toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('@$username',
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (action != null) action!,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
