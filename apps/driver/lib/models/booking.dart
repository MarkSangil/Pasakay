/// Dispute window after confirmation (fallback; server setting is authoritative).
const Duration kBookingDisputeWindow = Duration(minutes: 60);

int? _disputeWindowMinutesOverride;

/// Apply admin-configured dispute window to client countdowns.
void setDisputeWindowMinutes(int minutes) {
  if (minutes < 1) return;
  _disputeWindowMinutesOverride = minutes;
}

Duration get effectiveDisputeWindow {
  final mins = _disputeWindowMinutesOverride;
  if (mins == null) return kBookingDisputeWindow;
  return Duration(minutes: mins);
}

enum RideRequestStatus { pending, accepted, rejected, expired, cancelled }

extension RideRequestStatusX on RideRequestStatus {
  String get dbValue => name.toUpperCase();

  String get label => switch (this) {
        RideRequestStatus.pending => 'Pending',
        RideRequestStatus.accepted => 'Accepted',
        RideRequestStatus.rejected => 'Rejected',
        RideRequestStatus.expired => 'Expired',
        RideRequestStatus.cancelled => 'Cancelled',
      };

  static RideRequestStatus fromDb(String value) {
    return RideRequestStatus.values.firstWhere(
      (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => RideRequestStatus.pending,
    );
  }
}

class RideRequest {
  const RideRequest({
    required this.id,
    required this.commuterId,
    required this.driverId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.respondedAt,
    this.commuterName,
    this.commuterMobile,
  });

  final String id;
  final String commuterId;
  final String driverId;
  final RideRequestStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? respondedAt;
  final String? commuterName;
  final String? commuterMobile;

  String get displayName =>
      (commuterName == null || commuterName!.trim().isEmpty)
          ? 'Passenger'
          : commuterName!;

  bool get isPending => status == RideRequestStatus.pending;

  factory RideRequest.fromJson(Map<String, dynamic> json) {
    String? name;
    final commuter = json['commuter'];
    if (commuter is Map) {
      name = commuter['full_name'] as String?;
    }
    name ??= json['passenger_name'] as String?;
    return RideRequest(
      id: (json['request_id'] ?? json['id']) as String,
      commuterId: json['commuter_id'] as String,
      driverId: json['driver_id'] as String,
      status: RideRequestStatusX.fromDb(json['status'] as String? ?? 'PENDING'),
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      respondedAt: json['responded_at'] != null
          ? DateTime.parse(json['responded_at'] as String)
          : null,
      commuterName: name,
      // Contact only during accepted BOOKED bookings — never on pending requests.
      commuterMobile: null,
    );
  }
}

enum BookingStatus { booked, flagged, completed, cancelled }

extension BookingStatusX on BookingStatus {
  String get dbValue => name.toUpperCase();

  String get label => switch (this) {
        BookingStatus.booked => 'Booked',
        BookingStatus.flagged => 'Flagged',
        BookingStatus.completed => 'Completed',
        BookingStatus.cancelled => 'Cancelled',
      };

  String get badgeLabel => switch (this) {
        BookingStatus.booked => 'Confirmed Booking',
        BookingStatus.flagged => 'Disputed',
        BookingStatus.completed => 'Completed',
        BookingStatus.cancelled => 'Cancelled',
      };

  static BookingStatus fromDb(String value) {
    return BookingStatus.values.firstWhere(
      (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => BookingStatus.booked,
    );
  }
}

/// Flag reasons offered in the driver UI (server stores free text).
abstract final class BookingFlagReasons {
  static const notMyPassenger = 'Not my passenger';
  static const wrongDriver = 'Passenger selected the wrong driver';
  static const didNotAgree = 'I did not agree to this booking';
  static const other = 'Other';

  static const all = [notMyPassenger, wrongDriver, didNotAgree, other];
}

class Booking {
  const Booking({
    required this.id,
    required this.requestId,
    required this.commuterId,
    required this.driverId,
    required this.status,
    required this.confirmedAt,
    required this.reviewEligibleAt,
    this.completedAt,
    this.cancelledAt,
    this.flaggedAt,
    this.flagReason,
    this.flagDetails,
    this.reviewedAt,
    this.commuterName,
    this.commuterMobile,
  });

  final String id;
  final String requestId;
  final String commuterId;
  final String driverId;
  final BookingStatus status;
  final DateTime confirmedAt;
  final DateTime reviewEligibleAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final DateTime? flaggedAt;
  final String? flagReason;
  final String? flagDetails;
  final DateTime? reviewedAt;
  final String? commuterName;
  final String? commuterMobile;

  String get displayName =>
      (commuterName == null || commuterName!.trim().isEmpty)
          ? 'Passenger'
          : commuterName!;

  DateTime get disputeDeadline => confirmedAt.add(effectiveDisputeWindow);

  bool get canFlag {
    if (status != BookingStatus.booked) return false;
    return DateTime.now().toUtc().isBefore(disputeDeadline.toUtc());
  }

  Duration? get disputeRemaining {
    if (!canFlag) return null;
    final left = disputeDeadline.toUtc().difference(DateTime.now().toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  bool get canComplete => status == BookingStatus.booked;

  bool canFlagAt(DateTime now, {int? disputeMinutes}) {
    final mins = disputeMinutes ??
        _disputeWindowMinutesOverride ??
        kBookingDisputeWindow.inMinutes;
    return status == BookingStatus.booked &&
        now.isBefore(confirmedAt.add(Duration(minutes: mins)));
  }

  factory Booking.fromJson(Map<String, dynamic> json) {
    String? name;
    String? mobile;
    final status = BookingStatusX.fromDb(json['status'] as String? ?? 'BOOKED');
    final commuter = json['commuter'];
    if (commuter is Map) {
      name = commuter['full_name'] as String?;
      // Contact numbers are only visible while the booking is accepted (BOOKED).
      if (status == BookingStatus.booked) {
        mobile =
            (commuter['contact_number'] ?? commuter['mobile_number']) as String?;
      }
    }
    name ??= json['passenger_name'] as String?;
    return Booking(
      id: (json['booking_id'] ?? json['id']) as String,
      requestId: json['request_id'] as String,
      commuterId: json['commuter_id'] as String,
      driverId: json['driver_id'] as String,
      status: status,
      confirmedAt: DateTime.parse(json['confirmed_at'] as String),
      reviewEligibleAt: DateTime.parse(json['review_eligible_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'] as String)
          : null,
      flaggedAt: json['flagged_at'] != null
          ? DateTime.parse(json['flagged_at'] as String)
          : null,
      flagReason: json['flag_reason'] as String?,
      flagDetails: json['flag_details'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      commuterName: name,
      commuterMobile: mobile,
    );
  }
}
