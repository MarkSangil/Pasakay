import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/auth_validators.dart';
import '../../models/models.dart';
import '../../services/auth_service.dart';
import '../../services/customer_repository.dart';
import '../../services/push_notification_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final customerRepositoryProvider =
    Provider<CustomerRepository>((ref) => CustomerRepository());

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref.watch(customerRepositoryProvider));
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

class SessionController extends AsyncNotifier<Commuter?> {
  @override
  Future<Commuter?> build() async {
    ref.listen(authStateProvider, (_, next) {
      next.whenData((auth) {
        if (auth.event == AuthChangeEvent.signedOut) {
          // Keep a settled null session so auth screens are not remounted.
          if (state.hasValue && state.value == null) return;
          state = const AsyncData(null);
        } else if (auth.event == AuthChangeEvent.signedIn ||
            auth.event == AuthChangeEvent.initialSession) {
          // Silent refresh — do not flip to AsyncLoading (that used to bounce
          // login/signup to /splash and wipe in-form error messages).
          _refreshQuietly();
        }
      });
    });
    return _requireUsableSession(
      await ref.read(authServiceProvider).fetchCurrentCommuter(),
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return _requireUsableSession(
        await ref.read(authServiceProvider).fetchCurrentCommuter(),
      );
    });
  }

  Future<void> _refreshQuietly() async {
    try {
      final next = await _requireUsableSession(
        await ref.read(authServiceProvider).fetchCurrentCommuter(),
      );
      state = AsyncData(next);
    } catch (_) {
      state = const AsyncData(null);
    }
  }

  Future<void> login(String mobile, String password) async {
    try {
      await ref.read(authServiceProvider).login(
            mobile: mobile,
            password: password,
          );
      final commuter =
          await ref.read(authServiceProvider).fetchCurrentCommuter();
      if (commuter == null) {
        await ref.read(authServiceProvider).logout();
        throw AuthFlowException(
          'No passenger account found for these credentials. '
          'Use the driver app if you registered as a driver.',
        );
      }
      final allowed = await _requireLoginAllowed(commuter);
      state = AsyncData(allowed);
    } catch (error) {
      state = const AsyncData(null);
      if (error is AuthFlowException) rethrow;
      throw AuthFlowException(AuthValidators.friendlyAuthError(error));
    }
  }

  /// Session may include active + suspended. Deactivated / pending cannot stay signed in.
  Future<Commuter?> _requireUsableSession(Commuter? commuter) async {
    if (commuter == null) {
      if (ref.read(authServiceProvider).currentUser != null) {
        await ref.read(authServiceProvider).logout();
      }
      return null;
    }
    if (commuter.status == 'active' || commuter.status == 'suspended') {
      return commuter;
    }
    await ref.read(authServiceProvider).logout();
    return null;
  }

  Future<Commuter?> _requireLoginAllowed(Commuter? commuter) async {
    if (commuter == null) return null;
    if (commuter.status == 'active' || commuter.status == 'suspended') {
      return commuter;
    }
    await ref.read(authServiceProvider).logout();
    final detail =
        (commuter.statusReason == null || commuter.statusReason!.isEmpty)
            ? ''
            : ' ${commuter.statusReason}';
    throw AuthFlowException(
      switch (commuter.status) {
        'pending_verification' =>
          'Your account is waiting for administrator approval.$detail',
        'deactivated' => 'Your account has been deactivated.$detail',
        _ => 'This account cannot sign in.$detail',
      },
    );
  }

  Future<void> signUp({
    required String fullName,
    required String mobile,
    required String email,
    required String password,
  }) async {
    try {
      await ref.read(authServiceProvider).signUp(
            fullName: fullName,
            mobile: mobile,
            email: email,
            password: password,
          );
      state = const AsyncData(null);
    } catch (error) {
      state = const AsyncData(null);
      if (error is AuthFlowException) rethrow;
      throw AuthFlowException(AuthValidators.friendlyAuthError(error));
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return ref.read(authServiceProvider).changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
  }

  Future<void> logout() async {
    try {
      await ref.read(pushNotificationServiceProvider).stop();
    } catch (_) {}
    await ref.read(authServiceProvider).logout();
    state = const AsyncData(null);
  }
}

final sessionProvider =
    AsyncNotifierProvider<SessionController, Commuter?>(SessionController.new);

final pushRegistrationProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<Commuter?>>(
    sessionProvider,
    (previous, next) {
      if (next.isLoading || next.hasError) return;
      next.whenData((commuter) async {
        final push = ref.read(pushNotificationServiceProvider);
        if (commuter != null &&
            (commuter.status == 'active' || commuter.status == 'suspended')) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          await push.startForCommuter(commuter.id);
        } else if (previous?.value != null && commuter == null) {
          await push.stop();
        }
      });
    },
    fireImmediately: true,
  );
});
