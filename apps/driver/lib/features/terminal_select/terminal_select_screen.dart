import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/terminal.dart';

class TerminalSelectScreen extends ConsumerStatefulWidget {
  const TerminalSelectScreen({super.key});

  @override
  ConsumerState<TerminalSelectScreen> createState() =>
      _TerminalSelectScreenState();
}

class _TerminalSelectScreenState extends ConsumerState<TerminalSelectScreen> {
  List<Terminal> _terminals = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref.read(driverRepositoryProvider).fetchTerminals();
      if (mounted) {
        setState(() {
          _terminals = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _select(Terminal terminal) async {
    await ref.read(sessionProvider.notifier).selectTerminal(terminal.id);
    if (mounted) context.go('/bookings');
  }

  Terminal? get _bayanMain {
    for (final t in _terminals) {
      if (t.isMain) return t;
    }
    for (final t in _terminals) {
      if (t.name.toLowerCase().contains('bayan')) return t;
    }
    return null;
  }

  Terminal? _resolveAssigned(String? assignedId) {
    if (assignedId == null) return null;
    for (final t in _terminals) {
      if (t.id == assignedId) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(sessionProvider).value;
    final assigned =
        driver?.assignedTerminal ?? _resolveAssigned(driver?.assignedTerminalId);
    final bayan = _bayanMain;

    // Mockup: exactly two choices — Assigned Terminal + Bayan Main.
    final cards = <Widget>[];
    if (assigned != null) {
      cards.add(
        _TerminalCard(
          title: 'Assigned Terminal',
          subtitle: 'I am at my designated terminal.',
          terminalName: assigned.name,
          address: assigned.address.isEmpty
              ? 'Brgy. San Luis, Antipolo City'
              : assigned.address,
          plateNumber: driver?.plateNumber,
          showStar: true,
          onTap: () => _select(assigned),
        ),
      );
    }
    if (bayan != null && bayan.id != assigned?.id) {
      cards.add(
        _TerminalCard(
          title: 'Bayan Terminal (Main Terminal)',
          subtitle: 'I am at the main terminal in Bayan.',
          terminalName: 'Bayan Terminal (Main Terminal)',
          address: bayan.address.isEmpty
              ? 'Brgy. San Luis, Antipolo City'
              : bayan.address,
          showStar: false,
          onTap: () => _select(bayan),
        ),
      );
    }

    // No assigned terminal yet — list all so the driver can still proceed.
    if (assigned == null && !_loading && _error == null) {
      cards
        ..clear()
        ..addAll(
          _terminals.map(
            (t) => _TerminalCard(
              title: t.isMain ? 'Bayan Terminal (Main Terminal)' : t.name,
              subtitle: t.isMain
                  ? 'I am at the main terminal in Bayan.'
                  : 'I am at this terminal today.',
              terminalName:
                  t.isMain ? 'Bayan Terminal (Main Terminal)' : t.name,
              address: t.address.isEmpty
                  ? 'Brgy. San Luis, Antipolo City'
                  : t.address,
              showStar: t.isMain,
              onTap: () => _select(t),
            ),
          ),
        );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 40, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Where are you today?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your current terminal location.',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: cards.isEmpty
                        ? [
                            Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: Text(
                                'No terminals available yet.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ]
                        : cards,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalCard extends StatelessWidget {
  const _TerminalCard({
    required this.title,
    required this.subtitle,
    required this.terminalName,
    required this.address,
    required this.showStar,
    required this.onTap,
    this.plateNumber,
  });

  final String title;
  final String subtitle;
  final String terminalName;
  final String address;
  final bool showStar;
  final VoidCallback onTap;
  final String? plateNumber;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.white,
        elevation: 0,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 10, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E5E1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _BuildingIcon(showStar: showStar),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.successSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              terminalName,
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              address,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            if (plateNumber != null &&
                                plateNumber!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Plate No. $plateNumber',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF6B736E),
                  size: 26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mockup building mark — dark green facade with optional star badge.
class _BuildingIcon extends StatelessWidget {
  const _BuildingIcon({required this.showStar});

  final bool showStar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: CustomPaint(
        painter: _BuildingIconPainter(showStar: showStar),
      ),
    );
  }
}

class _BuildingIconPainter extends CustomPainter {
  _BuildingIconPainter({required this.showStar});

  final bool showStar;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.18, h * 0.28, w * 0.64, h * 0.62),
      const Radius.circular(3),
    );
    canvas.drawRRect(body, paint);

    final roof = Path()
      ..moveTo(w * 0.12, h * 0.30)
      ..lineTo(w * 0.50, h * 0.08)
      ..lineTo(w * 0.88, h * 0.30)
      ..close();
    canvas.drawPath(roof, paint);

    final flagPaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.50, h * 0.08),
      Offset(w * 0.50, h * 0.01),
      flagPaint,
    );
    final flag = Path()
      ..moveTo(w * 0.50, h * 0.01)
      ..lineTo(w * 0.68, h * 0.04)
      ..lineTo(w * 0.50, h * 0.07)
      ..close();
    canvas.drawPath(flag, paint);

    final window = Paint()..color = Colors.white;
    for (var r = 0; r < 2; r++) {
      for (var c = 0; c < 3; c++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              w * 0.26 + c * w * 0.18,
              h * 0.38 + r * h * 0.18,
              w * 0.10,
              h * 0.10,
            ),
            const Radius.circular(1),
          ),
          window,
        );
      }
    }

    if (showStar) {
      final badgeCenter = Offset(w * 0.50, h * 0.78);
      canvas.drawCircle(badgeCenter, w * 0.14, Paint()..color = Colors.white);
      canvas.drawCircle(
        badgeCenter,
        w * 0.11,
        Paint()..color = AppColors.primary,
      );
      _drawStar(canvas, badgeCenter, w * 0.07, Colors.white);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    const n = 5;
    for (var i = 0; i < n * 2; i++) {
      final a = -math.pi / 2 + i * math.pi / n;
      final r = i.isEven ? radius : radius * 0.45;
      final point = Offset(
        center.dx + r * math.cos(a),
        center.dy + r * math.sin(a),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _BuildingIconPainter oldDelegate) =>
      oldDelegate.showStar != showStar;
}
