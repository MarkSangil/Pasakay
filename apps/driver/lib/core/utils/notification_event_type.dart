/// Stable notification event type identifiers used by backend + clients.
abstract final class NotificationEventType {
  static const shiftApproaching = 'DRIVER_SHIFT_APPROACHING';
  static const shiftStarted = 'DRIVER_SHIFT_STARTED';
  static const shiftEnded = 'DRIVER_SHIFT_ENDED';
  static const scheduleUpdated = 'DRIVER_SCHEDULE_UPDATED';
  static const scheduleCancelled = 'DRIVER_SCHEDULE_CANCELLED';
  static const terminalUpdated = 'DRIVER_TERMINAL_UPDATED';
  static const availabilityUpdated = 'DRIVER_AVAILABILITY_UPDATED';
  static const followedAvailable = 'FOLLOWED_DRIVER_AVAILABLE';
  static const followedUnavailable = 'FOLLOWED_DRIVER_UNAVAILABLE';
  static const newRequest = 'NEW_REQUEST';
  static const newDriverReview = 'NEW_DRIVER_REVIEW';
  static const system = 'SYSTEM';

  static String routeFor({
    required String? eventType,
    required Map<String, dynamic> data,
    required bool isDriverApp,
  }) {
    final explicit = data['route']?.toString();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final driverId = data['driver_id']?.toString();
    switch (eventType) {
      case shiftApproaching:
      case shiftStarted:
      case shiftEnded:
      case scheduleUpdated:
      case scheduleCancelled:
      case availabilityUpdated:
        return isDriverApp ? '/profile' : '/terminals';
      case terminalUpdated:
        return isDriverApp ? '/profile' : '/terminals';
      case followedAvailable:
      case followedUnavailable:
        if (driverId != null && driverId.isNotEmpty) {
          return '/driver/$driverId';
        }
        return '/terminals';
      case newRequest:
        return '/bookings';
      case newDriverReview:
        return '/reviews';
      default:
        return isDriverApp ? '/notifications' : '/terminals';
    }
  }

  /// Deterministic dedupe key helper (mirrors SQL convention).
  static String dedupeKey({
    required String eventType,
    required String recipientId,
    String? driverId,
    String? shiftId,
    required String dayYyyyMmDd,
  }) {
    final parts = <String>[
      eventType,
      recipientId,
      if (driverId != null) driverId,
      if (shiftId != null) shiftId,
      dayYyyyMmDd,
    ];
    return parts.join(':');
  }
}
