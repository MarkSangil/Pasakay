import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

class DisputedBookingsScreen extends ConsumerStatefulWidget {
  const DisputedBookingsScreen({super.key});

  @override
  ConsumerState<DisputedBookingsScreen> createState() =>
      _DisputedBookingsScreenState();
}

class _DisputedBookingsScreenState
    extends ConsumerState<DisputedBookingsScreen> {
  late Future<List<FlaggedBookingRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(adminRepositoryProvider).fetchFlaggedBookings();
  }

  void _reload() {
    setState(() {
      _future = ref.read(adminRepositoryProvider).fetchFlaggedBookings();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FlaggedBookingRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Text(friendlyError(snapshot.error!)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            PageHeader(
              title: 'Disputed Bookings',
              subtitle:
                  'Driver FLAGGED disputes and passenger rider reports (auto-cancelled). '
                  'Restore marks a driver dispute completed; cancel voids it.',
              action: IconButton(
                onPressed: _reload,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
              ),
            ),
            const SizedBox(height: 16),
            DataCard(
              child: items.isEmpty
                  ? const EmptyState(message: 'No disputed bookings.')
                  : Column(
                      children: [
                        const TableHeader(
                          cells: ['Booking', 'Flagged', 'Reason', ''],
                        ),
                        for (final booking in items)
                          _Row(
                            booking: booking,
                            onRestore: () => _resolve(booking, 'restore'),
                            onCancel: () => _resolve(booking, 'cancel'),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resolve(FlaggedBookingRecord booking, String action) async {
    final restore = action == 'restore';
    final ok = await confirmAction(
      context,
      title: restore ? 'Restore booking?' : 'Cancel booking?',
      message: restore
          ? 'This marks the disputed booking as COMPLETED (valid trip).'
          : 'This cancels the booking. There is no undo.',
      confirmLabel: restore ? 'Restore' : 'Cancel booking',
      destructive: !restore,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).resolveDisputedBooking(
            bookingId: booking.id,
            action: action,
          );
      if (mounted) {
        showInfo(
          context,
          restore ? 'Booking restored as completed.' : 'Booking cancelled.',
        );
      }
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.booking,
    required this.onRestore,
    required this.onCancel,
  });

  final FlaggedBookingRecord booking;
  final VoidCallback onRestore;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${booking.commuterName ?? 'Commuter'} → ${booking.driverName ?? 'Driver'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (booking.isPassengerReport) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Passenger report · ${booking.status}',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Confirmed ${formatWhen(booking.confirmedAt)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'ID ${booking.id}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              formatWhen(booking.flaggedAt),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.flagReason ?? '—'),
                if (booking.flagDetails != null &&
                    booking.flagDetails!.trim().isNotEmpty)
                  Text(
                    booking.flagDetails!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: booking.isPassengerReport
                ? const Text(
                    'Already cancelled',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  )
                : Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                          onPressed: onRestore, child: const Text('Restore')),
                      TextButton(
                        onPressed: onCancel,
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.danger),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
