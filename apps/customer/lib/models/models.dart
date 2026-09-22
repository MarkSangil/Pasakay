class Terminal {
  const Terminal({
    required this.id,
    required this.name,
    this.address = 'Brgy. San Luis, Antipolo City',
  });

  final String id;
  final String name;
  final String address;

  bool get isMain => name.toLowerCase().contains('bayan');

  factory Terminal.fromJson(Map<String, dynamic> json) {
    return Terminal(
      id: (json['terminal_id'] ?? json['id']) as String,
      name: (json['terminal_name'] ?? json['name'] ?? '') as String,
      address: (json['address'] as String?) ?? 'Brgy. San Luis, Antipolo City',
    );
  }
}

class Shift {
  const Shift({
    required this.id,
    required this.label,
    required this.startTime,
    required this.endTime,
  });

  final String id;
  final String label;
  final String startTime;
  final String endTime;

  /// Compact chip label like "6AM - 12NN".
  String get chipLabel {
    String fmt(String t) {
      final parts = t.split(':');
      final h = int.tryParse(parts.first) ?? 0;
      if (h == 0) return '12AM';
      if (h == 12) return '12NN';
      if (h < 12) return '${h}AM';
      return '${h - 12}PM';
    }

    // Prefer curated labels from DB when possible.
    final lower = label.toLowerCase();
    if (lower.contains('6:00 am') || lower.contains('6am')) {
      return '6AM - 12NN';
    }
    if (lower.contains('12:00 nn') || lower.contains('12nn')) {
      return '12NN - 6PM';
    }
    if (lower.contains('6:00 pm') || lower.contains('6pm')) {
      return '6PM - 12AM';
    }
    return '${fmt(startTime)} - ${fmt(endTime)}';
  }

  factory Shift.fromJson(Map<String, dynamic> json) {
    return Shift(
      id: (json['shift_id'] ?? json['id']) as String,
      label: (json['label'] ?? '') as String,
      startTime: json['shift_start_time'].toString(),
      endTime: json['shift_end_time'].toString(),
    );
  }
}

class DriverSummary {
  const DriverSummary({
    required this.id,
    required this.fullName,
    required this.contactNumber,
    required this.plateNumber,
    this.todaNumber,
    this.terminalId,
    this.shiftId,
    this.terminalName,
    this.shiftLabel,
    this.yearsOfService = 0,
    this.isBooked = false,
  });

  final String id;
  final String fullName;
  final String contactNumber;
  final String plateNumber;
  final String? todaNumber;
  final String? terminalId;
  final String? shiftId;
  final String? terminalName;
  final String? shiftLabel;
  final int yearsOfService;
  final bool isBooked;

  factory DriverSummary.fromJson(Map<String, dynamic> json) {
    String? terminalName;
    String? shiftLabel;
    // Prefer the driver's current (picked) terminal over the assigned one —
    // terminal driver lists are keyed by the effective terminal.
    final currentTerminal = json['current_terminal'];
    final terminal = json['terminal'] ?? json['terminals'];
    final shift = json['shift'] ?? json['shifts'];
    if (currentTerminal is Map) {
      terminalName =
          (currentTerminal['terminal_name'] ?? currentTerminal['name'])
              as String?;
    }
    if (terminalName == null && terminal is Map) {
      terminalName = (terminal['terminal_name'] ?? terminal['name']) as String?;
    }
    if (shift is Map) {
      shiftLabel = shift['label'] as String?;
    }
    terminalName ??= json['terminal_name'] as String?;
    shiftLabel ??= json['shift_label'] as String?;

    final currentTerminalId = json['current_terminal_id'] as String?;
    return DriverSummary(
      id: (json['driver_id'] ?? json['id']) as String,
      fullName: (json['full_name'] ?? 'Driver') as String,
      contactNumber: (json['contact_number'] ?? '') as String,
      plateNumber: (json['plate_number'] ?? '—') as String,
      todaNumber: json['toda_number'] as String?,
      terminalId: currentTerminalId ?? json['terminal_id'] as String?,
      shiftId: json['shift_id'] as String?,
      terminalName: terminalName,
      shiftLabel: shiftLabel,
      yearsOfService: (json['years_of_service'] as num?)?.toInt() ?? 0,
      isBooked: json['is_booked'] == true,
    );
  }
}

class Commuter {
  const Commuter({
    required this.id,
    required this.fullName,
    required this.contactNumber,
    this.emailAddress,
    required this.username,
    this.status = 'active',
    this.statusReason,
  });

  final String id;
  final String fullName;
  final String contactNumber;
  final String? emailAddress;
  final String username;
  final String status;
  final String? statusReason;

  factory Commuter.fromJson(Map<String, dynamic> json) {
    return Commuter(
      id: (json['commuter_id'] ?? json['id']) as String,
      fullName: (json['full_name'] ?? 'Commuter') as String,
      contactNumber: (json['contact_number'] ?? '') as String,
      emailAddress: json['email_address'] as String?,
      username: (json['username'] ?? '') as String,
      status: json['status'] as String? ?? 'active',
      statusReason: json['status_reason'] as String?,
    );
  }
}

class DriverReview {
  const DriverReview({
    required this.id,
    required this.driverId,
    required this.rating,
    required this.createdAt,
    this.content,
    this.driverName,
  });

  final String id;
  final String driverId;
  final int rating;
  final DateTime createdAt;
  final String? content;
  final String? driverName;

  factory DriverReview.fromJson(Map<String, dynamic> json) {
    String? driverName;
    final driver = json['driver'] ?? json['drivers'];
    if (driver is Map) {
      driverName = driver['full_name'] as String?;
    }
    return DriverReview(
      id: (json['review_id'] ?? json['id']) as String,
      driverId: json['driver_id'] as String,
      rating: (json['rating'] as num).toInt(),
      content: (json['content'] ?? json['comment']) as String?,
      createdAt: DateTime.parse(
        (json['date_created'] ?? json['created_at']).toString(),
      ),
      driverName: driverName,
    );
  }
}

class RecentContact {
  const RecentContact({
    required this.driverId,
    required this.driverName,
    required this.terminalName,
    required this.contactNumber,
    required this.at,
    required this.channel,
  });

  final String driverId;
  final String driverName;
  final String terminalName;
  final String contactNumber;
  final DateTime at;
  final String channel; // call | sms

  Map<String, dynamic> toJson() => {
        'driverId': driverId,
        'driverName': driverName,
        'terminalName': terminalName,
        'contactNumber': contactNumber,
        'at': at.toIso8601String(),
        'channel': channel,
      };

  factory RecentContact.fromJson(Map<String, dynamic> json) {
    return RecentContact(
      driverId: json['driverId'] as String,
      driverName: json['driverName'] as String? ?? 'Driver',
      terminalName: json['terminalName'] as String? ?? '',
      contactNumber: json['contactNumber'] as String? ?? '',
      at: DateTime.parse(json['at'] as String),
      channel: json['channel'] as String? ?? 'sms',
    );
  }
}
