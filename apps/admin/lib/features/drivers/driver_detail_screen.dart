import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/driver_form_validators.dart';
import '../../core/utils/text_formatters.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

class DriverDetailScreen extends ConsumerStatefulWidget {
  const DriverDetailScreen({super.key, required this.driverId});

  final String driverId;

  @override
  ConsumerState<DriverDetailScreen> createState() => _DriverDetailScreenState();
}

class _DriverDetailScreenState extends ConsumerState<DriverDetailScreen> {
  late Future<_DetailPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DetailPage> _load() async {
    final repo = ref.read(adminRepositoryProvider);
    final results = await Future.wait([
      repo.fetchDriver(widget.driverId),
      repo.fetchTerminals(),
      repo.fetchShifts(),
      repo.isDriverOnShift(widget.driverId),
    ]);
    return _DetailPage(
      driver: results[0] as DriverRecord?,
      terminals: results[1] as List<TerminalRecord>,
      shifts: results[2] as List<ShiftRecord>,
      onShiftNow: results[3] as bool,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DetailPage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading driver...'),
              ],
            ),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Text(friendlyError(snapshot.error!)),
          );
        }
        final page = snapshot.data!;
        if (page.driver == null) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: () => context.go('/drivers'),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to drivers'),
                ),
                const SizedBox(height: 24),
                const Text('Driver not found.'),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            TextButton.icon(
              onPressed: () => context.go('/drivers'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to drivers'),
            ),
            const SizedBox(height: 12),
            PageHeader(
              title: page.driver!.fullName,
              subtitle: 'View and update profile details and shift availability.',
              action: StatusChip(status: page.driver!.status),
            ),
            const SizedBox(height: 20),
            _DetailsCard(
              page: page,
              onSaved: _reload,
            ),
            const SizedBox(height: 16),
            _AvailabilityCard(
              page: page,
              onSaved: _reload,
            ),
          ],
        );
      },
    );
  }
}

class _DetailPage {
  const _DetailPage({
    required this.driver,
    required this.terminals,
    required this.shifts,
    required this.onShiftNow,
  });

  final DriverRecord? driver;
  final List<TerminalRecord> terminals;
  final List<ShiftRecord> shifts;
  final bool onShiftNow;
}

class _DetailsCard extends ConsumerStatefulWidget {
  const _DetailsCard({required this.page, required this.onSaved});

  final _DetailPage page;
  final VoidCallback onSaved;

  @override
  ConsumerState<_DetailsCard> createState() => _DetailsCardState();
}

