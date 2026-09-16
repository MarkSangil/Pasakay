import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/admin_widgets.dart';

class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;

  static const _items = [
    _Nav('Overview', '/overview', Icons.dashboard_outlined),
    _Nav('Drivers', '/drivers', Icons.badge_outlined),
    _Nav('Terminals', '/terminals', Icons.place_outlined),
    _Nav('Shifts', '/shifts', Icons.schedule_outlined),
    _Nav('Booking Settings', '/booking-settings', Icons.timer_outlined),
    _Nav('Commuters', '/commuters', Icons.people_outline),
    _Nav('Reviews', '/reviews', Icons.rate_review_outlined),
    _Nav('Disputed Bookings', '/disputed-bookings', Icons.gavel_outlined),
    _Nav('Review Reports', '/review-reports', Icons.flag_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = ref.watch(sessionProvider).value;
    final location = GoRouterState.of(context).uri.path;

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 248,
            color: AppColors.primaryDark,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PASAKAY',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'System admin',
                          style: TextStyle(color: Color(0xFFB7D0C2), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  for (final item in _items)
                    _NavButton(
                      item: item,
                      selected: location == item.path ||
                          (item.path != '/overview' &&
                              location.startsWith(item.path)),
                      onTap: () => context.go(item.path),
                    ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          admin?.fullName ?? 'Admin',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          admin?.email ?? '',
                          style: const TextStyle(color: Color(0xFFB7D0C2), fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => _changePassword(context, ref),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                          ),
                          child: const Text('Change password'),
                        ),
                        TextButton(
                          onPressed: () => ref.read(sessionProvider.notifier).logout(),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.accentSoft,
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                          ),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: AppColors.background,
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final next = await promptText(
      context,
      title: 'Change password',
      label: 'New password',
      obscure: true,
      confirmLabel: 'Update',
    );
    if (next == null || next.isEmpty || !context.mounted) return;
    try {
      await ref.read(adminRepositoryProvider).changePassword(next);
      if (context.mounted) showInfo(context, 'Password updated');
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _Nav {
  const _Nav(this.label, this.path, this.icon);
  final String label;
  final String path;
  final IconData icon;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _Nav item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: selected ? AppColors.accent : Colors.white),
                const SizedBox(width: 10),
                Text(
                  item.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
