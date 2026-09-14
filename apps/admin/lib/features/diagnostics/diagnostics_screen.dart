import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  bool _crashesOnly = false;
  String? _openId;
  late Future<List<DeviceLogRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(adminRepositoryProvider).fetchDeviceLogs();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DeviceLogRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Text(friendlyError(snapshot.error!)),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final logs = snapshot.data!.where((log) => !_crashesOnly || log.isCrash).toList();

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const PageHeader(
              title: 'Diagnostics',
              subtitle: 'Read-only device and crash logs for troubleshooting.',
            ),
            const SizedBox(height: 16),
            FilterChip(
              label: const Text('Crashes only'),
              selected: _crashesOnly,
              onSelected: (value) => setState(() => _crashesOnly = value),
            ),
            const SizedBox(height: 16),
            DataCard(
              child: logs.isEmpty
                  ? const EmptyState(
                      message:
                          'No diagnostic logs yet. Crash rows show up only when an app records one.',
                    )
                  : Column(
                      children: [
                        const TableHeader(
                          cells: ['When', 'User', 'Device', 'App', ''],
                        ),
                        for (final log in logs) _LogRow(
                          log: log,
                          open: _openId == log.id,
                          onToggle: () => setState(
                            () => _openId = _openId == log.id ? null : log.id,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.log,
    required this.open,
    required this.onToggle,
  });

  final DeviceLogRecord log;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text(formatWhen(log.accessedAt))),
                Expanded(
                  child: Text('${log.userName ?? 'Unknown'} · ${log.userType}'),
                ),
                Expanded(child: Text('${log.deviceModel ?? '—'} · ${log.osVersion ?? '—'}')),
                Expanded(child: Text(log.appVersion ?? '—')),
                Expanded(
                  child: TextButton(
                    onPressed: log.isCrash ? onToggle : null,
                    child: Text(log.isCrash ? (open ? 'Hide crash' : 'View crash') : 'No crash log'),
                  ),
                ),
              ],
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SelectableText(log.crashLog ?? ''),
            ),
        ],
      ),
    );
  }
}
