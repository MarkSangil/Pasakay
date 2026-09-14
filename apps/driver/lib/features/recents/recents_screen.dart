import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_formats.dart';
import '../../models/booking.dart';
import '../../widgets/common_widgets.dart';

class RecentsScreen extends ConsumerStatefulWidget {
  const RecentsScreen({super.key});

  @override
  ConsumerState<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends ConsumerState<RecentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Booking> _today = const [];
  List<Booking> _yesterday = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
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
      final now = DateTime.now();
      final startToday = DateTime(now.year, now.month, now.day);
      final startYesterday = startToday.subtract(const Duration(days: 1));
      final repo = ref.read(driverRepositoryProvider);
      final today = await repo.fetchBookings(
        driverId: driver.id,
        from: startToday,
        to: startToday.add(const Duration(days: 1)),
      );
      final yesterday = await repo.fetchBookings(
        driverId: driver.id,
        from: startYesterday,
        to: startToday,
      );
      if (!mounted) return;
      setState(() {
        _today = today;
        _yesterday = yesterday;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const DriverAppBar(title: 'Recents'),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Today'),
                Tab(text: 'Yesterday'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _RecentList(items: _today),
                      _RecentList(items: _yesterday),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecentList extends ConsumerWidget {
  const _RecentList({required this.items});

  final List<Booking> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No recent trips.',
          style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted),
        ),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final b = items[index];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: const CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.border,
            child: Icon(Icons.person, color: AppColors.textMuted),
          ),
          title: Text(
            b.passengerName,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          subtitle: Text(
            b.pickupTerminal?.name ?? 'Terminal',
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormats.time.format(b.scheduledAt.toLocal()),
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Call',
                onPressed: () =>
                    ref.read(authServiceProvider).openCall(b.passengerMobile),
                icon: const Icon(
                  Icons.phone,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
