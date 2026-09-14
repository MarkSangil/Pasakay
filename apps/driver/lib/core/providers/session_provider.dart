import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/driver.dart';
import '../../services/auth_service.dart';
import '../../services/driver_repository.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final driverRepositoryProvider =
    Provider<DriverRepository>((ref) => DriverRepository());

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

class SessionController extends AsyncNotifier<Driver?> {
  @override
  Future<Driver?> build() async {
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
    return _requireActive(
      await ref.read(authServiceProvider).fetchCurrentDriver(),
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return _requireActive(
        await ref.read(authServiceProvider).fetchCurrentDriver(),
      );
    });
  }

  Future<void> login(String mobile, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authServiceProvider).login(
            mobile: mobile,
            password: password,
          );
      return _requireActive(
        await ref.read(authServiceProvider).fetchCurrentDriver(),
      );
    });
  }

  Future<void> signUp({
    required String fullName,
    required String mobile,
    required String email,
    required String password,
    required String licenseNumber,
    required String plateNumber,
    String? assignedTerminalId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authServiceProvider).signUp(
            fullName: fullName,
            mobile: mobile,
            email: email,
            password: password,
            licenseNumber: licenseNumber,
            plateNumber: plateNumber,
            assignedTerminalId: assignedTerminalId,
          );
      final driver = await ref.read(authServiceProvider).fetchCurrentDriver();
      return _requireActive(driver);
    });
  }

  Future<Driver?> _requireActive(Driver? driver) async {
    if (driver == null || driver.status == 'active') return driver;
    await ref.read(authServiceProvider).logout();
    throw Exception(_blockedMessage(driver.status, driver.statusReason));
  }

  String _blockedMessage(String status, String? reason) {
    final detail = (reason == null || reason.isEmpty) ? '' : ' $reason';
    return switch (status) {
      'pending_verification' =>
        'Your account is waiting for an administrator to visually verify your license.$detail',
      'suspended' => 'Your account is suspended.$detail',
      'deactivated' => 'Your account has been deactivated.$detail',
      _ => 'This account cannot sign in.$detail',
    };
  }

  Future<void> selectTerminal(String terminalId) async {
    await ref.read(authServiceProvider).updateCurrentTerminal(terminalId);
    await refresh();
  }

  Future<void> logout() async {
    await ref.read(authServiceProvider).logout();
    state = const AsyncData(null);
  }
}

final sessionProvider =
    AsyncNotifierProvider<SessionController, Driver?>(SessionController.new);
