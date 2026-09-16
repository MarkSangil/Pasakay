import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

class TerminalsScreen extends ConsumerStatefulWidget {
  const TerminalsScreen({super.key});

  @override
  ConsumerState<TerminalsScreen> createState() => _TerminalsScreenState();
}

class _TerminalsScreenState extends ConsumerState<TerminalsScreen> {
  late Future<List<TerminalRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(adminRepositoryProvider).fetchTerminals();
  }

  void _reload() {
    setState(() {
      _future = ref.read(adminRepositoryProvider).fetchTerminals();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TerminalRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(28),
            child: Text(friendlyError(snapshot.error!)),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final terminals = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            PageHeader(
              title: 'Terminals',
              subtitle: 'A plain-text list of terminals. No map and no capacity limits.',
              action: FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Add terminal'),
              ),
            ),
            const SizedBox(height: 16),
            DataCard(
              child: terminals.isEmpty
                  ? const EmptyState(message: 'No terminals yet.')
                  : Column(
                      children: [
                        const TableHeader(cells: ['Name', 'Assigned drivers', 'Added', '']),
                        for (final terminal in terminals)
                          _Row(
                            terminal: terminal,
                            onEdit: () => _edit(terminal),
                            onDelete: () => _delete(terminal),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _edit([TerminalRecord? existing]) async {
    final name = await promptText(
      context,
      title: existing == null ? 'Add terminal' : 'Edit terminal',
      label: 'Terminal name',
      initial: existing?.name,
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final repo = ref.read(adminRepositoryProvider);
      if (existing == null) {
        await repo.createTerminal(name);
      } else {
        await repo.updateTerminal(existing.id, name);
      }
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _delete(TerminalRecord terminal) async {
    if (terminal.assignedDrivers > 0) {
      showInfo(
        context,
        'Cannot delete this terminal while ${terminal.assignedDrivers} driver(s) are still assigned. Reassign them first.',
      );
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Delete terminal?',
      message: 'Remove ${terminal.name} from the list?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(adminRepositoryProvider).deleteTerminal(terminal.id);
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.terminal,
    required this.onEdit,
    required this.onDelete,
  });

  final TerminalRecord terminal;
  final VoidCallback onEdit;
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
          Expanded(flex: 2, child: Text(terminal.name, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text('${terminal.assignedDrivers}')),
          Expanded(child: Text(formatWhen(terminal.createdAt))),
          Expanded(
            child: Row(
              children: [
                TextButton(onPressed: onEdit, child: const Text('Edit')),
                TextButton(onPressed: onDelete, child: const Text('Delete')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
