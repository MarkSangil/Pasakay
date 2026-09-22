import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

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
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(driverRepositoryProvider);
      await repo.fetchBookingSettings();
      final booking = await repo.fetchBooking(widget.bookingId);
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

  Future<void> _flag() async {
    final result = await showDialog<_FlagResult>(
      context: context,
      builder: (context) => const _FlagDialog(),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(driverRepositoryProvider).flagBooking(
            bookingId: widget.bookingId,
            reason: result.reason,
            details: result.details,
          );
      if (!mounted) return;
      setState(() => _booking = updated);
      ref.read(bookingsRefreshProvider.notifier).bump();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking reported for review.')),
      );
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
    final mobile = _booking?.commuterMobile;
    final auth = ref.read(authServiceProvider);
    final ok = call ? await auth.openCall(mobile) : await auth.openSms(mobile);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (mobile == null || mobile.trim().isEmpty)
                ? 'No passenger phone number available.'
                : 'Could not open the ${call ? 'phone' : 'messages'} app.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = _booking;

    return Scaffold(
      appBar: DriverAppBar(
        title: 'Booking Details',
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
                      onFlag: _flag,
                      onComplete: _complete,
                      onCall: () => _contact(call: true),
                      onMessage: () => _contact(call: false),
                      onBackToBookings: () => context.go('/bookings'),
                    ),
    );
  }

  Future<void> _complete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish booking?'),
        content: const Text(
          'Mark this trip as finished so you can accept another request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finish booking'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final updated =
          await ref.read(driverRepositoryProvider).completeBooking(widget.bookingId);
      if (!mounted) return;
      setState(() => _booking = updated);
      ref.read(bookingsRefreshProvider.notifier).bump();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking finished. You can accept another request.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({
    required this.booking,
    required this.busy,
    required this.onFlag,
    required this.onComplete,
    required this.onCall,
    required this.onMessage,
    required this.onBackToBookings,
  });

  final Booking booking;
  final bool busy;
  final VoidCallback onFlag;
  final VoidCallback onComplete;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onBackToBookings;

  @override
  Widget build(BuildContext context) {
    final badge = switch (booking.status) {
      BookingStatus.booked => (
          AppColors.successSoft,
          AppColors.success,
          booking.status.badgeLabel,
        ),
      BookingStatus.flagged => (
          AppColors.warningSoft,
          AppColors.warning,
          booking.status.badgeLabel,
        ),
      BookingStatus.completed => (
          AppColors.statusCompletedBg,
          AppColors.statusCompletedFg,
          booking.status.badgeLabel,
        ),
      BookingStatus.cancelled => (
          AppColors.dangerSoft,
          AppColors.danger,
          booking.status.badgeLabel,
        ),
    };
    final remaining = booking.disputeRemaining;

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
                  DateFormats.time.format(booking.confirmedAt.toLocal()),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  DateFormats.date.format(booking.confirmedAt.toLocal()),
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textSecondary,
                  ),
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
                            booking.displayName,
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          if (booking.status == BookingStatus.booked &&
                              booking.commuterMobile != null &&
                              booking.commuterMobile!.trim().isNotEmpty)
                            Text(
                              booking.commuterMobile!,
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            )
                          else if (booking.status != BookingStatus.booked)
                            Text(
                              'Contact hidden after booking ends',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (booking.status == BookingStatus.booked) ...[
                      IconButton(
                        onPressed: onMessage,
                        tooltip: 'Message',
                        icon: const Icon(
                          Icons.sms_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                      IconButton(
                        onPressed: onCall,
                        tooltip: 'Call',
                        icon: const Icon(
                          Icons.call_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                if (remaining != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warningSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'This booking stays active for '
                      '${_formatCountdown(remaining)}. '
                      'It will finish automatically afterward, or you can finish it early.',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
                if (booking.flagReason != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Flag reason',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    booking.flagReason!,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (booking.flagDetails != null &&
                      booking.flagDetails!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      booking.flagDetails!,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
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
            if (booking.canComplete) ...[
              ElevatedButton(
                onPressed: onComplete,
                child: const Text('Finish Booking'),
              ),
              const SizedBox(height: 10),
            ],
            if (booking.canFlag) ...[
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
                onPressed: onFlag,
                child: const Text('Report as Wrong / Not My Passenger'),
              ),
              const SizedBox(height: 10),
            ],
            if (booking.canComplete)
              OutlinedButton(
                onPressed: onBackToBookings,
                child: const Text('Back to Bookings'),
              )
            else
              ElevatedButton(
                onPressed: onBackToBookings,
                child: const Text('Back to Bookings'),
              ),
          ],
        ],
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

class _FlagDialog extends StatefulWidget {
  const _FlagDialog();

  @override
  State<_FlagDialog> createState() => _FlagDialogState();
}

class _FlagDialogState extends State<_FlagDialog> {
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
      title: const Text('Report booking'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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


