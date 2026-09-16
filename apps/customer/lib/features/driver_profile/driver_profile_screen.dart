import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_utils.dart';
import '../../models/models.dart';
import '../../models/ride_booking.dart';
import '../../widgets/common_widgets.dart';

class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key, required this.driverId});

  final String driverId;

  @override
  ConsumerState<DriverProfileScreen> createState() =>
      _DriverProfileScreenState();
}

class _DriverProfileScreenState extends ConsumerState<DriverProfileScreen> {
  DriverSummary? _driver;
  DriverRequestContext? _ctx;
  bool _loading = true;
  bool _following = false;
  bool _followBusy = false;
  bool _requestBusy = false;
  String? _error;
  RealtimeChannel? _requestChannel;
  RealtimeChannel? _bookingChannel;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    unawaited(_requestChannel?.unsubscribe());
    unawaited(_bookingChannel?.unsubscribe());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(customerRepositoryProvider);
      final driver = await repo.fetchDriver(widget.driverId);
      final following = await repo.isFollowingDriver(widget.driverId);
      DriverRequestContext? ctx;
      if (driver != null) {
        ctx = await repo.fetchDriverRequestContext(widget.driverId);
      }
      if (!mounted) return;
      setState(() {
        _driver = driver;
        _following = following;
        _ctx = ctx;
        _loading = false;
        _error = driver == null ? 'Driver not found' : null;
      });
      _bindLiveUpdates();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshContext() async {
    try {
      final ctx = await ref
          .read(customerRepositoryProvider)
          .fetchDriverRequestContext(widget.driverId);
      if (!mounted) return;
      setState(() => _ctx = ctx);
      _syncPolling();
    } catch (_) {}
  }

  void _bindLiveUpdates() {
    final userId = ref.read(authServiceProvider).currentUser?.id;
    if (userId == null) return;

    final repo = ref.read(customerRepositoryProvider);
    unawaited(_requestChannel?.unsubscribe());
    unawaited(_bookingChannel?.unsubscribe());

    _requestChannel = repo.subscribeRideRequestUpdates(
      commuterId: userId,
      driverId: widget.driverId,
      onChange: (_) => unawaited(_refreshContext()),
    );
    _bookingChannel = repo.subscribeBookingUpdates(
      commuterId: userId,
      driverId: widget.driverId,
      onChange: (_) => unawaited(_refreshContext()),
    );
    _syncPolling();
  }

