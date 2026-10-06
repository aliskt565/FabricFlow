// ============================================================
// lib/models/sales_model.dart
//
// UPDATE: Order Tracking Timeline — added `statusHistory`.
//
//   statusHistory is a List<Map<String, dynamic>>, each entry shaped:
//     { 'status': 'Pending', 'timestamp': '2026-06-30T10:00:00.000' }
//
//   - A new sale is created with ONE history entry for its initial
//     status (matches whatever `status` the sale starts as — Pending
//     in normal flow).
//   - Every subsequent status change (via updateSaleStatus in
//     FirestoreService) appends one more entry — never rewrites or
//     removes prior entries, so the full Pending → Processing →
//     Completed (or → Cancelled) journey is preserved permanently for
//     the customer's order tracking UI.
//   - Existing Firestore documents created before this field existed
//     simply parse with an empty statusHistory list (no migration
//     needed) — the customer tracking UI falls back to just showing
//     the current status with no timeline in that case.
// ============================================================
enum SaleStatus { pending, processing, completed, cancelled }

extension SaleStatusX on SaleStatus {
  String get value {
    switch (this) {
      case SaleStatus.pending:    return 'Pending';
      case SaleStatus.processing: return 'Processing';
      case SaleStatus.completed:  return 'Completed';
      case SaleStatus.cancelled:  return 'Cancelled';
    }
  }

  static SaleStatus fromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'completed':  return SaleStatus.completed;
      case 'processing': return SaleStatus.processing;
      case 'cancelled':
      case 'canceled': return SaleStatus.cancelled;
      case 'pending':
      default:           return SaleStatus.pending;
    }
  }

  List<SaleStatus> get allowedNextStatuses {
    switch (this) {
      case SaleStatus.pending:
        return [SaleStatus.processing, SaleStatus.cancelled];
      case SaleStatus.processing:
        return [SaleStatus.completed, SaleStatus.cancelled];
      case SaleStatus.completed:
        return [SaleStatus.cancelled];
      case SaleStatus.cancelled:
        return [SaleStatus.pending];
    }
  }
}

class SalesModel {
  final String              id;
  final String              customerId;
  final String              customerName;
  final List<Map<String, dynamic>> items;
  final double              totalAmount;
  final DateTime            date;
  final SaleStatus          status;
  final List<Map<String, dynamic>> statusHistory;

  SalesModel({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.items,
    required this.totalAmount,
    required this.date,
    this.status = SaleStatus.pending,
    List<Map<String, dynamic>>? statusHistory,
  }) : statusHistory = statusHistory ??
            [
              {
                'status':    status.value,
                'timestamp': DateTime.now().toIso8601String(),
              }
            ];

  Map<String, dynamic> toJson() => {
    'id':            id,
    'customerId':    customerId,
    'customerName':  customerName,
    'items':         items,
    'totalAmount':   totalAmount,
    'date':          date.toIso8601String(),
    'status':        status.value,
    'statusHistory': statusHistory,
  };

  factory SalesModel.fromJson(Map<String, dynamic> json) => SalesModel(
    id:           json['id'] as String? ?? '',
    customerId:   json['customerId'] as String? ?? '',
    customerName: json['customerName'] as String? ?? '',
    items: (json['items'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
    totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
    date: json['date'] != null
        ? DateTime.tryParse(json['date'] as String) ?? DateTime.now()
        : DateTime.now(),
    status: SaleStatusX.fromString(json['status'] as String?),
    statusHistory: (json['statusHistory'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [],
  );

  SalesModel copyWith({SaleStatus? status, List<Map<String, dynamic>>? statusHistory}) =>
      SalesModel(
        id: id, customerId: customerId, customerName: customerName,
        items: items, totalAmount: totalAmount, date: date,
        status: status ?? this.status,
        statusHistory: statusHistory ?? this.statusHistory,
      );
}