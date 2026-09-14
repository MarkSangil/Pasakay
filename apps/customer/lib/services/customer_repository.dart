import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'supabase_config.dart';

class CustomerRepository {
  CustomerRepository({SupabaseClient? client})
      : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;
  static const _recentKey = 'pasakay_customer_recent_contacts';

  Future<List<Terminal>> fetchTerminals() async {
    final rows =
        await _client.from('terminals').select().order('terminal_name');
    return (rows as List)
        .map((e) => Terminal.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Shift>> fetchShifts() async {
    final rows =
        await _client.from('shifts').select().order('shift_start_time');
    return (rows as List)
        .map((e) => Shift.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<DriverSummary>> fetchDrivers({
    required String terminalId,
    String? shiftId,
  }) async {
    var query = _client
        .from('drivers')
        .select(
          '*, terminal:terminals!drivers_terminal_id_fkey(*),'
          ' shift:shifts!drivers_shift_id_fkey(*)',
        )
        .eq('terminal_id', terminalId)
        .eq('is_active', true);

    if (shiftId != null) {
      query = query.eq('shift_id', shiftId);
    }

    final rows = await query.order('full_name');
    return (rows as List)
        .map((e) => DriverSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<DriverSummary?> fetchDriver(String driverId) async {
    final row = await _client
        .from('drivers')
        .select(
          '*, terminal:terminals!drivers_terminal_id_fkey(*),'
          ' shift:shifts!drivers_shift_id_fkey(*)',
        )
        .eq('driver_id', driverId)
        .maybeSingle();
    if (row == null) return null;
    return DriverSummary.fromJson(row);
  }

  Future<void> submitReview({
    required String driverId,
    required int rating,
    String? content,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not signed in');

    await _client.from('reviews').insert({
      'commuter_id': user.id,
      'driver_id': driverId,
      'rating': rating,
      'content': content?.trim().isEmpty == true ? null : content?.trim(),
    });
  }

  Future<List<DriverReview>> fetchMyReviews() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];

    final rows = await _client
        .from('reviews')
        .select('*, driver:drivers!reviews_driver_id_fkey(full_name)')
        .eq('commuter_id', user.id)
        .order('date_created', ascending: false);
    return (rows as List)
        .map((e) => DriverReview.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<RecentContact>> loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentKey);
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => RecentContact.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> addRecent(RecentContact contact) async {
    final existing = await loadRecent();
    final next = [
      contact,
      ...existing.where((c) => c.driverId != contact.driverId),
    ].take(40).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recentKey,
      jsonEncode(next.map((e) => e.toJson()).toList()),
    );
  }
}
