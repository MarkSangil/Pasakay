import 'terminal.dart';

enum ShiftType { morning, afternoon, evening }

extension ShiftTypeX on ShiftType {
  String get dbValue => name;

  String get label => switch (this) {
        ShiftType.morning => 'Morning',
        ShiftType.afternoon => 'Afternoon',
        ShiftType.evening => 'Evening',
      };

  static ShiftType fromDb(String value) {
    return ShiftType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ShiftType.morning,
    );
  }
}

class Driver {
  const Driver({
    required this.id,
    required this.fullName,
    required this.mobileNumber,
    required this.email,
    this.todaNumber,
    this.licenseNumber,
    this.plateNumber,
    this.yearsOfService = 0,
    this.assignedTerminalId,
    this.currentTerminalId,
    this.shiftId,
    this.avatarUrl,
    this.averageRating = 0,
    this.reviewCount = 0,
    this.isActive = true,
    this.status = 'active',
    this.statusReason,
    this.assignedTerminal,
    this.currentTerminal,
    this.onShift = false,
  });

  final String id;
  final String fullName;
  final String mobileNumber;
  final String email;
  final String? todaNumber;
  final String? licenseNumber;
  final String? plateNumber;
  final int yearsOfService;
  final String? assignedTerminalId;
  final String? currentTerminalId;
  final String? shiftId;
  final String? avatarUrl;
  final double averageRating;
  final int reviewCount;
  final bool isActive;
  final String status;
  final String? statusReason;
  final Terminal? assignedTerminal;
  final Terminal? currentTerminal;
  final bool onShift;

  Driver copyWith({
    String? currentTerminalId,
    Terminal? currentTerminal,
    bool? onShift,
    String? avatarUrl,
  }) {
    return Driver(
      id: id,
      fullName: fullName,
      mobileNumber: mobileNumber,
      email: email,
      todaNumber: todaNumber,
      licenseNumber: licenseNumber,
      plateNumber: plateNumber,
      yearsOfService: yearsOfService,
      assignedTerminalId: assignedTerminalId,
      currentTerminalId: currentTerminalId ?? this.currentTerminalId,
      shiftId: shiftId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      averageRating: averageRating,
      reviewCount: reviewCount,
      isActive: isActive,
      status: status,
      statusReason: statusReason,
      assignedTerminal: assignedTerminal,
      currentTerminal: currentTerminal ?? this.currentTerminal,
      onShift: onShift ?? this.onShift,
    );
  }

  factory Driver.fromJson(Map<String, dynamic> json) {
    Terminal? assigned;
    Terminal? current;
    final assignedRaw =
        json['assigned_terminal'] ?? json['terminal'] ?? json['terminals'];
    final currentRaw = json['current_terminal'];
    if (assignedRaw is Map<String, dynamic>) {
      assigned = Terminal.fromJson(assignedRaw);
    }
    if (currentRaw is Map<String, dynamic>) {
      current = Terminal.fromJson(currentRaw);
    }

    final id = (json['driver_id'] ?? json['id']) as String;
    final terminalId =
        (json['terminal_id'] ?? json['assigned_terminal_id']) as String?;

    return Driver(
      id: id,
      fullName: json['full_name'] as String? ?? 'Driver',
      mobileNumber:
          (json['contact_number'] ?? json['mobile_number'] ?? '') as String,
      email: (json['email'] ?? json['email_address'] ?? '') as String,
      todaNumber: json['toda_number'] as String?,
      licenseNumber: (json['driver_license_number'] ?? json['license_number'])
          as String?,
      plateNumber: json['plate_number'] as String?,
      yearsOfService: (json['years_of_service'] as num?)?.toInt() ?? 0,
      assignedTerminalId: terminalId,
      // Do not fall back to assigned — mockup requires an explicit "where today" pick.
      currentTerminalId: json['current_terminal_id'] as String?,
      shiftId: json['shift_id'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      averageRating: (json['average_rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      status: json['status'] as String? ??
          ((json['is_active'] as bool? ?? true) ? 'active' : 'deactivated'),
      statusReason: json['status_reason'] as String?,
      assignedTerminal: assigned,
      currentTerminal: current ?? assigned,
    );
  }
}

class DriverSchedule {
  const DriverSchedule({
    required this.id,
    required this.driverId,
    required this.shift,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.terminalId,
    this.isActive = true,
  });

  final String id;
  final String driverId;
  final ShiftType shift;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final String? terminalId;
  final bool isActive;

  factory DriverSchedule.fromJson(Map<String, dynamic> json) {
    return DriverSchedule(
      id: json['id'] as String,
      driverId: (json['driver_id'] ?? '') as String,
      shift: ShiftTypeX.fromDb(json['shift'] as String? ?? 'morning'),
      dayOfWeek: (json['day_of_week'] as num?)?.toInt() ?? 0,
      startTime: json['start_time'].toString(),
      endTime: json['end_time'].toString(),
      terminalId: json['terminal_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class DriverShift {
  const DriverShift({
    required this.id,
    required this.driverId,
    required this.terminalId,
    required this.shiftDate,
    required this.shift,
    required this.startAt,
    required this.endAt,
    this.terminal,
  });

  final String id;
  final String driverId;
  final String terminalId;
  final DateTime shiftDate;
  final ShiftType shift;
  final DateTime startAt;
  final DateTime endAt;
  final Terminal? terminal;

  factory DriverShift.fromJson(Map<String, dynamic> json) {
    Terminal? terminal;
    final raw = json['terminal'];
    if (raw is Map<String, dynamic>) {
      terminal = Terminal.fromJson(raw);
    }
    return DriverShift(
      id: json['id'] as String,
      driverId: json['driver_id'] as String,
      terminalId: json['terminal_id'] as String,
      shiftDate: DateTime.parse(json['shift_date'].toString()),
      shift: ShiftTypeX.fromDb(json['shift'] as String? ?? 'morning'),
      startAt: DateTime.parse(json['start_at'] as String),
      endAt: DateTime.parse(json['end_at'] as String),
      terminal: terminal,
    );
  }
}
