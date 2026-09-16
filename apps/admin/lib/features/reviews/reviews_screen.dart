import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

class ReviewsScreen extends ConsumerStatefulWidget {
  const ReviewsScreen({super.key});

  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends ConsumerState<ReviewsScreen> {
  String _filter = 'all';
  late Future<List<ReviewRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(adminRepositoryProvider).fetchReviews();
  }

  void _reload() {
    setState(() {
      _future = ref.read(adminRepositoryProvider).fetchReviews();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ReviewRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(friendlyError(snapshot.error!)),
                const SizedBox(height: 12),
                FilledButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        final reviews = all.where((r) {
          return switch (_filter) {
            'hidden' => r.isHidden,
            'visible' => !r.isHidden,
            'text' => (r.content ?? '').trim().isNotEmpty,
            'booking' => r.bookingId != null,
            _ => true,
          };
        }).toList();

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              PageHeader(
                title: 'Reviews',
                subtitle:
                    'Live passenger reviews from the database. ${all.length} total.',
                action: IconButton(
                  tooltip: 'Refresh',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                value: _filter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All reviews')),
                  DropdownMenuItem(value: 'visible', child: Text('Visible')),
                  DropdownMenuItem(value: 'hidden', child: Text('Hidden')),
                  DropdownMenuItem(value: 'text', child: Text('Has text')),
                  DropdownMenuItem(
                    value: 'booking',
                    child: Text('Booking-linked'),
                  ),
                ],
                onChanged: (value) => setState(() => _filter = value ?? 'all'),
              ),
              const SizedBox(height: 16),
              DataCard(
                child: reviews.isEmpty
                    ? const EmptyState(
                        message:
                            'No reviews yet. New booking reviews will appear here after passengers submit them.',
                      )
                    : Column(
                        children: [
                          const TableHeader(
                            cells: ['Review', 'Rating', 'Visibility', ''],
                          ),
                          for (final review in reviews)
                            _Row(
                              review: review,
                              onHide: () => _hide(review),
                              onDelete: () => _delete(review),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _hide(ReviewRecord review) async {
    String? note = review.moderationNote;
    if (!review.isHidden) {
      note = await promptText(
        context,
        title: 'Hide review',
        label: 'Note (optional)',
        initial: review.moderationNote,
        confirmLabel: 'Hide',
        maxLines: 3,
      );
      if (note == null || !mounted) return;
    }
    try {
      await ref.read(adminRepositoryProvider).setReviewHidden(
            review.id,
            hidden: !review.isHidden,
            note: note,
          );
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _delete(ReviewRecord review) async {
    final ok = await confirmAction(
      context,
      title: 'Remove review?',
      message:
          'This permanently deletes the review. There is no undo and no change log.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).deleteReview(review.id);
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.review,
    required this.onHide,
    required this.onDelete,
  });

  final ReviewRecord review;
  final VoidCallback onHide;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = (review.content ?? '').trim();
    final plate = (review.driverPlate ?? '').trim();
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
                  '${review.commuterName ?? 'Commuter'} → ${review.driverName ?? 'Driver'}'
                  '${plate.isEmpty ? '' : ' ($plate)'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(text.isEmpty ? 'Rating only' : text),
                Text(
                  [
                    formatWhen(review.createdAt),
                    if (review.bookingId != null) 'Booking-linked',
                  ].join(' · '),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Text('${review.rating} / 5')),
          Expanded(child: Text(review.isHidden ? 'Hidden' : 'Visible')),
          Expanded(
            child: Wrap(
              children: [
                TextButton(
                  onPressed: onHide,
                  child: Text(review.isHidden ? 'Unhide' : 'Hide'),
                ),
                TextButton(onPressed: onDelete, child: const Text('Remove')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
