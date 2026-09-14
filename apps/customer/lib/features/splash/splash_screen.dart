import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/session_provider.dart';
import '../../widgets/common_widgets.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1400), _go);
  }

  void _go() {
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    if (session.isLoading) {
      Future<void>.delayed(const Duration(milliseconds: 400), _go);
      return;
    }
    if (session.value != null) {
      context.go('/terminals');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SkylineBackground(
        child: SafeArea(
          child: Center(
            child: BrandHeader(),
          ),
        ),
      ),
    );
  }
}
