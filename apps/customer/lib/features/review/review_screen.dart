import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../widgets/common_widgets.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _reviewCtrl = TextEditingController();
  int _rating = 0;
  String? _selectedDriverId;
  List<RecentContact> _recent = const [];
  List<DriverReview> _myReviews = const [];
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(customerRepositoryProvider);
    final recent = await repo.loadRecent();
    final reviews = await repo.fetchMyReviews();
    if (!mounted) return;
    setState(() {
      _recent = recent;
      _myReviews = reviews;
      _selectedDriverId ??= recent.isNotEmpty ? recent.first.driverId : null;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (_selectedDriverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a recent driver to review.')),
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
      await ref.read(customerRepositoryProvider).submitReview(
            driverId: _selectedDriverId!,
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
    final uniqueRecent = <String, RecentContact>{};
    for (final r in _recent) {
      uniqueRecent.putIfAbsent(r.driverId, () => r);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const GreenAppBar(title: 'Review'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                Text(
                  'Rate your experience',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                if (uniqueRecent.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDriverId,
                    decoration: const InputDecoration(
                      labelText: 'Driver',
                    ),
                    items: uniqueRecent.values
                        .map(
                          (d) => DropdownMenuItem(
                            value: d.driverId,
                            child: Text(d.driverName),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedDriverId = v),
                  )
                else
                  Text(
                    'Contact a driver first to leave a review.',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textMuted,
                    ),
                  ),
                const SizedBox(height: 14),
                StarRating(
                  value: _rating,
                  size: 36,
                  onChanged: (v) => setState(() => _rating = v),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _reviewCtrl,
                  maxLines: 4,
                  maxLength: 300,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Write your review (optional)',
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
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
                const SizedBox(height: 28),
                const SectionTitle('Recent Drivers'),
                const SizedBox(height: 10),
                if (uniqueRecent.isEmpty)
                  Text(
                    'No recent drivers yet.',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textMuted,
                    ),
                  )
                else
                  ...uniqueRecent.values.map((d) {
                    final prior = _myReviews
                        .where((r) => r.driverId == d.driverId)
                        .toList();
                    final rating = prior.isEmpty ? 0 : prior.first.rating;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const AvatarCircle(size: 42),
                      title: Text(
                        d.driverName,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      subtitle: StarRating(value: rating, size: 18),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/driver/${d.driverId}'),
                    );
                  }),
              ],
            ),
    );
  }
}
