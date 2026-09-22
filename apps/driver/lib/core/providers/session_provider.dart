import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/auth_validators.dart';
import '../../models/driver.dart';
import '../../services/auth_service.dart';
import '../../services/driver_repository.dart';
import '../../services/push_notification_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final driverRepositoryProvider =
    Provider<DriverRepository>((ref) => DriverRepository());

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref.watch(driverRepositoryProvider));
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

class SessionController extends AsyncNotifier<Driver?> {
  @override
  Future<Driver?> build() async {
    ref.listen(authStateProvider, (_, next) {
      next.whenData((auth) {
        if (auth.event == AuthChangeEvent.signedOut) {
          if (state.hasValue && state.value == null) return;
          state = const AsyncData(null);
        } else if (auth.event == AuthChangeEvent.signedIn ||
            auth.event == AuthChangeEvent.initialSession) {
          _refreshQuietly();
        }
      });
    });

    return _requireUsableSession(
      await ref.read(authServiceProvider).fetchCurrentDriver(),
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return _requireUsableSession(
        await ref.read(authServiceProvider).fetchCurrentDriver(),
      );
    });
  }

  Future<void> _refreshQuietly() async {
    try {
      final next = await _requireUsableSession(
        await ref.read(authServiceProvider).fetchCurrentDriver(),
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
      final driver = await ref.read(authServiceProvider).fetchCurrentDriver();
      if (driver == null) {
        await ref.read(authServiceProvider).logout();
        throw AuthFlowException(
          'No driver account found for these credentials. '
          'Use the passenger app if you registered as a commuter.',
        );
      }
      final allowed = await _requireLoginAllowed(driver);
      state = AsyncData(allowed);
    } catch (error) {
      state = const AsyncData(null);
      if (error is AuthFlowException) rethrow;
      throw AuthFlowException(AuthValidators.friendlyAuthError(error));
    }
  }

  Future<void> signUp({
    required String fullName,
    required String mobile,
    required String email,
    required String password,
    required String licenseNumber,
    required String plateNumber,
    required String assignedTerminalId,
  }) async {
    try {
      await ref.read(authServiceProvider).signUp(
            fullName: fullName,
            mobile: mobile,
            email: email,
            password: password,
            licenseNumber: licenseNumber,
            plateNumber: plateNumber,
            assignedTerminalId: assignedTerminalId,
          );
      state = const AsyncData(null);
    } catch (error) {
      state = const AsyncData(null);
      if (error is AuthFlowException) rethrow;
      throw AuthFlowException(AuthValidators.friendlyAuthError(error));
    }
  }

  /// Only active drivers may stay signed in. Suspended is replaced by
  /// deactivated; pending cannot sign in.
  Future<Driver?> _requireUsableSession(Driver? driver) async {
    if (driver == null) {
      if (ref.read(authServiceProvider).currentUser != null) {
        await ref.read(authServiceProvider).logout();
      }
      return null;
    }
    if (driver.status == 'active') {
      return driver;
    }
    await ref.read(authServiceProvider).logout();
    return null;
  }

  Future<Driver?> _requireLoginAllowed(Driver? driver) async {
    if (driver == null) return null;
    if (driver.status == 'active') {
      return driver;
    }
    await ref.read(authServiceProvider).logout();
    throw AuthFlowException(_blockedMessage(driver.status, driver.statusReason));
  }

  String _blockedMessage(String status, String? reason) {
    final detail = (reason == null || reason.isEmpty) ? '' : ' $reason';
    return switch (status) {
      'pending_verification' =>
        'Your account is waiting for an administrator to visually verify your license.$detail',
      'deactivated' || 'suspended' => 'Your account has been deactivated.$detail',
      _ => 'This account cannot sign in.$detail',
    };
  }

  Future<void> selectTerminal(String terminalId) async {
    await ref.read(authServiceProvider).updateCurrentTerminal(terminalId);
    await refresh();
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
    AsyncNotifierProvider<SessionController, Driver?>(SessionController.new);

class BookingsRefresh extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final bookingsRefreshProvider =
    NotifierProvider<BookingsRefresh, int>(BookingsRefresh.new);

/// Registers FCM + realtime heads-up when a usable driver session is present.
final pushRegistrationProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<Driver?>>(
    sessionProvider,
    (previous, next) {
      // Ignore loading/error transitions so we don't delete tokens mid-refresh.
      if (next.isLoading || next.hasError) return;
      next.whenData((driver) async {
        final push = ref.read(pushNotificationServiceProvider);
        push.onInboxChanged = () {
          ref.read(bookingsRefreshProvider.notifier).bump();
        };
        if (driver != null && driver.status == 'active') {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          await push.startForDriver(driver.id);
        } else if (previous?.value != null && driver == null) {
          await push.stop();
        }
      });
    },
    fireImmediately: true,
  );
});
