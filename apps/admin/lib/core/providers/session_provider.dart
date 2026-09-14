import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/admin_models.dart';
import '../../services/admin_repository.dart';
import '../../services/supabase_config.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository();
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return SupabaseConfig.client.auth.onAuthStateChange;
});

class SessionController extends AsyncNotifier<AdminProfile?> {
  @override
  Future<AdminProfile?> build() async {
    ref.listen(authStateProvider, (_, next) {
      next.whenData((auth) {
        if (auth.event == AuthChangeEvent.signedOut) {
          state = const AsyncData(null);
        } else if (auth.event == AuthChangeEvent.signedIn ||
            auth.event == AuthChangeEvent.initialSession) {
          refresh();
        }
      });
    });
    return _load();
  }

  Future<AdminProfile?> _load() async {
    final admin = await ref.read(adminRepositoryProvider).fetchCurrentAdmin();
    if (admin == null && SupabaseConfig.client.auth.currentUser != null) {
      await SupabaseConfig.client.auth.signOut();
    }
    return admin;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    final next = await AsyncValue.guard(() async {
      await SupabaseConfig.client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final admin = await ref.read(adminRepositoryProvider).fetchCurrentAdmin();
      if (admin == null) {
        await SupabaseConfig.client.auth.signOut();
        throw Exception('This account is not an active system administrator.');
      }
      return admin;
    });
    state = next;
    if (next.hasError) throw next.error!;
  }

  Future<void> logout() async {
    await SupabaseConfig.client.auth.signOut();
    state = const AsyncData(null);
  }
}

final sessionProvider =
    AsyncNotifierProvider<SessionController, AdminProfile?>(
  SessionController.new,
);