class _DetailsCardState extends ConsumerState<_DetailsCard> {
  bool _editing = false;
  bool _saving = false;
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.page.driver!.fullName);
  late final _contact =
      TextEditingController(text: widget.page.driver!.contactNumber);
  late final _username =
      TextEditingController(text: widget.page.driver!.username);
  late final _license =
      TextEditingController(text: widget.page.driver!.licenseNumber);
  late final _plate =
      TextEditingController(text: widget.page.driver!.plateNumber);
  late final _toda =
      TextEditingController(text: widget.page.driver!.todaNumber ?? '');
  late String? _terminalId = widget.page.driver!.terminalId;

  @override
  void didUpdateWidget(covariant _DetailsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.page.driver?.id == widget.page.driver?.id) {
      final d = widget.page.driver!;
      _name.text = d.fullName;
      _contact.text = d.contactNumber;
      _username.text = d.username;
      _license.text = d.licenseNumber;
      _plate.text = d.plateNumber;
      _toda.text = d.todaNumber ?? '';
      _terminalId = d.terminalId;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _username.dispose();
    _license.dispose();
    _plate.dispose();
    _toda.dispose();
    super.dispose();
  }

  void _cancel() {
    final d = widget.page.driver!;
    setState(() {
      _editing = false;
      _name.text = d.fullName;
      _contact.text = d.contactNumber;
      _username.text = d.username;
      _license.text = d.licenseNumber;
      _plate.text = d.plateNumber;
      _toda.text = d.todaNumber ?? '';
      _terminalId = d.terminalId;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final driver = widget.page.driver!;
      await ref.read(adminRepositoryProvider).updateDriver(
            driverId: driver.id,
            fullName: _name.text.trim(),
            contactNumber: _contact.text.trim(),
            licenseNumber: _license.text.trim(),
            plateNumber: _plate.text.trim(),
            username: _username.text.trim(),
            terminalId: _terminalId!,
            shiftId: driver.shiftId,
            todaNumber: _toda.text.trim(),
          );
      if (!mounted) return;
      setState(() => _editing = false);
      showInfo(context, 'Driver details updated successfully.');
      widget.onSaved();
    } catch (error) {
      if (mounted) {
        showError(
          context,
          'Unable to update driver details. ${friendlyError(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.page.driver!;
    return DataCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Driver details',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (!_editing)
                  OutlinedButton(
                    onPressed: () => setState(() => _editing = true),
                    child: const Text('Edit'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_editing) ...[
              _DetailRow(label: 'Name', value: driver.fullName),
              _DetailRow(label: 'Phone', value: driver.contactNumber),
              _DetailRow(label: 'Username', value: driver.username),
              _DetailRow(label: 'License No.', value: driver.licenseNumber),
              _DetailRow(
                label: 'License check',
                value: driver.licenseVerified
                    ? 'Visually verified${driver.licenseVerifiedAt == null ? '' : ' · ${formatWhen(driver.licenseVerifiedAt)}'}'
                    : 'Not verified',
              ),
              _DetailRow(label: 'Plate', value: driver.plateNumber),
              _DetailRow(label: 'SSLTODA No.', value: driver.todaNumber ?? '—'),
              _DetailRow(label: 'Terminal', value: driver.terminalName ?? '—'),
              _DetailRow(label: 'Status', value: statusLabel(driver.status)),
              if (driver.statusReason != null && driver.statusReason!.isNotEmpty)
                _DetailRow(label: 'Status reason', value: driver.statusReason!),
            ] else
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      validator: DriverFormValidators.requiredName,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _contact,
                      decoration:
                          const InputDecoration(labelText: 'Contact number'),
                      validator: DriverFormValidators.contactNumber,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(labelText: 'Username'),
                      validator: DriverFormValidators.requiredName,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _license,
                      inputFormatters: [DriverLicenseFormatter()],
                      decoration: const InputDecoration(
                        labelText: "Driver's License (D00-00-000000)",
                        helperText:
                            'Changing the license clears verification until checked again.',
                      ),
                      validator: DriverFormValidators.licenseNumber,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _plate,
                      inputFormatters: [PlateNumberFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Plate Number (ABC-1234)',
                      ),
                      validator: DriverFormValidators.plateNumber,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _toda,
                      decoration: const InputDecoration(
                        labelText: 'SSLTODA No.',
                      ),
                      validator: (v) =>
                          DriverFormValidators.ssltodaNumber(v),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _terminalId,
                      decoration:
                          const InputDecoration(labelText: 'Terminal'),
                      items: [
                        for (final t in widget.page.terminals)
                          DropdownMenuItem(value: t.id, child: Text(t.name)),
                      ],
                      onChanged: (value) =>
                          setState(() => _terminalId = value),
                      validator: (v) =>
                          DriverFormValidators.requiredSelection(v, 'terminal'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _saving ? null : _cancel,
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? 'Saving...' : 'Save Changes'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AvailabilityCard extends ConsumerStatefulWidget {
  const _AvailabilityCard({required this.page, required this.onSaved});

  final _DetailPage page;
  final VoidCallback onSaved;

  @override
  ConsumerState<_AvailabilityCard> createState() => _AvailabilityCardState();
}

class _AvailabilityCardState extends ConsumerState<_AvailabilityCard> {
  late String? _shiftId = widget.page.driver!.shiftId;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _AvailabilityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.driver?.shiftId != widget.page.driver?.shiftId) {
      _shiftId = widget.page.driver!.shiftId;
    }
  }

  Future<void> _save() async {
    if (_shiftId == null) {
      showError(context, 'Select one of the 3 shift blocks.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(adminRepositoryProvider).updateDriverAvailability(
            driver: widget.page.driver!,
            shiftId: _shiftId!,
          );
      if (!mounted) return;
      showInfo(context, 'Driver availability updated successfully.');
      widget.onSaved();
    } catch (error) {
      if (mounted) {
        showError(
          context,
          'Unable to update availability. ${friendlyError(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.page.driver!;
            final current = widget.page.shifts
                .where((s) => s.id == driver.shiftId)
                .cast<ShiftRecord?>()
                .firstOrNull;
    final dirty = _shiftId != driver.shiftId;

    return DataCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Driver availability',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'PASAKAY availability is the assigned shift block (one of 3). '
              'It is schedule assignment, not clock-in attendance.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            _DetailRow(
              label: 'Current assignment',
              value: current == null
                  ? '—'
                  : '${current.label} (${current.window})',
            ),
            _DetailRow(
              label: 'On shift now',
              value: widget.page.onShiftNow
                  ? 'Yes (active account + inside shift window, Asia/Manila)'
                  : 'No',
            ),
            if (driver.status != 'active')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'This driver is ${statusLabel(driver.status).toLowerCase()}, '
                  'so they will not appear as on shift until activated.',
                  style: const TextStyle(color: AppColors.warning, fontSize: 13),
                ),
              ),
            DropdownButtonFormField<String>(
              initialValue: _shiftId,
              decoration: const InputDecoration(labelText: 'Assigned shift'),
              items: [
                for (final shift in widget.page.shifts)
                  DropdownMenuItem(
                    value: shift.id,
                    child: Text('${shift.label} (${shift.window})'),
                  ),
              ],
              onChanged: (value) => setState(() => _shiftId = value),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving || !dirty
                      ? null
                      : () => setState(() => _shiftId = driver.shiftId),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving || !dirty ? null : _save,
                  child: Text(_saving ? 'Saving...' : 'Save Availability'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
