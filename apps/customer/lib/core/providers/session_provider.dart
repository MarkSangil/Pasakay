import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/customer_repository.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final customerRepositoryProvider =
    Provider<CustomerRepository>((ref) => CustomerRepository());

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

class SessionController extends AsyncNotifier<Commuter?> {
  @override
  Future<Commuter?> build() async {
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
    return ref.read(authServiceProvider).fetchCurrentCommuter();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).fetchCurrentCommuter(),
    );
  }

  Future<void> login(String emailOrPhone, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authServiceProvider).login(
            emailOrPhone: emailOrPhone,
            password: password,
          );
      return _requireActive(
        await ref.read(authServiceProvider).fetchCurrentCommuter(),
      );
    });
  }

  Future<Commuter?> _requireActive(Commuter? commuter) async {
    if (commuter == null || commuter.status == 'active') return commuter;
    await ref.read(authServiceProvider).logout();
    final detail = (commuter.statusReason == null || commuter.statusReason!.isEmpty)
        ? ''
        : ' ${commuter.statusReason}';
    throw Exception(
      commuter.status == 'suspended'
          ? 'Your account is suspended.$detail'
          : 'Your account has been deactivated.$detail',
    );
  }

  Future<void> signUp({
    required String fullName,
    required String mobile,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authServiceProvider).signUp(
            fullName: fullName,
            mobile: mobile,
            email: email,
            password: password,
          );
      return ref.read(authServiceProvider).fetchCurrentCommuter();
    });
  }

  Future<void> logout() async {
    await ref.read(authServiceProvider).logout();
    state = const AsyncData(null);
  }
}

final sessionProvider =
    AsyncNotifierProvider<SessionController, Commuter?>(SessionController.new);
