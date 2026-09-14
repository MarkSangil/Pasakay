import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_formats.dart';
import '../../models/booking.dart';
import '../../widgets/common_widgets.dart';
import '../bookings/bookings_screen.dart';

class BookingDetailsScreen extends ConsumerStatefulWidget {
  const BookingDetailsScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<BookingDetailsScreen> createState() =>
      _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends ConsumerState<BookingDetailsScreen> {
  Booking? _booking;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final booking =
          await ref.read(driverRepositoryProvider).fetchBooking(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _loading = false;
        if (booking == null) _error = 'Booking not found.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final updated =
          await ref.read(driverRepositoryProvider).startTrip(widget.bookingId);
      setState(() => _booking = updated);
      ref.read(bookingsRefreshProvider.notifier).bump();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() async {
    setState(() => _busy = true);
    try {
      final updated =
          await ref.read(driverRepositoryProvider).completeTrip(widget.bookingId);
      setState(() => _booking = updated);
      ref.read(bookingsRefreshProvider.notifier).bump();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel trip?'),
        content: const Text('This will mark the booking as cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final updated =
          await ref.read(driverRepositoryProvider).cancelTrip(widget.bookingId);
      setState(() => _booking = updated);
      ref.read(bookingsRefreshProvider.notifier).bump();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contact({required bool call}) async {
    final mobile = _booking?.passengerMobile;
    final auth = ref.read(authServiceProvider);
    if (call) {
      await auth.openCall(mobile);
    } else {
      await auth.openSms(mobile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = _booking;
    final title = switch (booking?.status) {
      BookingStatus.ongoing => 'Trip Ongoing',
      BookingStatus.completed => 'Trip Completed',
      _ => 'Booking Details',
    };

    return Scaffold(
      appBar: DriverAppBar(
        title: title,
        showMenu: false,
        onBack: () => context.pop(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : booking == null
                  ? const SizedBox.shrink()
                  : _DetailsBody(
                      booking: booking,
                      busy: _busy,
                      onStart: _start,
                      onComplete: _complete,
                      onCancel: _cancel,
                      onCall: () => _contact(call: true),
                      onMessage: () => _contact(call: false),
                      onBackToBookings: () => context.go('/bookings'),
                    ),
    );
  }
}

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({
    required this.booking,
    required this.busy,
    required this.onStart,
    required this.onComplete,
    required this.onCancel,
    required this.onCall,
    required this.onMessage,
    required this.onBackToBookings,
  });

  final Booking booking;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onBackToBookings;

  @override
  Widget build(BuildContext context) {
    final badge = switch (booking.status) {
      BookingStatus.upcoming => (
          AppColors.successSoft,
          AppColors.success,
          booking.status.badgeLabel,
        ),
      BookingStatus.ongoing => (
          AppColors.warningSoft,
          AppColors.warning,
          booking.status.badgeLabel,
        ),
      BookingStatus.completed => (
          const Color(0xFFEEEEEE),
          AppColors.textSecondary,
          booking.status.badgeLabel,
        ),
      BookingStatus.cancelled => (
          AppColors.dangerSoft,
          AppColors.danger,
          booking.status.badgeLabel,
        ),
    };

    final fare = NumberFormat.currency(locale: 'en_PH', symbol: '₱')
        .format(booking.actualFare ?? booking.estimatedFare);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusBadge(
                  label: badge.$3,
                  background: badge.$1,
                  foreground: badge.$2,
                ),
                const SizedBox(height: 16),
                Text(
                  DateFormats.time.format(booking.scheduledAt.toLocal()),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  DateFormats.date.format(booking.scheduledAt.toLocal()),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.border,
                      child: Icon(Icons.person, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            booking.passengerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${booking.passengerCount} passenger${booking.passengerCount == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onMessage,
                      tooltip: 'Message',
                      icon: const Icon(Icons.sms_outlined, color: AppColors.primary),
                    ),
                    IconButton(
                      onPressed: onCall,
                      tooltip: 'Call',
                      icon: const Icon(Icons.call_outlined, color: AppColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (booking.status != BookingStatus.completed) ...[
                  _VerticalRoute(booking: booking),
                ] else ...[
                  _HorizontalRoute(booking: booking),
                ],
                if (booking.status == BookingStatus.ongoing) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_car_filled_outlined,
                            color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Trip Status: ${booking.tripStatusNote ?? 'In progress'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (booking.notes != null && booking.notes!.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Booking Notes',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    booking.notes!,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  booking.status == BookingStatus.completed
                      ? 'Actual Fare Collected'
                      : 'Estimated Fare',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                Text(
                  fare,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: booking.status == BookingStatus.completed
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            )
          else ...[
            if (booking.status == BookingStatus.upcoming) ...[
              ElevatedButton(
                onPressed: onStart,
                child: const Text('Start Trip'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onCall,
                icon: const Icon(Icons.phone_outlined),
                label: const Text('Contact Passenger'),
              ),
            ],
            if (booking.status == BookingStatus.ongoing) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                      onPressed: onCancel,
                      child: const Text('Cancel Trip'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onComplete,
                      child: const Text('Mark as Completed'),
                    ),
                  ),
                ],
              ),
            ],
            if (booking.status == BookingStatus.completed) ...[
              OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Receipt view coming soon.')),
                  );
                },
                child: const Text('View Receipt'),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: onBackToBookings,
                child: const Text('Back to Bookings'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _VerticalRoute extends StatelessWidget {
  const _VerticalRoute({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _point(
          icon: Icons.circle,
          color: AppColors.success,
          title: booking.pickupTerminal?.name ?? 'Pickup',
          subtitle: booking.pickupTerminal?.city ?? 'Antipolo City',
        ),
        Container(
          margin: const EdgeInsets.only(left: 7),
          alignment: Alignment.centerLeft,
          height: 24,
          child: Container(width: 2, color: AppColors.border),
        ),
        _point(
          icon: Icons.location_on,
          color: AppColors.textPrimary,
          title: booking.dropoffTerminal?.name ?? 'Drop-off',
          subtitle: booking.dropoffTerminal?.city ?? 'Antipolo City',
        ),
      ],
    );
  }

  Widget _point({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _HorizontalRoute extends StatelessWidget {
  const _HorizontalRoute({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            booking.pickupTerminal?.name ?? 'Pickup',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        const Icon(Icons.arrow_forward_rounded, color: AppColors.primary),
        Expanded(
          child: Text(
            booking.dropoffTerminal?.name ?? 'Drop-off',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
