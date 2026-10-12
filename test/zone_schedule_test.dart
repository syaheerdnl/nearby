import 'package:flutter_test/flutter_test.dart';
import 'package:nearby/core/constants.dart';
import 'package:nearby/core/place_category.dart';
import 'package:nearby/models/zone.dart';

int hm(int h, int m) => h * 60 + m;

Zone zone({bool onceOnly = false, int? from, int? to}) => Zone(
      id: 'z1',
      ownerId: 'u1',
      name: 'Home',
      latitude: 2.35,
      longitude: 102.1,
      radiusMeters: 150,
      triggerType: TriggerType.enter,
      category: PlaceCategory.home,
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 1),
      onceOnly: onceOnly,
      activeFrom: from,
      activeTo: to,
    );

void main() {
  group('Zone.minuteInWindow', () {
    test('daytime window 08:00-22:00', () {
      final f = hm(8, 0), t = hm(22, 0);
      expect(Zone.minuteInWindow(hm(7, 59), f, t), isFalse);
      expect(Zone.minuteInWindow(hm(8, 0), f, t), isTrue); // start included
      expect(Zone.minuteInWindow(hm(13, 30), f, t), isTrue);
      expect(Zone.minuteInWindow(hm(21, 59), f, t), isTrue);
      expect(Zone.minuteInWindow(hm(22, 0), f, t), isFalse); // end excluded
    });

    test('overnight window 22:00-06:00 wraps midnight', () {
      final f = hm(22, 0), t = hm(6, 0);
      expect(Zone.minuteInWindow(hm(23, 0), f, t), isTrue);
      expect(Zone.minuteInWindow(hm(0, 0), f, t), isTrue);
      expect(Zone.minuteInWindow(hm(5, 59), f, t), isTrue);
      expect(Zone.minuteInWindow(hm(6, 0), f, t), isFalse);
      expect(Zone.minuteInWindow(hm(12, 0), f, t), isFalse);
    });

    test('same start and end means all day', () {
      expect(Zone.minuteInWindow(hm(3, 0), hm(9, 0), hm(9, 0)), isTrue);
    });
  });

  group('Zone.isActiveAt', () {
    test('no window: always active', () {
      expect(zone().isActiveAt(DateTime(2026, 10, 12, 3, 0)), isTrue);
    });

    test('uses local hour and minute', () {
      final z = zone(from: hm(8, 0), to: hm(22, 0));
      expect(z.isActiveAt(DateTime(2026, 10, 12, 7, 30)), isFalse);
      expect(z.isActiveAt(DateTime(2026, 10, 12, 12, 0)), isTrue);
    });
  });

  group('Zone storage', () {
    test('local row round-trip keeps schedule', () {
      final z = zone(onceOnly: true, from: hm(22, 0), to: hm(6, 0));
      final back = Zone.fromLocal(z.toLocal(SyncStatus.synced));
      expect(back.onceOnly, isTrue);
      expect(back.activeFrom, hm(22, 0));
      expect(back.activeTo, hm(6, 0));
    });

    test('old local rows without the new columns still load', () {
      final row = zone().toLocal(SyncStatus.synced)
        ..remove('once_only')
        ..remove('active_from')
        ..remove('active_to');
      final back = Zone.fromLocal(row);
      expect(back.onceOnly, isFalse);
      expect(back.hasActiveWindow, isFalse);
    });

    test('remote row reads schedule; copyWith can clear the window', () {
      final remote = {
        ...zone().toRemote(),
        'updated_at': '2026-10-01T00:00:00Z',
        'once_only': true,
        'active_from': 480,
        'active_to': 1320,
      };
      final z = Zone.fromRemote(remote);
      expect(z.onceOnly, isTrue);
      expect(z.activeFrom, 480);
      expect(z.copyWith(clearActiveWindow: true).hasActiveWindow, isFalse);
    });
  });
}
