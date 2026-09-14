class Terminal {
  const Terminal({
    required this.id,
    required this.name,
    this.address = '',
    this.city = 'Antipolo City',
    this.isMain = false,
  });

  final String id;
  final String name;
  final String address;
  final String city;
  final bool isMain;

  factory Terminal.fromJson(Map<String, dynamic> json) {
    return Terminal(
      id: (json['terminal_id'] ?? json['id']) as String,
      name: (json['terminal_name'] ?? json['name'] ?? '') as String,
      address: (json['address'] as String?) ?? 'Brgy. San Luis, Antipolo City',
      city: (json['city'] as String?) ?? 'Antipolo City',
      isMain: (json['is_main'] as bool?) ??
          ((json['terminal_name'] ?? json['name'] ?? '') as String)
              .toLowerCase()
              .contains('bayan'),
    );
  }
}
