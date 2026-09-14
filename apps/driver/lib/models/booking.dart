import 'terminal.dart';

enum BookingStatus { upcoming, ongoing, completed, cancelled }

extension BookingStatusX on BookingStatus {
  String get dbValue => name;

  String get label => switch (this) {
        BookingStatus.upcoming => 'Upcoming',
        BookingStatus.ongoing => 'Ongoing',
        BookingStatus.completed => 'Completed',
        BookingStatus.cancelled => 'Cancelled',
      };

  String get badgeLabel => switch (this) {
        BookingStatus.upcoming => 'Upcoming Booking',
        BookingStatus.ongoing => 'Ongoing Trip',
        BookingStatus.completed => 'Completed Trip',
        BookingStatus.cancelled => 'Cancelled',
      };

  static BookingStatus fromDb(String value) {
    return BookingStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => BookingStatus.upcoming,
    );
  }
}

class Booking {
  const Booking({
    required this.id,
    required this.driverId,
    required this.passengerName,
    required this.passengerCount,
    required this.pickupTerminalId,
    required this.dropoffTerminalId,
    required this.scheduledAt,
    required this.status,
    required this.estimatedFare,
    this.passengerId,
    this.shiftId,
    this.passengerMobile,
    this.tripStatusNote,
    this.notes,
    this.actualFare,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.pickupTerminal,
    this.dropoffTerminal,
  });

  final String id;
  final String driverId;
  final String? passengerId;
  final String? shiftId;
  final String passengerName;
  final String? passengerMobile;
  final int passengerCount;
  final String pickupTerminalId;
  final String dropoffTerminalId;
  final DateTime scheduledAt;
  final BookingStatus status;
  final String? tripStatusNote;
  final String? notes;
  final double estimatedFare;
  final double? actualFare;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final Terminal? pickupTerminal;
  final Terminal? dropoffTerminal;

  Booking copyWith({
    BookingStatus? status,
    String? tripStatusNote,
    double? actualFare,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? cancelledAt,
  }) {
    return Booking(
      id: id,
      driverId: driverId,
      passengerId: passengerId,
      shiftId: shiftId,
      passengerName: passengerName,
      passengerMobile: passengerMobile,
      passengerCount: passengerCount,
      pickupTerminalId: pickupTerminalId,
      dropoffTerminalId: dropoffTerminalId,
      scheduledAt: scheduledAt,
      status: status ?? this.status,
      tripStatusNote: tripStatusNote ?? this.tripStatusNote,
      notes: notes,
      estimatedFare: estimatedFare,
      actualFare: actualFare ?? this.actualFare,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      pickupTerminal: pickupTerminal,
      dropoffTerminal: dropoffTerminal,
    );
  }

  factory Booking.fromJson(Map<String, dynamic> json) {
    Terminal? pickup;
    Terminal? dropoff;
    final p = json['pickup_terminal'];
    final d = json['dropoff_terminal'];
    if (p is Map<String, dynamic>) pickup = Terminal.fromJson(p);
    if (d is Map<String, dynamic>) dropoff = Terminal.fromJson(d);

    return Booking(
      id: json['id'] as String,
      driverId: json['driver_id'] as String,
      passengerId: json['passenger_id'] as String?,
      shiftId: json['shift_id'] as String?,
      passengerName: json['passenger_name'] as String? ?? 'Passenger',
      passengerMobile: json['passenger_mobile'] as String?,
      passengerCount: (json['passenger_count'] as num?)?.toInt() ?? 1,
      pickupTerminalId: json['pickup_terminal_id'] as String,
      dropoffTerminalId: json['dropoff_terminal_id'] as String,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      status: BookingStatusX.fromDb(json['status'] as String? ?? 'upcoming'),
      tripStatusNote: json['trip_status_note'] as String?,
      notes: json['notes'] as String?,
      estimatedFare: (json['estimated_fare'] as num?)?.toDouble() ?? 0,
      actualFare: (json['actual_fare'] as num?)?.toDouble(),
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'] as String)
          : null,
      pickupTerminal: pickup,
      dropoffTerminal: dropoff,
    );
  }
}
