import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/session_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'services/push_notification_service.dart';
import 'services/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? initError;
  try {
    await SupabaseConfig.initialize();
  } catch (e) {
    initError = e;
  }

  if (initError == null) {
    await PushNotificationService.initializeFirebase();
  }

  runApp(
    ProviderScope(
      child: PasakayCustomerApp(initError: initError),
    ),
  );
}

class PasakayCustomerApp extends ConsumerWidget {
  const PasakayCustomerApp({super.key, this.initError});

  final Object? initError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: _ConfigErrorScreen(error: initError!),
      );
    }

    final router = ref.watch(routerProvider);
    ref.watch(sessionProvider);
    ref.watch(pushRegistrationProvider);
    ref.read(pushNotificationServiceProvider).onOpenRoute = (route) {
      router.go(route);
    };

    return MaterialApp.router(
      title: 'Pasakay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}

class _ConfigErrorScreen extends StatelessWidget {
  const _ConfigErrorScreen({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Supabase not configured',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(error.toString()),
              const SizedBox(height: 16),
              const Text(
                '1. Open apps/customer/.env\n'
                '2. Paste the same SUPABASE_URL and SUPABASE_ANON_KEY as the driver app\n'
                '3. Restart the app',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
