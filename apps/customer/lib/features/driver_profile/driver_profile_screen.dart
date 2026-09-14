import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_utils.dart';
import '../../models/models.dart';
import '../../widgets/common_widgets.dart';

class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key, required this.driverId});

  final String driverId;

  @override
  ConsumerState<DriverProfileScreen> createState() =>
      _DriverProfileScreenState();
}

class _DriverProfileScreenState extends ConsumerState<DriverProfileScreen> {
  DriverSummary? _driver;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final driver =
          await ref.read(customerRepositoryProvider).fetchDriver(widget.driverId);
      if (!mounted) return;
      setState(() {
        _driver = driver;
        _loading = false;
        _error = driver == null ? 'Driver not found' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _contact(String channel) async {
    final driver = _driver;
    if (driver == null) return;
    await ref.read(customerRepositoryProvider).addRecent(
          RecentContact(
            driverId: driver.id,
            driverName: driver.fullName,
            terminalName: driver.terminalName ?? '',
            contactNumber: driver.contactNumber,
            at: DateTime.now(),
            channel: channel,
          ),
        );
    final auth = ref.read(authServiceProvider);
    if (channel == 'call') {
      await auth.openCall(driver.contactNumber);
    } else {
      await auth.openSms(driver.contactNumber);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = _driver;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const GreenAppBar(title: 'Driver Profile', showBack: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                        children: [
                          const Center(child: AvatarCircle(size: 96)),
                          const SizedBox(height: 14),
                          Text(
                            driver!.fullName,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            driver.todaNumber == null ||
                                    driver.todaNumber!.isEmpty
                                ? 'SSLTODA No. —'
                                : 'SSLTODA No. ${driver.todaNumber}',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 28),
                          _InfoRow(
                            icon: Icons.directions_car_outlined,
                            label: 'Plate Number',
                            value: driver.plateNumber,
                          ),
                          _InfoRow(
                            icon: Icons.phone_outlined,
                            label: 'Mobile Number',
                            value: PhoneUtils.display(driver.contactNumber),
                          ),
                          _InfoRow(
                            icon: Icons.workspace_premium_outlined,
                            label: 'Years of Service',
                            value: driver.yearsOfService > 0
                                ? '${driver.yearsOfService} years'
                                : '—',
                          ),
                          _InfoRow(
                            icon: Icons.location_on_outlined,
                            label: 'Assigned Terminal',
                            value: driver.terminalName ?? '—',
                          ),
                          _InfoRow(
                            icon: Icons.schedule_outlined,
                            label: 'Current Schedule',
                            value: driver.shiftLabel ?? '—',
                          ),
                        ],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _contact('call'),
                                icon: const Icon(Icons.phone_rounded),
                                label: const Text('Call'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _contact('sms'),
                                icon: const Icon(Icons.chat_bubble_outline),
                                label: const Text('Message'),
                              ),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
