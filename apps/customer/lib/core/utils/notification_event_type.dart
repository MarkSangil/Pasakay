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
  static const requestAccepted = 'REQUEST_ACCEPTED';
  static const requestRejected = 'REQUEST_REJECTED';
  static const requestExpired = 'REQUEST_EXPIRED';
  static const bookingConfirmed = 'BOOKING_CONFIRMED';
  static const bookingFlagged = 'BOOKING_FLAGGED';
  static const reviewAvailable = 'REVIEW_AVAILABLE';
  static const newDriverReview = 'NEW_DRIVER_REVIEW';
  static const system = 'SYSTEM';

  static String routeFor({
    required String? eventType,
    required Map<String, dynamic> data,
  }) {
    final explicit = data['route']?.toString();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final driverId = data['driver_id']?.toString();
    final bookingId = data['booking_id']?.toString();
    switch (eventType) {
      case followedAvailable:
      case followedUnavailable:
        if (driverId != null && driverId.isNotEmpty) {
          return '/driver/$driverId';
        }
        return '/terminals';
      case requestAccepted:
      case bookingConfirmed:
      case requestRejected:
      case requestExpired:
      case bookingFlagged:
        return '/history';
      case reviewAvailable:
        if (bookingId != null && bookingId.isNotEmpty) {
          return '/review?bookingId=$bookingId';
        }
        return '/history';
      default:
        return '/notifications';
    }
  }

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
