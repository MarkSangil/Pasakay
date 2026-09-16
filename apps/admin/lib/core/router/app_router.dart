import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/commuters/commuters_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/disputes/disputed_bookings_screen.dart';
import '../../features/disputes/review_reports_screen.dart';
import '../../features/drivers/driver_detail_screen.dart';
import '../../features/drivers/drivers_screen.dart';
import '../../features/reviews/reviews_screen.dart';
import '../../features/settings/booking_settings_screen.dart';
import '../../features/shell/admin_shell.dart';
import '../../features/shifts/shifts_screen.dart';
import '../../features/terminals/terminals_screen.dart';
import '../providers/session_provider.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionProvider);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/overview',
    refreshListenable: _RouterRefresh(ref),
    redirect: (context, state) {
      final loading = session.isLoading;
      final signedIn = session.value != null;
      final loggingIn = state.matchedLocation == '/login';

      if (loading) return null;
      if (!signedIn && !loggingIn) return '/login';
      if (signedIn && loggingIn) return '/overview';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(path: '/overview', builder: (_, _) => const DashboardScreen()),
          GoRoute(path: '/drivers', builder: (_, _) => const DriversScreen()),
          GoRoute(
            path: '/drivers/:id',
            builder: (_, state) => DriverDetailScreen(
              driverId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(path: '/terminals', builder: (_, _) => const TerminalsScreen()),
          GoRoute(path: '/shifts', builder: (_, _) => const ShiftsScreen()),
          GoRoute(
            path: '/booking-settings',
            builder: (_, _) => const BookingSettingsScreen(),
          ),
          GoRoute(path: '/commuters', builder: (_, _) => const CommutersScreen()),
          GoRoute(path: '/reviews', builder: (_, _) => const ReviewsScreen()),
          GoRoute(
            path: '/disputed-bookings',
            builder: (_, _) => const DisputedBookingsScreen(),
          ),
          GoRoute(
            path: '/review-reports',
            builder: (_, _) => const ReviewReportsScreen(),
          ),
        ],
      ),
    ],
  );
});

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(this.ref) {
    ref.listen(sessionProvider, (_, _) => notifyListeners());
  }

  final Ref ref;
}
