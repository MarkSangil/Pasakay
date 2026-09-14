import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/session_provider.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Overview>(
      future: ref.watch(adminRepositoryProvider).fetchOverview(),
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
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const PageHeader(
              title: 'Overview',
              subtitle:
                  'Operations console for the PASAKAY study. These counts are operational, not an analytics dashboard.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                MetricCard(
                  label: 'Drivers',
                  value: '${data.driversTotal}',
                  caption:
                      '${data.driversPending} pending · ${data.driversActive} active · ${data.driversSuspended} suspended',
                  onTap: () => context.go('/drivers'),
                ),
                MetricCard(
                  label: 'Commuters',
                  value: '${data.commutersTotal}',
                  caption: '${data.commutersSuspended} suspended or deactivated',
                  onTap: () => context.go('/commuters'),
                ),
                MetricCard(
                  label: 'Terminals',
                  value: '${data.terminals}',
                  caption: 'Plain-text list, no map pins',
                  onTap: () => context.go('/terminals'),
                ),
                MetricCard(
                  label: 'Shifts',
                  value: '${data.shifts}',
                  caption: 'Fixed blocks only',
                  onTap: () => context.go('/shifts'),
                ),
                MetricCard(
                  label: 'Reviews',
                  value: '${data.reviewsVisible}',
                  caption: '${data.reviewsHidden} hidden',
                  onTap: () => context.go('/reviews'),
                ),
                MetricCard(
                  label: 'Diagnostics',
                  value: '${data.deviceLogs}',
                  caption: '${data.crashLogs} crash logs, read only',
                  onTap: () => context.go('/diagnostics'),
                ),
                MetricCard(
                  label: 'Privacy requests',
                  value: '${data.privacyOpen}',
                  caption: 'Open requests logged by admin',
                  onTap: () => context.go('/privacy'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
