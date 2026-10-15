import 'list_item.dart';
import 'payment_record.dart';
import 'receipt.dart';

/// An item someone bought, with the receipt still waiting to be paid.
typedef OwedEntry = ({ListItem item, Receipt receipt});

/// Unpaid receipts between me and one other person on a list.
class OwedGroup {
  const OwedGroup({required this.personId, required this.entries});

  /// The other person: the buyer when I own the list, the owner when I don't.
  final String personId;
  final List<OwedEntry> entries;

  /// Whole sen, so adding receipts never drifts (see [Receipt.amountSen]).
  int get totalSen => entries.fold(0, (sum, e) => sum + e.receipt.amountSen);
}

/// Who owes whom on one list. Only receipts that aren't paid count; items
/// without a receipt have no amount yet, so they don't count either.
///
/// As the owner ([iOwn]): one group per friend I owe, largest first.
/// As a friend: at most one group, what the owner ([ownerId]) owes me.
List<OwedGroup> owedByPerson({
  required List<ListItem> items,
  required Map<String, Receipt> receipts,
  required Map<String, PaymentRecord> payments,
  required String me,
  required bool iOwn,
  required String ownerId,
}) {
  final byPerson = <String, List<OwedEntry>>{};
  for (final item in items) {
    final r = receipts[item.id];
    if (r == null) continue;
    final paid =
        payments.containsKey(r.id) || item.status == ItemStatus.settled;
    if (paid) continue;
    if (iOwn) {
      if (r.uploadedBy == me) continue; // I bought it myself: nobody owes.
      byPerson.putIfAbsent(r.uploadedBy, () => []).add((
        item: item,
        receipt: r,
      ));
    } else if (r.uploadedBy == me) {
      byPerson.putIfAbsent(ownerId, () => []).add((item: item, receipt: r));
    }
  }
  final groups = [
    for (final e in byPerson.entries)
      OwedGroup(personId: e.key, entries: e.value),
  ];
  groups.sort((a, b) => b.totalSen.compareTo(a.totalSen));
  return groups;
}
