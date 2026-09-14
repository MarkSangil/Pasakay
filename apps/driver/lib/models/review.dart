class Review {
  const Review({
    required this.id,
    required this.driverId,
    required this.passengerName,
    required this.rating,
    required this.createdAt,
    this.bookingId,
    this.passengerId,
    this.comment,
  });

  final String id;
  final String driverId;
  final String? bookingId;
  final String? passengerId;
  final String passengerName;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String,
      driverId: json['driver_id'] as String,
      bookingId: json['booking_id'] as String?,
      passengerId: json['passenger_id'] as String?,
      passengerName: json['passenger_name'] as String? ?? 'Passenger',
      rating: (json['rating'] as num).toInt(),
      comment: json['comment'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.driverId,
    required this.event,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.data = const {},
  });

  final String id;
  final String driverId;
  final String event;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      driverId: json['driver_id'] as String,
      event: json['event'] as String? ?? 'system',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
