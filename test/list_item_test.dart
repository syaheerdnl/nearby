import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/models/list_item.dart';
import 'package:nearby/models/shared_list.dart';

ListItem item(ItemStatus s, {String? claimedBy, String name = 'Beras'}) =>
    ListItem(
      id: 'i1',
      listId: 'l1',
      name: name,
      quantity: 1,
      status: s,
      claimedBy: claimedBy,
      createdBy: 'owner',
    );

void main() {
  const me = 'aina', other = 'mak';

  group('ListItem.transition', () {
    test('claim only from open, and records who', () {
      expect(ListItem.transition(item(ItemStatus.open), ItemAction.claim, me),
          {'status': 'claimed', 'claimed_by': me});
      expect(
          ListItem.transition(
              item(ItemStatus.claimed, claimedBy: other), ItemAction.claim, me),
          isNull);
    });

    test("unclaim only your own claim", () {
      expect(
          ListItem.transition(
              item(ItemStatus.claimed, claimedBy: me), ItemAction.unclaim, me),
          {'status': 'open', 'claimed_by': null});
      expect(
          ListItem.transition(item(ItemStatus.claimed, claimedBy: other),
              ItemAction.unclaim, me),
          isNull);
    });

    test('bought keeps the claimer, or credits you if unclaimed', () {
      expect(
          ListItem.transition(item(ItemStatus.claimed, claimedBy: other),
              ItemAction.bought, me),
          {'status': 'bought', 'claimed_by': other});
      expect(ListItem.transition(item(ItemStatus.open), ItemAction.bought, me),
          {'status': 'bought', 'claimed_by': me});
      expect(
          ListItem.transition(item(ItemStatus.bought, claimedBy: other),
              ItemAction.bought, me),
          isNull);
    });

    test('reopen clears the claim; no-op when already open', () {
      expect(
          ListItem.transition(item(ItemStatus.bought, claimedBy: other),
              ItemAction.reopen, me),
          {'status': 'open', 'claimed_by': null});
      expect(ListItem.transition(item(ItemStatus.open), ItemAction.reopen, me),
          isNull);
    });
  });

  test('sortItems: open, then claimed, then bought; A-Z inside', () {
    final sorted = sortItems([
      item(ItemStatus.bought, name: 'Gula'),
      item(ItemStatus.open, name: 'Telur'),
      item(ItemStatus.claimed, name: 'Minyak'),
      item(ItemStatus.open, name: 'beras'),
    ]);
    expect(sorted.map((i) => i.name), ['beras', 'Telur', 'Minyak', 'Gula']);
  });

  test('SharedPlace local row round-trip keeps open items', () {
    const p = SharedPlace(
      zoneId: 'z',
      listId: 'l',
      listTitle: 'Barang dapur',
      ownerName: 'syaheerdnl',
      name: 'Mydin',
      latitude: 2.35,
      longitude: 102.1,
      radiusMeters: 200,
      openItems: ['Beras 5kg', 'Telur x30'],
    );
    final back = SharedPlace.fromLocal(p.toLocal());
    expect(back.openItems, ['Beras 5kg', 'Telur x30']);
    expect(back.radiusMeters, 200);
  });
}
