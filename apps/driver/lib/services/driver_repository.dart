import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/booking.dart';
import '../models/driver.dart';
import '../models/review.dart';
import '../models/terminal.dart';
import 'supabase_config.dart';

class DriverRepository {
  DriverRepository({SupabaseClient? client})
      : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  static const _bookingSelect =
      '*, pickup_terminal:terminals!bookings_pickup_terminal_id_fkey(*), '
      'dropoff_terminal:terminals!bookings_dropoff_terminal_id_fkey(*)';

  Future<List<Terminal>> fetchTerminals() async {
    final rows =
        await _client.from('terminals').select().order('terminal_name');
    return (rows as List)
        .map((e) => Terminal.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<DriverShift?> fetchTodaysShift(String driverId) async {
    final today = DateTime.now();
    final date =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final row = await _client
        .from('driver_shifts')
        .select('*, terminal:terminals(*)')
        .eq('driver_id', driverId)
        .eq('shift_date', date)
        .order('start_at')
        .limit(1)
        .maybeSingle();

    if (row == null) return null;
    return DriverShift.fromJson(row);
  }

  Future<List<Booking>> fetchBookings({
    required String driverId,
    BookingStatus? status,
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _client.from('bookings').select(_bookingSelect).eq('driver_id', driverId);

    if (status != null) {
      query = query.eq('status', status.dbValue);
    }
    if (from != null) {
      query = query.gte('scheduled_at', from.toUtc().toIso8601String());
    }
    if (to != null) {
      query = query.lt('scheduled_at', to.toUtc().toIso8601String());
    }

    final rows = await query.order('scheduled_at');
    return (rows as List)
        .map((e) => Booking.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Booking?> fetchBooking(String id) async {
    final row = await _client
        .from('bookings')
        .select(_bookingSelect)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    return Booking.fromJson(row);
  }

  Future<Booking> startTrip(String bookingId) async {
    final row = await _client
        .from('bookings')
        .update({
          'status': BookingStatus.ongoing.dbValue,
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'trip_status_note': 'En route to pick up passenger',
        })
        .eq('id', bookingId)
        .select(_bookingSelect)
        .single();
    return Booking.fromJson(row);
  }

  Future<Booking> completeTrip(String bookingId, {double? actualFare}) async {
    final existing = await fetchBooking(bookingId);
    final fare = actualFare ?? existing?.estimatedFare ?? 0;
    final row = await _client
        .from('bookings')
        .update({
          'status': BookingStatus.completed.dbValue,
          'completed_at': DateTime.now().toUtc().toIso8601String(),
          'actual_fare': fare,
          'trip_status_note': 'Trip completed',
        })
        .eq('id', bookingId)
        .select(_bookingSelect)
        .single();
    return Booking.fromJson(row);
  }

  Future<Booking> cancelTrip(String bookingId) async {
    final row = await _client
        .from('bookings')
        .update({
          'status': BookingStatus.cancelled.dbValue,
          'cancelled_at': DateTime.now().toUtc().toIso8601String(),
          'trip_status_note': 'Trip cancelled',
        })
        .eq('id', bookingId)
        .select(_bookingSelect)
        .single();
    return Booking.fromJson(row);
  }

  Future<List<Review>> fetchReviews(String driverId, {int? limit}) async {
    var query = _client
        .from('reviews')
        .select()
        .eq('driver_id', driverId)
        .order('created_at', ascending: false);
    if (limit != null) {
      query = query.limit(limit);
    }
    final rows = await query;
    return (rows as List)
        .map((e) => Review.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<AppNotification>> fetchNotifications(String driverId) async {
    final rows = await _client
        .from('notifications')
        .select()
        .eq('driver_id', driverId)
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List)
        .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<int> unreadNotificationCount(String driverId) async {
    final rows = await _client
        .from('notifications')
        .select('id')
        .eq('driver_id', driverId)
        .eq('is_read', false);
    return (rows as List).length;
  }

  Future<void> markNotificationsRead(String driverId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('driver_id', driverId)
        .eq('is_read', false);
  }

  Future<void> upsertDeviceToken({
    required String driverId,
    required String token,
    required String platform,
  }) async {
    await _client.from('device_tokens').upsert({
      'driver_id': driverId,
      'token': token,
      'platform': platform,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'driver_id,token');
  }

  /// Realtime channel for bookings assigned to this driver.
  RealtimeChannel subscribeBookings({
    required String driverId,
    required void Function(PostgresChangePayload payload) onChange,
  }) {
    return _client
        .channel('bookings-$driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driverId,
          ),
          callback: onChange,
        )
        .subscribe();
  }

  RealtimeChannel subscribeNotifications({
    required String driverId,
    required void Function(PostgresChangePayload payload) onChange,
  }) {
    return _client
        .channel('notifications-$driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driverId,
          ),
          callback: onChange,
        )
        .subscribe();
  }
}
