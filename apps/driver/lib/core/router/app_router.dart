import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/booking_details/booking_details_screen.dart';
import '../../features/bookings/bookings_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/recents/recents_screen.dart';
import '../../features/reviews/reviews_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/signup/signup_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/terminal_select/terminal_select_screen.dart';
import '../providers/session_provider.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionProvider);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: _RouterRefresh(ref),
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup' ||
          state.matchedLocation == '/splash';

      if (session.isLoading) {
        return state.matchedLocation == '/splash' ? null : '/splash';
      }

      final driver = session.value;
      final signedIn = driver != null;

      if (!signedIn && !loggingIn) return '/login';
      if (signedIn && (state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup' ||
          state.matchedLocation == '/splash')) {
        if (driver.currentTerminalId == null) return '/terminal';
        return '/bookings';
      }
      if (signedIn &&
          driver.currentTerminalId == null &&
          state.matchedLocation != '/terminal') {
        return '/terminal';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(
        path: '/terminal',
        builder: (_, __) => const TerminalSelectScreen(),
      ),
      GoRoute(
        path: '/booking/:id',
        builder: (_, state) => BookingDetailsScreen(
          bookingId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/bookings',
                builder: (_, __) => const BookingsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/recents',
                builder: (_, __) => const RecentsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reviews',
                builder: (_, __) => const ReviewsScreen(),
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
