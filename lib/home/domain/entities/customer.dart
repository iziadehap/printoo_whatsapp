class Customer {
  final String id;
  final String name;
  final String number;
  final String displayPhone;
  final String relativeTime;

  Customer({
    required this.id,
    required this.name,
    required this.number,
    required this.displayPhone,
    required this.relativeTime,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id']?.toString() ?? '',
    name: json['name'] ?? '',
    number: json['number'] ?? '',
    displayPhone: json['displayPhone'] ?? '',
    relativeTime: json['relativeTime'] ?? '',
  );
}
