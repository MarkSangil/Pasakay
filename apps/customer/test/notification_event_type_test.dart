import 'package:flutter_test/flutter_test.dart';

import 'package:pasakay_customer/core/utils/notification_event_type.dart';

void main() {
  group('NotificationEventType (customer)', () {
    test('followed availability routes to driver profile', () {
      expect(
        NotificationEventType.routeFor(
          eventType: NotificationEventType.followedUnavailable,
          data: const {'driver_id': 'drv-1'},
        ),
        '/driver/drv-1',
      );
    });

    test('dedupe key includes all identity parts', () {
      final key = NotificationEventType.dedupeKey(
        eventType: NotificationEventType.followedAvailable,
        recipientId: 'c1',
        driverId: 'd1',
        shiftId: 's1',
        dayYyyyMmDd: '2026-09-15',
      );
      expect(key.split(':').length, 5);
      expect(key.startsWith('FOLLOWED_DRIVER_AVAILABLE:'), isTrue);
    });
  });
}
