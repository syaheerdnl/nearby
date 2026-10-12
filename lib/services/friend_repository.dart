import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_client.dart';
import '../models/friend.dart';

/// Friends live only on the server (no offline copy): you need a connection
/// to find someone anyway. Row-level security limits every query to rows the
/// signed-in user is part of.
class FriendRepository {
  String get _me {
    final id = supabase.auth.currentUser?.id;
    if (id == null) throw const FriendException('Not signed in.');
    return id;
  }

  Future<List<Friend>> list() async {
    final me = _me;
    final rows = await supabase
        .from('friends')
        .select('id, user_id, friend_id, requested_by, status')
        .or('user_id.eq.$me,friend_id.eq.$me');
    final others = <String>{
      for (final r in rows)
        (r['user_id'] == me ? r['friend_id'] : r['user_id']) as String,
    };
    final names = <String, String>{};
    if (others.isNotEmpty) {
      final profiles = await supabase
          .from('profiles')
          .select('id, username')
          .inFilter('id', others.toList());
      for (final p in profiles) {
        names[p['id'] as String] = p['username'] as String;
      }
    }
    final out = [
      for (final r in rows) Friend.fromRow(r, me, names),
    ].whereType<Friend>().toList()
      ..sort((x, y) => x.username.compareTo(y.username));
    return out;
  }

  /// Usernames containing [query] (min 2 chars), excluding yourself.
  Future<List<ProfileHit>> search(String query) async {
    final q = query.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (q.length < 2) return const [];
    final rows = await supabase
        .from('profiles')
        .select('id, username')
        .ilike('username', '%$q%')
        .neq('id', _me)
        .order('username')
        .limit(10);
    return [
      for (final r in rows)
        ProfileHit(userId: r['id'] as String, username: r['username'] as String),
    ];
  }

  Future<void> sendRequest(String otherUserId) async {
    final me = _me;
    try {
      await supabase.from('friends').insert({
        'user_id': me,
        'friend_id': otherUserId,
        'requested_by': me,
      });
    } on PostgrestException catch (e) {
      // friends_pair_uidx: a row for this pair already exists.
      if (e.code == '23505') {
        throw const FriendException('You already have a request with them.');
      }
      rethrow;
    }
  }

  Future<void> accept(String rowId) =>
      supabase.from('friends').update({'status': 'accepted'}).eq('id', rowId);

  /// Decline, cancel or unfriend.
  Future<void> remove(String rowId) =>
      supabase.from('friends').delete().eq('id', rowId);
}

class FriendException implements Exception {
  const FriendException(this.message);
  final String message;
  @override
  String toString() => message;
}
