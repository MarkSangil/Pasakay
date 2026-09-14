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

  static const _reviewSelect =
      '*, commuter:commuters!reviews_commuter_id_fkey(full_name, username),'
      ' driver:drivers!reviews_driver_id_fkey(full_name)';

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
    final rows = await _client
        .from('reviews')
        .select(_reviewSelect)
        .order('date_created', ascending: false);
    return (rows as List)
        .map((e) => ReviewRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
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

  Future<void> verifyLicense(String driverId, {required bool verified}) {
    return _client.rpc('admin_verify_driver_license', params: {
      'p_driver_id': driverId,
      'p_verified': verified,
    });
  }

  Future<void> setDriverStatus(String driverId, String status, String? reason) {
    return _client.rpc('admin_set_driver_status', params: {
      'p_driver_id': driverId,
      'p_status': status,
      'p_reason': reason,
    });
  }

  Future<void> resetDriverPassword(String driverId, String password) {
    return _client.rpc('admin_reset_driver_password', params: {
      'p_driver_id': driverId,
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
}
