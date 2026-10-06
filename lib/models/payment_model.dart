// ============================================================
// lib/models/payment_model.dart
//
// PAYMENT TRACKING SYSTEM — data model
//
// DESIGN PATTERN (Stripe / Shopify style):
//   A Sale can have MULTIPLE PaymentModel records (installments,
//   partial payments, refunds). The Sale itself never stores a
//   single "amountPaid" field — that would break under partial
//   payments and refunds. Instead, balance is always computed by
//   summing PaymentModel records for a given saleId (see
//   PaymentService.getSaleBalance).
//
//   PaymentMethod is intentionally split into two layers:
//     - `method`        → WHAT the customer used (cash, bank, jazzcash...)
//     - `gatewayId`      → WHICH PaymentGateway implementation processed it
//                          ('manual' today; 'jazzcash_api' / 'stripe_api'
//                          / 'easypaisa_api' when a real integration is
//                          plugged in later). This is what makes the
//                          system "future-proof" without any migration —
//                          a real gateway is just a new gatewayId value
//                          plus a new PaymentGateway implementation.
//
// FIRESTORE SCHEMA
// Collection: payments
// Document fields:
//   id               String
//   saleId           String   — links to sales/{saleId}
//   customerId       String
//   customerName     String
//   amount           double
//   method           String   — PaymentMethod.value
//   gatewayId        String   — 'manual' | 'jazzcash_api' | 'easypaisa_api' | 'stripe_api'
//   status           String   — PaymentStatus.value
//   transactionRef    String   — receipt no. (manual) or gateway txn ID (real gateway)
//   notes            String   — optional free text (e.g. "2nd installment")
//   gatewayResponse  Map      — raw response from a real gateway (empty for manual)
//   recordedByUid    String   — actorUid who recorded the payment
//   recordedByName   String   — actorName who recorded the payment
//   createdAt        String   — ISO8601
//   updatedAt        String   — ISO8601
//
// Indexing strategy:
//   - Composite index on (saleId ASC, createdAt DESC) — payment history per sale
//   - Composite index on (customerId ASC, createdAt DESC) — per-customer payment views
//   - Single-field index on createdAt DESC — default chronological feed
// ============================================================

/// HOW a payment was made, from the customer's point of view.
/// Extensible: adding a new method later is one new enum value plus
/// one new case in `value`/`fromString`/`label`/`icon` — no breaking
/// changes anywhere else.
enum PaymentMethod { cash, bankTransfer, jazzCash, easyPaisa, card }

extension PaymentMethodX on PaymentMethod {
  String get value {
    switch (this) {
      case PaymentMethod.cash:         return 'Cash';
      case PaymentMethod.bankTransfer: return 'Bank Transfer';
      case PaymentMethod.jazzCash:     return 'JazzCash';
      case PaymentMethod.easyPaisa:    return 'EasyPaisa';
      case PaymentMethod.card:         return 'Card';
    }
  }

  /// Whether this method, when picked, REQUIRES a transaction
  /// reference number before the payment can be recorded. Cash is
  /// the only exception — everything else leaves a paper/digital
  /// trail that should be captured.
  bool get requiresReference {
    switch (this) {
      case PaymentMethod.cash: return false;
      default:                 return true;
    }
  }

  static PaymentMethod fromString(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'Cash':          return PaymentMethod.cash;
      case 'Bank Transfer': return PaymentMethod.bankTransfer;
      case 'JazzCash':      return PaymentMethod.jazzCash;
      case 'EasyPaisa':     return PaymentMethod.easyPaisa;
      case 'Card':          return PaymentMethod.card;
      default:              return PaymentMethod.cash;
    }
  }
}

/// Lifecycle of a single payment record — mirrors how Stripe/Shopify
/// model a payment's state machine, NOT the sale's own status.
enum PaymentStatus { pending, completed, failed, refunded }

extension PaymentStatusX on PaymentStatus {
  String get value {
    switch (this) {
      case PaymentStatus.pending:   return 'Pending';
      case PaymentStatus.completed: return 'Completed';
      case PaymentStatus.failed:    return 'Failed';
      case PaymentStatus.refunded:  return 'Refunded';
    }
  }

  static PaymentStatus fromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'completed': return PaymentStatus.completed;
      case 'failed':    return PaymentStatus.failed;
      case 'refunded':  return PaymentStatus.refunded;
      case 'pending':
      default:          return PaymentStatus.pending;
    }
  }

  /// Only COMPLETED payments count toward a sale's paid balance.
  /// Pending/failed/refunded must never be summed into amountPaid —
  /// this is the single most important invariant in this whole
  /// payment system.
  bool get countsTowardBalance => this == PaymentStatus.completed;
}

