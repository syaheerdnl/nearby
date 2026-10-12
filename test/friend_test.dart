import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/models/friend.dart';

void main() {
  const me = 'me', other = 'aina';
  const names = {'aina': 'aina_adik'};

  Map<String, dynamic> row(String a, String b, String by, String status) =>
      {'id': 'r1', 'user_id': a, 'friend_id': b, 'requested_by': by, 'status': status};

  test('accepted friendship either way round', () {
    final f1 = Friend.fromRow(row(me, other, me, 'accepted'), me, names)!;
    final f2 = Friend.fromRow(row(other, me, other, 'accepted'), me, names)!;
    expect(f1.state, FriendState.accepted);
    expect(f2.state, FriendState.accepted);
    expect(f1.userId, other);
    expect(f2.userId, other);
    expect(f1.username, 'aina_adik');
  });

  test('pending: who asked decides incoming vs outgoing', () {
    expect(Friend.fromRow(row(me, other, me, 'pending'), me, names)!.state,
        FriendState.outgoing);
    expect(Friend.fromRow(row(other, me, other, 'pending'), me, names)!.state,
        FriendState.incoming);
  });

  test('rows not involving me are ignored', () {
    expect(Friend.fromRow(row('x', 'y', 'x', 'pending'), me, names), isNull);
  });
}
