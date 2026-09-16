class Review {
  const Review({
    required this.id,
    required this.driverId,
    required this.rating,
    required this.createdAt,
    this.bookingId,
    this.comment,
  });

  final String id;
  final String driverId;
  final String? bookingId;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: (json['review_id'] ?? json['id']) as String,
      driverId: json['driver_id'] as String,
      bookingId: json['booking_id'] as String?,
      rating: (json['rating'] as num).toInt(),
      comment: (json['content'] ?? json['comment']) as String?,
      createdAt: DateTime.parse(
        (json['date_created'] ?? json['created_at']).toString(),
      ),
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
    final message = (json['message_content'] ?? json['body'] ?? '') as String;
    final explicitTitle = json['title'] as String?;
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AppNotification(
      id: (json['notification_id'] ?? json['id']) as String,
      driverId: (json['related_driver_id'] ??
              json['recipient_id'] ??
              json['driver_id'] ??
              '') as String,
      event: (json['event_type'] ?? json['event'] ?? 'SYSTEM') as String,
      title: (explicitTitle != null && explicitTitle.isNotEmpty)
          ? explicitTitle
          : 'Pasakay',
      body: message,
      data: data,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(
        (json['date_sent'] ?? json['created_at']) as String,
      ),
    );
  }
}
