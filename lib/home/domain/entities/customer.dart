class Customer {
  final String id;
  final String name;
  final String number;
  final String displayPhone;
  final String relativeTime;
  final String? profilePicUrl;  

  Customer({
    required this.id,
    required this.name,
    required this.number,
    required this.displayPhone,
    required this.relativeTime,
    this.profilePicUrl,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id']?.toString() ?? '',
    name: json['name'] ?? '',
    number: json['number'] ?? '',
    displayPhone: json['displayPhone'] ?? '',
    relativeTime: json['relativeTime'] ?? '', 
    profilePicUrl: json['profilePicUrl'],
  );
}
