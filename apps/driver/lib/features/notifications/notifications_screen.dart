import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/review.dart';
import '../../widgets/common_widgets.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<AppNotification> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final driver = ref.read(sessionProvider).value;
    if (driver == null) return;
    setState(() => _loading = true);
    try {
      final repo = ref.read(driverRepositoryProvider);
      final items = await repo.fetchNotifications(driver.id);
      await repo.markNotificationsRead(driver.id);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: DriverAppBar(
        title: 'Notifications',
        showMenu: false,
        onBack: () => context.pop(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Text(
                    'No notifications yet.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final n = _items[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: n.isRead
                              ? AppColors.border
                              : AppColors.successSoft,
                          child: Icon(
                            Icons.notifications_outlined,
                            color: n.isRead
                                ? AppColors.textMuted
                                : AppColors.primary,
                          ),
                        ),
                        title: Text(
                          n.title,
                          style: TextStyle(
                            fontWeight:
                                n.isRead ? FontWeight.w600 : FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(n.body),
                        trailing: Text(
                          timeago.format(n.createdAt.toLocal()),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
