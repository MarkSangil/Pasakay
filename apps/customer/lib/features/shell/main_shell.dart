import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: navigationShell.goBranch,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.successSoft,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined, color: AppColors.navInactive),
            selectedIcon: Icon(Icons.location_on, color: AppColors.primary),
            label: 'Terminals',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined, color: AppColors.navInactive),
            selectedIcon: Icon(Icons.history, color: AppColors.primary),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline_rounded, color: AppColors.navInactive),
            selectedIcon: Icon(Icons.star_rounded, color: AppColors.primary),
            label: 'Review',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded, color: AppColors.navInactive),
            selectedIcon: Icon(Icons.person_rounded, color: AppColors.primary),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
