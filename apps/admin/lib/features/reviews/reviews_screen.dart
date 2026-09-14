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
    setState(() => _future = ref.read(adminRepositoryProvider).fetchReviews());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ReviewRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Text(friendlyError(snapshot.error!)),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final reviews = snapshot.data!.where((r) {
          return switch (_filter) {
            'hidden' => r.isHidden,
            'visible' => !r.isHidden,
            'text' => (r.content ?? '').trim().isNotEmpty,
            _ => true,
          };
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const PageHeader(
              title: 'Reviews',
              subtitle: 'Manually hide or remove a rating and optional comment.',
            ),
            const SizedBox(height: 16),
            DropdownButton<String>(
              value: _filter,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All reviews')),
                DropdownMenuItem(value: 'visible', child: Text('Visible')),
                DropdownMenuItem(value: 'hidden', child: Text('Hidden')),
                DropdownMenuItem(value: 'text', child: Text('Has text')),
              ],
              onChanged: (value) => setState(() => _filter = value ?? 'all'),
            ),
            const SizedBox(height: 16),
            DataCard(
              child: reviews.isEmpty
                  ? const EmptyState(message: 'No reviews in this view.')
                  : Column(
                      children: [
                        const TableHeader(cells: ['Review', 'Rating', 'Visibility', '']),
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
      message: 'This permanently deletes the review. There is no undo and no change log.',
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
                  '${review.commuterName ?? 'Commuter'} → ${review.driverName ?? 'Driver'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(text.isEmpty ? 'Rating only' : text),
                Text(
                  formatWhen(review.createdAt),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
