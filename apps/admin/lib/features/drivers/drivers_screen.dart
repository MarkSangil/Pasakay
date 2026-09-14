import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

class DriversScreen extends ConsumerStatefulWidget {
  const DriversScreen({super.key});

  @override
  ConsumerState<DriversScreen> createState() => _DriversScreenState();
}

class _DriversScreenState extends ConsumerState<DriversScreen> {
  String _query = '';
  String _status = 'all';
  late Future<_DriverPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DriverPage> _load() async {
    final repo = ref.read(adminRepositoryProvider);
    final results = await Future.wait([
      repo.fetchDrivers(),
      repo.fetchTerminals(),
      repo.fetchShifts(),
    ]);
    return _DriverPage(
      drivers: results[0] as List<DriverRecord>,
      terminals: results[1] as List<TerminalRecord>,
      shifts: results[2] as List<ShiftRecord>,
    );
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DriverPage>(
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
        final page = snapshot.data!;
        final query = _query.trim().toLowerCase();
        final drivers = page.drivers.where((d) {
          final matchesStatus = _status == 'all' || d.status == _status;
          final haystack =
              '${d.fullName} ${d.username} ${d.contactNumber} ${d.licenseNumber} ${d.plateNumber}'
                  .toLowerCase();
          return matchesStatus && (query.isEmpty || haystack.contains(query));
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            PageHeader(
              title: 'Drivers',
              subtitle: 'Add, edit, assign, verify, suspend, or remove driver profiles.',
              action: FilledButton.icon(
                onPressed: page.terminals.isEmpty || page.shifts.isEmpty
                    ? null
                    : () => _edit(page),
                icon: const Icon(Icons.add),
                label: const Text('Add driver'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SearchField(
                  hint: 'Search name, plate, license',
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _status,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All statuses')),
                    DropdownMenuItem(value: 'pending_verification', child: Text('Pending')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                    DropdownMenuItem(value: 'deactivated', child: Text('Deactivated')),
                  ],
                  onChanged: (value) => setState(() => _status = value ?? 'all'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DataCard(
              child: drivers.isEmpty
                  ? const EmptyState(message: 'No drivers match this filter.')
                  : Column(
                      children: [
                        const TableHeader(
                          cells: ['Driver', 'Assignment', 'License', 'Status', ''],
                        ),
                        for (final driver in drivers)
                          _DriverRow(
                            driver: driver,
                            onEdit: () => _edit(page, existing: driver),
                            onVerify: () => _verify(driver),
                            onStatus: () => _setStatus(driver),
                            onReset: () => _resetPassword(driver),
                            onDelete: () => _delete(driver),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _edit(_DriverPage page, {DriverRecord? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _DriverFormDialog(page: page, existing: existing),
    );
    if (saved == true) _reload();
  }

  Future<void> _verify(DriverRecord driver) async {
    final verified = await showDialog<bool>(
      context: context,
      builder: (context) => _VerifyDialog(driver: driver),
    );
    if (verified == null) return;
    try {
      await ref.read(adminRepositoryProvider).verifyLicense(
            driver.id,
            verified: verified,
          );
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _setStatus(DriverRecord driver) async {
    final result = await showDialog<_StatusChoice>(
      context: context,
      builder: (context) => _StatusDialog(driver: driver),
    );
    if (result == null) return;
    try {
      await ref.read(adminRepositoryProvider).setDriverStatus(
            driver.id,
            result.status,
            result.reason,
          );
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _resetPassword(DriverRecord driver) async {
    final password = await promptText(
      context,
      title: 'Reset password',
      label: 'Temporary password',
      obscure: true,
      confirmLabel: 'Reset',
    );
    if (password == null || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).resetDriverPassword(driver.id, password);
      if (mounted) {
        showInfo(context, 'Password reset. Give it to the driver outside the app.');
      }
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _delete(DriverRecord driver) async {
    final ok = await confirmAction(
      context,
      title: 'Remove driver?',
      message:
          'This deletes ${driver.fullName} and their login. Reviews tied to them are removed. No change log is kept.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).deleteDriver(driver.id);
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class _DriverPage {
  const _DriverPage({
    required this.drivers,
    required this.terminals,
    required this.shifts,
  });

  final List<DriverRecord> drivers;
  final List<TerminalRecord> terminals;
  final List<ShiftRecord> shifts;
}

class _DriverRow extends StatelessWidget {
  const _DriverRow({
    required this.driver,
    required this.onEdit,
    required this.onVerify,
    required this.onStatus,
    required this.onReset,
    required this.onDelete,
  });

  final DriverRecord driver;
  final VoidCallback onEdit;
  final VoidCallback onVerify;
  final VoidCallback onStatus;
  final VoidCallback onReset;
  final VoidCallback onDelete;

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
                Text(driver.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${driver.contactNumber} · ${driver.plateNumber}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text('${driver.terminalName ?? '—'} · ${driver.shiftLabel ?? '—'}'),
          ),
          Expanded(
            child: Text(
              driver.licenseVerified
                  ? '${driver.licenseNumber} · visually checked'
                  : '${driver.licenseNumber} · not checked',
              style: TextStyle(
                color: driver.licenseVerified ? AppColors.success : AppColors.warning,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(child: StatusChip(status: driver.status)),
          Expanded(
            child: Wrap(
              spacing: 4,
              children: [
                TextButton(onPressed: onEdit, child: const Text('Edit')),
                TextButton(onPressed: onVerify, child: const Text('Verify')),
                TextButton(onPressed: onStatus, child: const Text('Status')),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'reset') onReset();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'reset', child: Text('Reset password')),
                    PopupMenuItem(value: 'delete', child: Text('Remove')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverFormDialog extends ConsumerStatefulWidget {
  const _DriverFormDialog({required this.page, this.existing});

  final _DriverPage page;
  final DriverRecord? existing;

  @override
  ConsumerState<_DriverFormDialog> createState() => _DriverFormDialogState();
}

class _DriverFormDialogState extends ConsumerState<_DriverFormDialog> {
  late final _name = TextEditingController(text: widget.existing?.fullName);
  late final _contact = TextEditingController(text: widget.existing?.contactNumber);
  late final _license = TextEditingController(text: widget.existing?.licenseNumber);
  late final _plate = TextEditingController(text: widget.existing?.plateNumber);
  late final _toda = TextEditingController(text: widget.existing?.todaNumber);
  late final _username = TextEditingController(text: widget.existing?.username);
  final _password = TextEditingController();
  late String? _terminalId = widget.existing?.terminalId ?? widget.page.terminals.first.id;
  late String? _shiftId = widget.existing?.shiftId ?? widget.page.shifts.first.id;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _license.dispose();
    _plate.dispose();
    _toda.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(adminRepositoryProvider);
      if (widget.existing == null) {
        await repo.createDriver(
          fullName: _name.text.trim(),
          contactNumber: _contact.text.trim(),
          licenseNumber: _license.text.trim(),
          plateNumber: _plate.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          terminalId: _terminalId!,
          shiftId: _shiftId!,
          todaNumber: _toda.text.trim(),
        );
      } else {
        await repo.updateDriver(
          driverId: widget.existing!.id,
          fullName: _name.text.trim(),
          contactNumber: _contact.text.trim(),
          licenseNumber: _license.text.trim(),
          plateNumber: _plate.text.trim(),
          username: _username.text.trim(),
          terminalId: _terminalId!,
          shiftId: _shiftId!,
          todaNumber: _toda.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Edit driver' : 'Add driver'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 10),
              TextField(
                controller: _contact,
                decoration: const InputDecoration(labelText: 'Contact number'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  helperText: 'Leave blank to use the contact number',
                ),
              ),
              if (!editing) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Temporary password'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _license,
                decoration: const InputDecoration(
                  labelText: 'License number',
                  helperText: 'Entered as given. Not checked against a government database.',
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: _plate, decoration: const InputDecoration(labelText: 'Plate number')),
              const SizedBox(height: 10),
              TextField(
                controller: _toda,
                decoration: const InputDecoration(labelText: 'TODA number (optional)'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _terminalId,
                decoration: const InputDecoration(labelText: 'Terminal'),
                items: [
                  for (final terminal in widget.page.terminals)
                    DropdownMenuItem(value: terminal.id, child: Text(terminal.name)),
                ],
                onChanged: (value) => setState(() => _terminalId = value),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _shiftId,
                decoration: const InputDecoration(labelText: 'Shift'),
                items: [
                  for (final shift in widget.page.shifts)
                    DropdownMenuItem(
                      value: shift.id,
                      child: Text('${shift.label} (${shift.window})'),
                    ),
                ],
                onChanged: (value) => setState(() => _shiftId = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(editing ? 'Save' : 'Create pending account'),
        ),
      ],
    );
  }
}

class _VerifyDialog extends StatefulWidget {
  const _VerifyDialog({required this.driver});

  final DriverRecord driver;

  @override
  State<_VerifyDialog> createState() => _VerifyDialogState();
}

class _VerifyDialogState extends State<_VerifyDialog> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Visual license check'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.driver.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SelectableText(
              widget.driver.licenseNumber,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _checked,
              onChanged: (value) => setState(() => _checked = value ?? false),
              title: const Text('I have visually checked this license number'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Clear verification'),
        ),
        FilledButton(
          onPressed: _checked ? () => Navigator.pop(context, true) : null,
          child: const Text('Mark verified'),
        ),
      ],
    );
  }
}

class _StatusChoice {
  const _StatusChoice(this.status, this.reason);
  final String status;
  final String? reason;
}

class _StatusDialog extends StatefulWidget {
  const _StatusDialog({required this.driver});

  final DriverRecord driver;

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  late String _status;
  late final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _status = widget.driver.status;
    _reason.text = widget.driver.statusReason ?? '';
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canActivate = widget.driver.licenseVerified;
    return AlertDialog(
      title: const Text('Account status'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _status,
              items: [
                DropdownMenuItem(
                  value: 'active',
                  enabled: canActivate,
                  child: Text(canActivate ? 'Active' : 'Active (license not verified)'),
                ),
                const DropdownMenuItem(
                  value: 'pending_verification',
                  child: Text('Pending verification'),
                ),
                const DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                const DropdownMenuItem(value: 'deactivated', child: Text('Deactivated')),
              ],
              onChanged: (value) => setState(() => _status = value ?? _status),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason',
                helperText: 'Required for suspend and deactivate. There is no blacklist.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _StatusChoice(_status, _reason.text.trim()),
          ),
          child: const Text('Update status'),
        ),
      ],
    );
  }
}
