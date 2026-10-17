import 'package:intl/intl.dart';

String statusLabel(String status) => switch (status) {
  'pending_verification' => 'Pending verification',
  'active' => 'Active',
  // Suspended was replaced by Deactivated (same effect: blocked login).
  'suspended' => 'Deactivated',
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
    required this.plateNumber,
    required this.username,
    required this.terminalId,
    required this.shiftId,
    required this.status,
    required this.todaVerified,
    this.todaNumber,
    this.statusReason,
    this.terminalName,
    this.shiftLabel,
    this.todaVerifiedAt,
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String contactNumber;
  final String plateNumber;
  final String? todaNumber;
  final String username;
  final String terminalId;
  final String shiftId;
  final String status;

  /// TODA-plate verification flag (server columns are still named
  /// `license_verified*`; see the TODA-plate migration).
  final bool todaVerified;
  final String? statusReason;
  final String? terminalName;
  final String? shiftLabel;
  final DateTime? todaVerifiedAt;
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
      plateNumber: json['plate_number'] as String? ?? '',
      todaNumber: json['toda_number'] as String?,
      username: json['username'] as String? ?? '',
      terminalId: json['terminal_id'] as String,
      shiftId: json['shift_id'] as String,
      status: json['status'] as String? ?? 'pending_verification',
      todaVerified: json['license_verified'] as bool? ?? false,
      statusReason: json['status_reason'] as String?,
      terminalName: terminalName,
      shiftLabel: shiftLabel,
      todaVerifiedAt: json['license_verified_at'] == null
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
      commuterName =
          (commuter['full_name'] ?? json['commuter_name']) as String?;
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

/// A pending driver request to move to a different shift block.
class ShiftChangeRequestRecord {
  const ShiftChangeRequestRecord({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.requestedShiftId,
    this.plateNumber,
    this.currentShiftId,
    this.currentShiftLabel,
    this.requestedShiftLabel,
    this.requestedShiftStart,
    this.requestedShiftEnd,
    this.createdAt,
  });

  final String id;
  final String driverId;
  final String driverName;
  final String? plateNumber;
  final String? currentShiftId;
  final String? currentShiftLabel;
  final String requestedShiftId;
  final String? requestedShiftLabel;
  final String? requestedShiftStart;
  final String? requestedShiftEnd;
  final DateTime? createdAt;

  String get requestedWindow =>
      requestedShiftStart == null || requestedShiftEnd == null
      ? ''
      : ' (${formatClock(requestedShiftStart!)} – ${formatClock(requestedShiftEnd!)})';

  factory ShiftChangeRequestRecord.fromJson(Map<String, dynamic> json) {
    return ShiftChangeRequestRecord(
      id: json['id'] as String,
      driverId: json['driverId'] as String,
      driverName: json['driverName'] as String? ?? 'Driver',
      plateNumber: json['plateNumber'] as String?,
      currentShiftId: json['currentShiftId'] as String?,
      currentShiftLabel: json['currentShiftLabel'] as String?,
      requestedShiftId: json['requestedShiftId'] as String,
      requestedShiftLabel: json['requestedShiftLabel'] as String?,
      requestedShiftStart: json['requestedShiftStart']?.toString(),
      requestedShiftEnd: json['requestedShiftEnd']?.toString(),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
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
    int n(String key, int fallback) => (json[key] as num?)?.toInt() ?? fallback;
    return BookingSettings(
      disputeWindowMinutes: n('dispute_window_minutes', 60),
      requestExpireMinutes: n('request_expire_minutes', 30),
      requestCooldownMinutes: n('request_cooldown_minutes', 30),
      reviewEligibleMinutes: n('review_eligible_minutes', 0),
    );
  }
}

/// Current foreground-activity state of one account — driver or commuter
/// (admin list + detail).
///
/// States: `active_now` (open session, heartbeat within timeout, account
/// active), `inactive` (stale or background-ended), `offline` (explicit
/// logout, nothing after), `unknown` (no activity rows at all).
class UserActivityState {
  const UserActivityState({
    required this.userId,
    required this.fullName,
    required this.accountStatus,
    required this.state,
    this.lastSeen,
    this.currentActiveSeconds,
  });

  final String userId;
  final String fullName;
  final String accountStatus;
  final String state;
  final DateTime? lastSeen;
  final int? currentActiveSeconds;

  static DateTime? _dt(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  factory UserActivityState.fromJson(Map<String, dynamic> json) {
    return UserActivityState(
      userId: (json['driver_id'] ?? json['commuter_id'] ?? '') as String,
      fullName: json['full_name'] as String? ?? 'Driver',
      accountStatus: json['account_status'] as String? ?? 'unknown',
      state: json['activity_state'] as String? ?? 'unknown',
      lastSeen: _dt(json['last_seen']),
      currentActiveSeconds: (json['current_active_seconds'] as num?)?.toInt(),
    );
  }

  String get label => switch (state) {
    'active_now' => 'Active now',
    'inactive' => 'Inactive',
    'offline' => 'Offline',
    _ => 'Unknown',
  };
}

/// Back-compat alias: the same model is used for commuter activity.
typedef DriverActivityState = UserActivityState;

/// One recorded audit-trail entry (screen open or key action).
class AuditLogEntry {
  const AuditLogEntry({
    required this.logId,
    required this.action,
    required this.detail,
    required this.occurredAt,
  });

  final String logId;
  final String action;
  final Map<String, String> detail;
  final DateTime occurredAt;

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['detail'];
    return AuditLogEntry(
      logId: (json['log_id'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      detail: raw is Map
          ? Map.fromEntries(
              raw.entries
                  .where((e) => e.value != null)
                  .map((e) => MapEntry(e.key.toString(), e.value.toString())),
            )
          : const {},
      occurredAt: DateTime.parse(json['occurred_at'].toString()),
    );
  }

  /// Human sentence for the admin UI, e.g. "Opened Driver List · driver: Juan".
  String get displayText {
    final label = auditActionLabel(action);
    final extra = detail.entries
        .where((e) => e.value.trim().isNotEmpty)
        .map((e) => '${_prettyKey(e.key)}: ${e.value}')
        .join(' · ');
    return extra.isEmpty ? label : '$label · $extra';
  }

  static String _prettyKey(String key) => switch (key) {
    'driver_id' => 'driver id',
    'commuter_id' => 'passenger id',
    'booking_id' => 'booking id',
    'review_id' => 'review id',
    'terminal_id' => 'terminal id',
    _ => key.replaceAll('_', ' '),
  };
}

/// Friendly label for a raw audit action code.
String auditActionLabel(String action) {
  final named = <String, String>{
    'login': 'Signed in',
    'logout': 'Signed out',
    'call_driver': 'Called driver',
    'sms_driver': 'Texted driver',
    'call_commuter': 'Called passenger',
    'sms_commuter': 'Texted passenger',
    'submit_report': 'Submitted a report',
    'submit_review': 'Submitted a review',
    'flag_review': 'Flagged a review',
    'complete_booking': 'Finished a booking',
    'choose_terminal': 'Chose a terminal',
  };
  return named[action] ??
      (action.startsWith('screen_')
          ? 'Opened ${_humanize(action.replaceFirst('screen_', ''))}'
          : _humanize(action));
}

String _humanize(String code) {
  if (code.isEmpty) return 'Activity';
  final spaced = code.replaceAll('_', ' ');
  return spaced
      .split(' ')
      .map(
        (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}',
      )
      .join(' ');
}

/// One foreground span inside a usage summary period.
class UsageSession {
  const UsageSession({
    required this.sessionId,
    required this.startedAt,
    this.endedAt,
    this.endReason,
    required this.beats,
    this.foregroundSeconds,
  });

  final String sessionId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? endReason;
  final int beats;
  final int? foregroundSeconds;

  factory UsageSession.fromJson(Map<String, dynamic> json) {
    return UsageSession(
      sessionId: json['session_id'] as String,
      startedAt: DateTime.parse(json['started_at'].toString()),
      endedAt: json['ended_at'] == null
          ? null
          : DateTime.tryParse(json['ended_at'].toString()),
      endReason: json['end_reason'] as String?,
      beats: (json['beats'] as num?)?.toInt() ?? 0,
      foregroundSeconds: (json['foreground_seconds'] as num?)?.toInt(),
    );
  }
}

/// Totals for one driver over a reporting period. Foreground usage only:
/// summed heartbeat-chain time, never login-to-logout spans.
class DriverUsageSummary {
  const DriverUsageSummary({
    required this.totalForegroundSeconds,
    required this.sessions,
    required this.activeDays,
    this.firstSeen,
    this.lastSeen,
    this.sessionsDetail = const [],
  });

  final int totalForegroundSeconds;
  final int sessions;
  final int activeDays;
  final DateTime? firstSeen;
  final DateTime? lastSeen;
  final List<UsageSession> sessionsDetail;

  factory DriverUsageSummary.fromJson(Map<String, dynamic> json) {
    final detail = json['sessions_detail'];
    return DriverUsageSummary(
      totalForegroundSeconds:
          (json['total_foreground_seconds'] as num?)?.toInt() ?? 0,
      sessions: (json['sessions'] as num?)?.toInt() ?? 0,
      activeDays: (json['active_days'] as num?)?.toInt() ?? 0,
      firstSeen: json['first_seen'] == null
          ? null
          : DateTime.tryParse(json['first_seen'].toString()),
      lastSeen: json['last_seen'] == null
          ? null
          : DateTime.tryParse(json['last_seen'].toString()),
      sessionsDetail: detail is List
          ? detail
                .map(
                  (e) => UsageSession.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList()
          : const [],
    );
  }
}
