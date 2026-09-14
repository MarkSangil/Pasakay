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
      final reviews = await ref
          .read(driverRepositoryProvider)
          .fetchReviews(driver.id, limit: _showAll ? null : 10);
      if (!mounted) return;
      setState(() {
        _reviews = reviews;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(sessionProvider).value;
    final rating = driver?.averageRating ?? 0;
    final count = driver?.reviewCount ?? _reviews.length;

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
                  // Mockup: large score on the left, stars + count on the right.
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
                    ..._reviews.map((r) => _ReviewCard(review: r)),
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
  const _ReviewCard({required this.review});
  final Review review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.border,
                child: Icon(Icons.person, size: 20, color: AppColors.textMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  review.passengerName,
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
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: Text(
                review.comment!,
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 50),
            child: Text(
              DateFormats.dateShort.format(review.createdAt.toLocal()),
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
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
