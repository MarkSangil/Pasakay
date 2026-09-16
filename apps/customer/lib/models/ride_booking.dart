class RideRequest {
  const RideRequest({
    required this.id,
    required this.commuterId,
    required this.driverId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.respondedAt,
    this.driverName,
    this.commuterName,
  });

  final String id;
  final String commuterId;
  final String driverId;
  final String status; // PENDING|ACCEPTED|REJECTED|EXPIRED|CANCELLED
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? respondedAt;
  final String? driverName;
  final String? commuterName;

  factory RideRequest.fromJson(Map<String, dynamic> json) {
    String? driverName;
    String? commuterName;
    final driver = json['driver'];
    final commuter = json['commuter'];
    if (driver is Map) driverName = driver['full_name'] as String?;
    if (commuter is Map) commuterName = commuter['full_name'] as String?;
    return RideRequest(
      id: (json['request_id'] ?? json['id']) as String,
      commuterId: json['commuter_id'] as String,
      driverId: json['driver_id'] as String,
      status: json['status'] as String? ?? 'PENDING',
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      respondedAt: json['responded_at'] != null
          ? DateTime.parse(json['responded_at'] as String)
          : null,
      driverName: driverName,
      commuterName: commuterName,
    );
  }
}

class BookingRecord {
  const BookingRecord({
    required this.id,
    required this.requestId,
    required this.commuterId,
    required this.driverId,
    required this.status,
    required this.confirmedAt,
    required this.reviewEligibleAt,
    this.completedAt,
    this.flaggedAt,
    this.flagReason,
    this.reviewedAt,
    this.passengerReportedAt,
    this.driverName,
    this.commuterName,
  });

  final String id;
  final String requestId;
  final String commuterId;
  final String driverId;
  final String status; // BOOKED|FLAGGED|COMPLETED|CANCELLED
  final DateTime confirmedAt;
  final DateTime reviewEligibleAt;
  final DateTime? completedAt;
  final DateTime? flaggedAt;
  final String? flagReason;
  final DateTime? reviewedAt;
  final DateTime? passengerReportedAt;
  final String? driverName;
  final String? commuterName;

  bool reviewAvailable(DateTime serverNow) {
    // One action after finish: review only if not reviewed and not reported.
    return status == 'COMPLETED' &&
        reviewedAt == null &&
        passengerReportedAt == null;
  }

  bool get canReportRider =>
      status == 'COMPLETED' &&
      passengerReportedAt == null &&
      reviewedAt == null;

  String displayLabel(DateTime serverNow) {
    if (passengerReportedAt != null) return 'Reported';
    if (status == 'FLAGGED') return 'Booking Disputed';
    if (status == 'CANCELLED') return 'Cancelled';
    if (status == 'BOOKED') return 'Booking Confirmed';
    if (status == 'COMPLETED') {
      if (reviewedAt != null) return 'Reviewed';
      return 'Review Available';
    }
    return status;
  }

  factory BookingRecord.fromJson(Map<String, dynamic> json) {
    String? driverName;
    String? commuterName;
    final driver = json['driver'];
    final commuter = json['commuter'];
    if (driver is Map) driverName = driver['full_name'] as String?;
    if (commuter is Map) commuterName = commuter['full_name'] as String?;
    return BookingRecord(
      id: (json['booking_id'] ?? json['id']) as String,
      requestId: json['request_id'] as String,
      commuterId: json['commuter_id'] as String,
      driverId: json['driver_id'] as String,
      status: json['status'] as String? ?? 'BOOKED',
      confirmedAt: DateTime.parse(json['confirmed_at'] as String),
      reviewEligibleAt: DateTime.parse(json['review_eligible_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      flaggedAt: json['flagged_at'] != null
          ? DateTime.parse(json['flagged_at'] as String)
          : null,
      flagReason: json['flag_reason'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      passengerReportedAt: json['passenger_reported_at'] != null
          ? DateTime.parse(json['passenger_reported_at'] as String)
          : null,
      driverName: driverName,
      commuterName: commuterName ?? json['passenger_name'] as String?,
    );
  }
}

class DriverRequestContext {
  const DriverRequestContext({
    required this.onShift,
    required this.canRequest,
    required this.callSmsEnabled,
    required this.canReport,
    required this.canReview,
    required this.serverNow,
    this.reason,
    this.request,
    this.booking,
    this.peerContact,
    this.reportableBookingId,
    this.reviewableBookingId,
  });

  final bool onShift;
  final bool canRequest;
  final bool callSmsEnabled;
  final bool canReport;
  final bool canReview;
  final DateTime serverNow;
  final String? reason;
  final RideRequest? request;
  final BookingRecord? booking;
  final String? peerContact;
  final String? reportableBookingId;
  final String? reviewableBookingId;

  bool get alreadyReviewed =>
      booking?.status == 'COMPLETED' && booking?.reviewedAt != null;

  bool get alreadyReported => booking?.passengerReportedAt != null;

  factory DriverRequestContext.fromJson(Map<String, dynamic> json) {
    RideRequest? request;
    BookingRecord? booking;
    final req = json['request'];
    final book = json['booking'];
    if (req is Map) {
      request = RideRequest.fromJson(Map<String, dynamic>.from(req));
    }
    if (book is Map) {
      booking = BookingRecord.fromJson(Map<String, dynamic>.from(book));
    }
    return DriverRequestContext(
      onShift: json['on_shift'] == true,
      canRequest: json['can_request'] == true,
      callSmsEnabled: json['call_sms_enabled'] == true,
      canReport: json['can_report'] == true,
      canReview: json['can_review'] == true,
      serverNow: DateTime.parse(json['server_now'] as String),
      reason: json['reason'] as String?,
      request: request,
      booking: booking,
      peerContact: json['peer_contact'] as String?,
      reportableBookingId: json['reportable_booking_id'] as String?,
      reviewableBookingId: json['reviewable_booking_id'] as String?,
    );
  }
}
