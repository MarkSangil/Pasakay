import 'package:intl/intl.dart';

String statusLabel(String status) => switch (status) {
      'pending_verification' => 'Pending verification',
      'active' => 'Active',
      'suspended' => 'Suspended',
      'deactivated' => 'Deactivated',
      'received' => 'Received',
      'in_progress' => 'In progress',
      'completed' => 'Completed',
      'denied' => 'Denied',
      'retained' => 'Retained',
      _ => status,
    };

String formatWhen(DateTime? value) {
  if (value == null) return '—';
  return DateFormat('MMM d, yyyy · h:mm a').format(value.toLocal());
}

String formatClock(String raw) {
  final parts = raw.split(':');
  final hour = int.tryParse(parts.first) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, hour, minute));
}

class AdminProfile {
  const AdminProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.username,
  });

  final String id;
  final String fullName;
  final String email;
  final String username;

  factory AdminProfile.fromJson(Map<String, dynamic> json) {
    return AdminProfile(
      id: json['admin_id'] as String,
      fullName: json['full_name'] as String? ?? 'System Admin',
      email: json['email'] as String? ?? '',
      username: json['username'] as String? ?? '',
    );
  }
}

class Overview {
  const Overview({
    this.driversTotal = 0,
    this.driversPending = 0,
    this.driversActive = 0,
    this.driversSuspended = 0,
    this.commutersTotal = 0,
    this.commutersSuspended = 0,
    this.terminals = 0,
    this.shifts = 0,
    this.reviewsVisible = 0,
    this.reviewsHidden = 0,
    this.requestsPending = 0,
    this.requestsTotal = 0,
    this.bookingsBooked = 0,
    this.bookingsCompleted = 0,
    this.bookingsFlagged = 0,
    this.bookingsCancelled = 0,
    this.bookingsTotal = 0,
    this.reviewReportsOpen = 0,
    this.crashLogs = 0,
    this.deviceLogs = 0,
    this.privacyOpen = 0,
    this.generatedAt,
  });

  final int driversTotal;
  final int driversPending;
  final int driversActive;
  final int driversSuspended;
  final int commutersTotal;
  final int commutersSuspended;
  final int terminals;
  final int shifts;
  final int reviewsVisible;
  final int reviewsHidden;
  final int requestsPending;
  final int requestsTotal;
  final int bookingsBooked;
  final int bookingsCompleted;
  final int bookingsFlagged;
  final int bookingsCancelled;
  final int bookingsTotal;
  final int reviewReportsOpen;
  final int crashLogs;
  final int deviceLogs;
  final int privacyOpen;
  final DateTime? generatedAt;

