import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils/phone_utils.dart';
import '../models/driver.dart';
import 'supabase_config.dart';

class AuthService {
  AuthService({SupabaseClient? client}) : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> login({
    required String mobile,
    required String password,
  }) {
    final email = PhoneUtils.toAuthEmail(mobile);
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp({
    required String fullName,
    required String mobile,
    required String email,
    required String password,
    required String licenseNumber,
    required String plateNumber,
    String? assignedTerminalId,
  }) async {
    final authEmail = PhoneUtils.toAuthEmail(mobile);
    final response = await _client.auth.signUp(
      email: authEmail,
      password: password,
      data: {
        'full_name': fullName,
        'mobile_number': PhoneUtils.normalize(mobile),
        'contact_number': PhoneUtils.normalize(mobile),
        'email': email.trim(),
        'license_number': licenseNumber.trim(),
        'driver_license_number': licenseNumber.trim(),
        'plate_number': plateNumber.trim().toUpperCase(),
        'username': PhoneUtils.normalize(mobile),
        'assigned_terminal_id': ?assignedTerminalId,
        'role': 'driver',
      },
    );

    final user = response.user;
    if (user != null && assignedTerminalId != null) {
      // Ensure profile row exists for contract schema (terminal_id + shift_id required).
      final shifts = await _client.from('shifts').select('shift_id').limit(1);
      final shiftId = (shifts as List).isNotEmpty
          ? (shifts.first as Map)['shift_id'] as String?
          : null;
      if (shiftId != null) {
        await _client.from('drivers').upsert({
          'driver_id': user.id,
          'full_name': fullName,
          'contact_number': PhoneUtils.normalize(mobile),
          'driver_license_number': licenseNumber.trim(),
          'plate_number': plateNumber.trim().toUpperCase(),
          'username': PhoneUtils.normalize(mobile),
          'terminal_id': assignedTerminalId,
          'shift_id': shiftId,
          'is_active': false,
          'license_verified': false,
          'status': 'pending_verification',
        });
      }
    }

    return response;
  }

  Future<void> logout() => _client.auth.signOut();

  Future<Driver?> fetchCurrentDriver() async {
    final user = currentUser;
    if (user == null) return null;

    // Contract ERD schema
    try {
      final row = await _client
          .from('drivers')
          .select(
            '*, terminal:terminals!drivers_terminal_id_fkey(*),'
            ' current_terminal:terminals!drivers_current_terminal_id_fkey(*)',
          )
          .eq('driver_id', user.id)
          .maybeSingle();
      if (row != null) {
        final driver = Driver.fromJson(row);
        final onShift = await isOnShift(driver.id);
        return driver.copyWith(onShift: onShift);
      }
    } catch (_) {
      // Fall through to legacy shape.
    }

    // Legacy schema fallback
    try {
      final row = await _client
          .from('drivers')
          .select(
            '*, assigned_terminal:terminals!drivers_assigned_terminal_id_fkey(*), '
            'current_terminal:terminals!drivers_current_terminal_id_fkey(*)',
          )
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) return null;
      final driver = Driver.fromJson(row);
      final onShift = await isOnShift(driver.id);
      return driver.copyWith(onShift: onShift);
    } catch (_) {
      return null;
    }
  }

  Future<bool> isOnShift(String driverId) async {
    try {
      final result = await _client.rpc(
        'is_driver_on_shift',
        params: {'p_driver_id': driverId},
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateCurrentTerminal(String terminalId) async {
    final user = currentUser;
    if (user == null) return;

    // Keep assigned terminal_id; only update where the driver is today.
    try {
      await _client.from('drivers').update({
        'current_terminal_id': terminalId,
      }).eq('driver_id', user.id);
      return;
    } catch (_) {}

    try {
      await _client.from('drivers').update({
        'current_terminal_id': terminalId,
      }).eq('id', user.id);
    } catch (_) {}
  }

  Future<void> openSms(String? mobile, {String? body}) async {
    if (mobile == null || mobile.isEmpty) return;
    final uri = Uri(
      scheme: 'sms',
      path: PhoneUtils.normalize(mobile),
      queryParameters: body == null ? null : {'body': body},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> openCall(String? mobile) async {
    if (mobile == null || mobile.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: PhoneUtils.normalize(mobile));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
