import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_validators.dart';
import '../../models/ride_booking.dart';
import '../../widgets/common_widgets.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<RideRequest> _requests = const [];
  List<BookingRecord> _bookings = const [];
  DateTime _serverNow = DateTime.now().toUtc();
  bool _loading = true;
  String? _error;
  String? _autoOpenedReviewFor;

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
      final repo = ref.read(customerRepositoryProvider);
      final results = await Future.wait([
        repo.fetchMyRideRequests(),
        repo.fetchMyBookings(),
      ]);
      if (!mounted) return;
      final bookings = results[1] as List<BookingRecord>;
      final now = DateTime.now().toUtc();
      setState(() {
        _requests = results[0] as List<RideRequest>;
        _bookings = bookings;
        _serverNow = now;
        _loading = false;
      });
      _maybeOpenPendingReview(bookings, now);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthValidators.friendlyError(e);
        _loading = false;
      });
    }
  }

  void _maybeOpenPendingReview(List<BookingRecord> bookings, DateTime now) {
    final pending = bookings.where((b) => b.reviewAvailable(now)).toList();
    if (pending.isEmpty) return;
    final target = pending.first;
    // Open once per booking while this screen session is alive; still available
    // from the list until the passenger submits.
    if (_autoOpenedReviewFor == target.id) return;
    _autoOpenedReviewFor = target.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go('/review?bookingId=${target.id}');
    });
  }

  Future<void> _reportBooking(BookingRecord booking) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report rider'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Reporting a finished trip disables review for this booking.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Describe the issue',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit report'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true || reason.isEmpty) {
      if (ok == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A reason is required.')),
        );
      }
      return;
    }
    try {
      await ref.read(customerRepositoryProvider).reportDriverBooking(
            bookingId: booking.id,
            reason: reason,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rider reported. Review is no longer available.'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthValidators.friendlyError(e))),
      );
    }
  }

  String _requestLabel(RideRequest r) {
    return switch (r.status) {
      'PENDING' => 'Pending Request',
      'ACCEPTED' => 'Request Accepted',
      'REJECTED' => 'Request Rejected',
      'EXPIRED' => 'Request Expired',
      'CANCELLED' => 'Cancelled',
      _ => r.status,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const GreenAppBar(title: 'History'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    children: [
                      const SectionTitle('Bookings'),
                      const SizedBox(height: 10),
                      if (_bookings.isEmpty)
                        Text(
                          'No bookings yet. Request a driver to get started.',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.textMuted,
                          ),
                        )
                      else
                        ..._bookings.map((b) {
                          final label = b.displayLabel(_serverNow);
                          final reviewReady = b.reviewAvailable(_serverNow);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(
                                b.driverName ?? 'Driver',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label),
                                  if (reviewReady)
                                    Row(
                                      children: [
                                        Text(
                                          'Review Available',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip:
                                              'Leave one review for this completed booking. PASAKAY does not use GPS or trip tracking.',
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (_) => AlertDialog(
                                                title: const Text('About reviews'),
                                                content: const Text(
                                                  "You're seeing this review prompt because this booking was confirmed after the driver accepted your request. PASAKAY does not use GPS or trip tracking to verify rides.",
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                    child: const Text('OK'),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.info_outline,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (b.canReportRider)
                                    TextButton(
                                      onPressed: () => _reportBooking(b),
                                      child: Text(
                                        'Report rider',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: AppColors.danger,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              trailing: reviewReady
                                  ? const Icon(Icons.star_rounded,
                                      color: AppColors.primary)
                                  : const Icon(Icons.chevron_right),
                              onTap: () {
                                if (reviewReady) {
                                  context.go('/review?bookingId=${b.id}');
                                } else {
                                  context.push('/driver/${b.driverId}');
                                }
                              },
                            ),
                          );
                        }),
                      const SizedBox(height: 22),
                      const SectionTitle('Requests'),
                      const SizedBox(height: 10),
                      if (_requests.isEmpty)
                        Text(
                          'No requests yet.',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.textMuted,
                          ),
                        )
                      else
                        ..._requests.map(
                          (r) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              r.driverName ?? 'Driver',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(_requestLabel(r)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/driver/${r.driverId}'),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
