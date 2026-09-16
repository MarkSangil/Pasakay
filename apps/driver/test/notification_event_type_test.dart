import 'package:flutter_test/flutter_test.dart';

import 'package:pasakay_driver/core/utils/notification_event_type.dart';

void main() {
  group('NotificationEventType', () {
    test('dedupe keys are deterministic and unique per day/shift', () {
      final a = NotificationEventType.dedupeKey(
        eventType: NotificationEventType.shiftApproaching,
        recipientId: 'd1',
        driverId: 'd1',
        shiftId: 's1',
        dayYyyyMmDd: '2026-09-15',
      );
      final b = NotificationEventType.dedupeKey(
        eventType: NotificationEventType.shiftApproaching,
        recipientId: 'd1',
        driverId: 'd1',
        shiftId: 's1',
        dayYyyyMmDd: '2026-09-15',
      );
      final c = NotificationEventType.dedupeKey(
        eventType: NotificationEventType.shiftApproaching,
        recipientId: 'd1',
        driverId: 'd1',
        shiftId: 's1',
        dayYyyyMmDd: '2026-09-16',
      );
      expect(a, b);
      expect(a, isNot(c));
      expect(a, 'DRIVER_SHIFT_APPROACHING:d1:d1:s1:2026-09-15');
    });

    test('driver routes map schedule events to profile', () {
      expect(
        NotificationEventType.routeFor(
          eventType: NotificationEventType.shiftStarted,
          data: const {},
          isDriverApp: true,
        ),
        '/profile',
      );
      expect(
        NotificationEventType.routeFor(
          eventType: NotificationEventType.terminalUpdated,
          data: const {},
          isDriverApp: true,
        ),
        '/profile',
      );
    });

    test('followed driver routes open driver profile', () {
      expect(
        NotificationEventType.routeFor(
          eventType: NotificationEventType.followedAvailable,
          data: const {'driver_id': 'abc'},
          isDriverApp: false,
        ),
        '/driver/abc',
      );
    });

    test('explicit route in data wins', () {
      expect(
        NotificationEventType.routeFor(
          eventType: NotificationEventType.system,
          data: const {'route': '/notifications'},
          isDriverApp: true,
        ),
        '/notifications',
      );
    });

    test('new request and review deep links', () {
      expect(
        NotificationEventType.routeFor(
          eventType: NotificationEventType.newRequest,
          data: const {},
          isDriverApp: true,
        ),
        '/bookings',
      );
      expect(
        NotificationEventType.routeFor(
          eventType: NotificationEventType.newDriverReview,
          data: const {},
          isDriverApp: true,
        ),
        '/reviews',
      );
    });
  });
}