class PaymentModel {
  final String              id;
  final String              saleId;
  final String              customerId;
  final String              customerName;
  final double               amount;
  final PaymentMethod        method;
  final String               gatewayId;
  final PaymentStatus        status;
  final String               transactionRef;
  final String               notes;
  final Map<String, dynamic> gatewayResponse;
  final String               recordedByUid;
  final String               recordedByName;
  final DateTime              createdAt;
  final DateTime              updatedAt;

  static const String manualGatewayId = 'manual';

  PaymentModel({
    required this.id,
    required this.saleId,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.method,
    this.gatewayId        = manualGatewayId,
    this.status           = PaymentStatus.pending,
    this.transactionRef   = '',
    this.notes            = '',
    this.gatewayResponse  = const {},
    required this.recordedByUid,
    required this.recordedByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id':              id,
    'saleId':          saleId,
    'customerId':      customerId,
    'customerName':    customerName,
    'amount':          amount,
    'method':          method.value,
    'gatewayId':       gatewayId,
    'status':          status.value,
    'transactionRef':  transactionRef,
    'notes':           notes,
    'gatewayResponse': gatewayResponse,
    'recordedByUid':   recordedByUid,
    'recordedByName':  recordedByName,
    'createdAt':       createdAt.toIso8601String(),
    'updatedAt':       updatedAt.toIso8601String(),
  };

  factory PaymentModel.fromJson(Map<String, dynamic> json) => PaymentModel(
    id:             json['id'] as String? ?? '',
    saleId:         json['saleId'] as String? ?? '',
    customerId:     json['customerId'] as String? ?? '',
    customerName:   json['customerName'] as String? ?? '',
    amount:         (json['amount'] as num?)?.toDouble() ?? 0,
    method:         PaymentMethodX.fromString(json['method'] as String?),
    gatewayId:      json['gatewayId'] as String? ?? manualGatewayId,
    status:         PaymentStatusX.fromString(json['status'] as String?),
    transactionRef: json['transactionRef'] as String? ?? '',
    notes:          json['notes'] as String? ?? '',
    gatewayResponse: json['gatewayResponse'] != null
        ? Map<String, dynamic>.from(json['gatewayResponse'] as Map)
        : const {},
    recordedByUid:  json['recordedByUid'] as String? ?? '',
    recordedByName: json['recordedByName'] as String? ?? 'Unknown',
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
        : DateTime.now(),
    updatedAt: json['updatedAt'] != null
        ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
        : DateTime.now(),
  );

  PaymentModel copyWith({
    PaymentStatus?        status,
    String?               transactionRef,
    Map<String, dynamic>? gatewayResponse,
    DateTime?             updatedAt,
  }) => PaymentModel(
    id:              id,
    saleId:          saleId,
    customerId:      customerId,
    customerName:    customerName,
    amount:          amount,
    method:          method,
    gatewayId:       gatewayId,
    status:          status ?? this.status,
    transactionRef:  transactionRef ?? this.transactionRef,
    notes:           notes,
    gatewayResponse: gatewayResponse ?? this.gatewayResponse,
    recordedByUid:   recordedByUid,
    recordedByName:  recordedByName,
    createdAt:       createdAt,
    updatedAt:       updatedAt ?? DateTime.now(),
  );
}

/// Computed (not stored) summary of a sale's payment state — returned
/// by PaymentService.getSaleBalance(). Never persisted directly so it
/// can never drift out of sync with the underlying payment records.
class SaleBalance {
  final double totalAmount;
  final double amountPaid;
  final List<PaymentModel> payments;

  const SaleBalance({
    required this.totalAmount,
    required this.amountPaid,
    required this.payments,
  });

  double get amountDue => (totalAmount - amountPaid).clamp(0, totalAmount);

  bool get isFullyPaid => amountDue <= 0.009 && totalAmount > 0;

  bool get isPartiallyPaid => amountPaid > 0.009 && !isFullyPaid;

  bool get isUnpaid => amountPaid <= 0.009;

  /// Human label matching the Paid / Partial / Unpaid vocabulary used
  /// across the rest of the app's status badges.
  String get label {
    if (isFullyPaid) return 'Paid';
    if (isPartiallyPaid) return 'Partial';
    return 'Unpaid';
  }
}