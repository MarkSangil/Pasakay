import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/admin_models.dart';
import '../../widgets/admin_widgets.dart';

class BookingSettingsScreen extends ConsumerStatefulWidget {
  const BookingSettingsScreen({super.key});

  @override
  ConsumerState<BookingSettingsScreen> createState() =>
      _BookingSettingsScreenState();
}

class _BookingSettingsScreenState extends ConsumerState<BookingSettingsScreen> {
  late Future<BookingSettings> _future;
  final _dispute = TextEditingController();
  final _expire = TextEditingController();
  final _cooldown = TextEditingController();
  final _review = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _dispute.dispose();
    _expire.dispose();
    _cooldown.dispose();
    _review.dispose();
    super.dispose();
  }

  Future<BookingSettings> _load() async {
    final settings =
        await ref.read(adminRepositoryProvider).fetchBookingSettings();
    _dispute.text = '${settings.disputeWindowMinutes}';
    _expire.text = '${settings.requestExpireMinutes}';
    _cooldown.text = '${settings.requestCooldownMinutes}';
    _review.text = '${settings.reviewEligibleMinutes}';
    return settings;
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _save() async {
    final dispute = int.tryParse(_dispute.text.trim());
    final expire = int.tryParse(_expire.text.trim());
    final cooldown = int.tryParse(_cooldown.text.trim());
    final review = int.tryParse(_review.text.trim());
    if (dispute == null || expire == null || cooldown == null || review == null) {
      showError(context, 'Enter whole numbers for every field.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(adminRepositoryProvider).updateBookingSettings(
            disputeWindowMinutes: dispute,
            requestExpireMinutes: expire,
            requestCooldownMinutes: cooldown,
            reviewEligibleMinutes: review,
          );
      if (!mounted) return;
      showInfo(context, 'Booking settings saved.');
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BookingSettings>(
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

        return ListView(
          padding: const EdgeInsets.all(28),
          children: [
            PageHeader(
              title: 'Booking Settings',
              subtitle:
                  'Configure the booking timer, request windows, and review delay.',
              action: IconButton(
                onPressed: _reload,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
              ),
            ),
            const SizedBox(height: 16),
            DataCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Timers (minutes)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'The dispute / booking timer is how long an accepted booking stays active before auto-complete. Drivers can also finish early.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 18),
                    _NumberField(
                      controller: _dispute,
                      label: 'Booking / dispute timer',
                      helper: 'Default 20. Drivers can report during this window.',
                    ),
                    const SizedBox(height: 12),
                    _NumberField(
                      controller: _expire,
                      label: 'Request expiry',
                      helper: 'How long a pending passenger request stays open.',
                    ),
                    const SizedBox(height: 12),
                    _NumberField(
                      controller: _cooldown,
                      label: 'Request cooldown',
                      helper:
                          'Wait time before the same passenger can request the same driver again.',
                    ),
                    const SizedBox(height: 12),
                    _NumberField(
                      controller: _review,
                      label: 'Review eligible after',
                      helper:
                          'Minutes after confirmation before a completed booking can be reviewed (0 = immediately when completed).',
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save settings'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
