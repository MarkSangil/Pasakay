import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/driver_list/driver_list_screen.dart';
import '../../features/driver_profile/driver_profile_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/recent/recent_screen.dart';
import '../../features/review/review_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/terminals/terminals_screen.dart';
import '../providers/session_provider.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionProvider);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: _RouterRefresh(ref),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final loggingIn =
          loc == '/login' || loc == '/signup' || loc == '/splash';

      if (session.isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      final signedIn = session.value != null;

      if (!signedIn && !loggingIn) return '/login';
      if (signedIn && loggingIn) return '/terminals';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
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
                path: '/recent',
                builder: (_, __) => const RecentScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/review',
                builder: (_, __) => const ReviewScreen(),
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
  _RouterRefresh(this._ref) {
    _ref.listen(sessionProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;
}
