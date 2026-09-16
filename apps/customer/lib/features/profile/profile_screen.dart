import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_validators.dart';
import '../../core/utils/phone_utils.dart';
import '../../widgets/common_widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commuter = ref.watch(sessionProvider).value;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const GreenAppBar(title: 'Profile'),
      body: commuter == null
          ? const Center(child: Text('Not signed in'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              children: [
                const Center(child: AvatarCircle(size: 96)),
                const SizedBox(height: 14),
                Text(
                  commuter.fullName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  PhoneUtils.display(commuter.contactNumber),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                _row(Icons.email_outlined, 'Email',
                    commuter.emailAddress ?? '—'),
                _row(Icons.person_outline, 'Username', commuter.username),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_outlined,
                      color: AppColors.primary),
                  title: const Text('Notifications'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/notifications'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_active_outlined,
                      color: AppColors.primary),
                  title: const Text('Enable push notifications'),
                  subtitle: const Text('Show the system permission prompt'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _enablePush(context, ref),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune,
                      color: AppColors.primary),
                  title: const Text('Notification preferences'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editPrefs(context, ref),
                ),
                const SizedBox(height: 18),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                  ),
                  onPressed: () => _changePassword(context, ref),
                  child: const Text('Change Password'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  onPressed: () async {
                    await ref.read(sessionProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  },
                  child: const Text('Log Out'),
                ),
              ],
            ),
    );
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_PasswordChange>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(sessionProvider.notifier).changePassword(
            currentPassword: result.current,
            newPassword: result.next,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated successfully.')),
        );
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _enablePush(BuildContext context, WidgetRef ref) async {
    final push = ref.read(pushNotificationServiceProvider);
    final commuter = ref.read(sessionProvider).value;
    final granted = await push.requestPermission();
    if (commuter != null && commuter.status == 'active') {
      // Force re-start so a newly granted permission can fetch/save the token.
      await push.stop();
      await push.startForCommuter(commuter.id);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted
              ? 'Push notifications enabled.'
              : 'Permission denied. Enable notifications in system Settings.',
        ),
      ),
    );
  }

  Future<void> _editPrefs(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(customerRepositoryProvider);
    final prefs = await repo.fetchNotificationPreferences();
    if (!context.mounted) return;
    var followed = prefs['followed_driver_availability'] ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Notification preferences'),
              content: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Followed driver availability'),
                subtitle: const Text(
                  'When drivers you follow become available or unavailable',
                ),
                value: followed,
                onChanged: (v) => setLocal(() => followed = v),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved != true) return;
    await repo.upsertNotificationPreferences(
      followedDriverAvailability: followed,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferences saved.')),
      );
    }
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordChange {
  const _PasswordChange(this.current, this.next);
  final String current;
  final String next;
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
              validator: AuthValidators.password,
            ),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Confirm new password'),
              validator: (v) => AuthValidators.confirmPassword(v, _next.text),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, _PasswordChange(_current.text, _next.text));
          },
          child: const Text('Update'),
        ),
      ],
    );
  }
}
