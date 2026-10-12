/// One row of `public.friends`, seen from the signed-in user's side.
enum FriendState { accepted, incoming, outgoing }

class Friend {
  const Friend({
    required this.rowId,
    required this.userId,
    required this.username,
    required this.state,
  });

  /// `friends.id` (used to accept / remove).
  final String rowId;

  /// The other person's user id.
  final String userId;
  final String username;
  final FriendState state;

  /// Builds from a `friends` row. [me] is the signed-in user; [names] maps
  /// user id -> username from `profiles`.
  static Friend? fromRow(
      Map<String, dynamic> row, String me, Map<String, String> names) {
    final a = row['user_id'] as String?;
    final b = row['friend_id'] as String?;
    final by = row['requested_by'] as String?;
    if (a == null || b == null || by == null) return null;
    if (a != me && b != me) return null;
    final other = a == me ? b : a;
    final state = row['status'] == 'accepted'
        ? FriendState.accepted
        : (by == me ? FriendState.outgoing : FriendState.incoming);
    return Friend(
      rowId: row['id'] as String,
      userId: other,
      username: names[other] ?? 'unknown',
      state: state,
    );
  }
}

/// A search hit from `profiles`.
class ProfileHit {
  const ProfileHit({required this.userId, required this.username});
  final String userId;
  final String username;
}
