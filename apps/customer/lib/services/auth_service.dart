import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/auth_validators.dart';
import '../core/utils/contact_launcher.dart';
import '../core/utils/phone_utils.dart';
import '../models/models.dart';
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
          'p_role': 'commuter',
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

  /// Phone sign-in. Account must be admin-approved (active).
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
      await _assertCommuterRole(response.user);
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
  }) async {
    final normalized = PhoneUtils.normalize(mobile);
    try {
      final trimmedEmail = email.trim().toLowerCase();
      await _client.rpc('register_commuter', params: {
        'p_full_name': fullName.trim(),
        'p_mobile': normalized,
        'p_email': trimmedEmail.isEmpty ? null : trimmedEmail,
        'p_password': password,
      });
      // Account exists but stays pending until admin approval.
      throw AuthFlowException(
        'Account created. An administrator must approve your account before you can sign in.',
        isSuccessInfo: true,
      );
    } on AuthFlowException {
      rethrow;
    } on PostgrestException catch (e) {
      throw AuthFlowException(
        e.message.isNotEmpty
            ? e.message
            : AuthValidators.friendlyAuthError(e),
      );
    } on AuthException catch (e) {
      throw AuthFlowException(AuthValidators.friendlyAuthError(e));
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
    final identity = user.email ?? '';
    try {
      await _client.auth.signInWithPassword(
        email: identity,
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

  Future<void> _assertCommuterRole(User? user) async {
    if (user == null) return;
    final role = user.userMetadata?['role']?.toString();
    if (role != null && role != 'commuter') {
      await logout();
      throw AuthFlowException(
        'This account is not a passenger account. Use the driver app instead.',
      );
    }
  }

  Future<Commuter?> fetchCurrentCommuter() async {
    final user = currentUser;
    if (user == null) return null;

    final role = user.userMetadata?['role']?.toString();
    if (role != null && role != 'commuter') return null;

    final row = await _client
        .from('commuters')
        .select()
        .eq('commuter_id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return Commuter.fromJson(row);
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
