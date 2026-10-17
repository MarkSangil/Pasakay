import 'dart:async';

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
  late Future<_CommuterPage> _future;
  Map<String, DriverActivityState> _liveActivity = {};
  Timer? _sweepTimer;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Same live cadence as the Drivers list: a passenger who opens the app
    // is reflected in the activity column within this interval.
    _sweepTimer = Timer.periodic(const Duration(minutes: 5), (_) => _sweep());
  }

  @override
  void dispose() {
    _sweepTimer?.cancel();
    super.dispose();
  }

  Future<_CommuterPage> _load() async {
    final repo = ref.read(adminRepositoryProvider);
    final results = await Future.wait([
      repo.fetchCommuters(),
      // Best effort: activity states must never block the commuter list.
      repo.fetchCommuterActivityStates().catchError(
        (_) => <DriverActivityState>[],
      ),
    ]);
    final states = results[1] as List<DriverActivityState>;
    return _CommuterPage(
      commuters: results[0] as List<CommuterRecord>,
      activityByUser: {for (final s in states) s.userId: s},
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  /// Periodic refresh of app-activity states only (lightweight RPC).
  Future<void> _sweep() async {
    if (!mounted) return;
    try {
      final states = await ref
          .read(adminRepositoryProvider)
          .fetchCommuterActivityStates();
      if (!mounted) return;
      setState(() {
        _liveActivity = {for (final s in states) s.userId: s};
      });
    } catch (_) {
      // Best effort: keep showing the last known states.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CommuterPage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Text(friendlyError(snapshot.error!)),
          );
        }
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final page = snapshot.data!;
        // The sweep's live states win over the page-load snapshot so new
        // logins appear in the list without a manual reload.
        final activityStates = _liveActivity.isNotEmpty
            ? _liveActivity
            : page.activityByUser;
        final commuters = page.commuters.where((c) {
          final haystack = '${c.fullName} ${c.username} ${c.contactNumber}'
              .toLowerCase();
          return haystack.contains(_query.toLowerCase());
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const PageHeader(
              title: 'Commuters',
              subtitle: 'Approve pending signups, or deactivate accounts.',
            ),
            const SizedBox(height: 16),
            SearchField(
              hint: 'Search name or contact',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 16),
            DataCard(
              child: commuters.isEmpty
                  ? const EmptyState(message: 'No commuter accounts match.')
                  : Column(
                      children: [
                        const TableHeader(
                          cells: [
                            'Commuter',
                            'Contact',
                            'App activity',
                            'Status',
                            '',
                          ],
                        ),
                        for (final commuter in commuters)
                          _Row(
                            commuter: commuter,
                            activity: activityStates[commuter.id],
                            onStatus: () => _setStatus(commuter),
                            onReset: () => _resetPassword(commuter),
                            onActivity: () => _showActivity(commuter),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showActivity(CommuterRecord commuter) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _CommuterActivityDialog(commuter: commuter),
    );
    _reload();
  }

  Future<void> _setStatus(CommuterRecord commuter) async {
    final result = await showDialog<_Choice>(
      context: context,
      builder: (context) => _StatusDialog(commuter: commuter),
    );
    if (result == null || !mounted) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .setCommuterStatus(commuter.id, result.status, result.reason);
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

class _CommuterPage {
  const _CommuterPage({required this.commuters, required this.activityByUser});

  final List<CommuterRecord> commuters;
  final Map<String, DriverActivityState> activityByUser;
}

class _Row extends StatelessWidget {
  const _Row({
    required this.commuter,
    required this.onStatus,
    required this.onReset,
    required this.onActivity,
    this.activity,
  });

  final CommuterRecord commuter;
  final VoidCallback onStatus;
  final VoidCallback onReset;
  final VoidCallback onActivity;
  final DriverActivityState? activity;

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
                Text(
                  commuter.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  commuter.username,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: Text(commuter.contactNumber)),
          Expanded(child: _CommuterActivityCell(activity: activity)),
          Expanded(child: StatusChip(status: commuter.status)),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: onActivity,
                    child: const Text('Activity'),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'status') onStatus();
                      if (value == 'reset') onReset();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'status', child: Text('Set status')),
                      PopupMenuItem(
                        value: 'reset',
                        child: Text('Reset password'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recorded foreground-app activity (not account status or login).
/// Missing data renders as Unknown, never as active.
class _CommuterActivityCell extends StatelessWidget {
  const _CommuterActivityCell({required this.activity});

  final DriverActivityState? activity;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    if (a == null) {
      return const Text('—', style: TextStyle(fontSize: 13));
    }
    final color = switch (a.state) {
      'active_now' => AppColors.success,
      'inactive' => AppColors.warning,
      'offline' => AppColors.textMuted,
      _ => AppColors.textSecondary,
    };
    final detail = a.state == 'active_now' && a.currentActiveSeconds != null
        ? 'active ${_formatDuration(a.currentActiveSeconds!)}'
        : (a.lastSeen == null ? 'never seen' : formatWhen(a.lastSeen));
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                a.label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                detail,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final h = totalSeconds ~/ 3600;
    if (h > 0)
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Per-commuter dialog: live activity state + usage totals (Today/7/30)
/// plus the audit trail of screens and key actions.
class _CommuterActivityDialog extends ConsumerStatefulWidget {
  const _CommuterActivityDialog({required this.commuter});

  final CommuterRecord commuter;

  @override
  ConsumerState<_CommuterActivityDialog> createState() =>
      _CommuterActivityDialogState();
}

class _CommuterActivityDialogState
    extends ConsumerState<_CommuterActivityDialog> {
  int _rangeDays = 7;
  late Future<_CommuterActivityPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_CommuterActivityPage> _load() async {
    final repo = ref.read(adminRepositoryProvider);
    final now = DateTime.now().toUtc();
    final from = now.subtract(Duration(days: _rangeDays));
    final results = await Future.wait([
      // Best effort: a state failure must not hide usage totals.
      repo
          .fetchCommuterActivityStates()
          .then(
            (list) => list
                .where((s) => s.userId == widget.commuter.id)
                .cast<DriverActivityState?>()
                .firstOrNull,
          )
          .catchError((_) => null),
      repo.fetchCommuterUsageSummary(
        commuterId: widget.commuter.id,
        from: from,
        to: now,
      ),
      // Best effort: audit trail must not hide usage totals.
      repo
          .fetchAuditLogs(role: 'commuter', userId: widget.commuter.id)
          .catchError((_) => <AuditLogEntry>[]),
    ]);
    return _CommuterActivityPage(
      state: results[0] as DriverActivityState?,
      summary: results[1] as DriverUsageSummary,
      logs: results[2] as List<AuditLogEntry>,
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.commuter.fullName),
      content: SizedBox(
        width: 560,
        child: FutureBuilder<_CommuterActivityPage>(
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
            String clock(int totalSeconds) {
              final h = totalSeconds ~/ 3600;
              final m = (totalSeconds % 3600) ~/ 60;
              final s = totalSeconds % 60;
              final mm = m.toString().padLeft(2, '0');
              final ss = s.toString().padLeft(2, '0');
              return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
            }

            String stateMeaning(DriverActivityState state) {
              final current = state.currentActiveSeconds == null
                  ? ''
                  : ' · active ${clock(state.currentActiveSeconds!)}';
              return switch (state.state) {
                'active_now' =>
                  'Active now — foreground heartbeat within timeout$current',
                'inactive' => 'Inactive — no heartbeat within the timeout (includes stale sessions)',
                'offline' => 'Offline — logged out, nothing since',
                _ => 'Unknown — not enough data to judge',
              };
            }

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('App activity'),
                      const Spacer(),
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
                    'Recorded foreground usage — not login time or account status.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _DRow(
                    label: 'State',
                    value: state == null
                        ? 'Unknown (no data)'
                        : stateMeaning(state),
                  ),
                  _DRow(
                    label: 'Last seen',
                    value: summary.lastSeen == null
                        ? 'Never recorded'
                        : formatWhen(summary.lastSeen),
                  ),
                  _DRow(
                    label: 'Foreground use',
                    value:
                        '${clock(summary.totalForegroundSeconds)} over ${page.days == 1 ? 'today' : '${page.days} days'}',
                  ),
                  _DRow(label: 'Sessions', value: '${summary.sessions}'),
                  _DRow(label: 'Active days', value: '${summary.activeDays}'),
                  const Divider(height: 24),
                  const Text(
                    'Activity log (latest actions)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (page.logs.isEmpty)
                    const Text(
                      'No recorded actions yet.',
                      style: TextStyle(color: AppColors.textSecondary),
                    )
                  else
                    for (final log in page.logs.take(20))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${formatWhen(log.occurredAt)} · ${log.displayText}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _CommuterActivityPage {
  const _CommuterActivityPage({
    required this.state,
    required this.summary,
    required this.logs,
    required this.days,
  });

  final DriverActivityState? state;
  final DriverUsageSummary summary;
  final List<AuditLogEntry> logs;
  final int days;
}

class _DRow extends StatelessWidget {
  const _DRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
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
                DropdownMenuItem(
                  value: 'active',
                  child: Text('Active (approve)'),
                ),
                DropdownMenuItem(
                  value: 'deactivated',
                  child: Text('Deactivated'),
                ),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _Choice(_status, _reason.text.trim())),
          child: const Text('Update'),
        ),
      ],
    );
  }
}
