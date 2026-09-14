import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_formats.dart';
import '../../models/booking.dart';
import '../../models/driver.dart';
import '../../widgets/common_widgets.dart';

class BookingsRefresh extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final bookingsRefreshProvider =
    NotifierProvider<BookingsRefresh, int>(BookingsRefresh.new);

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Booking> _bookings = const [];
  DriverShift? _shift;
  bool _loading = true;
  int _unread = 0;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    await _load();
    final driver = ref.read(sessionProvider).value;
    if (driver == null) return;
    _channel?.unsubscribe();
    _channel = ref.read(driverRepositoryProvider).subscribeBookings(
          driverId: driver.id,
          onChange: (_) => _load(silent: true),
        );
  }

  Future<void> _load({bool silent = false}) async {
    final driver = ref.read(sessionProvider).value;
    if (driver == null) return;
    if (!silent) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final repo = ref.read(driverRepositoryProvider);
      final results = await Future.wait([
        repo.fetchBookings(driverId: driver.id),
        repo.fetchTodaysShift(driver.id),
        repo.unreadNotificationCount(driver.id),
      ]);
      if (!mounted) return;
      setState(() {
        _bookings = results[0] as List<Booking>;
        _shift = results[1] as DriverShift?;
        _unread = results[2] as int;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Keep chrome visible even if bookings table is unavailable.
      setState(() {
        _bookings = const [];
        _shift = null;
        _unread = 0;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _tabs.dispose();
    super.dispose();
  }

  List<Booking> _filtered(BookingStatus status) =>
      _bookings.where((b) => b.status == status).toList();

  @override
  Widget build(BuildContext context) {
    ref.listen(bookingsRefreshProvider, (_, __) => _load());
    final driver = ref.watch(sessionProvider).value;
    final upcoming = _filtered(BookingStatus.upcoming);
    final ongoing = _filtered(BookingStatus.ongoing);
    final completed = _filtered(BookingStatus.completed);
    final shiftLabel = _shift == null
        ? '${DateFormats.shiftHeader.format(DateTime.now())} • 6:00 AM - 2:00 PM'
        : '${DateFormats.shiftHeader.format(_shift!.shiftDate)} • ${DateFormats.timeRange(_shift!.startAt.toLocal(), _shift!.endAt.toLocal())}';
    final terminalName = driver?.currentTerminal?.name ??
        driver?.assignedTerminal?.name ??
        'Select terminal';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: DriverAppBar(
        title: 'Bookings This Shift',
        unreadCount: _unread,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              children: [
                Text(
                  shiftLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => context.push('/terminal'),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          terminalName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TabBar(
                  controller: _tabs,
                  tabs: [
                    Tab(text: 'Upcoming (${upcoming.length})'),
                    Tab(text: 'Ongoing (${ongoing.length})'),
                    Tab(text: 'Completed (${completed.length})'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _BookingList(items: upcoming, onRefresh: _load),
                      _BookingList(items: ongoing, onRefresh: _load),
                      _BookingList(items: completed, onRefresh: _load),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh List'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingList extends StatelessWidget {
  const _BookingList({required this.items, required this.onRefresh});

  final List<Booking> items;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No bookings in this tab.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final booking = items[index];
          return _BookingCard(booking: booking);
        },
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (booking.status) {
      BookingStatus.upcoming => (
          AppColors.successSoft,
          AppColors.success,
        ),
      BookingStatus.ongoing => (
          AppColors.warningSoft,
          AppColors.warning,
        ),
      BookingStatus.completed => (
          const Color(0xFFEEEEEE),
          AppColors.textSecondary,
        ),
      BookingStatus.cancelled => (
          AppColors.dangerSoft,
          AppColors.danger,
        ),
    };

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/booking/${booking.id}'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      DateFormats.time.format(booking.scheduledAt.toLocal()),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                booking.passengerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            StatusBadge(
                              label: booking.status.label,
                              background: statusColor.$1,
                              foreground: statusColor.$2,
                            ),
                          ],
                        ),
                        Text(
                          '${booking.passengerCount} passenger${booking.passengerCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _RouteLine(
                          pickup: booking.pickupTerminal?.name ?? 'Pickup',
                          dropoff: booking.dropoffTerminal?.name ?? 'Drop-off',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(120, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () => context.push('/booking/${booking.id}'),
                  child: const Text('View Details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({required this.pickup, required this.dropoff});

  final String pickup;
  final String dropoff;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.circle, size: 10, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pickup,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Container(
          margin: const EdgeInsets.only(left: 4),
          alignment: Alignment.centerLeft,
          height: 10,
          child: Container(width: 1.5, color: AppColors.border),
        ),
        Row(
          children: [
            const Icon(Icons.location_on, size: 12, color: AppColors.textPrimary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                dropoff,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
