import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

class CommutersScreen extends ConsumerStatefulWidget {
  const CommutersScreen({super.key});

  @override
  ConsumerState<CommutersScreen> createState() => _CommutersScreenState();
}

class _CommutersScreenState extends ConsumerState<CommutersScreen> {
  String _query = '';
  late Future<List<CommuterRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(adminRepositoryProvider).fetchCommuters();
  }

  void _reload() {
    setState(() {
      _future = ref.read(adminRepositoryProvider).fetchCommuters();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CommuterRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Text(friendlyError(snapshot.error!)),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final commuters = snapshot.data!.where((c) {
          final haystack = '${c.fullName} ${c.username} ${c.contactNumber}'.toLowerCase();
          return haystack.contains(_query.toLowerCase());
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const PageHeader(
              title: 'Commuters',
              subtitle:
                  'Approve pending signups, or deactivate accounts.',
            ),
            const SizedBox(height: 16),
            SearchField(hint: 'Search name or contact', onChanged: (v) => setState(() => _query = v)),
            const SizedBox(height: 16),
            DataCard(
              child: commuters.isEmpty
                  ? const EmptyState(message: 'No commuter accounts match.')
                  : Column(
                      children: [
                        const TableHeader(cells: ['Commuter', 'Contact', 'Status', '']),
                        for (final commuter in commuters)
                          _Row(
                            commuter: commuter,
                            onStatus: () => _setStatus(commuter),
                            onReset: () => _resetPassword(commuter),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _setStatus(CommuterRecord commuter) async {
    final result = await showDialog<_Choice>(
      context: context,
      builder: (context) => _StatusDialog(commuter: commuter),
    );
    if (result == null || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).setCommuterStatus(
            commuter.id,
            result.status,
            result.reason,
          );
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _resetPassword(CommuterRecord commuter) async {
    final password = await promptText(
      context,
      title: 'Reset password',
      label: 'Temporary password',
      obscure: true,
      confirmLabel: 'Reset',
    );
    if (password == null || !mounted) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .resetCommuterPassword(commuter.id, password);
      if (mounted) {
        showInfo(
          context,
          'Password reset. Give it to the passenger outside the app.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class _Choice {
  const _Choice(this.status, this.reason);
  final String status;
  final String? reason;
}

class _Row extends StatelessWidget {
  const _Row({
    required this.commuter,
    required this.onStatus,
    required this.onReset,
  });

  final CommuterRecord commuter;
  final VoidCallback onStatus;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(commuter.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(commuter.username, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Expanded(child: Text(commuter.contactNumber)),
          Expanded(child: StatusChip(status: commuter.status)),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'status') onStatus();
                  if (value == 'reset') onReset();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'status', child: Text('Set status')),
                  PopupMenuItem(value: 'reset', child: Text('Reset password')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDialog extends StatefulWidget {
  const _StatusDialog({required this.commuter});
  final CommuterRecord commuter;

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  late String _status;
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pending accounts are approved by setting Active.
    // Suspended was merged into Deactivated.
    final raw = widget.commuter.status;
    _status = raw == 'pending_verification'
        ? 'active'
        : (raw == 'suspended' ? 'deactivated' : raw);
    _reason.text = widget.commuter.statusReason ?? '';
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.commuter.fullName),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _status,
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active (approve)')),
                DropdownMenuItem(value: 'deactivated', child: Text('Deactivated')),
              ],
              onChanged: (value) => setState(() => _status = value ?? _status),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason',
                helperText: 'Required to deactivate. Reactivate is allowed.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _Choice(_status, _reason.text.trim())),
          child: const Text('Update'),
        ),
      ],
    );
  }
}
