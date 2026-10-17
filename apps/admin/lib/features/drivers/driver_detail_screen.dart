import 'dart:async';

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
              subtitle:
                  'View and update profile details and shift availability.',
              action: StatusChip(status: page.driver!.status),
            ),
            const SizedBox(height: 20),
            _DetailsCard(page: page, onSaved: _reload),
            const SizedBox(height: 16),
            _AvailabilityCard(page: page, onSaved: _reload),
            const SizedBox(height: 16),
            _ActivityCard(driverId: page.driver!.id),
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
  late final _contact = TextEditingController(
    text: widget.page.driver!.contactNumber,
  );
  late final _username = TextEditingController(
    text: widget.page.driver!.username,
  );
  late final _plate = TextEditingController(
    text: widget.page.driver!.plateNumber,
  );
  late final _toda = TextEditingController(
    text: widget.page.driver!.todaNumber ?? '',
  );
  late String? _terminalId = widget.page.driver!.terminalId;

  @override
  void didUpdateWidget(covariant _DetailsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.page.driver?.id == widget.page.driver?.id) {
      final d = widget.page.driver!;
      _name.text = d.fullName;
      _contact.text = d.contactNumber;
      _username.text = d.username;
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
      await ref
          .read(adminRepositoryProvider)
          .updateDriver(
            driverId: driver.id,
            fullName: _name.text.trim(),
            contactNumber: _contact.text.trim(),
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
              _DetailRow(
                label: 'TODA Plate No.',
                value: driver.todaNumber ?? '—',
              ),
              _DetailRow(
                label: 'Verification',
                value: driver.todaVerified
                    ? 'Verified${driver.todaVerifiedAt == null ? '' : ' · ${formatWhen(driver.todaVerifiedAt)}'}'
                    : 'Not verified',
              ),
              _DetailRow(label: 'Plate', value: driver.plateNumber),
              _DetailRow(label: 'Terminal', value: driver.terminalName ?? '—'),
              _DetailRow(label: 'Status', value: statusLabel(driver.status)),
              if (driver.statusReason != null &&
                  driver.statusReason!.isNotEmpty)
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
                      decoration: const InputDecoration(
                        labelText: 'Contact number',
                      ),
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
                        labelText: 'TODA Plate Number (e.g. SSLTODA No. 00876)',
                        helperText: 'Changing the TODA plate clears verification until checked again.',
                      ),
                      validator: DriverFormValidators.todaPlateNumber,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _terminalId,
                      decoration: const InputDecoration(labelText: 'Terminal'),
                      items: [
                        for (final t in widget.page.terminals)
                          DropdownMenuItem(value: t.id, child: Text(t.name)),
                      ],
                      onChanged: (value) => setState(() => _terminalId = value),
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
      await ref
          .read(adminRepositoryProvider)
          .updateDriverAvailability(
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
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondary),
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
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 13,
                  ),
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

/// Recorded foreground-app usage for one driver.
///
/// Shows the live activity state plus totals over a selectable reporting
/// period. Totals count heartbeat-backed foreground time only — never
/// login-to-logout spans, background time, or gaps past the timeout.
class _ActivityCard extends ConsumerStatefulWidget {
  const _ActivityCard({required this.driverId});

  final String driverId;

  @override
  ConsumerState<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends ConsumerState<_ActivityCard> {
  int _rangeDays = 7;
  late Future<_ActivityPage> _future;
  Timer? _sweepTimer;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Periodic refresh so logins/heartbeats made after the screen opened
    // are reflected without leaving the page.
    _sweepTimer = Timer.periodic(const Duration(minutes: 5), (_) => _sweep());
  }

  @override
  void dispose() {
    _sweepTimer?.cancel();
    super.dispose();
  }

