import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_models.dart';
import 'supabase_config.dart';

class AdminRepository {
  AdminRepository({SupabaseClient? client})
      : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  static const _driverSelect =
      '*, terminal:terminals!drivers_terminal_id_fkey(terminal_id, terminal_name),'
      ' shift:shifts!drivers_shift_id_fkey(shift_id, label, shift_start_time, shift_end_time)';

  static const _flaggedBookingSelect =
      '*, commuter:commuters!bookings_commuter_id_fkey(full_name, contact_number),'
      ' driver:drivers!bookings_driver_id_fkey(full_name, plate_number)';

  static const _reviewReportSelect =
      '*, driver:drivers!review_reports_driver_id_fkey(full_name),'
      ' review:reviews!review_reports_review_id_fkey('
      'review_id, rating, content, commuter:commuters!reviews_commuter_id_fkey(full_name)'
      ')';

  Future<AdminProfile?> fetchCurrentAdmin() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client
        .from('admins')
        .select()
        .eq('admin_id', user.id)
        .eq('is_active', true)
        .maybeSingle();
    if (row == null) return null;
    return AdminProfile.fromJson(row);
  }

  Future<Overview> fetchOverview() async {
    final raw = await _client.rpc('admin_overview');
    return Overview.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<List<DriverRecord>> fetchDrivers() async {
    final rows = await _client.from('drivers').select(_driverSelect).order('full_name');
    return (rows as List)
        .map((e) => DriverRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<DriverRecord?> fetchDriver(String driverId) async {
    final row = await _client
        .from('drivers')
        .select(_driverSelect)
        .eq('driver_id', driverId)
        .maybeSingle();
    if (row == null) return null;
    return DriverRecord.fromJson(row);
  }

  /// Contract availability: whether the assigned shift window includes now (Asia/Manila)
  /// and the driver account is active.
  Future<bool> isDriverOnShift(String driverId) async {
    final raw = await _client.rpc(
      'is_driver_on_shift',
      params: {'p_driver_id': driverId},
    );
    return raw == true;
  }

  Future<List<TerminalRecord>> fetchTerminals() async {
    final rows = await _client.from('terminals').select().order('terminal_name');
    final terminals = (rows as List)
        .map((e) => TerminalRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final drivers = await fetchDrivers();
    return terminals
        .map(
          (t) => t.copyWith(
            assignedDrivers: drivers
                .where((d) => d.terminalId == t.id)
                .length,
          ),
        )
        .toList();
  }

  Future<List<ShiftRecord>> fetchShifts() async {
    final rows =
        await _client.from('shifts').select().order('shift_start_time');
    return (rows as List)
        .map((e) => ShiftRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<CommuterRecord>> fetchCommuters() async {
    final rows =
        await _client.from('commuters').select().order('full_name');
    return (rows as List)
        .map((e) => CommuterRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<ReviewRecord>> fetchReviews() async {
    final raw = await _client.rpc('admin_list_reviews');
    final rows = raw is List ? raw : const [];
    return rows
        .map((e) => ReviewRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<FlaggedBookingRecord>> fetchFlaggedBookings() async {
    final flagged = await _client
        .from('bookings')
        .select(_flaggedBookingSelect)
        .eq('status', 'FLAGGED')
        .order('flagged_at', ascending: false);
    final passengerReported = await _client
        .from('bookings')
        .select(_flaggedBookingSelect)
        .not('passenger_reported_at', 'is', null)
        .order('passenger_reported_at', ascending: false);
    final byId = <String, FlaggedBookingRecord>{};
    for (final e in [...flagged as List, ...passengerReported as List]) {
      final row = FlaggedBookingRecord.fromJson(Map<String, dynamic>.from(e as Map));
      byId[row.id] = row;
    }
    final items = byId.values.toList()
      ..sort((a, b) => b.flaggedAt.compareTo(a.flaggedAt));
    return items;
  }

  Future<void> resolveDisputedBooking({
    required String bookingId,
    required String action,
  }) async {
    await _client.rpc(
      'admin_resolve_disputed_booking',
      params: {
        'p_booking_id': bookingId,
        'p_action': action,
      },
    );
  }

  Future<List<ReviewReportRecord>> fetchOpenReviewReports() async {
    final rows = await _client
        .from('review_reports')
        .select(_reviewReportSelect)
        .eq('status', 'OPEN')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) =>
            ReviewReportRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> resolveReviewReport({
    required String reportId,
    required String action,
  }) async {
    await _client.rpc(
      'admin_resolve_review_report',
      params: {
        'p_report_id': reportId,
        'p_action': action,
      },
    );
  }

  Future<List<DeviceLogRecord>> fetchDeviceLogs() async {
    final rows = await _client
        .from('device_logs')
        .select()
        .order('access_datetime', ascending: false);
    final logs = (rows as List)
        .map((e) => DeviceLogRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (logs.isEmpty) return logs;

    final names = <String, String>{};
    for (final driver in await fetchDrivers()) {
      names[driver.id] = driver.fullName;
    }
    for (final commuter in await fetchCommuters()) {
      names[commuter.id] = commuter.fullName;
    }
    return logs
        .map((log) => log.copyWith(userName: names[log.userId] ?? 'Unknown user'))
        .toList();
  }

  Future<List<PrivacyRequestRecord>> fetchPrivacyRequests() async {
    final rows = await _client
        .from('privacy_requests')
        .select()
        .order('received_at', ascending: false);
    return (rows as List)
        .map((e) =>
            PrivacyRequestRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> createDriver({
    required String fullName,
    required String contactNumber,
    required String licenseNumber,
    required String plateNumber,
    required String username,
    required String password,
    required String terminalId,
    required String shiftId,
    String? todaNumber,
  }) {
    return _client.rpc('admin_create_driver', params: {
      'p_full_name': fullName,
      'p_contact_number': contactNumber,
      'p_license_number': licenseNumber,
      'p_plate_number': plateNumber,
      'p_toda_number': todaNumber,
      'p_username': username,
      'p_password': password,
      'p_terminal_id': terminalId,
      'p_shift_id': shiftId,
    });
  }

  Future<void> updateDriver({
    required String driverId,
    required String fullName,
    required String contactNumber,
    required String licenseNumber,
    required String plateNumber,
    required String username,
    required String terminalId,
    required String shiftId,
    String? todaNumber,
  }) {
    return _client.rpc('admin_update_driver', params: {
      'p_driver_id': driverId,
      'p_full_name': fullName,
      'p_contact_number': contactNumber,
      'p_license_number': licenseNumber,
      'p_plate_number': plateNumber,
      'p_toda_number': todaNumber,
      'p_username': username,
      'p_terminal_id': terminalId,
      'p_shift_id': shiftId,
    });
  }

  /// Availability in PASAKAY is the single assigned shift block (one of 3).
  Future<void> updateDriverAvailability({
    required DriverRecord driver,
    required String shiftId,
  }) {
    return updateDriver(
      driverId: driver.id,
      fullName: driver.fullName,
      contactNumber: driver.contactNumber,
      licenseNumber: driver.licenseNumber,
      plateNumber: driver.plateNumber,
      username: driver.username,
      terminalId: driver.terminalId,
      shiftId: shiftId,
      todaNumber: driver.todaNumber,
    );
  }

  Future<void> verifyLicense(
    String driverId, {
    required bool verified,
    String? todaNumber,
  }) {
    return _client.rpc('admin_verify_driver_license', params: {
      'p_driver_id': driverId,
      'p_verified': verified,
      'p_toda_number': todaNumber,
    });
  }

  Future<void> setDriverStatus(String driverId, String status, String? reason) {
    return _client.rpc('admin_set_driver_status', params: {
      'p_driver_id': driverId,
      'p_status': status,
      'p_reason': reason,
    });
  }

  /// Pending driver shift-change requests (from the driver app).
  Future<List<ShiftChangeRequestRecord>> fetchShiftChangeRequests() async {
    final raw = await _client.rpc('admin_list_shift_change_requests');
    final rows = raw is List ? raw : const [];
    return rows
        .map((e) =>
            ShiftChangeRequestRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Approve (moves driver to the requested shift) or reject a request.
  /// Returns the refreshed pending list.
  Future<List<ShiftChangeRequestRecord>> reviewShiftChangeRequest({
    required String requestId,
    required bool approve,
    String? note,
  }) async {
    final raw = await _client.rpc(
      'admin_review_shift_change_request',
      params: {
        'p_request_id': requestId,
        'p_approve': approve,
        'p_note': note,
      },
    );
    final rows = raw is List ? raw : const [];
    return rows
        .map((e) =>
            ShiftChangeRequestRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> resetDriverPassword(String driverId, String password) {
    return _client.rpc('admin_reset_driver_password', params: {
      'p_driver_id': driverId,
      'p_password': password,
    });
  }

  Future<void> resetCommuterPassword(String commuterId, String password) {
    return _client.rpc('admin_reset_commuter_password', params: {
      'p_commuter_id': commuterId,
      'p_password': password,
    });
  }

  Future<void> deleteDriver(String driverId) {
    return _client.rpc('admin_delete_driver', params: {'p_driver_id': driverId});
  }

  Future<void> createTerminal(String name) {
    return _client.rpc('admin_create_terminal', params: {'p_name': name});
  }

  Future<void> updateTerminal(String id, String name) {
    return _client.rpc('admin_update_terminal', params: {
      'p_terminal_id': id,
      'p_name': name,
    });
  }

  Future<void> deleteTerminal(String id) {
    return _client.rpc('admin_delete_terminal', params: {'p_terminal_id': id});
  }

  Future<String?> updateShift({
    required String id,
    required String label,
    required String startTime,
    required String endTime,
  }) async {
    final result = await _client.rpc('admin_update_shift', params: {
      'p_shift_id': id,
      'p_label': label,
      'p_start_time': startTime,
      'p_end_time': endTime,
    });
    if (result is String && result.trim().isNotEmpty) return result;
    return null;
  }

  Future<void> setCommuterStatus(String id, String status, String? reason) {
    return _client.rpc('admin_set_commuter_status', params: {
      'p_commuter_id': id,
      'p_status': status,
      'p_reason': reason,
    });
  }

  Future<void> setReviewHidden(String id, {required bool hidden, String? note}) {
    return _client.rpc('admin_set_review_hidden', params: {
      'p_review_id': id,
      'p_hidden': hidden,
      'p_note': note,
    });
  }

  Future<void> deleteReview(String id) {
    return _client.rpc('admin_delete_review', params: {'p_review_id': id});
  }

  Future<void> logPrivacyRequest({
    String? subjectUserId,
    String? subjectRole,
    required String subjectName,
    String? subjectContact,
    required String requestType,
    String? details,
  }) {
    return _client.rpc('admin_log_privacy_request', params: {
      'p_subject_user_id': subjectUserId,
      'p_subject_role': subjectRole,
      'p_subject_name': subjectName,
      'p_subject_contact': subjectContact,
      'p_request_type': requestType,
      'p_details': details,
    });
  }

  Future<void> setPrivacyStatus(String id, String status, String? notes) {
    return _client.rpc('admin_set_privacy_status', params: {
      'p_request_id': id,
      'p_status': status,
      'p_notes': notes,
    });
  }

  Future<Map<String, dynamic>> subjectSnapshot(String requestId) async {
    final raw = await _client.rpc(
      'admin_subject_snapshot',
      params: {'p_request_id': requestId},
    );
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<void> applyCorrection({
    required String requestId,
    required String fullName,
    required String contactNumber,
    String? emailAddress,
  }) {
    return _client.rpc('admin_apply_correction', params: {
      'p_request_id': requestId,
      'p_full_name': fullName,
      'p_contact_number': contactNumber,
      'p_email_address': emailAddress,
    });
  }

  Future<void> processDeletion({
    required String requestId,
    required bool retentionApplies,
    String? retentionReason,
    required String confirmName,
  }) {
    return _client.rpc('admin_process_deletion', params: {
      'p_request_id': requestId,
      'p_retention_applies': retentionApplies,
      'p_retention_reason': retentionReason,
      'p_confirm_name': confirmName,
    });
  }

  Future<void> changePassword(String password) {
    return _client.rpc('admin_change_password', params: {'p_password': password});
  }

  Future<BookingSettings> fetchBookingSettings() async {
    final raw = await _client.rpc('get_booking_settings');
    return BookingSettings.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<BookingSettings> updateBookingSettings({
    required int disputeWindowMinutes,
    required int requestExpireMinutes,
    required int requestCooldownMinutes,
    required int reviewEligibleMinutes,
  }) async {
    final raw = await _client.rpc(
      'admin_set_booking_settings',
      params: {
        'p_dispute_window_minutes': disputeWindowMinutes,
        'p_request_expire_minutes': requestExpireMinutes,
        'p_request_cooldown_minutes': requestCooldownMinutes,
        'p_review_eligible_minutes': reviewEligibleMinutes,
      },
    );
    return BookingSettings.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<Set<String>> fetchBookedDriverIds() async {
    final rows = await _client
        .from('bookings')
        .select('driver_id')
        .eq('status', 'BOOKED');
    return {
      for (final e in rows as List)
        (Map<String, dynamic>.from(e as Map)['driver_id'] as String),
    };
  }
}
