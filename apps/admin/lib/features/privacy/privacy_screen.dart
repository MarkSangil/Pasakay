import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  late Future<_PrivacyPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PrivacyPage> _load() async {
    final repo = ref.read(adminRepositoryProvider);
    final results = await Future.wait([
      repo.fetchPrivacyRequests(),
      repo.fetchCommuters(),
      repo.fetchDrivers(),
    ]);
    return _PrivacyPage(
      requests: results[0] as List<PrivacyRequestRecord>,
      commuters: results[1] as List<CommuterRecord>,
      drivers: results[2] as List<DriverRecord>,
    );
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PrivacyPage>(
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
            PageHeader(
              title: 'Data privacy',
              subtitle: 'Log and handle access, correction, and deletion requests.',
              action: FilledButton.icon(
                onPressed: () => _log(page),
                icon: const Icon(Icons.add),
                label: const Text('Log request'),
              ),
            ),
            const SizedBox(height: 16),
            DataCard(
              child: page.requests.isEmpty
                  ? const EmptyState(message: 'No privacy requests logged yet.')
                  : Column(
                      children: [
                        const TableHeader(cells: ['Request', 'Type', 'Status', '']),
                        for (final request in page.requests)
                          _Row(
                            request: request,
                            onOpen: () => _handle(page, request),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _log(_PrivacyPage page) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _LogDialog(page: page),
    );
    if (saved == true) _reload();
  }

  Future<void> _handle(_PrivacyPage page, PrivacyRequestRecord request) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _HandleDialog(page: page, request: request),
    );
    _reload();
  }
}

class _PrivacyPage {
  const _PrivacyPage({
    required this.requests,
    required this.commuters,
    required this.drivers,
  });

  final List<PrivacyRequestRecord> requests;
  final List<CommuterRecord> commuters;
  final List<DriverRecord> drivers;
}

class _SubjectOption {
  const _SubjectOption({
    required this.id,
    required this.role,
    required this.name,
    required this.contact,
    this.email,
  });

  final String id;
  final String role;
  final String name;
  final String contact;
  final String? email;
}

class _Row extends StatelessWidget {
  const _Row({required this.request, required this.onOpen});

  final PrivacyRequestRecord request;
  final VoidCallback onOpen;

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
                Text(request.subjectName, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${request.subjectRole ?? 'Unlinked'} · ${formatWhen(request.receivedAt)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(child: Text(statusLabel(request.requestType))),
          Expanded(child: StatusChip(status: request.status)),
          Expanded(
            child: TextButton(onPressed: onOpen, child: const Text('Handle')),
          ),
        ],
      ),
    );
  }
}

class _LogDialog extends ConsumerStatefulWidget {
  const _LogDialog({required this.page});
  final _PrivacyPage page;

  @override
  ConsumerState<_LogDialog> createState() => _LogDialogState();
}

class _LogDialogState extends ConsumerState<_LogDialog> {
  String _type = 'access';
  _SubjectOption? _subject;
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _details = TextEditingController();
  bool _saving = false;

  List<_SubjectOption> get _options => [
        for (final c in widget.page.commuters)
          _SubjectOption(
            id: c.id,
            role: 'commuter',
            name: c.fullName,
            contact: c.contactNumber,
            email: c.emailAddress,
          ),
        for (final d in widget.page.drivers)
          _SubjectOption(
            id: d.id,
            role: 'driver',
            name: d.fullName,
            contact: d.contactNumber,
          ),
      ];

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(adminRepositoryProvider).logPrivacyRequest(
            subjectUserId: _subject?.id,
            subjectRole: _subject?.role,
            subjectName: _name.text.trim(),
            subjectContact: _contact.text.trim(),
            requestType: _type,
            details: _details.text.trim(),
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
      title: const Text('Log a request'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'access', child: Text('Access')),
                DropdownMenuItem(value: 'correction', child: Text('Correction')),
                DropdownMenuItem(value: 'deletion', child: Text('Deletion')),
              ],
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Link an account (optional)'),
              items: [
                for (final option in _options)
                  DropdownMenuItem(
                    value: '${option.role}:${option.id}',
                    child: Text('${option.name} (${option.role})'),
                  ),
              ],
              onChanged: (value) {
                final option = _options.cast<_SubjectOption?>().firstWhere(
                      (o) => '${o!.role}:${o.id}' == value,
                      orElse: () => null,
                    );
                setState(() {
                  _subject = option;
                  if (option != null) {
                    _name.text = option.name;
                    _contact.text = option.contact;
                  }
                });
              },
            ),
            const SizedBox(height: 10),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Subject name')),
            const SizedBox(height: 10),
            TextField(controller: _contact, decoration: const InputDecoration(labelText: 'Contact')),
            const SizedBox(height: 10),
            TextField(
              controller: _details,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'What they asked, from outside the app'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Log request')),
      ],
    );
  }
}