  factory Overview.fromJson(Map<String, dynamic> json) {
    int n(String key) {
      final v = json[key];
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    DateTime? t(String key) {
      final v = json[key];
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return Overview(
      driversTotal: n('drivers_total'),
      driversPending: n('drivers_pending'),
      driversActive: n('drivers_active'),
      driversSuspended: n('drivers_suspended'),
      commutersTotal: n('commuters_total'),
      commutersSuspended: n('commuters_suspended'),
      terminals: n('terminals'),
      shifts: n('shifts'),
      reviewsVisible: n('reviews_visible'),
      reviewsHidden: n('reviews_hidden'),
      requestsPending: n('requests_pending'),
      requestsTotal: n('requests_total'),
      bookingsBooked: n('bookings_booked'),
      bookingsCompleted: n('bookings_completed'),
      bookingsFlagged: n('bookings_flagged'),
      bookingsCancelled: n('bookings_cancelled'),
      bookingsTotal: n('bookings_total'),
      reviewReportsOpen: n('review_reports_open'),
      crashLogs: n('crash_logs'),
      deviceLogs: n('device_logs'),
      privacyOpen: n('privacy_open'),
      generatedAt: t('generated_at'),
    );
  }
}

class TerminalRecord {
  const TerminalRecord({
    required this.id,
    required this.name,
    required this.createdAt,
    this.assignedDrivers = 0,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int assignedDrivers;

  factory TerminalRecord.fromJson(Map<String, dynamic> json) {
    return TerminalRecord(
      id: json['terminal_id'] as String,
      name: json['terminal_name'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'].toString()),
    );
  }

  TerminalRecord copyWith({int? assignedDrivers}) {
    return TerminalRecord(
      id: id,
      name: name,
      createdAt: createdAt,
      assignedDrivers: assignedDrivers ?? this.assignedDrivers,
    );
  }
}

class ShiftRecord {
  const ShiftRecord({
    required this.id,
    required this.label,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final String label;
  final String startTime;
  final String endTime;

  String get window => '${formatClock(startTime)} – ${formatClock(endTime)}';

  factory ShiftRecord.fromJson(Map<String, dynamic> json) {
    return ShiftRecord(
      id: json['shift_id'] as String,
      label: json['label'] as String? ?? '',
      startTime: json['shift_start_time'].toString(),
      endTime: json['shift_end_time'].toString(),
    );
  }
}

class DriverRecord {
  const DriverRecord({
    required this.id,
    required this.fullName,
    required this.contactNumber,
    required this.licenseNumber,
    required this.plateNumber,
    required this.username,
    required this.terminalId,
    required this.shiftId,
    required this.status,
    required this.licenseVerified,
    this.todaNumber,
    this.statusReason,
    this.terminalName,
    this.shiftLabel,
    this.licenseVerifiedAt,
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String contactNumber;
  final String licenseNumber;
  final String plateNumber;
  final String? todaNumber;
  final String username;
  final String terminalId;
  final String shiftId;
  final String status;
  final bool licenseVerified;
  final String? statusReason;
  final String? terminalName;
  final String? shiftLabel;
  final DateTime? licenseVerifiedAt;
  final DateTime? createdAt;

  factory DriverRecord.fromJson(Map<String, dynamic> json) {
    String? terminalName;
    String? shiftLabel;
    final terminal = json['terminal'];
    final shift = json['shift'];
    if (terminal is Map) {
      terminalName = terminal['terminal_name'] as String?;
    }
    if (shift is Map) {
      shiftLabel = shift['label'] as String?;
    }
    return DriverRecord(
      id: json['driver_id'] as String,
      fullName: json['full_name'] as String? ?? '',
      contactNumber: json['contact_number'] as String? ?? '',
      licenseNumber: json['driver_license_number'] as String? ?? '',
      plateNumber: json['plate_number'] as String? ?? '',
      todaNumber: json['toda_number'] as String?,
      username: json['username'] as String? ?? '',
      terminalId: json['terminal_id'] as String,
      shiftId: json['shift_id'] as String,
      status: json['status'] as String? ?? 'pending_verification',
      licenseVerified: json['license_verified'] as bool? ?? false,
      statusReason: json['status_reason'] as String?,
      terminalName: terminalName,
      shiftLabel: shiftLabel,
      licenseVerifiedAt: json['license_verified_at'] == null
          ? null
          : DateTime.parse(json['license_verified_at'].toString()),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'].toString()),
    );
  }
}

class CommuterRecord {
  const CommuterRecord({
    required this.id,
    required this.fullName,
    required this.contactNumber,
    required this.username,
    required this.status,
    this.emailAddress,
    this.statusReason,
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String contactNumber;
  final String? emailAddress;
  final String username;
  final String status;
  final String? statusReason;
  final DateTime? createdAt;

  factory CommuterRecord.fromJson(Map<String, dynamic> json) {
    return CommuterRecord(
      id: json['commuter_id'] as String,
      fullName: json['full_name'] as String? ?? '',
      contactNumber: json['contact_number'] as String? ?? '',
      emailAddress: json['email_address'] as String?,
      username: json['username'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      statusReason: json['status_reason'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'].toString()),
    );
  }
}

class ReviewRecord {
  const ReviewRecord({
    required this.id,
    required this.commuterId,
    required this.driverId,
    required this.rating,
    required this.createdAt,
    required this.isHidden,
    this.bookingId,
    this.content,
    this.commuterName,
    this.driverName,
    this.driverPlate,
    this.moderationNote,
  });

  final String id;
  final String commuterId;
  final String driverId;
  final String? bookingId;
  final int rating;
  final String? content;
  final DateTime createdAt;
  final bool isHidden;
  final String? commuterName;
  final String? driverName;
  final String? driverPlate;
  final String? moderationNote;

  factory ReviewRecord.fromJson(Map<String, dynamic> json) {
    String? commuterName;
    String? driverName;
    String? driverPlate;
    final commuter = json['commuter'];
    final driver = json['driver'];
    if (commuter is Map) {
      commuterName = (commuter['full_name'] ?? json['commuter_name']) as String?;
    } else {
      commuterName = json['commuter_name'] as String?;
    }
    if (driver is Map) {
      driverName = (driver['full_name'] ?? json['driver_name']) as String?;
      driverPlate = (driver['plate_number'] ?? json['driver_plate']) as String?;
    } else {
      driverName = json['driver_name'] as String?;
      driverPlate = json['driver_plate'] as String?;
    }
    final createdRaw = json['date_created'] ?? json['created_at'];
    return ReviewRecord(
      id: (json['review_id'] ?? json['id']) as String,
      commuterId: json['commuter_id'] as String,
      driverId: json['driver_id'] as String,
      bookingId: json['booking_id'] as String?,
      rating: (json['rating'] as num).toInt(),
      content: json['content'] as String?,
      createdAt: DateTime.parse(createdRaw.toString()),
      isHidden: json['is_hidden'] as bool? ?? false,
      commuterName: commuterName,
      driverName: driverName,
      driverPlate: driverPlate,
      moderationNote: json['moderation_note'] as String?,
    );
  }
}

class DeviceLogRecord {
  const DeviceLogRecord({
    required this.id,
    required this.userId,
    required this.userType,
    required this.accessedAt,
    this.deviceModel,
    this.osVersion,
    this.appVersion,
    this.crashLog,
    this.userName,
  });

  final String id;
  final String userId;
  final String userType;
  final String? deviceModel;
  final String? osVersion;
  final String? appVersion;
  final DateTime accessedAt;
  final String? crashLog;
  final String? userName;

  bool get isCrash => crashLog != null && crashLog!.trim().isNotEmpty;

  factory DeviceLogRecord.fromJson(Map<String, dynamic> json) {
    return DeviceLogRecord(
      id: json['log_id'] as String,
      userId: json['user_id'] as String,
      userType: json['user_type'] as String? ?? '',
      deviceModel: json['device_model'] as String?,
      osVersion: json['os_version'] as String?,
      appVersion: json['app_version'] as String?,
      accessedAt: DateTime.parse(json['access_datetime'].toString()),
      crashLog: json['crash_error_log'] as String?,
    );
  }

  DeviceLogRecord copyWith({String? userName}) {
    return DeviceLogRecord(
      id: id,
      userId: userId,
      userType: userType,
      accessedAt: accessedAt,
      deviceModel: deviceModel,
      osVersion: osVersion,
      appVersion: appVersion,
      crashLog: crashLog,
      userName: userName ?? this.userName,
    );
  }
}

class FlaggedBookingRecord {
  const FlaggedBookingRecord({
    required this.id,
    required this.requestId,
    required this.commuterId,
    required this.driverId,
    required this.status,
    required this.confirmedAt,
    required this.flaggedAt,
    this.flagReason,
    this.flagDetails,
    this.commuterName,
    this.driverName,
    this.passengerReportedAt,
  });

  final String id;
  final String requestId;
  final String commuterId;
  final String driverId;
  final String status;
  final DateTime confirmedAt;
  final DateTime flaggedAt;
  final String? flagReason;
  final String? flagDetails;
  final String? commuterName;
  final String? driverName;
  final DateTime? passengerReportedAt;

  bool get isPassengerReport => passengerReportedAt != null;

  factory FlaggedBookingRecord.fromJson(Map<String, dynamic> json) {
    String? commuterName;
    String? driverName;
    final commuter = json['commuter'];
    final driver = json['driver'];
    if (commuter is Map) commuterName = commuter['full_name'] as String?;
    if (driver is Map) driverName = driver['full_name'] as String?;
    final passengerReportedAt = json['passenger_reported_at'] == null
        ? null
        : DateTime.parse(json['passenger_reported_at'].toString());
    return FlaggedBookingRecord(
      id: json['booking_id'] as String,
      requestId: json['request_id'] as String,
      commuterId: json['commuter_id'] as String,
      driverId: json['driver_id'] as String,
      status: json['status'] as String? ?? 'FLAGGED',
      confirmedAt: DateTime.parse(json['confirmed_at'].toString()),
      flaggedAt: json['flagged_at'] == null
          ? (passengerReportedAt ??
              DateTime.parse(json['confirmed_at'].toString()))
          : DateTime.parse(json['flagged_at'].toString()),
      flagReason: json['flag_reason'] as String?,
      flagDetails: json['flag_details'] as String?,
      commuterName: commuterName ?? json['passenger_name'] as String?,
      driverName: driverName,
      passengerReportedAt: passengerReportedAt,
    );
  }
}

class ReviewReportRecord {
  const ReviewReportRecord({
    required this.id,
    required this.reviewId,
    required this.driverId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.details,
    this.driverName,
    this.reviewRating,
    this.reviewContent,
    this.commuterName,
  });

  final String id;
  final String reviewId;
  final String driverId;
  final String reason;
  final String? details;
  final String status;
  final DateTime createdAt;
  final String? driverName;
  final int? reviewRating;
  final String? reviewContent;
  final String? commuterName;

  factory ReviewReportRecord.fromJson(Map<String, dynamic> json) {
    String? driverName;
    int? rating;
    String? content;
    String? commuterName;

    final driver = json['driver'];
    if (driver is Map) driverName = driver['full_name'] as String?;

    final review = json['review'];
    if (review is Map) {
      rating = (review['rating'] as num?)?.toInt();
      content = review['content'] as String?;
      final commuter = review['commuter'];
      if (commuter is Map) {
        commuterName = commuter['full_name'] as String?;
      }
    }

    return ReviewReportRecord(
      id: json['report_id'] as String,
      reviewId: json['review_id'] as String,
      driverId: json['driver_id'] as String,
      reason: json['reason'] as String? ?? '',
      details: json['details'] as String?,
      status: json['status'] as String? ?? 'OPEN',
      createdAt: DateTime.parse(json['created_at'].toString()),
      driverName: driverName,
      reviewRating: rating,
      reviewContent: content,
      commuterName: commuterName,
    );
  }
}

class PrivacyRequestRecord {
  const PrivacyRequestRecord({
    required this.id,
    required this.subjectName,
    required this.requestType,
    required this.status,
    required this.receivedAt,
    this.subjectUserId,
    this.subjectRole,
    this.subjectContact,
    this.details,
    this.adminNotes,
    this.retentionApplies = false,
    this.retentionReason,
    this.resolvedAt,
    this.correctionPayload,
  });

  final String id;
  final String? subjectUserId;
  final String? subjectRole;
  final String subjectName;
  final String? subjectContact;
  final String requestType;
  final String status;
  final String? details;
  final String? adminNotes;
  final bool retentionApplies;
  final String? retentionReason;
  final DateTime receivedAt;
  final DateTime? resolvedAt;
  final Map<String, dynamic>? correctionPayload;

  factory PrivacyRequestRecord.fromJson(Map<String, dynamic> json) {
    final payload = json['correction_payload'];
    return PrivacyRequestRecord(
      id: json['request_id'] as String,
      subjectUserId: json['subject_user_id'] as String?,
      subjectRole: json['subject_role'] as String?,
      subjectName: json['subject_name'] as String? ?? '',
      subjectContact: json['subject_contact'] as String?,
      requestType: json['request_type'] as String? ?? '',
      status: json['status'] as String? ?? 'received',
      details: json['details'] as String?,
      adminNotes: json['admin_notes'] as String?,
      retentionApplies: json['retention_applies'] as bool? ?? false,
      retentionReason: json['retention_reason'] as String?,
      receivedAt: DateTime.parse(json['received_at'].toString()),
      resolvedAt: json['resolved_at'] == null
          ? null
          : DateTime.parse(json['resolved_at'].toString()),
      correctionPayload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : null,
    );
  }
}

class BookingSettings {
  const BookingSettings({
    required this.disputeWindowMinutes,
    required this.requestExpireMinutes,
    required this.requestCooldownMinutes,
    required this.reviewEligibleMinutes,
  });

  final int disputeWindowMinutes;
  final int requestExpireMinutes;
  final int requestCooldownMinutes;
  final int reviewEligibleMinutes;

  factory BookingSettings.fromJson(Map<String, dynamic> json) {
    int n(String key, int fallback) =>
        (json[key] as num?)?.toInt() ?? fallback;
    return BookingSettings(
      disputeWindowMinutes: n('dispute_window_minutes', 20),
      requestExpireMinutes: n('request_expire_minutes', 30),
      requestCooldownMinutes: n('request_cooldown_minutes', 30),
      reviewEligibleMinutes: n('review_eligible_minutes', 0),
    );
  }
}
