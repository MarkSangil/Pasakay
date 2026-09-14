import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';

/// Full logo lockup from asset (pin + PASAKAY + tagline already in the image).
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    this.compact = false,
    this.dense = false,
  });

  /// Login uses [compact]. Signup uses [dense] (smaller for the long form).
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final double logoWidth;
    if (dense) {
      logoWidth = (width * 0.36).clamp(120.0, 148.0);
    } else if (compact) {
      // Login mockup — larger lockup.
      logoWidth = (width * 0.90).clamp(220.0, 280.0);
    } else {
      logoWidth = (width * 0.58).clamp(200.0, 260.0);
    }

    return Image.asset(
      AppConstants.logoAsset,
      width: logoWidth,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'PASAKAY',
    );
  }
}

/// Full-screen white + bottom city skyline from background asset.
/// Pair with [Scaffold.resizeToAvoidBottomInset] = false so the scaffold
/// body (and this skyline) keep a fixed height while the keyboard is open.
class SkylineBackground extends StatelessWidget {
  const SkylineBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.white),
        Positioned.fill(
          child: Image.asset(
            AppConstants.backgroundAsset,
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => const Align(
              alignment: Alignment.bottomCenter,
              child: CustomPaint(
                size: Size(double.infinity, 160),
                painter: _SkylinePainter(),
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _SkylinePainter extends CustomPainter {
  const _SkylinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.skyline.withValues(alpha: 0.7);
    final path = Path()..moveTo(0, size.height);
    final peaks = <double>[
      0.08, 0.18, 0.22, 0.28, 0.34, 0.42, 0.48, 0.55, 0.62, 0.70, 0.78, 0.86, 0.94, 1.0,
    ];
    final heights = <double>[
      0.55, 0.35, 0.70, 0.45, 0.80, 0.40, 0.65, 0.50, 0.75, 0.42, 0.60, 0.38, 0.72, 0.50,
    ];
    for (var i = 0; i < peaks.length; i++) {
      final x = peaks[i] * size.width;
      final y = size.height * (1 - heights[i] * 0.85);
      path.lineTo(x, y);
      path.lineTo(x + 8, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.onToggleObscure,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 22),
        suffixIcon: suffix ??
            (onToggleObscure == null
                ? null
                : IconButton(
                    onPressed: onToggleObscure,
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textMuted,
                    ),
                  )),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class DriverAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DriverAppBar({
    super.key,
    required this.title,
    this.showMenu = true,
    this.onBack,
    this.unreadCount = 0,
  });

  final String title;
  final bool showMenu;
  final VoidCallback? onBack;
  final int unreadCount;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: onBack != null
          ? IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 32),
              onPressed: onBack,
            )
          : showMenu
              ? IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Menu coming soon')),
                    );
                  },
                )
              : null,
      title: Text(title),
      actions: [
        IconButton(
          onPressed: () => context.push('/notifications'),
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            backgroundColor: AppColors.danger,
            label: Text('$unreadCount', style: const TextStyle(fontSize: 10)),
            child: const Icon(Icons.notifications_none_rounded),
          ),
        ),
      ],
    );
  }
}

class SectionOrDivider extends StatelessWidget {
  const SectionOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          child: ColoredBox(
            color: AppColors.textMuted,
            child: SizedBox(height: 1.5),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OR',
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        const Expanded(
          child: ColoredBox(
            color: AppColors.textMuted,
            child: SizedBox(height: 1.5),
          ),
        ),
      ],
    );
  }
}