  Future<_ActivityPage> _load() async {
    final repo = ref.read(adminRepositoryProvider);
    final now = DateTime.now().toUtc();
    final from = now.subtract(Duration(days: _rangeDays));
    final results = await Future.wait([
      // Best effort: a state failure must not hide the usage totals.
      repo
          .fetchDriverActivityStates()
          .then(
            (list) => list
                .where((s) => s.driverId == widget.driverId)
                .cast<DriverActivityState?>()
                .firstOrNull,
          )
          .catchError((_) => null),
      repo.fetchDriverUsageSummary(
        driverId: widget.driverId,
        from: from,
        to: now,
      ),
    ]);
    return _ActivityPage(
      state: results[0] as DriverActivityState?,
      summary: results[1] as DriverUsageSummary,
      days: _rangeDays,
    );
  }

  void _setRange(int days) {
    if (days == _rangeDays) return;
    setState(() {
      _rangeDays = days;
      _future = _load();
    });
  }

  /// Periodic refresh of the activity state + usage summary. Best effort:
  /// the sweep never blanks the card on a transient failure.
  Future<void> _sweep() async {
    if (!mounted) return;
    try {
      final next = await _load();
      if (!mounted) return;
      setState(() {
        _future = Future.value(next);
      });
    } catch (_) {
      // Keep showing the previous data on failure.
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    'App usage',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('Today')),
                    ButtonSegment(value: 7, label: Text('7 days')),
                    ButtonSegment(value: 30, label: Text('30 days')),
                  ],
                  selected: {_rangeDays},
                  onSelectionChanged: (set) => _setRange(set.first),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Recorded foreground usage — not login time, shift, or account status.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 14),
            FutureBuilder<_ActivityPage>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Text(friendlyError(snapshot.error!));
                }
                final page = snapshot.data!;
                final summary = page.summary;
                final state = page.state;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailRow(
                      label: 'State',
                      value: state == null
                          ? 'Unknown (no data)'
                          : _stateMeaning(state),
                    ),
                    _DetailRow(
                      label: 'Last seen',
                      value: summary.lastSeen == null
                          ? 'Never recorded'
                          : formatWhen(summary.lastSeen),
                    ),
                    _DetailRow(
                      label: 'Foreground use',
                      value:
                          '${_clock(summary.totalForegroundSeconds)} over ${page.days == 1 ? 'today' : '${page.days} days'}',
                    ),
                    _DetailRow(label: 'Sessions', value: '${summary.sessions}'),
                    _DetailRow(
                      label: 'Active days',
                      value: '${summary.activeDays}',
                    ),
                    if (summary.sessions == 0 &&
                        summary.totalForegroundSeconds == 0)
                      const Padding(
                        padding: EdgeInsets.only(top: 4, bottom: 8),
                        child: Text(
                          'No qualifying foreground activity in this period. '
                          'This driver never opened the app here, or usage predates tracking.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (summary.sessionsDetail.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Recent sessions (up to 50)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      for (final s in summary.sessionsDetail.take(20))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${formatWhen(s.startedAt)} → ${s.endedAt == null ? 'open' : formatWhen(s.endedAt)}'
                            ' · ${s.beats} beats'
                            '${s.foregroundSeconds == null ? '' : ' · ${_clock(s.foregroundSeconds!)} foreground'}'
                            '${s.endReason == null ? '' : ' · ended: ${s.endReason}'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _stateMeaning(DriverActivityState state) {
    final current = state.currentActiveSeconds == null
        ? ''
        : ' · active ${_clock(state.currentActiveSeconds!)}';
    return switch (state.state) {
      'active_now' =>
        'Active now — foreground heartbeat within timeout$current',
      'inactive' =>
        'Inactive — no heartbeat within the timeout (includes stale sessions)',
      'offline' => 'Offline — logged out, nothing since',
      _ => 'Unknown — not enough data to judge',
    };
  }

  String _clock(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  }
}

class _ActivityPage {
  const _ActivityPage({
    required this.state,
    required this.summary,
    required this.days,
  });

  final DriverActivityState? state;
  final DriverUsageSummary summary;
  final int days;
}
