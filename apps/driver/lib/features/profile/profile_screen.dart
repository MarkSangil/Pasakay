import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_validators.dart';
import '../../core/utils/phone_utils.dart';
import '../../models/shift.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/legal_dialog.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final driver = session.value;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const DriverAppBar(title: 'My Profile'),
      body: session.isLoading
          ? const Center(child: CircularProgressIndicator())
          : driver == null
              ? const Center(child: Text('Not signed in'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  children: [
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 58,
                            backgroundColor: AppColors.border,
                            backgroundImage: driver.avatarUrl != null
                                ? NetworkImage(driver.avatarUrl!)
                                : null,
                            child: driver.avatarUrl == null
                                ? const Icon(
                                    Icons.person,
                                    size: 58,
                                    color: AppColors.textMuted,
                                  )
                                : null,
                          ),
                          Positioned(
                            right: 2,
                            bottom: 2,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.photo_camera_outlined,
                                size: 15,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      driver.fullName,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      driver.todaNumber ?? 'SSLTODA No. —',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _InfoRow(
                      icon: Icons.airport_shuttle_outlined,
                      label: 'Plate Number',
                      value: driver.plateNumber ?? '—',
                    ),
                    _InfoRow(
                      icon: Icons.phone_outlined,
                      label: 'Mobile Number',
                      value: PhoneUtils.display(driver.mobileNumber),
                    ),
                    _InfoRow(
                      icon: Icons.star_outline_rounded,
                      label: 'Designated Terminal',
                      value: driver.assignedTerminal?.name ?? 'Not assigned',
                    ),
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      label: 'Current Location',
                      value: driver.currentTerminal?.name ?? 'Not set',
                      onTap: () => context.push('/terminal'),
                    ),
                    _OperatingScheduleRow(
                      shiftId: driver.shiftId,
                      onShift: driver.onShift,
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => _enablePush(context, ref, driver.id),
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('Enable push notifications'),
                    ),
                    TextButton.icon(
                      onPressed: () => _editNotificationPrefs(context, ref, driver.id),
                      icon: const Icon(Icons.notifications_outlined),
                      label: const Text('Notification preferences'),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.support_agent_outlined,
                        color: AppColors.primary,
                      ),
                      title: Text(
                        'Contact Administrator',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text('pasakay06@gmail.com'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showLegalDialog(
                        context,
                        initialTab: LegalTab.contact,
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.description_outlined,
                        color: AppColors.primary,
                      ),
                      title: Text(
                        'Terms and Conditions',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showLegalDialog(
                        context,
                        initialTab: LegalTab.terms,
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.privacy_tip_outlined,
                        color: AppColors.primary,
                      ),
                      title: Text(
                        'Privacy Policy',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showLegalDialog(
                        context,
                        initialTab: LegalTab.privacy,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _changePassword(context, ref),
                      child: Text(
                        'Change Password',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(
                          color: AppColors.danger,
                          width: 1.5,
                        ),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        await ref.read(sessionProvider.notifier).logout();
                        if (context.mounted) context.go('/login');
                      },
                      child: Text(
                        'Log Out',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
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

  Future<void> _enablePush(
    BuildContext context,
    WidgetRef ref,
    String driverId,
  ) async {
    final push = ref.read(pushNotificationServiceProvider);
    final granted = await push.requestPermission();
    await push.stop();
    await push.startForDriver(driverId);
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

  Future<void> _editNotificationPrefs(
    BuildContext context,
    WidgetRef ref,
    String driverId,
  ) async {
    final repo = ref.read(driverRepositoryProvider);
    final prefs = await repo.fetchNotificationPreferences(driverId);
    if (!context.mounted) return;
    var reminders = prefs['schedule_reminders'] ?? true;
    var changes = prefs['schedule_changes'] ?? true;
    var availability = prefs['availability_changes'] ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Notification preferences'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Schedule reminders'),
                    subtitle: const Text('Approaching, start, and end'),
                    value: reminders,
                    onChanged: (v) => setLocal(() => reminders = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Schedule changes'),
                    subtitle: const Text('Updates, cancellations, terminal'),
                    value: changes,
                    onChanged: (v) => setLocal(() => changes = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Availability changes'),
                    value: availability,
                    onChanged: (v) => setLocal(() => availability = v),
                  ),
                ],
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
    try {
      await repo.upsertNotificationPreferences(
        driverId: driverId,
        scheduleReminders: reminders,
        scheduleChanges: changes,
        availabilityChanges: availability,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification preferences saved.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordChange {
  const _PasswordChange(this.current, this.next);
  final String current;
  final String next;
}

/// Shows the assigned shift block and lets the driver request a change
/// (requires admin approval before it takes effect).
class _OperatingScheduleRow extends ConsumerStatefulWidget {
  const _OperatingScheduleRow({required this.shiftId, required this.onShift});

  final String? shiftId;
  final bool onShift;

  @override
  ConsumerState<_OperatingScheduleRow> createState() =>
      _OperatingScheduleRowState();
}

class _OperatingScheduleRowState extends ConsumerState<_OperatingScheduleRow> {
  List<Shift> _shifts = const [];
  Map<String, dynamic>? _pending;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final repo = ref.read(driverRepositoryProvider);
    try {
      final results = await Future.wait([
        repo.fetchShifts(),
        repo.fetchMyShiftChangeRequest(),
      ]);
      if (!mounted) return;
      setState(() {
        _shifts = results[0] as List<Shift>;
        _pending = results[1] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String get _currentLabel {
    final id = widget.shiftId;
    if (id == null) return 'Not assigned';
    for (final s in _shifts) {
      if (s.id == id) return s.label;
    }
    return 'Assigned shift';
  }

  String get _value {
    if (_loading) return 'Loading…';
    if (_pending?['hasPendingRequest'] == true) {
      final label = _pending?['requestedShiftLabel']?.toString();
      return 'Change pending${label == null || label.isEmpty ? '' : ' → $label'}';
    }
    if (widget.onShift) return 'On shift now • $_currentLabel';
    return _currentLabel;
  }

  Future<void> _openChangeDialog() async {
    if (_busy || _loading) return;
    if (_pending?['hasPendingRequest'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A shift change request is already waiting for admin approval.',
          ),
        ),
      );
      return;
    }
    final options = _shifts.where((s) => s.id != widget.shiftId).toList();
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other shifts are available.')),
      );
      return;
    }
    final selected = await showDialog<Shift>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request shift change'),
        content: SizedBox(
          width: 340,
          child: ListView(
            shrinkWrap: true,
            children: options
                .map(
                  (s) => RadioListTile<Shift>(
                    title: Text(s.label),
                    value: s,
                    groupValue: null,
                    onChanged: (v) => Navigator.pop(context, v),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(driverRepositoryProvider)
          .requestShiftChange(selected.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift change request sent. Waiting for admin approval.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthValidators.friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InfoRow(
      icon: Icons.schedule_outlined,
      label: 'Operating Schedule',
      value: _value,
      onTap: _openChangeDialog,
    );
  }
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
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _current,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current password'),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
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
                validator: (v) =>
                    AuthValidators.confirmPassword(v, _next.text),
              ),
            ],
          ),
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
            Navigator.pop(
              context,
              _PasswordChange(_current.text, _next.text),
            );
          },
          child: const Text('Update'),
        ),
      ],
    );
  }
}