class _HandleDialog extends ConsumerStatefulWidget {
  const _HandleDialog({required this.page, required this.request});

  final _PrivacyPage page;
  final PrivacyRequestRecord request;

  @override
  ConsumerState<_HandleDialog> createState() => _HandleDialogState();
}

class _HandleDialogState extends ConsumerState<_HandleDialog> {
  late final _name = TextEditingController(text: widget.request.subjectName);
  late final _contact = TextEditingController(text: widget.request.subjectContact);
  late final _email = TextEditingController();
  late final _notes = TextEditingController(text: widget.request.adminNotes);
  late final _confirm = TextEditingController();
  late final _retentionReason = TextEditingController(
    text: 'Research study retention during the PASAKAY study period.',
  );
  bool _retention = true;
  bool _busy = false;
  Map<String, dynamic>? _snapshot;

  @override
  void initState() {
    super.initState();
    final subject = _linked;
    if (subject?.email != null) _email.text = subject!.email!;
  }

  _SubjectOption? get _linked {
    final id = widget.request.subjectUserId;
    if (id == null) return null;
    for (final c in widget.page.commuters) {
      if (c.id == id) {
        return _SubjectOption(
          id: c.id,
          role: 'commuter',
          name: c.fullName,
          contact: c.contactNumber,
          email: c.emailAddress,
        );
      }
    }
    for (final d in widget.page.drivers) {
      if (d.id == id) {
        return _SubjectOption(
          id: d.id,
          role: 'driver',
          name: d.fullName,
          contact: d.contactNumber,
        );
      }
    }
    return null;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(Map<String, dynamic> snapshot) async {
    final text = const JsonEncoder.withIndent('  ').convert(snapshot);
    await copyText(context, text);
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    return AlertDialog(
      title: Text('${statusLabel(request.requestType)} · ${request.subjectName}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(request.details ?? 'No details recorded.'),
              const SizedBox(height: 12),
              if (request.requestType == 'access') ...[
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            final snapshot = await ref
                                .read(adminRepositoryProvider)
                                .subjectSnapshot(request.id);
                            setState(() => _snapshot = snapshot);
                          } catch (error) {
                            if (!context.mounted) return;
                            showError(context, error);
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: const Text('Generate data snapshot'),
                ),
                if (_snapshot != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(const JsonEncoder.withIndent('  ').convert(_snapshot)),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _download(_snapshot!),
                    child: const Text('Copy JSON'),
                  ),
                ],
              ],
              if (request.requestType == 'correction') ...[
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Corrected name')),
                const SizedBox(height: 8),
                TextField(controller: _contact, decoration: const InputDecoration(labelText: 'Corrected contact')),
                const SizedBox(height: 8),
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(
                    labelText: 'Corrected email (commuter only)',
                  ),
                ),
              ],
              if (request.requestType == 'deletion') ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _retention,
                  onChanged: (value) => setState(() => _retention = value ?? true),
                  title: const Text('Research or legal retention applies'),
                  subtitle: const Text(
                    'Identifiers are anonymized and the account is deactivated. Records stay because the study may override full deletion.',
                  ),
                ),
                if (_retention)
                  TextField(
                    controller: _retentionReason,
                    decoration: const InputDecoration(labelText: 'Retention reason'),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirm,
                  decoration: const InputDecoration(labelText: 'Type the subject name to confirm'),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Admin notes'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        if (request.status != 'denied')
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(() => ref.read(adminRepositoryProvider).setPrivacyStatus(
                      request.id,
                      'denied',
                      _notes.text,
                    )),
            child: const Text('Deny'),
          ),
        if (request.requestType == 'access')
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() => ref.read(adminRepositoryProvider).setPrivacyStatus(
                      request.id,
                      'completed',
                      _notes.text,
                    )),
            child: const Text('Mark completed'),
          ),
        if (request.requestType == 'correction')
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() => ref.read(adminRepositoryProvider).applyCorrection(
                      requestId: request.id,
                      fullName: _name.text,
                      contactNumber: _contact.text,
                      emailAddress: _email.text,
                    )),
            child: const Text('Apply correction'),
          ),
        if (request.requestType == 'deletion')
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: _busy
                ? null
                : () => _run(() => ref.read(adminRepositoryProvider).processDeletion(
                      requestId: request.id,
                      retentionApplies: _retention,
                      retentionReason: _retentionReason.text,
                      confirmName: _confirm.text,
                    )),
            child: const Text('Process deletion'),
          ),
      ],
    );
  }
}
