// ============================================================
// lib/models/activity_log_model.dart
//
// Activity Logging / Audit Trail — data model
//
// FIRESTORE SCHEMA
// Collection: activity_logs
// Document fields:
//   id               String    — Firestore doc ID
//   userId           String    — Firebase Auth UID of the actor
//   username         String    — Display name/email of the actor
//   action           String    — canonical ActivityAction.value
//   entity           String    — canonical ActivityEntity.value
//   recordId         String    — ID of the affected record (product, sale, user, payment...)
//   timestamp        String    — ISO8601 timestamp (client-generated for ordering)
//   serverTimestamp  Timestamp — Firestore serverTimestamp() for trust/ordering
//   details          Map       — free-form extra context (old/new values etc.)
//
// Indexing strategy (see firestore.indexes.json):
//   - Composite index on (entity ASC, timestamp DESC) — entity-filtered views
//   - Composite index on (userId ASC, timestamp DESC) — per-user activity views
//   - Single-field index on timestamp DESC — default chronological feed
// ============================================================

/// All trackable actions in the system.
enum ActivityAction {
  login,
  logout,
  productCreate,
  productUpdate,
  productDelete,
  salesCreate,
  salesUpdate,
  salesComplete,
  salesCancel,
  userCreate,
  userUpdate,
  userDelete,
  roleChange,
  paymentRecord,
  paymentRefund,
}

extension ActivityActionX on ActivityAction {
  /// Canonical string stored in Firestore — single source of truth,
  /// avoids the "completed" vs "Completed" class of bug seen in
  /// SaleStatus by always writing/reading through this getter.
  String get value {
    switch (this) {
      case ActivityAction.login:          return 'Login';
      case ActivityAction.logout:         return 'Logout';
      case ActivityAction.productCreate:  return 'Product Create';
      case ActivityAction.productUpdate:  return 'Product Update';
      case ActivityAction.productDelete:  return 'Product Delete';
      case ActivityAction.salesCreate:    return 'Sales Create';
      case ActivityAction.salesUpdate:    return 'Sales Update';
      case ActivityAction.salesComplete:  return 'Sales Complete';
      case ActivityAction.salesCancel:    return 'Sales Cancel';
      case ActivityAction.userCreate:     return 'User Create';
      case ActivityAction.userUpdate:     return 'User Update';
      case ActivityAction.userDelete:     return 'User Delete';
      case ActivityAction.roleChange:     return 'Role Change';
      case ActivityAction.paymentRecord:  return 'Payment Record';
      case ActivityAction.paymentRefund:  return 'Payment Refund';
    }
  }

  static ActivityAction fromString(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'Login':            return ActivityAction.login;
      case 'Logout':           return ActivityAction.logout;
      case 'Product Create':   return ActivityAction.productCreate;
      case 'Product Update':   return ActivityAction.productUpdate;
      case 'Product Delete':   return ActivityAction.productDelete;
      case 'Sales Create':     return ActivityAction.salesCreate;
      case 'Sales Update':     return ActivityAction.salesUpdate;
      case 'Sales Complete':   return ActivityAction.salesComplete;
      case 'Sales Cancel':     return ActivityAction.salesCancel;
      case 'User Create':      return ActivityAction.userCreate;
      case 'User Update':      return ActivityAction.userUpdate;
      case 'User Delete':      return ActivityAction.userDelete;
      case 'Role Change':      return ActivityAction.roleChange;
      case 'Payment Record':   return ActivityAction.paymentRecord;
      case 'Payment Refund':   return ActivityAction.paymentRefund;
      default:                 return ActivityAction.login; // safe fallback
    }
  }
}

/// Which part of the system the action touched. Used for filtering
/// the log feed (e.g. "show me only Sales activity").
enum ActivityEntity { auth, product, sale, user, payment }

extension ActivityEntityX on ActivityEntity {
  String get value {
    switch (this) {
      case ActivityEntity.auth:    return 'Auth';
      case ActivityEntity.product: return 'Product';
      case ActivityEntity.sale:    return 'Sale';
      case ActivityEntity.user:    return 'User';
      case ActivityEntity.payment: return 'Payment';
    }
  }

  static ActivityEntity fromString(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'Auth':    return ActivityEntity.auth;
      case 'Product': return ActivityEntity.product;
      case 'Sale':    return ActivityEntity.sale;
      case 'User':    return ActivityEntity.user;
      case 'Payment': return ActivityEntity.payment;
      default:        return ActivityEntity.auth;
    }
  }
}

class ActivityLogModel {
  final String          id;
  final String          userId;
  final String          username;
  final ActivityAction  action;
  final ActivityEntity  entity;
  final String          recordId;
  final DateTime        timestamp;
  final Map<String, dynamic> details;

  ActivityLogModel({
    required this.id,
    required this.userId,
    required this.username,
    required this.action,
    required this.entity,
    required this.recordId,
    DateTime? timestamp,
    this.details = const {},
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id':        id,
    'userId':    userId,
    'username':  username,
    'action':    action.value,
    'entity':    entity.value,
    'recordId':  recordId,
    'timestamp': timestamp.toIso8601String(),
    'details':   details,
    // serverTimestamp is added separately at write-time in the service
    // (FieldValue.serverTimestamp() cannot be embedded in toJson()
    // because it's a sentinel, not a real value).
  };

  factory ActivityLogModel.fromJson(Map<String, dynamic> json) =>
      ActivityLogModel(
        id:        json['id'] as String? ?? '',
        userId:    json['userId'] as String? ?? '',
        username:  json['username'] as String? ?? 'Unknown',
        action:    ActivityActionX.fromString(json['action'] as String?),
        entity:    ActivityEntityX.fromString(json['entity'] as String?),
        recordId:  json['recordId'] as String? ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
            : DateTime.now(),
        details: json['details'] != null
            ? Map<String, dynamic>.from(json['details'] as Map)
            : const {},
      );
}