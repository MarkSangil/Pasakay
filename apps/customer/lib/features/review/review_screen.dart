import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/ride_booking.dart';
import '../../widgets/common_widgets.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, this.bookingId});

  final String? bookingId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _reviewCtrl = TextEditingController();
  int _rating = 0;
  List<BookingRecord> _eligible = const [];
  String? _selectedBookingId;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedBookingId = widget.bookingId;
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(customerRepositoryProvider);
    final bookings = await repo.fetchMyBookings();
    final now = DateTime.now().toUtc();
    final eligible =
        bookings.where((b) => b.reviewAvailable(now)).toList(growable: false);
    if (!mounted) return;
    setState(() {
      _eligible = eligible;
      _selectedBookingId ??=
          eligible.isNotEmpty ? eligible.first.id : widget.bookingId;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    final bookingId = _selectedBookingId;
    if (bookingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No booking available to review.')),
      );
      return;
    }
    if (_rating < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap a star rating first.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(customerRepositoryProvider).submitBookingReview(
            bookingId: bookingId,
            rating: _rating,
            content: _reviewCtrl.text,
          );
      if (!mounted) return;
      _reviewCtrl.clear();
      setState(() => _rating = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for your review!')),
      );
      await _load();
      if (!mounted) return;
      if (_eligible.isEmpty) {
        context.go('/history');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const GreenAppBar(title: 'Review'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                Row(
                  children: [
                    Text(
                      'Rate your experience',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    IconButton(
                      tooltip:
                          "You're seeing this review prompt because this booking was confirmed after the driver accepted your request. PASAKAY does not use GPS or trip tracking to verify rides.",
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
                                onPressed: () => Navigator.pop(context),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.info_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_eligible.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _selectedBookingId,
                    decoration: const InputDecoration(
                      labelText: 'Completed booking',
                    ),
                    items: _eligible
                        .map(
                          (b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(b.driverName ?? 'Driver'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedBookingId = v),
                  )
                else
                  Text(
                    'No completed bookings left to review. Reported trips and already-reviewed bookings cannot be reviewed.',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textMuted,
                    ),
                  ),
                const SizedBox(height: 14),
                StarRating(
                  value: _rating,
                  size: 36,
                  onChanged: _eligible.isEmpty
                      ? null
                      : (v) => setState(() => _rating = v),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _reviewCtrl,
                  maxLines: 4,
                  maxLength: 300,
                  enabled: _eligible.isNotEmpty,
                  decoration: const InputDecoration(
                    hintText: 'Write your review (optional)',
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed:
                      _submitting || _eligible.isEmpty ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit Review'),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => context.go('/history'),
                  child: const Text('Open History'),
                ),
              ],
            ),
    );
  }
}
