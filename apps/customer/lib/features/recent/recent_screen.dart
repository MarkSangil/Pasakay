import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../widgets/common_widgets.dart';

class RecentScreen extends ConsumerStatefulWidget {
  const RecentScreen({super.key});

  @override
  ConsumerState<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends ConsumerState<RecentScreen> {
  List<RecentContact> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final items = await ref.read(customerRepositoryProvider).loadRecent();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Map<String, List<RecentContact>> _grouped() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final map = <String, List<RecentContact>>{
      'Today': [],
      'Yesterday': [],
      'Earlier': [],
    };
    for (final item in _items) {
      final day = DateTime(item.at.year, item.at.month, item.at.day);
      if (day == today) {
        map['Today']!.add(item);
      } else if (day == yesterday) {
        map['Yesterday']!.add(item);
      } else {
        map['Earlier']!.add(item);
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const GreenAppBar(title: 'Recent'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Text(
                    'No recent contacts yet.\nCall or message a driver to see them here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textMuted,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      for (final entry in grouped.entries)
                        if (entry.value.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
                            child: Text(
                              entry.key,
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          ...entry.value.map((item) {
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              title: Text(
                                item.driverName,
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                              subtitle: Text(
                                item.terminalName,
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    DateFormat('h:mm a').format(item.at),
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    item.channel == 'call'
                                        ? Icons.phone_rounded
                                        : Icons.chat_bubble_rounded,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                ],
                              ),
                              onTap: () =>
                                  context.push('/driver/${item.driverId}'),
                            );
                          }),
                        ],
                    ],
                  ),
                ),
    );
  }
}
