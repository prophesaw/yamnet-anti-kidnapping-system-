class EmergencyContact {
  final String id;
  String name;
  String phoneNumber;
  int priority; // lower number = higher priority (1 = first to be contacted)

  EmergencyContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.priority,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phoneNumber': phoneNumber,
        'priority': priority,
      };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String,
      name: json['name'] as String,
      phoneNumber: json['phoneNumber'] as String,
      priority: json['priority'] as int,
    );
  }
}
