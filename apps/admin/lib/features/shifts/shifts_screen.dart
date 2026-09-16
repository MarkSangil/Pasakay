import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

class ShiftsScreen extends ConsumerStatefulWidget {
  const ShiftsScreen({super.key});

  @override
  ConsumerState<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends ConsumerState<ShiftsScreen> {
  late Future<_ShiftPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ShiftPage> _load() async {
    final repo = ref.read(adminRepositoryProvider);
    final results = await Future.wait([
      repo.fetchShifts(),
      repo.fetchDrivers(),
      repo.fetchBookedDriverIds(),
    ]);
    return _ShiftPage(
      shifts: results[0] as List<ShiftRecord>,
      drivers: results[1] as List<DriverRecord>,
      bookedDriverIds: results[2] as Set<String>,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ShiftPage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Text(friendlyError(snapshot.error!)),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final page = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const PageHeader(
              title: 'Shifts',
              subtitle: 'Edit the 3 predefined blocks and reassign drivers.',
            ),
            const SizedBox(height: 16),
            for (final shift in page.shifts) ...[
              _ShiftCard(
                shift: shift,
                drivers: page.drivers.where((d) => d.shiftId == shift.id).toList(),
                bookedDriverIds: page.bookedDriverIds,
                allShifts: page.shifts,
                onEdit: () => _edit(shift),
                onReassign: (driver, nextId) => _reassign(driver, nextId),
              ),
              const SizedBox(height: 14),
            ],
          ],
        );
      },
    );
  }

  Future<void> _edit(ShiftRecord shift) async {
    final result = await showDialog<_ShiftEdit>(
      context: context,
      builder: (context) => _ShiftDialog(shift: shift),
    );
    if (result == null || !mounted) return;
    try {
      final warning = await ref.read(adminRepositoryProvider).updateShift(
            id: shift.id,
            label: result.label,
            startTime: result.start,
            endTime: result.end,
          );
      if (mounted && warning != null) showInfo(context, warning);
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _reassign(DriverRecord driver, String shiftId) async {
    try {
      await ref.read(adminRepositoryProvider).updateDriver(
            driverId: driver.id,
            fullName: driver.fullName,
            contactNumber: driver.contactNumber,
            licenseNumber: driver.licenseNumber,
            plateNumber: driver.plateNumber,
            username: driver.username,
            terminalId: driver.terminalId,
            shiftId: shiftId,
            todaNumber: driver.todaNumber,
          );
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class _ShiftPage {
  const _ShiftPage({
    required this.shifts,
    required this.drivers,
    required this.bookedDriverIds,
  });
  final List<ShiftRecord> shifts;
  final List<DriverRecord> drivers;
  final Set<String> bookedDriverIds;
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.shift,
    required this.drivers,
    required this.bookedDriverIds,
    required this.allShifts,
    required this.onEdit,
    required this.onReassign,
  });

  final ShiftRecord shift;
  final List<DriverRecord> drivers;
  final Set<String> bookedDriverIds;
  final List<ShiftRecord> allShifts;
  final VoidCallback onEdit;
  final void Function(DriverRecord driver, String shiftId) onReassign;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shift.label, style: Theme.of(context).textTheme.titleMedium),
                      Text(shift.window, style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                OutlinedButton(onPressed: onEdit, child: const Text('Edit times')),
              ],
            ),
            const SizedBox(height: 12),
            if (drivers.isEmpty)
              const Text('No drivers assigned to this block.')
            else
              for (final driver in drivers)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(child: Text(driver.fullName)),
                            if (bookedDriverIds.contains(driver.id)) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.warningSoft,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Booked',
                                  style: TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(driver.terminalName ?? '', style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: driver.shiftId,
                        items: [
                          for (final item in allShifts)
                            DropdownMenuItem(value: item.id, child: Text(item.label)),
                        ],
                        onChanged: (value) {
                          if (value != null && value != driver.shiftId) {
                            onReassign(driver, value);
                          }
                        },
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

class _ShiftEdit {
  const _ShiftEdit(this.label, this.start, this.end);
  final String label;
  final String start;
  final String end;
}

class _ShiftDialog extends StatefulWidget {
  const _ShiftDialog({required this.shift});
  final ShiftRecord shift;

  @override
  State<_ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<_ShiftDialog> {
  late final _label = TextEditingController(text: widget.shift.label);
  late final _start = TextEditingController(text: widget.shift.startTime.substring(0, 5));
  late final _end = TextEditingController(text: widget.shift.endTime.substring(0, 5));

  @override
  void dispose() {
    _label.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit shift block'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _label, decoration: const InputDecoration(labelText: 'Label')),
            const SizedBox(height: 10),
            TextField(
              controller: _start,
              decoration: const InputDecoration(labelText: 'Start (HH:MM)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _end,
              decoration: const InputDecoration(labelText: 'End (HH:MM)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ShiftEdit(_label.text.trim(), _start.text.trim(), _end.text.trim()),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
