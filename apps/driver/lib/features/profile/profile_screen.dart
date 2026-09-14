import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_utils.dart';
import '../../widgets/common_widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final driver = session.value;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const DriverAppBar(title: 'My Profile'),
      body: session.isLoading
          ? const Center(child: CircularProgressIndicator())
          : driver == null
              ? const Center(child: Text('Not signed in'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                  children: [
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 58,
                            backgroundColor: AppColors.border,
                            backgroundImage: driver.avatarUrl != null
                                ? NetworkImage(driver.avatarUrl!)
                                : null,
                            child: driver.avatarUrl == null
                                ? const Icon(
                                    Icons.person,
                                    size: 58,
                                    color: AppColors.textMuted,
                                  )
                                : null,
                          ),
                          Positioned(
                            right: 2,
                            bottom: 2,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.photo_camera_outlined,
                                size: 15,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      driver.fullName,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      driver.todaNumber ?? 'SSLTODA No. —',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _InfoRow(
                      icon: Icons.airport_shuttle_outlined,
                      label: 'Plate Number',
                      value: driver.plateNumber ?? '—',
                    ),
                    _InfoRow(
                      icon: Icons.phone_outlined,
                      label: 'Mobile Number',
                      value: PhoneUtils.display(driver.mobileNumber),
                    ),
                    _InfoRow(
                      icon: Icons.timelapse_rounded,
                      label: 'Years of Service',
                      value: '${driver.yearsOfService} years',
                    ),
                    _InfoRow(
                      icon: Icons.star_outline_rounded,
                      label: 'Designated Terminal',
                      value: driver.assignedTerminal?.name ?? 'Not assigned',
                    ),
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      label: 'Current Location',
                      value: driver.currentTerminal?.name ?? 'Not set',
                      onTap: () => context.push('/terminal'),
                    ),
                    const SizedBox(height: 28),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(
                          color: AppColors.danger,
                          width: 1.5,
                        ),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        await ref.read(sessionProvider.notifier).logout();
                        if (context.mounted) context.go('/login');
                      },
                      child: Text(
                        'Log Out',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
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
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
