import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/auth_validators.dart';
import '../core/utils/contact_launcher.dart';
import '../core/utils/phone_utils.dart';
import '../models/driver.dart';
import 'supabase_config.dart';

class AuthService {
  AuthService({SupabaseClient? client}) : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<String> _resolveLoginEmail(String mobile) async {
    final normalized = PhoneUtils.normalize(mobile);
    if (normalized.isEmpty) {
      throw AuthFlowException('Enter your mobile number.');
    }
    try {
      final raw = await _client.rpc(
        'resolve_auth_email',
        params: {
          'p_role': 'driver',
          'p_login': normalized,
        },
      );
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.trim().toLowerCase();
      }
    } on PostgrestException catch (e) {
      throw AuthFlowException(
        e.message.isNotEmpty
            ? e.message
            : AuthValidators.friendlyAuthError(e),
      );
    }
    return PhoneUtils.toAuthEmail(normalized);
  }

  /// Phone sign-in. Requires the signup email to already be confirmed.
  Future<AuthResponse> login({
    required String mobile,
    required String password,
  }) async {
    try {
      final email = await _resolveLoginEmail(mobile);
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      await _assertDriverRole(response.user);
      return response;
    } on AuthException catch (e) {
      throw AuthFlowException(AuthValidators.friendlyAuthError(e));
    }
  }

  Future<AuthResponse> signUp({
    required String fullName,
    required String mobile,
    required String email,
    required String password,
    required String licenseNumber,
    required String plateNumber,
    required String assignedTerminalId,
  }) async {
    final normalized = PhoneUtils.normalize(mobile);
    try {
      final trimmedEmail = email.trim().toLowerCase();
      await _client.rpc('register_driver', params: {
        'p_full_name': fullName.trim(),
        'p_mobile': normalized,
        'p_email': trimmedEmail.isEmpty ? null : trimmedEmail,
        'p_password': password,
        'p_license': licenseNumber.trim(),
        'p_plate': plateNumber.trim().toUpperCase(),
        'p_terminal_id': assignedTerminalId,
      });
      throw AuthFlowException(
        'Account created. An administrator must verify your license before you can sign in.',
        isSuccessInfo: true,
      );
    } on AuthFlowException {
      rethrow;
    } on AuthException catch (e) {
      throw AuthFlowException(AuthValidators.friendlyAuthError(e));
    } on PostgrestException catch (e) {
      throw AuthFlowException(
        e.message.isNotEmpty
            ? e.message
            : AuthValidators.friendlyAuthError(e),
      );
    }
  }

  Future<void> logout() => _client.auth.signOut();

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw AuthFlowException('You must be signed in to change your password.');
    }
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw AuthFlowException('Unable to verify your account email.');
    }
    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
    } on AuthException catch (_) {
      throw AuthFlowException('Current password is incorrect.');
    }
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw AuthFlowException(AuthValidators.friendlyAuthError(e));
    }
  }

  Future<void> _assertDriverRole(User? user) async {
    if (user == null) return;
    final role = user.userMetadata?['role']?.toString();
    if (role != null && role != 'driver') {
      await logout();
      throw AuthFlowException(
        'This account is not a driver account. Use the passenger app instead.',
      );
    }
  }

  Future<Driver?> fetchCurrentDriver() async {
    final user = currentUser;
    if (user == null) return null;

    final role = user.userMetadata?['role']?.toString();
    if (role != null && role != 'driver') return null;

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
    } catch (_) {}

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

  /// Opens the device Messages / SMS app only (default SMS package on Android).
  Future<bool> openSms(String? mobile, {String? body}) async {
    if (mobile == null || mobile.trim().isEmpty) return false;
    return ContactLauncher.openSms(mobile, body: body);
  }

  /// Opens the device Phone dialer only.
  Future<bool> openCall(String? mobile) async {
    if (mobile == null || mobile.trim().isEmpty) return false;
    return ContactLauncher.openCall(mobile);
  }
}
