import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pasakay_customer/core/providers/session_provider.dart';
import 'package:pasakay_customer/features/history/history_screen.dart';
import 'package:pasakay_customer/models/ride_booking.dart';
import 'package:pasakay_customer/services/customer_repository.dart';

/// Controllable stand-in: futures complete only when the test says so.
class _FakeCustomerRepository extends CustomerRepository {
  _FakeCustomerRepository() : super.forTest();

  final requestsCompleter = Completer<List<RideRequest>>();
  final bookingsCompleter = Completer<List<BookingRecord>>();

  @override
  Future<List<RideRequest>> fetchMyRideRequests() => requestsCompleter.future;

  @override
  Future<List<BookingRecord>> fetchMyBookings() => bookingsCompleter.future;
}

BookingRecord _booking({required String id, required String status}) {
  final now = DateTime.now().toUtc();
  return BookingRecord(
    id: id,
    requestId: 'req-$id',
    commuterId: 'commuter-1',
    driverId: 'driver-1',
    status: status,
    confirmedAt: now.subtract(const Duration(minutes: 10)),
    reviewEligibleAt: now.subtract(const Duration(minutes: 5)),
    completedAt: status == 'COMPLETED' ? now : null,
    driverName: 'Tricycle Driver 3',
  );
}

_overrides(_FakeCustomerRepository repo) => [
  customerRepositoryProvider.overrideWithValue(repo),
];

void main() {
  setUpAll(() {
    // Widget tests have no network: fall back to bundled fonts.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('shows bookings once loading finishes', (tester) async {
    final repo = _FakeCustomerRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [customerRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repo.requestsCompleter.complete(<RideRequest>[]);
    repo.bookingsCompleter.complete([_booking(id: 'b1', status: 'BOOKED')]);
    await tester.pumpAndSettle();

    expect(find.text('Tricycle Driver 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing mid-load does not throw', (tester) async {
    final repo = _FakeCustomerRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [customerRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.pump(); // initState microtask starts _load

    // Replace the whole tree (disposing HistoryScreen) while requests fly.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('ELSEWHERE'))),
    );

    repo.requestsCompleter.complete(<RideRequest>[]);
    repo.bookingsCompleter.complete([_booking(id: 'b1', status: 'BOOKED')]);
    await tester.pumpAndSettle();

    expect(find.text('ELSEWHERE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an error message when loading fails', (tester) async {
    final repo = _FakeCustomerRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [customerRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );

    repo.requestsCompleter.completeError(Exception('network down'));
    repo.bookingsCompleter.complete(<BookingRecord>[]);
    await tester.pumpAndSettle();

    // friendlyError surfaces the message instead of a red screen.
    expect(find.textContaining('network down'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows empty state with no records', (tester) async {
    final repo = _FakeCustomerRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [customerRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );

    repo.requestsCompleter.complete(<RideRequest>[]);
    repo.bookingsCompleter.complete(<BookingRecord>[]);
    await tester.pumpAndSettle();

    expect(find.textContaining('No bookings yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-opens review for a completed booking', (tester) async {
    final repo = _FakeCustomerRepository();
    final router = GoRouter(
      initialLocation: '/history',
      routes: [
        GoRoute(
          path: '/history',
          builder: (context, state) => const HistoryScreen(),
        ),
        GoRoute(
          path: '/review',
          builder: (context, state) =>
              const Scaffold(body: Text('REVIEW STUB')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [customerRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    repo.requestsCompleter.complete(<RideRequest>[]);
    repo.bookingsCompleter.complete([_booking(id: 'b9', status: 'COMPLETED')]);
    await tester.pumpAndSettle();

    expect(find.text('REVIEW STUB'), findsOneWidget);
    expect(tester.takeException(), isNull);

    router.dispose();
    await tester.pump();
  });
}
