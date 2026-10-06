// ============================================================
// lib/services/customer_insights_service.dart
//
// Pure data-aggregation layer for per-customer purchase insights.
//
// WHY THIS FILE EXISTS:
// Follows the exact pattern established by report_data_service.dart
// for Reports — pure aggregation logic, separate from any widget,
// producing one immutable snapshot. This is deliberate (Standard 3:
// architectural consistency) rather than inventing a new pattern for
// a feature that is conceptually the same shape: "take raw Firestore
// model lists, compute derived numbers, hand back one snapshot."
//
// Computed from data that ALREADY EXISTS — no new Firestore writes,
// no new fields needed on CustomerModel or SalesModel. This is read-
// only aggregation over sales already filtered by customerId, the
// same field the Customer Dashboard already uses to show "my orders".
// ============================================================
import '../models/sales_model.dart';

/// Immutable, fully-computed snapshot of one customer's purchase
/// history — lifetime value, order count, last order date, and
/// average order value.
class CustomerInsightsSnapshot {
  final String   customerId;
  final int      totalOrders;
  final double   lifetimeValue;
  final double   averageOrderValue;
  final DateTime? lastOrderDate;
  final SaleStatus? lastOrderStatus;
  final List<SalesModel> orders; // chronological, most recent first

  const CustomerInsightsSnapshot({
    required this.customerId,
    required this.totalOrders,
    required this.lifetimeValue,
    required this.averageOrderValue,
    required this.lastOrderDate,
    required this.lastOrderStatus,
    required this.orders,
  });

  factory CustomerInsightsSnapshot.empty(String customerId) =>
      CustomerInsightsSnapshot(
        customerId: customerId,
        totalOrders: 0,
        lifetimeValue: 0,
        averageOrderValue: 0,
        lastOrderDate: null,
        lastOrderStatus: null,
        orders: const [],
      );

  /// Days since the customer's last order, or null if they have never
  /// ordered. Used by the UI to flag "inactive" customers (e.g. no
  /// order in 60+ days) without the widget re-deriving this itself.
  int? get daysSinceLastOrder {
    if (lastOrderDate == null) return null;
    return DateTime.now().difference(lastOrderDate!).inDays;
  }
}

class CustomerInsightsService {

  /// Builds a snapshot for ONE customer from the full sales list.
  /// Pass whatever the StreamBuilder currently holds for getSales() —
  /// this is pure, synchronous computation, no Firestore calls of
  /// its own (matches ReportDataService.build()'s contract exactly).
  CustomerInsightsSnapshot build(String customerId, List<SalesModel> allSales) {
    final mine = allSales.where((s) => s.customerId == customerId).toList()
      ..sort((a, b) => b.date.compareTo(a.date)); // most recent first

    if (mine.isEmpty) return CustomerInsightsSnapshot.empty(customerId);

    final lifetimeValue = mine.fold<double>(0, (sum, s) => sum + s.totalAmount);
    final avgOrderValue = lifetimeValue / mine.length;

    return CustomerInsightsSnapshot(
      customerId:        customerId,
      totalOrders:       mine.length,
      lifetimeValue:      lifetimeValue,
      averageOrderValue: avgOrderValue,
      lastOrderDate:     mine.first.date,
      lastOrderStatus:   mine.first.status,
      orders:            mine,
    );
  }

  /// Builds snapshots for ALL customers in one pass over the sales
  /// list — used by a customer list view that needs to show a quick
  /// "lifetime value" badge per row without re-filtering the full
  /// sales list once per customer (which would be O(n*m) instead of
  /// O(n)).
  Map<String, CustomerInsightsSnapshot> buildAll(
      List<String> customerIds, List<SalesModel> allSales) {
    // Group sales by customerId ONCE, then build each snapshot from
    // its own pre-filtered slice — avoids re-scanning the full sales
    // list once per customer.
    final byCustomer = <String, List<SalesModel>>{};
    for (final sale in allSales) {
      byCustomer.putIfAbsent(sale.customerId, () => []).add(sale);
    }

    final result = <String, CustomerInsightsSnapshot>{};
    for (final id in customerIds) {
      result[id] = build(id, byCustomer[id] ?? const []);
    }
    return result;
  }
}