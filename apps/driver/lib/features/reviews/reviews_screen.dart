import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_formats.dart';
import '../../models/review.dart';
import '../../widgets/common_widgets.dart';

class ReviewsScreen extends ConsumerStatefulWidget {
  const ReviewsScreen({super.key});

  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends ConsumerState<ReviewsScreen> {
  List<Review> _reviews = const [];
  double _averageRating = 0;
  int _reviewCount = 0;
  bool _loading = true;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final driver = ref.read(sessionProvider).value;
    if (driver == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final repo = ref.read(driverRepositoryProvider);
      final results = await Future.wait([
        repo.fetchReviews(driver.id, limit: _showAll ? null : 10),
        repo.fetchReviewSummary(driver.id),
      ]);
      if (!mounted) return;
      final summary =
          results[1] as ({double averageRating, int reviewCount});
      setState(() {
        _reviews = results[0] as List<Review>;
        _averageRating = summary.averageRating;
        _reviewCount = summary.reviewCount;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _report(Review review) async {
    final result = await showDialog<_ReportResult>(
      context: context,
      builder: (context) => const _ReportReviewDialog(),
    );
    if (result == null) return;
    try {
      await ref.read(driverRepositoryProvider).reportReview(
            reviewId: review.id,
            reason: result.reason,
            details: result.details,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review reported for moderation.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rating = _averageRating;
    final count = _reviewCount;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const DriverAppBar(title: 'Reviews'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        rating.toStringAsFixed(1),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Overall Rating',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _Stars(
                              rating: rating.round().clamp(0, 5),
                              size: 20,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '($count reviews)',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  if (_reviews.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          'No reviews yet.',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._reviews.map(
                      (r) => _ReviewCard(
                        review: r,
                        onReport: () => _report(r),
                      ),
                    ),
                  if (!_showAll && count > _reviews.length) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () async {
                        setState(() => _showAll = true);
                        await _load();
                      },
                      child: const Text('View all reviews'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, required this.onReport});
  final Review review;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Passenger review',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              _Stars(rating: review.rating, size: 16),
            ],
          ),
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment!,
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormats.dateShort.format(review.createdAt.toLocal()),
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton(
                onPressed: onReport,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Report Review'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating, this.size = 18});
  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
          color: AppColors.star,
          size: size,
        );
      }),
    );
  }
}

class _ReportResult {
  const _ReportResult({required this.reason, this.details});
  final String reason;
  final String? details;
}

class _ReportReviewDialog extends StatefulWidget {
  const _ReportReviewDialog();

  @override
  State<_ReportReviewDialog> createState() => _ReportReviewDialogState();
}

class _ReportReviewDialogState extends State<_ReportReviewDialog> {
  static const _reasons = [
    'Fake or misleading',
    'Harassment or abuse',
    'Not my passenger',
    'Other',
  ];

  String _reason = _reasons.first;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report Review'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final reason in _reasons)
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(reason, style: const TextStyle(fontSize: 14)),
                value: reason,
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v!),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _details,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                hintText: 'Add more context for moderators',
              ),
            ),
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
            if (_reason == 'Other' && details.isEmpty) {
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
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
