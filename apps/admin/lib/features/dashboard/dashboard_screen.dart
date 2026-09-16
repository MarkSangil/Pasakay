import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/session_provider.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late Future<Overview> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(adminRepositoryProvider).fetchOverview();
  }

  void _reload() {
    setState(() {
      _future = ref.read(adminRepositoryProvider).fetchOverview();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Overview>(
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
        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              PageHeader(
                title: 'Overview',
                subtitle: data.generatedAt == null
                    ? 'Live counts from the PASAKAY database.'
                    : 'Live counts as of ${formatWhen(data.generatedAt)}.',
                action: IconButton(
                  tooltip: 'Refresh',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
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
                    caption:
                        '${data.commutersSuspended} suspended or deactivated',
                    onTap: () => context.go('/commuters'),
                  ),
                  MetricCard(
                    label: 'Pending requests',
                    value: '${data.requestsPending}',
                    caption: '${data.requestsTotal} total ride requests',
                    onTap: () => context.go('/drivers'),
                  ),
                  MetricCard(
                    label: 'Active bookings',
                    value: '${data.bookingsBooked}',
                    caption:
                        '${data.bookingsCompleted} completed · ${data.bookingsCancelled} cancelled',
                    onTap: () => context.go('/disputed-bookings'),
                  ),
                  MetricCard(
                    label: 'Disputed bookings',
                    value: '${data.bookingsFlagged}',
                    caption: '${data.bookingsTotal} bookings overall',
                    onTap: () => context.go('/disputed-bookings'),
                  ),
                  MetricCard(
                    label: 'Review reports',
                    value: '${data.reviewReportsOpen}',
                    caption: 'Open reports awaiting admin action',
                    onTap: () => context.go('/review-reports'),
                  ),
                  MetricCard(
                    label: 'Reviews',
                    value: '${data.reviewsVisible}',
                    caption: '${data.reviewsHidden} hidden',
                    onTap: () => context.go('/reviews'),
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
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
