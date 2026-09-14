import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils/phone_utils.dart';
import '../models/models.dart';
import 'supabase_config.dart';

class AuthService {
  AuthService({SupabaseClient? client}) : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> login({
    required String emailOrPhone,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: PhoneUtils.toAuthEmail(emailOrPhone),
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String fullName,
    required String mobile,
    required String email,
    required String password,
  }) async {
    final authEmail = PhoneUtils.toAuthEmail(mobile);
    final response = await _client.auth.signUp(
      email: authEmail,
      password: password,
      data: {
        'full_name': fullName.trim(),
        'contact_number': PhoneUtils.normalize(mobile),
        'email_address': email.trim(),
        'username': PhoneUtils.normalize(mobile),
        'role': 'commuter',
      },
    );

    final user = response.user;
    if (user != null) {
      await _client.from('commuters').upsert({
        'commuter_id': user.id,
        'full_name': fullName.trim(),
        'contact_number': PhoneUtils.normalize(mobile),
        'email_address': email.trim(),
        'username': PhoneUtils.normalize(mobile),
      });
    }

    return response;
  }

  Future<void> logout() => _client.auth.signOut();

  Future<Commuter?> fetchCurrentCommuter() async {
    final user = currentUser;
    if (user == null) return null;

    final row = await _client
        .from('commuters')
        .select()
        .eq('commuter_id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return Commuter.fromJson(row);
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
