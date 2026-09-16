import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_formats.dart';
import '../../models/booking.dart';
import '../../models/driver.dart';
import '../../widgets/common_widgets.dart';

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs;
  List<RideRequest> _requests = const [];
  List<Booking> _bookings = const [];
  DriverShift? _shift;
  bool _loading = true;
  int _unread = 0;
  RealtimeChannel? _requestChannel;
  RealtimeChannel? _bookingChannel;
  Timer? _tick;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_load(silent: true));
    });
    Future.microtask(_bootstrap);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load(silent: true));
    }
  }

  Future<void> _bootstrap() async {
    await _load();
    final driver = ref.read(sessionProvider).value;
    if (driver == null) return;
    final repo = ref.read(driverRepositoryProvider);
    _requestChannel?.unsubscribe();
    _bookingChannel?.unsubscribe();
    _requestChannel = repo.subscribeRideRequests(
      driverId: driver.id,
      onChange: (_) => _load(silent: true),
    );
    _bookingChannel = repo.subscribeBookings(
      driverId: driver.id,
      onChange: (_) => _load(silent: true),
    );
  }

  Future<void> _load({bool silent = false}) async {
    final driver = ref.read(sessionProvider).value;
    if (driver == null) return;
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final repo = ref.read(driverRepositoryProvider);
      await repo.fetchBookingSettings();
      final requests = await repo.fetchRideRequests(
        driverId: driver.id,
        status: RideRequestStatus.pending,
      );
      final bookings = await repo.fetchBookings(driverId: driver.id);
      DriverShift? shift;
      try {
        shift = await repo.fetchTodaysShift(driver.id);
      } catch (_) {
        shift = null;
      }
      final unread = await repo.unreadNotificationCount(driver.id);
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _bookings = bookings;
        _shift = shift;
        _unread = unread;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Bookings load failed: $e');
      if (!mounted) return;
      if (!silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _accept(RideRequest request) async {
    try {
      await ref.read(driverRepositoryProvider).acceptRideRequest(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request accepted. Booking confirmed.')),
      );
      await _load(silent: true);
      _tabs.animateTo(1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _reject(RideRequest request) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject request?'),
        content: Text('${request.displayName} will be notified.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(driverRepositoryProvider).rejectRideRequest(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request rejected.')),
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _flag(Booking booking) async {
    final result = await showDialog<_FlagResult>(
      context: context,
      builder: (context) => const _FlagBookingDialog(),
    );
    if (result == null) return;
    try {
      await ref.read(driverRepositoryProvider).flagBooking(
            bookingId: booking.id,
            reason: result.reason,
            details: result.details,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking reported for review.')),
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _poll?.cancel();
    _requestChannel?.unsubscribe();
    _bookingChannel?.unsubscribe();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(bookingsRefreshProvider, (_, __) => _load(silent: true));
    final driver = ref.watch(sessionProvider).value;
    final shiftLabel = _shift == null
        ? '${DateFormats.shiftHeader.format(DateTime.now())} • On shift'
        : '${DateFormats.shiftHeader.format(_shift!.shiftDate)} • ${DateFormats.timeRange(_shift!.startAt.toLocal(), _shift!.endAt.toLocal())}';
    final terminalName = driver?.currentTerminal?.name ??
        driver?.assignedTerminal?.name ??
        'Select terminal';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: DriverAppBar(
        title: 'Requests & Bookings',
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
                  style: GoogleFonts.plusJakartaSans(
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
                          style: GoogleFonts.plusJakartaSans(
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
                    Tab(text: 'Requests (${_requests.length})'),
                    Tab(text: 'Bookings (${_bookings.length})'),
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
                      _RequestList(
                        items: _requests,
                        onRefresh: _load,
                        onAccept: _accept,
                        onReject: _reject,
                      ),
                      _BookingList(
                        items: _bookings,
                        onRefresh: _load,
                        onFlag: _flag,
                      ),
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

class _RequestList extends StatelessWidget {
  const _RequestList({
    required this.items,
    required this.onRefresh,
    required this.onAccept,
    required this.onReject,
  });

  final List<RideRequest> items;
  final Future<void> Function() onRefresh;
  final Future<void> Function(RideRequest) onAccept;
  final Future<void> Function(RideRequest) onReject;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No pending requests.',
          style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted),
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
          final request = items[index];
          return _RequestCard(
            request: request,
            onAccept: () => onAccept(request),
            onReject: () => onReject(request),
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  final RideRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.displayName,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              StatusBadge(
                label: request.status.label,
                background: AppColors.warningSoft,
                foreground: AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Requested ${DateFormats.time.format(request.createdAt.toLocal())}'
            ' · Expires ${DateFormats.time.format(request.expiresAt.toLocal())}',
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  onPressed: onReject,
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BookingList extends StatelessWidget {
  const _BookingList({
    required this.items,
    required this.onRefresh,
    required this.onFlag,
  });

  final List<Booking> items;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Booking) onFlag;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No bookings yet.',
          style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted),
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
          return _BookingCard(
            booking: booking,
            onFlag: () => onFlag(booking),
          );
        },
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.onFlag});

  final Booking booking;
  final VoidCallback onFlag;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (booking.status) {
      BookingStatus.booked => (AppColors.successSoft, AppColors.success),
      BookingStatus.flagged => (AppColors.warningSoft, AppColors.warning),
      BookingStatus.completed => (
          AppColors.statusCompletedBg,
          AppColors.statusCompletedFg,
        ),
      BookingStatus.cancelled => (AppColors.dangerSoft, AppColors.danger),
    };
    final remaining = booking.disputeRemaining;

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
                      DateFormats.time.format(booking.confirmedAt.toLocal()),
                      style: GoogleFonts.plusJakartaSans(
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
                                booking.displayName,
                                style: GoogleFonts.plusJakartaSans(
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
                        const SizedBox(height: 4),
                        Text(
                          booking.status == BookingStatus.booked
                              ? 'Confirmed booking'
                              : booking.status.badgeLabel,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        if (remaining != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Auto-finishes in ${_formatCountdown(remaining)}',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.warning,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (booking.flagReason != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Reason: ${booking.flagReason}',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (booking.canFlag)
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: onFlag,
                        child: const Text('Report as Wrong'),
                      ),
                    ),
                  if (booking.canFlag) const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () => context.push('/booking/${booking.id}'),
                      child: const Text('View Details'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatCountdown(Duration d) {
  final total = d.inSeconds.clamp(0, 24 * 3600);
  final m = (total ~/ 60).toString().padLeft(2, '0');
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

class _FlagResult {
  const _FlagResult({required this.reason, this.details});
  final String reason;
  final String? details;
}

class _FlagBookingDialog extends StatefulWidget {
  const _FlagBookingDialog();

  @override
  State<_FlagBookingDialog> createState() => _FlagBookingDialogState();
}

class _FlagBookingDialogState extends State<_FlagBookingDialog> {
  String _reason = BookingFlagReasons.notMyPassenger;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report as Wrong / Not My Passenger'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final reason in BookingFlagReasons.all)
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(reason, style: const TextStyle(fontSize: 14)),
                value: reason,
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v!),
              ),
            if (_reason == BookingFlagReasons.other) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _details,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Details',
                  hintText: 'Describe the issue',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final details = _details.text.trim();
            if (_reason == BookingFlagReasons.other && details.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please add details for Other.')),
              );
              return;
            }
            Navigator.pop(
              context,
              _FlagResult(
                reason: _reason,
                details: details.isEmpty ? null : details,
              ),
            );
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
