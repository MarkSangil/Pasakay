import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../widgets/common_widgets.dart';

class DriverListScreen extends ConsumerStatefulWidget {
  const DriverListScreen({
    super.key,
    required this.terminalId,
    required this.terminalName,
  });

  final String terminalId;
  final String terminalName;

  @override
  ConsumerState<DriverListScreen> createState() => _DriverListScreenState();
}

class _DriverListScreenState extends ConsumerState<DriverListScreen> {
  List<Shift> _shifts = const [];
  List<DriverSummary> _drivers = const [];
  String? _selectedShiftId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(customerRepositoryProvider);
      final shifts = await repo.fetchShifts();
      final selected = shifts.isNotEmpty ? shifts.first.id : null;
      final drivers = await repo.fetchDrivers(
        terminalId: widget.terminalId,
        shiftId: selected,
      );
      if (!mounted) return;
      setState(() {
        _shifts = shifts;
        _selectedShiftId = selected;
        _drivers = drivers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _selectShift(String shiftId) async {
    setState(() {
      _selectedShiftId = shiftId;
      _loading = true;
    });
    try {
      final drivers = await ref.read(customerRepositoryProvider).fetchDrivers(
            terminalId: widget.terminalId,
            shiftId: shiftId,
          );
      if (!mounted) return;
      setState(() {
        _drivers = drivers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _contact({
    required DriverSummary driver,
    required String channel,
  }) async {
    final auth = ref.read(authServiceProvider);
    await ref.read(customerRepositoryProvider).addRecent(
          RecentContact(
            driverId: driver.id,
            driverName: driver.fullName,
            terminalName: driver.terminalName ?? widget.terminalName,
            contactNumber: driver.contactNumber,
            at: DateTime.now(),
            channel: channel,
          ),
        );
    if (channel == 'call') {
      await auth.openCall(driver.contactNumber);
    } else {
      await auth.openSms(driver.contactNumber);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: GreenAppBar(title: widget.terminalName, showBack: true),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Select Schedule',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _shifts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = _shifts[i];
                final selected = s.id == _selectedShiftId;
                return ChoiceChip(
                  label: Text(s.chipLabel),
                  selected: selected,
                  onSelected: (_) => _selectShift(s.id),
                  selectedColor: AppColors.primary,
                  backgroundColor: Colors.white,
                  labelStyle: GoogleFonts.plusJakartaSans(
                    color: selected ? Colors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                  side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                  showCheckmark: false,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: Center(child: Text(_error!)))
          else if (_drivers.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No drivers on this schedule yet.',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: _drivers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final d = _drivers[i];
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => context.push('/driver/${d.id}'),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const AvatarCircle(size: 48),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.fullName,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Plate No. ${d.plateNumber}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    d.todaNumber == null || d.todaNumber!.isEmpty
                                        ? 'SSLTODA No. —'
                                        : 'SSLTODA No. ${d.todaNumber}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _RoundAction(
                              icon: Icons.phone_rounded,
                              onTap: () => _contact(driver: d, channel: 'call'),
                            ),
                            const SizedBox(width: 8),
                            _RoundAction(
                              icon: Icons.chat_bubble_rounded,
                              onTap: () => _contact(driver: d, channel: 'sms'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
