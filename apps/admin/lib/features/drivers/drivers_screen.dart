import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/driver_form_validators.dart';
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

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

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
                            onOpen: () => context.go('/drivers/${driver.id}'),
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

  Future<void> _edit(_DriverPage page) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _DriverFormDialog(page: page),
    );
    if (saved == true) _reload();
  }

  Future<void> _verify(DriverRecord driver) async {
    final result = await showDialog<_VerifyResult>(
      context: context,
      builder: (context) => _VerifyDialog(driver: driver),
    );
    if (result == null) return;
    try {
      await ref.read(adminRepositoryProvider).verifyLicense(
            driver.id,
            verified: result.verified,
            todaNumber: result.todaNumber,
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
    required this.onOpen,
    required this.onVerify,
    required this.onStatus,
    required this.onReset,
    required this.onDelete,
  });

  final DriverRecord driver;
  final VoidCallback onOpen;
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
            child: InkWell(
              onTap: onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driver.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  Text(
                    '${driver.contactNumber} · ${driver.plateNumber}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
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
                TextButton(onPressed: onOpen, child: const Text('Open')),
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
  const _DriverFormDialog({required this.page});

  final _DriverPage page;

  @override
  ConsumerState<_DriverFormDialog> createState() => _DriverFormDialogState();
}

class _DriverFormDialogState extends ConsumerState<_DriverFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _license = TextEditingController();
  final _plate = TextEditingController();
  final _toda = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  late String? _terminalId = widget.page.terminals.first.id;
  late String? _shiftId = widget.page.shifts.first.id;
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
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(adminRepositoryProvider).createDriver(
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
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add driver'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: DriverFormValidators.requiredName,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _contact,
                  decoration: const InputDecoration(labelText: 'Contact number'),
                  validator: DriverFormValidators.contactNumber,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    helperText: 'Leave blank to use the contact number',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Temporary password'),
                  validator: (v) =>
                      DriverFormValidators.password(v, required: true),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _license,
                  decoration: const InputDecoration(labelText: 'License number'),
                  validator: DriverFormValidators.licenseNumber,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _plate,
                  decoration: const InputDecoration(labelText: 'Plate number'),
                  validator: DriverFormValidators.plateNumber,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _toda,
                  decoration: const InputDecoration(labelText: 'SSLTODA No. (optional)'),
                  validator: (v) => DriverFormValidators.ssltodaNumber(v),
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
                  validator: (v) =>
                      DriverFormValidators.requiredSelection(v, 'terminal'),
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
                  validator: (v) =>
                      DriverFormValidators.requiredSelection(v, 'shift'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Create pending account'),
        ),
      ],
    );
  }
}

class _VerifyResult {
  const _VerifyResult({required this.verified, this.todaNumber});

  final bool verified;
  final String? todaNumber;
}

class _VerifyDialog extends StatefulWidget {
  const _VerifyDialog({required this.driver});

  final DriverRecord driver;

  @override
  State<_VerifyDialog> createState() => _VerifyDialogState();
}

class _VerifyDialogState extends State<_VerifyDialog> {
  bool _checked = false;
  late final _toda = TextEditingController(text: widget.driver.todaNumber ?? '');
  String? _todaError;

  @override
  void dispose() {
    _toda.dispose();
    super.dispose();
  }

  void _markVerified() {
    final error = DriverFormValidators.ssltodaNumber(_toda.text, required: true);
    setState(() => _todaError = error);
    if (!_checked || error != null) return;
    Navigator.pop(
      context,
      _VerifyResult(verified: true, todaNumber: _toda.text.trim()),
    );
  }

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
            Text(
              widget.driver.fullName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SelectableText(
              widget.driver.licenseNumber,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _toda,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'SSLTODA No.',
                helperText: 'Required when marking this driver as verified.',
                errorText: _todaError,
              ),
              onChanged: (_) {
                if (_todaError != null) setState(() => _todaError = null);
              },
            ),
            const SizedBox(height: 8),
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
          onPressed: () => Navigator.pop(
            context,
            const _VerifyResult(verified: false),
          ),
          child: const Text('Clear verification'),
        ),
        FilledButton(
          onPressed: _checked ? _markVerified : null,
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
