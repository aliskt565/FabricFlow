// ============================================================
// lib/services/report_data_service.dart
//
// Pure data-aggregation layer for the Reports module.
//
// WHY THIS FILE EXISTS:
// Previously, KPI math (totals, status counts, low-stock filtering)
// was scattered inline inside reports_screen.dart's StreamBuilder
// callbacks. That meant the in-app charts and any future export
// could easily drift out of sync (compute the same number two
// different ways by accident).
//
// This service takes the raw Firestore streams' latest values and
// produces ONE immutable snapshot (ReportSnapshot) that both:
//   1. The chart widgets in reports_screen.dart render from, and
//   2. The PDF/Excel exporters in report_export_service.dart read
//      from.
// Both paths see identical numbers, always.
// ============================================================
import '../models/sales_model.dart';
import '../models/product_model.dart';

class StatusBucket {
  final int    count;
  final double revenue;
  const StatusBucket(this.count, this.revenue);
}

class TopProduct {
  final String productId;
  final String name;
  final int    unitsSold;
  final double revenue;
  const TopProduct({
    required this.productId,
    required this.name,
    required this.unitsSold,
    required this.revenue,
  });
}

class MonthlyPoint {
  final String label;       // e.g. "Jan 2026"
  final int    year;
  final int    month;       // 1-12
  final int    orderCount;
  final double revenue;
  const MonthlyPoint({
    required this.label,
    required this.year,
    required this.month,
    required this.orderCount,
    required this.revenue,
  });
}

/// Immutable, fully-computed snapshot of everything the Reports
/// module needs — feeds both the in-app charts and the exporters.
class ReportSnapshot {
  final double                       totalRevenue;
  final int                          totalOrders;
  final double                       averageOrderValue;
  final int                          totalProducts;
  final int                          lowStockCount;
  final int                          outOfStockCount;
  final Map<String, StatusBucket>    statusBreakdown;   // key = SaleStatus.value
  final List<TopProduct>             topProducts;       // sorted desc by unitsSold
  final List<MonthlyPoint>           monthlyPerformance; // chronological, last 6 months
  final List<ProductModel>           lowStockProducts;
  final List<ProductModel>           allProducts;
  final Map<String, int>             categoryBreakdown; // category -> product count

  const ReportSnapshot({
    required this.totalRevenue,
    required this.totalOrders,
    required this.averageOrderValue,
    required this.totalProducts,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.statusBreakdown,
    required this.topProducts,
    required this.monthlyPerformance,
    required this.lowStockProducts,
    required this.allProducts,
    required this.categoryBreakdown,
  });

  factory ReportSnapshot.empty() => const ReportSnapshot(
    totalRevenue: 0, totalOrders: 0, averageOrderValue: 0,
    totalProducts: 0, lowStockCount: 0, outOfStockCount: 0,
    statusBreakdown: {}, topProducts: [], monthlyPerformance: [],
    lowStockProducts: [], allProducts: [], categoryBreakdown: {},
  );
}

class ReportDataService {

  /// Builds a complete snapshot from the latest sales + products lists.
  /// Pass whatever the StreamBuilders currently hold — this is pure,
  /// synchronous computation with no Firestore calls of its own.
  ReportSnapshot build(List<SalesModel> sales, List<ProductModel> products) {
    if (sales.isEmpty && products.isEmpty) return ReportSnapshot.empty();

    // ── Revenue & order totals ────────────────────────────────────────────
    final totalRevenue = sales.fold<double>(0, (sum, s) => sum + s.totalAmount);
    final totalOrders  = sales.length;
    final avgOrder     = totalOrders == 0 ? 0.0 : totalRevenue / totalOrders;

    // ── Status breakdown (all 4 statuses, even if count is 0) ────────────
    final statusMap = <String, StatusBucket>{};
    for (final status in SaleStatus.values) {
      final matching = sales.where((s) => s.status == status).toList();
      final rev = matching.fold<double>(0, (sum, s) => sum + s.totalAmount);
      statusMap[status.value] = StatusBucket(matching.length, rev);
    }

    // ── Top-selling products (aggregate units sold across all sales) ────
    final unitsSoldMap   = <String, int>{};
    final revenueMap     = <String, double>{};
    final nameMap        = <String, String>{};
    for (final sale in sales) {
      for (final item in sale.items) {
        final pid  = item['productId'] as String? ?? '';
        final name = item['productName'] as String? ?? 'Unknown';
        final qty  = (item['quantity'] as num?)?.toInt() ?? 0;
        final price = (item['price'] as num?)?.toDouble() ?? 0;
        unitsSoldMap[pid] = (unitsSoldMap[pid] ?? 0) + qty;
        revenueMap[pid]   = (revenueMap[pid] ?? 0) + (qty * price);
        nameMap[pid]      = name;
      }
    }
    final topProducts = unitsSoldMap.entries.map((e) => TopProduct(
      productId: e.key,
      name:      nameMap[e.key] ?? 'Unknown',
      unitsSold: e.value,
      revenue:   revenueMap[e.key] ?? 0,
    )).toList()
      ..sort((a, b) => b.unitsSold.compareTo(a.unitsSold));
    final top10 = topProducts.take(10).toList();

    // ── Monthly performance — last 6 calendar months, chronological ──────
    final now = DateTime.now();
    final months = List.generate(6, (i) {
      final d = DateTime(now.year, now.month - (5 - i), 1);
      return d;
    });
    final monthly = months.map((m) {
      final inMonth = sales.where((s) =>
          s.date.year == m.year && s.date.month == m.month).toList();
      final rev = inMonth.fold<double>(0, (sum, s) => sum + s.totalAmount);
      return MonthlyPoint(
        label:      _monthLabel(m),
        year:       m.year,
        month:      m.month,
        orderCount: inMonth.length,
        revenue:    rev,
      );
    }).toList();

    // ── Inventory stats ────────────────────────────────────────────────────
    final lowStock   = products.where((p) => p.stock > 0 && p.stock < 10).toList();
    final outOfStock = products.where((p) => p.stock == 0).toList();
    final categoryMap = <String, int>{};
    for (final p in products) {
      categoryMap[p.category] = (categoryMap[p.category] ?? 0) + 1;
    }

    return ReportSnapshot(
      totalRevenue:       totalRevenue,
      totalOrders:        totalOrders,
      averageOrderValue:  avgOrder,
      totalProducts:      products.length,
      lowStockCount:      lowStock.length,
      outOfStockCount:    outOfStock.length,
      statusBreakdown:    statusMap,
      topProducts:        top10,
      monthlyPerformance: monthly,
      lowStockProducts:   lowStock,
      allProducts:        products,
      categoryBreakdown:  categoryMap,
    );
  }

  String _monthLabel(DateTime d) {
    const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${names[d.month - 1]} ${d.year}';
  }
}