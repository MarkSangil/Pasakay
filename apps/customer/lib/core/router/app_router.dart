import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/driver_list/driver_list_screen.dart';
import '../../features/driver_profile/driver_profile_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/review/review_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/terminals/terminals_screen.dart';
import '../providers/session_provider.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(sessionProvider, (_, __) => refresh.tick());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      final onAuth =
          loc == '/login' || loc == '/signup' || loc == '/splash';

      // Stay on login/signup while session resolves so form errors remain visible.
      if (session.isLoading) {
        if (onAuth && loc != '/splash') return null;
        return loc == '/splash' ? null : '/splash';
      }

      final signedIn = session.value != null;

      if (!signedIn && !onAuth) return '/login';
      if (signedIn && onAuth) return '/terminals';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/terminal/:id',
        builder: (_, state) => DriverListScreen(
          terminalId: state.pathParameters['id']!,
          terminalName: state.uri.queryParameters['name'] ?? 'Terminal',
        ),
      ),
      GoRoute(
        path: '/driver/:id',
        builder: (_, state) => DriverProfileScreen(
          driverId: state.pathParameters['id']!,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/terminals',
                builder: (_, __) => const TerminalsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (_, __) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/review',
                builder: (_, state) => ReviewScreen(
                  bookingId: state.uri.queryParameters['bookingId'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, __) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _RouterRefresh extends ChangeNotifier {
  void tick() => notifyListeners();
}
