import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static Future<void> initialize() async {
    await dotenv.load(fileName: '.env');
    final url = dotenv.env['SUPABASE_URL'] ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    if (url.isEmpty ||
        anonKey.isEmpty ||
        url.contains('YOUR_PROJECT_REF') ||
        anonKey.contains('YOUR_SUPABASE')) {
      throw StateError(
        'Missing Supabase credentials. Copy .env.example to .env and set '
        'SUPABASE_URL and SUPABASE_ANON_KEY (same project as the driver app).',
      );
    }

    await Supabase.initialize(url: url, publishableKey: anonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
}
