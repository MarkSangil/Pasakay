import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/session_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'services/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? initError;
  try {
    await SupabaseConfig.initialize();
  } catch (e) {
    initError = e;
  }

  runApp(
    ProviderScope(
      child: PasakayDriverApp(initError: initError),
    ),
  );
}

class PasakayDriverApp extends ConsumerWidget {
  const PasakayDriverApp({super.key, this.initError});

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
    // Keep session alive for redirects.
    ref.watch(sessionProvider);

    return MaterialApp.router(
      title: 'Pasakay Driver',
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
                '1. Open apps/driver/.env\n'
                '2. Paste your project URL and anon key\n'
                '3. Run the SQL in supabase/migrations/\n'
                '4. Restart the app',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
