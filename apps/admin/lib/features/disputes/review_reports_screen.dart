import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

class ReviewReportsScreen extends ConsumerStatefulWidget {
  const ReviewReportsScreen({super.key});

  @override
  ConsumerState<ReviewReportsScreen> createState() =>
      _ReviewReportsScreenState();
}

class _ReviewReportsScreenState extends ConsumerState<ReviewReportsScreen> {
  late Future<List<ReviewReportRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(adminRepositoryProvider).fetchOpenReviewReports();
  }

  void _reload() {
    setState(() {
      _future = ref.read(adminRepositoryProvider).fetchOpenReviewReports();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ReviewReportRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Text(friendlyError(snapshot.error!)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            PageHeader(
              title: 'Review Reports',
              subtitle:
                  'OPEN reports from drivers. Resolve after moderation; dismiss if no action needed.',
              action: IconButton(
                onPressed: _reload,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
              ),
            ),
            const SizedBox(height: 16),
            DataCard(
              child: items.isEmpty
                  ? const EmptyState(message: 'No open review reports.')
                  : Column(
                      children: [
                        const TableHeader(
                          cells: ['Report', 'Review', 'Reason', ''],
                        ),
                        for (final report in items)
                          _Row(
                            report: report,
                            onResolve: () => _resolve(report, 'resolve'),
                            onDismiss: () => _resolve(report, 'dismiss'),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resolve(ReviewReportRecord report, String action) async {
    final resolve = action == 'resolve';
    final ok = await confirmAction(
      context,
      title: resolve ? 'Mark resolved?' : 'Dismiss report?',
      message: resolve
          ? 'Marks this report resolved after you handle moderation (e.g. hide the review).'
          : 'Dismisses the report with no further action.',
      confirmLabel: resolve ? 'Resolve' : 'Dismiss',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).resolveReviewReport(
            reportId: report.id,
            action: action,
          );
      if (mounted) {
        showInfo(
          context,
          resolve ? 'Report resolved.' : 'Report dismissed.',
        );
      }
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.report,
    required this.onResolve,
    required this.onDismiss,
  });

  final ReviewReportRecord report;
  final VoidCallback onResolve;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final content = (report.reviewContent ?? '').trim();
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
                  'Driver: ${report.driverName ?? 'Unknown'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Reported ${formatWhen(report.createdAt)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${report.commuterName ?? 'Commuter'} · ${report.reviewRating ?? '—'} / 5',
                ),
                Text(
                  content.isEmpty ? 'Rating only' : content,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(report.reason),
                if (report.details != null && report.details!.trim().isNotEmpty)
                  Text(
                    report.details!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 4,
              children: [
                TextButton(onPressed: onResolve, child: const Text('Resolve')),
                TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
