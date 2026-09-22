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

  factory Shift.fromJson(Map<String, dynamic> json) {
    return Shift(
      id: (json['shift_id'] ?? json['id']) as String,
      label: (json['label'] ?? '') as String,
      startTime: json['shift_start_time'].toString(),
      endTime: json['shift_end_time'].toString(),
    );
  }
}
