import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/phone_utils.dart';
import '../../widgets/common_widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commuter = ref.watch(sessionProvider).value;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const GreenAppBar(title: 'Profile'),
      body: commuter == null
          ? const Center(child: Text('Not signed in'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              children: [
                const Center(child: AvatarCircle(size: 96)),
                const SizedBox(height: 14),
                Text(
                  commuter.fullName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  PhoneUtils.display(commuter.contactNumber),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                _row(Icons.email_outlined, 'Email',
                    commuter.emailAddress ?? '—'),
                _row(Icons.person_outline, 'Username', commuter.username),
                const SizedBox(height: 28),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  onPressed: () => ref.read(sessionProvider.notifier).logout(),
                  child: const Text('Log Out'),
                ),
              ],
            ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
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
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
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
