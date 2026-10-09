import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/core/constants.dart';

void main() {
  test('trigger types round-trip through their database names', () {
    for (final t in TriggerType.values) {
      expect(TriggerType.fromName(t.name), t);
    }
  });

  test('sync status reads its stored value', () {
    for (final s in SyncStatus.values) {
      expect(SyncStatus.fromValue(s.value), s);
    }
    expect(SyncStatus.fromValue(null), SyncStatus.pendingUpsert);
  });
}