  void _syncPolling() {
    _pollTimer?.cancel();
    // While a request is pending, poll so the UI flips when the driver accepts
    // even if realtime is delayed.
    if (_ctx?.request?.status == 'PENDING') {
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        unawaited(_refreshContext());
      });
    }
  }

  Future<void> _toggleFollow() async {
    final driver = _driver;
    if (driver == null || _followBusy) return;
    setState(() => _followBusy = true);
    try {
      final repo = ref.read(customerRepositoryProvider);
      if (_following) {
        await repo.unfollowDriver(driver.id);
      } else {
        await repo.followDriver(driver.id);
      }
      if (!mounted) return;
      setState(() => _following = !_following);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  String get _requestLabel {
    final booking = _ctx?.booking;
    final req = _ctx?.request;
    if (req?.status == 'PENDING') return 'Request Pending';
    if (booking?.status == 'BOOKED') return 'Booking Confirmed';
    return 'Request';
  }

  bool get _hasActiveBooking => _ctx?.booking?.status == 'BOOKED';
  bool get _isSuspended =>
      ref.watch(sessionProvider).value?.status == 'suspended';

  Future<void> _sendRequest() async {
    final driver = _driver;
    if (driver == null || _requestBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send request?'),
        content: Text('Send request to ${driver.fullName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _requestBusy = true);
    try {
      await ref.read(customerRepositoryProvider).createRideRequest(driver.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent')),
      );
      await _load();
      _syncPolling();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('Exception:')
                ? e.toString().split('Exception:').last.trim()
                : 'Unable to send request. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _requestBusy = false);
    }
  }

  Future<void> _contact(String channel) async {
    final driver = _driver;
    final ctx = _ctx;
    final phone = ctx?.peerContact?.trim() ?? '';
    if (driver == null || ctx == null || !ctx.callSmsEnabled || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Driver contact is only available during an accepted booking.',
          ),
        ),
      );
      return;
    }
    await ref.read(customerRepositoryProvider).addRecent(
          RecentContact(
            driverId: driver.id,
            driverName: driver.fullName,
            terminalName: driver.terminalName ?? '',
            contactNumber: phone,
            at: DateTime.now(),
            channel: channel,
          ),
        );
    final auth = ref.read(authServiceProvider);
    final ok = channel == 'call'
        ? await auth.openCall(phone)
        : await auth.openSms(phone);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the ${channel == 'call' ? 'phone' : 'messages'} app.',
          ),
        ),
      );
    }
  }

  Future<void> _reportRider() async {
    final bookingId = _ctx?.reportableBookingId ?? _ctx?.booking?.id;
    if (bookingId == null || _requestBusy) return;
    final result = await showDialog<_ReportResult>(
      context: context,
      builder: (context) => const _ReportRiderDialog(),
    );
    if (result == null) return;
    setState(() => _requestBusy = true);
    try {
      await ref.read(customerRepositoryProvider).reportDriverBooking(
            bookingId: bookingId,
            reason: result.reason,
            details: result.details,
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
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _requestBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = _driver;
    final ctx = _ctx;
    final canRequest = ctx?.canRequest == true &&
        ctx?.request?.status != 'PENDING' &&
        !_hasActiveBooking &&
        !_isSuspended &&
        !_requestBusy;
    final showPending = ctx?.request?.status == 'PENDING';
    final callSms = ctx?.callSmsEnabled == true && _hasActiveBooking;
    final suspendedBanner = _isSuspended;
    final peerPhone = ctx?.peerContact?.trim() ?? '';
    final showPhone = callSms && peerPhone.isNotEmpty;
    final canReport = ctx?.canReport == true && !_requestBusy;
    final canReview = ctx?.canReview == true && !_requestBusy;
    final showReviewAction = canReview ||
        (ctx?.alreadyReviewed == true) ||
        (ctx?.alreadyReported == true &&
            ctx?.booking?.status == 'COMPLETED');
    final reviewEnabled = canReview;
    final reviewLabel = ctx?.alreadyReviewed == true
        ? 'Reviewed'
        : ctx?.alreadyReported == true
            ? 'Review unavailable'
            : 'Leave a review';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const GreenAppBar(title: 'Driver Profile', showBack: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                        children: [
                          const Center(child: AvatarCircle(size: 96)),
                          const SizedBox(height: 14),
                          Text(
                            driver!.fullName,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            driver.todaNumber == null ||
                                    driver.todaNumber!.isEmpty
                                ? 'SSLTODA No. —'
                                : 'SSLTODA No. ${driver.todaNumber}',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (ctx != null && !ctx.onShift) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Outside scheduled operating period',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          if (suspendedBanner) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Your account is suspended. You can browse but cannot send booking requests.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: 28),
                          _InfoRow(
                            icon: Icons.directions_car_outlined,
                            label: 'Plate Number',
                            value: driver.plateNumber,
                          ),
                          _InfoRow(
                            icon: Icons.phone_outlined,
                            label: 'Mobile Number',
                            value: showPhone
                                ? PhoneUtils.display(peerPhone)
                                : 'Visible during accepted booking only',
                          ),
                          _InfoRow(
                            icon: Icons.workspace_premium_outlined,
                            label: 'Years of Service',
                            value: driver.yearsOfService > 0
                                ? '${driver.yearsOfService} years'
                                : '—',
                          ),
                          _InfoRow(
                            icon: Icons.location_on_outlined,
                            label: 'Assigned Terminal',
                            value: driver.terminalName ?? '—',
                          ),
                          _InfoRow(
                            icon: Icons.schedule_outlined,
                            label: 'Current Schedule',
                            value: driver.shiftLabel ?? '—',
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton.icon(
                              onPressed: _followBusy ? null : _toggleFollow,
                              icon: Icon(
                                _following
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: AppColors.primary,
                              ),
                              label: Text(
                                _following
                                    ? 'Following — tap to unfollow'
                                    : 'Follow / Favorite',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: canRequest ? _sendRequest : null,
                                child: _requestBusy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        showPending
                                            ? 'Request Pending'
                                            : _requestLabel,
                                      ),
                              ),
                            ),
                            if (ctx?.reason != null &&
                                !canRequest &&
                                !showPending &&
                                !_hasActiveBooking)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  ctx!.reason!,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                            if (callSms) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _contact('call'),
                                      icon: const Icon(Icons.phone_rounded),
                                      label: const Text('Call'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _contact('sms'),
                                      icon: const Icon(Icons.sms_outlined),
                                      label: const Text('Message'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (showReviewAction) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: reviewEnabled
                                      ? () {
                                          final bookingId =
                                              ctx?.reviewableBookingId ??
                                                  ctx?.booking?.id;
                                          if (bookingId == null) return;
                                          context.go(
                                            '/review?bookingId=$bookingId',
                                          );
                                        }
                                      : null,
                                  icon: const Icon(Icons.star_outline_rounded),
                                  label: Text(reviewLabel),
                                ),
                              ),
                            ],
                            if (canReport) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.danger,
                                    side: const BorderSide(
                                      color: AppColors.danger,
                                    ),
                                  ),
                                  onPressed: _reportRider,
                                  icon: const Icon(Icons.flag_outlined),
                                  label: const Text('Report rider'),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Available after the booking finishes. Reporting disables review.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ReportResult {
  const _ReportResult({required this.reason, this.details});
  final String reason;
  final String? details;
}

abstract final class _RiderReportReasons {
  static const wrongDriver = 'Wrong / unexpected driver';
  static const unsafe = 'Unsafe or inappropriate behavior';
  static const noShow = 'Driver did not show up';
  static const other = 'Other';
  static const all = [wrongDriver, unsafe, noShow, other];
}

class _ReportRiderDialog extends StatefulWidget {
  const _ReportRiderDialog();

  @override
  State<_ReportRiderDialog> createState() => _ReportRiderDialogState();
}

class _ReportRiderDialogState extends State<_ReportRiderDialog> {
  String _reason = _RiderReportReasons.wrongDriver;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report rider'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reporting a finished trip disables review for this booking.',
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            for (final reason in _RiderReportReasons.all)
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(reason, style: const TextStyle(fontSize: 14)),
                value: reason,
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v!),
              ),
            if (_reason == _RiderReportReasons.other) ...[
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
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () {
            final details = _details.text.trim();
            if (_reason == _RiderReportReasons.other && details.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please add details for Other.')),
              );
              return;
            }
            Navigator.pop(
              context,
              _ReportResult(
                reason: _reason,
                details: details.isEmpty ? null : details,
              ),
            );
          },
          child: const Text('Submit report'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
