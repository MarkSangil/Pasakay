import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../models/ride_booking.dart';
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
    final raw = await _client.rpc(
      'list_terminal_shift_drivers',
      params: {
        'p_terminal_id': terminalId,
        'p_shift_id': shiftId,
      },
    );
    final rows = raw is List ? raw : const [];
    return rows
        .map((e) => DriverSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<DriverSummary?> fetchDriver(String driverId) async {
    final row = await _client
        .from('drivers')
        .select(
          'driver_id, full_name, plate_number, is_active,'
          ' status, terminal_id, shift_id, toda_number,'
          ' current_terminal_id,'
          ' terminal:terminals!drivers_terminal_id_fkey(*),'
          ' current_terminal:terminals!drivers_current_terminal_id_fkey(*),'
          ' shift:shifts!drivers_shift_id_fkey(*)',
        )
        .eq('driver_id', driverId)
        .maybeSingle();
    if (row == null) return null;
    final summary = DriverSummary.fromJson(row);
    final terminalId = summary.terminalId;
    if (terminalId == null) return summary;
    final listed = await fetchDrivers(
      terminalId: terminalId,
      shiftId: summary.shiftId,
    );
    for (final d in listed) {
      if (d.id == driverId) return d;
    }
    return summary;
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

  Future<void> upsertDeviceToken({
    required String commuterId,
    required String token,
    required String platform,
  }) async {
    await _client.from('commuter_device_tokens').upsert({
      'commuter_id': commuterId,
      'token': token,
      'platform': platform,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    await _client.rpc('register_commuter_device_token', params: {
      'p_token': token,
      'p_platform': platform,
    });
  }

  Future<void> deleteDeviceToken({
    required String commuterId,
    required String token,
  }) async {
    await _client
        .from('commuter_device_tokens')
        .delete()
        .eq('commuter_id', commuterId)
        .eq('token', token);
  }

  RealtimeChannel subscribeNotifications({
    required String commuterId,
    required void Function(PostgresChangePayload payload) onChange,
  }) {
    return _client
        .channel('notifications-$commuterId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: commuterId,
          ),
          callback: onChange,
        )
        .subscribe();
  }

  /// Live updates when this passenger's request for [driverId] changes (accept/reject).
  RealtimeChannel subscribeRideRequestUpdates({
    required String commuterId,
    required String driverId,
    required void Function(PostgresChangePayload payload) onChange,
  }) {
    return _client
        .channel('ride-requests-$commuterId-$driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ride_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'commuter_id',
            value: commuterId,
          ),
          callback: (payload) {
            final row = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            if (row['driver_id']?.toString() != driverId) return;
            onChange(payload);
          },
        )
        .subscribe();
  }

  /// Live updates when a booking with this driver is created/updated for the passenger.
  RealtimeChannel subscribeBookingUpdates({
    required String commuterId,
    required String driverId,
    required void Function(PostgresChangePayload payload) onChange,
  }) {
    return _client
        .channel('bookings-$commuterId-$driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'commuter_id',
            value: commuterId,
          ),
          callback: (payload) {
            final row = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            if (row['driver_id']?.toString() != driverId) return;
            onChange(payload);
          },
        )
        .subscribe();
  }

  Future<bool> isFollowingDriver(String driverId) async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final row = await _client
        .from('commuter_followed_drivers')
        .select('driver_id')
        .eq('commuter_id', user.id)
        .eq('driver_id', driverId)
        .maybeSingle();
    return row != null;
  }

  Future<void> followDriver(String driverId) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    await _client.from('commuter_followed_drivers').upsert({
      'commuter_id': user.id,
      'driver_id': driverId,
    });
  }

  Future<void> unfollowDriver(String driverId) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from('commuter_followed_drivers')
        .delete()
        .eq('commuter_id', user.id)
        .eq('driver_id', driverId);
  }

  Future<List<DriverSummary>> fetchFollowedDrivers() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final rows = await _client
        .from('commuter_followed_drivers')
        .select(
          'driver:drivers!commuter_followed_drivers_driver_id_fkey('
          'driver_id, full_name, plate_number, years_of_service, is_active,'
          ' status, terminal_id, shift_id, current_terminal_id,'
          ' terminal:terminals!drivers_terminal_id_fkey(*),'
          ' current_terminal:terminals!drivers_current_terminal_id_fkey(*),'
          ' shift:shifts!drivers_shift_id_fkey(*))',
        )
        .eq('commuter_id', user.id)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          final driver = map['driver'];
          if (driver is! Map) return null;
          return DriverSummary.fromJson(Map<String, dynamic>.from(driver));
        })
        .whereType<DriverSummary>()
        .toList();
  }

  Future<Map<String, bool>> fetchNotificationPreferences() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return {'followed_driver_availability': true};
    }
    final row = await _client
        .from('commuter_notification_preferences')
        .select()
        .eq('commuter_id', user.id)
        .maybeSingle();
    if (row == null) {
      return {'followed_driver_availability': true};
    }
    return {
      'followed_driver_availability':
          row['followed_driver_availability'] as bool? ?? true,
    };
  }

  Future<void> upsertNotificationPreferences({
    required bool followedDriverAvailability,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('commuter_notification_preferences').upsert({
      'commuter_id': user.id,
      'followed_driver_availability': followedDriverAvailability,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> fetchNotifications() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final rows = await _client
        .from('notifications')
        .select()
        .eq('recipient_id', user.id)
        .order('date_sent', ascending: false)
        .limit(50);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> markNotificationsRead() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('recipient_id', user.id)
        .eq('is_read', false);
  }

  Future<DriverRequestContext> fetchDriverRequestContext(String driverId) async {
    final raw = await _client.rpc(
      'get_driver_request_context',
      params: {'p_driver_id': driverId},
    );
    return DriverRequestContext.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<RideRequest> createRideRequest(String driverId) async {
    final raw = await _client.rpc(
      'create_ride_request',
      params: {'p_driver_id': driverId},
    );
    return RideRequest.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Future<List<RideRequest>> fetchMyRideRequests() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final rows = await _client
        .from('ride_requests')
        .select('*, driver:drivers!ride_requests_driver_id_fkey(full_name)')
        .eq('commuter_id', user.id)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => RideRequest.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<BookingRecord>> fetchMyBookings() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    await _client.rpc('reconcile_ride_workflow');
    final rows = await _client
        .from('bookings')
        .select('*, driver:drivers!bookings_driver_id_fkey(full_name)')
        .eq('commuter_id', user.id)
        .order('confirmed_at', ascending: false);
    return (rows as List)
        .map((e) => BookingRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> submitBookingReview({
    required String bookingId,
    required int rating,
    String? content,
  }) async {
    await _client.rpc(
      'submit_booking_review',
      params: {
        'p_booking_id': bookingId,
        'p_rating': rating,
        'p_content': content,
      },
    );
  }

  Future<BookingRecord> reportDriverBooking({
    required String bookingId,
    required String reason,
    String? details,
  }) async {
    final raw = await _client.rpc(
      'report_driver_booking',
      params: {
        'p_booking_id': bookingId,
        'p_reason': reason,
        'p_details': details,
      },
    );
    return BookingRecord.fromJson(Map<String, dynamic>.from(raw as Map));
  }
}
