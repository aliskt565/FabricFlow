// ============================================================
// lib/models/rbac_model.dart
// Role-Based Access Control — single source of truth
// ============================================================

/// Application roles in strict privilege order.
/// Higher index = higher privilege.
enum AppRole { customer, employee, manager }

extension AppRoleX on AppRole {

  /// Convert Firestore string → enum
  static AppRole fromString(String s) {
    switch (s.toLowerCase()) {
      case 'manager':  return AppRole.manager;
      case 'employee': return AppRole.employee;
      default:         return AppRole.customer;
    }
  }

  /// Convert enum → Firestore string
  String get name {
    switch (this) {
      case AppRole.manager:  return 'Manager';
      case AppRole.employee: return 'Employee';
      case AppRole.customer: return 'Customer';
    }
  }

  /// Numeric privilege level (higher = more powerful)
  int get level {
    switch (this) {
      case AppRole.manager:  return 3;
      case AppRole.employee: return 2;
      case AppRole.customer: return 1;
    }
  }

  // ── RBAC rules ─────────────────────────────────────────────────────────

  /// Can this role create user accounts at all?
  bool get canCreateUsers => this == AppRole.manager;

  /// Can this role create a user with [targetRole]?
  ///   Rule 1: Only Manager can create users.
  ///   Rule 2: Cannot create same-level role as self.
  ///   Rule 3: Cannot create higher-privilege role than self.
  bool canCreateRole(AppRole targetRole) {
    if (!canCreateUsers) return false;           // Rule 1
    if (targetRole.level >= level) return false; // Rules 2 & 3
    return true;
  }

  /// Roles this role is allowed to create.
  List<AppRole> get creatableRoles =>
      AppRole.values.where(canCreateRole).toList();

  // ── Feature permissions ────────────────────────────────────────────────

  bool get canReadInventory  => level >= AppRole.employee.level;
  bool get canWriteInventory => this == AppRole.manager;

  bool get canReadSales      => level >= AppRole.employee.level;
  bool get canWriteSales     => this == AppRole.manager;

  bool get canReadEmployees  => this == AppRole.manager;
  bool get canWriteEmployees => this == AppRole.manager;

  bool get canReadCustomers  => this == AppRole.manager;
  bool get canWriteCustomers => this == AppRole.manager;

  bool get canReadReports    => this == AppRole.manager;
  bool get canReadSettings   => this == AppRole.manager;

  bool get canBrowseProducts => this == AppRole.customer;
  bool get canPlaceOrders    => this == AppRole.customer;
}