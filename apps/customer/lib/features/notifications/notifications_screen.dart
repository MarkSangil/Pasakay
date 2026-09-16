import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/notification_event_type.dart';
import '../../widgets/common_widgets.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(customerRepositoryProvider);
      final items = await repo.fetchNotifications();
      await repo.markNotificationsRead();
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
      appBar: const GreenAppBar(title: 'Notifications', showBack: true),
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
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final n = _items[index];
                      final title = (n['title'] as String?)?.isNotEmpty == true
                          ? n['title'] as String
                          : 'Pasakay';
                      final body = n['message_content'] as String? ?? '';
                      final isRead = n['is_read'] as bool? ?? true;
                      final created = DateTime.tryParse(
                            n['date_sent']?.toString() ?? '',
                          ) ??
                          DateTime.now();
                      final data =
                          (n['data'] as Map?)?.cast<String, dynamic>() ?? {};
                      final route = NotificationEventType.routeFor(
                        eventType: n['event_type'] as String?,
                        data: {
                          ...data,
                          if (n['related_driver_id'] != null)
                            'driver_id': n['related_driver_id'],
                        },
                      );
                      return ListTile(
                        onTap: () => context.push(route),
                        leading: CircleAvatar(
                          backgroundColor: isRead
                              ? AppColors.border
                              : AppColors.successSoft,
                          child: Icon(
                            Icons.notifications_outlined,
                            color: isRead
                                ? AppColors.textMuted
                                : AppColors.primary,
                          ),
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontWeight:
                                isRead ? FontWeight.w600 : FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(body),
                        trailing: Text(
                          timeago.format(created.toLocal()),
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
