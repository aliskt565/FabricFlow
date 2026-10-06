class EmployeeModel {
  final String id;
  final String name;
  final String role;
  final String email;
  final String phone;
  final String salary;

  EmployeeModel({
    required this.id,
    required this.name,
    required this.role,
    required this.email,
    required this.phone,
    required this.salary,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
        'email': email,
        'phone': phone,
        'salary': salary,
      };

  factory EmployeeModel.fromJson(Map<String, dynamic> json) => EmployeeModel(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        role: json['role'] ?? '',
        email: json['email'] ?? '',
        phone: json['phone'] ?? '',
        salary: json['salary'] ?? '',
      );
}