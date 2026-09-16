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

  static const _requestSelect = '*';

  static const _bookingSelect =
      '*, passenger_name, commuter:commuters!bookings_commuter_id_fkey(full_name, contact_number)';

  // Do not join commuters — reviewer identity stays private from drivers.
  static const _reviewSelect =
      'review_id, driver_id, booking_id, rating, content, date_created, is_hidden';

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

  Future<List<RideRequest>> fetchRideRequests({
    required String driverId,
    RideRequestStatus? status,
  }) async {
    var query =
        _client.from('ride_requests').select(_requestSelect).eq('driver_id', driverId);

    if (status != null) {
      query = query.eq('status', status.dbValue);
    }

    final rows = await query.order('created_at', ascending: false);
    return (rows as List)
        .map((e) => RideRequest.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Booking>> fetchBookings({
    required String driverId,
    BookingStatus? status,
    DateTime? from,
    DateTime? to,
  }) async {
    var query =
        _client.from('bookings').select(_bookingSelect).eq('driver_id', driverId);

    if (status != null) {
      query = query.eq('status', status.dbValue);
    }
    if (from != null) {
      query = query.gte('confirmed_at', from.toUtc().toIso8601String());
    }
    if (to != null) {
      query = query.lt('confirmed_at', to.toUtc().toIso8601String());
    }

    final rows = await query.order('confirmed_at', ascending: false);
    return (rows as List)
        .map((e) => Booking.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Booking?> fetchBooking(String id) async {
    final row = await _client
        .from('bookings')
        .select(_bookingSelect)
        .eq('booking_id', id)
        .maybeSingle();
    if (row == null) return null;
    return Booking.fromJson(row);
  }

  Future<Booking> acceptRideRequest(String requestId) async {
    final row = await _client.rpc(
      'accept_ride_request',
      params: {'p_request_id': requestId},
    );
    return Booking.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<RideRequest> rejectRideRequest(String requestId) async {
    final row = await _client.rpc(
      'reject_ride_request',
      params: {'p_request_id': requestId},
    );
    return RideRequest.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<Booking> flagBooking({
    required String bookingId,
    required String reason,
    String? details,
  }) async {
    final row = await _client.rpc(
      'flag_booking',
      params: {
        'p_booking_id': bookingId,
        'p_reason': reason,
        'p_details': details,
      },
    );
    return Booking.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<Booking> completeBooking(String bookingId) async {
    final row = await _client.rpc(
      'complete_booking',
      params: {'p_booking_id': bookingId},
    );
    return Booking.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<Map<String, int>> fetchBookingSettings() async {
    final raw = await _client.rpc('get_booking_settings');
    final map = Map<String, dynamic>.from(raw as Map);
    final dispute = (map['dispute_window_minutes'] as num?)?.toInt() ?? 20;
    setDisputeWindowMinutes(dispute);
    return {
      'dispute_window_minutes': dispute,
      'request_expire_minutes':
          (map['request_expire_minutes'] as num?)?.toInt() ?? 30,
      'request_cooldown_minutes':
          (map['request_cooldown_minutes'] as num?)?.toInt() ?? 30,
      'review_eligible_minutes':
          (map['review_eligible_minutes'] as num?)?.toInt() ?? 0,
    };
  }

  Future<void> reportReview({
    required String reviewId,
    required String reason,
    String? details,
  }) async {
    await _client.rpc(
      'report_review',
      params: {
        'p_review_id': reviewId,
        'p_reason': reason,
        'p_details': details,
      },
    );
  }

  Future<List<Review>> fetchReviews(String driverId, {int? limit}) async {
    var query = _client
        .from('reviews')
        .select(_reviewSelect)
        .eq('driver_id', driverId)
        .eq('is_hidden', false)
        .order('date_created', ascending: false);
    if (limit != null) {
      query = query.limit(limit);
    }
    final rows = await query;
    return (rows as List)
        .map((e) => Review.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<({double averageRating, int reviewCount})> fetchReviewSummary(
    String driverId,
  ) async {
    final row = await _client
        .from('drivers')
        .select('average_rating, review_count')
        .eq('driver_id', driverId)
        .maybeSingle();
    if (row == null) {
      return (averageRating: 0.0, reviewCount: 0);
    }
    return (
      averageRating: (row['average_rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (row['review_count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<AppNotification>> fetchNotifications(String driverId) async {
    final rows = await _client
        .from('notifications')
        .select()
        .eq('recipient_id', driverId)
        .order('date_sent', ascending: false)
        .limit(50);
    return (rows as List)
        .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<int> unreadNotificationCount(String driverId) async {
    final rows = await _client
        .from('notifications')
        .select('notification_id')
        .eq('recipient_id', driverId)
        .eq('is_read', false);
    return (rows as List).length;
  }

  Future<void> markNotificationsRead(String driverId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('recipient_id', driverId)
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
    }, onConflict: 'token');
  }

  /// Claims this device token for the current auth user (security definer).
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    await _client.rpc('register_driver_device_token', params: {
      'p_token': token,
      'p_platform': platform,
    });
  }

  Future<void> deleteDeviceToken({
    required String driverId,
    required String token,
  }) async {
    await _client
        .from('device_tokens')
        .delete()
        .eq('driver_id', driverId)
        .eq('token', token);
  }

  Future<Map<String, bool>> fetchNotificationPreferences(String driverId) async {
    final row = await _client
        .from('driver_notification_preferences')
        .select()
        .eq('driver_id', driverId)
        .maybeSingle();
    if (row == null) {
      return {
        'schedule_reminders': true,
        'schedule_changes': true,
        'availability_changes': true,
      };
    }
    return {
      'schedule_reminders': row['schedule_reminders'] as bool? ?? true,
      'schedule_changes': row['schedule_changes'] as bool? ?? true,
      'availability_changes': row['availability_changes'] as bool? ?? true,
    };
  }

  Future<void> upsertNotificationPreferences({
    required String driverId,
    required bool scheduleReminders,
    required bool scheduleChanges,
    required bool availabilityChanges,
  }) async {
    await _client.from('driver_notification_preferences').upsert({
      'driver_id': driverId,
      'schedule_reminders': scheduleReminders,
      'schedule_changes': scheduleChanges,
      'availability_changes': availabilityChanges,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Realtime channel for ride requests assigned to this driver.
  RealtimeChannel subscribeRideRequests({
    required String driverId,
    required void Function(PostgresChangePayload payload) onChange,
    String channelPrefix = 'driver-screen-requests',
  }) {
    return _client
        .channel('$channelPrefix-$driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ride_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driverId,
          ),
          callback: onChange,
        )
        .subscribe();
  }

  /// Realtime channel for bookings assigned to this driver.
  RealtimeChannel subscribeBookings({
    required String driverId,
    required void Function(PostgresChangePayload payload) onChange,
    String channelPrefix = 'driver-screen-bookings',
  }) {
    return _client
        .channel('$channelPrefix-$driverId')
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
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: driverId,
          ),
          callback: onChange,
        )
        .subscribe();
  }
}
