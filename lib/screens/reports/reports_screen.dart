// ============================================================
// lib/screens/reports/reports_screen.dart
//
// ENHANCED REPORTS MODULE
//
// New in this version:
//   - 4 tabs: Overview / Sales & Revenue / Inventory / Top & Monthly
//   - Real charts via fl_chart: LineChart (revenue trend),
//     BarChart (monthly performance, top products), PieChart
//     (sales by status, inventory by category)
//   - Export menu (PDF + Excel) in the app bar — both formats use
//     the exact same ReportSnapshot data the charts render, so
//     numbers never drift between what you see and what you export
//   - All chart data comes from ReportDataService.build() — single
//     source of truth shared with ReportExportService
//
// LIBRARIES USED:
//   fl_chart   — in-app charts (line, bar, pie) — free, MIT license
//   (pdf, excel, permission_handler — used in report_export_service.dart)
//
// THEME MIGRATION: all hardcoded colors replaced with AppColors/
// AppGradients/AppRadius/AppText. One new token pair added to
// app_theme.dart during this migration: AppColors.gold/goldDeep,
// found only here for the #1 "top selling product" trophy badge.
// ============================================================
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/sales_model.dart';
import '../../models/product_model.dart';
import '../../services/firestore_service.dart';
import '../../services/report_data_service.dart';
import '../../services/report_export_service.dart';
import '../../theme/app_theme.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService       _fs       = FirestoreService();
  final ReportDataService      _dataSvc  = ReportDataService();
  final ReportExportService    _exportSvc = ReportExportService();
  late TabController _tabController;

  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  // ── Export handlers ─────────────────────────────────────────────────────
  Future<void> _handleExport(
      ReportSnapshot snapshot, bool isPdf) async {
    setState(() => _exporting = true);
    try {
      final path = isPdf
          ? await _exportSvc.exportPdf(snapshot)
          : await _exportSvc.exportExcel(snapshot);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.textPrimary, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(
                'Saved to Downloads:\n${path.split('/').last}',
                style: AppText.body().copyWith(fontSize: 13))),
          ]),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e', style: AppText.body()),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SalesModel>>(
      stream: _fs.getSales(),
      builder: (ctx, salesSnap) {
        return StreamBuilder<List<ProductModel>>(
          stream: _fs.getProducts(),
          builder: (ctx, prodSnap) {
            final sales    = salesSnap.data ?? [];
            final products = prodSnap.data ?? [];
            final snapshot = _dataSvc.build(sales, products);

            return Scaffold(
              backgroundColor: AppColors.background,
              body: NestedScrollView(
                headerSliverBuilder: (context, _) => [
                  SliverAppBar(
                    expandedHeight: 170,
                    pinned: true, floating: false,
                    backgroundColor: AppColors.background,
                    elevation: 0,
                    automaticallyImplyLeading: false,
                    actions: [
                      _exporting
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      color: AppColors.danger, strokeWidth: 2)),
                            )
                          : PopupMenuButton<String>(
                              icon: const Icon(Icons.ios_share_rounded, color: AppColors.textPrimary),
                              color: AppColors.surface,
                              shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
                              itemBuilder: (ctx) => [
                                PopupMenuItem(value: 'pdf', child: Row(children: [
                                  const Icon(Icons.picture_as_pdf_rounded, color: AppColors.danger, size: 18),
                                  const SizedBox(width: 10),
                                  Text('Export as PDF', style: AppText.body().copyWith(fontSize: 13)),
                                ])),
                                PopupMenuItem(value: 'xlsx', child: Row(children: [
                                  const Icon(Icons.table_chart_rounded, color: AppColors.success, size: 18),
                                  const SizedBox(width: 10),
                                  Text('Export as Excel', style: AppText.body().copyWith(fontSize: 13)),
                                ])),
                              ],
                              onSelected: (v) => _handleExport(snapshot, v == 'pdf'),
                            ),
                      const SizedBox(width: 8),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: const BoxDecoration(
                          gradient: AppGradients.background,
                        ),
                        child: SafeArea(child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  gradient: AppGradients.reportAccent,
                                  borderRadius: AppRadius.lgRadius),
                                child: const Icon(Icons.bar_chart_rounded, color: AppColors.textPrimary, size: 22),
                              ),
                              const SizedBox(width: 14),
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Reports', style: AppText.headline()),
                                Text('Business analytics & exports',
                                    style: AppText.caption(color: AppColors.textTertiary).copyWith(fontSize: 13)),
                              ]),
                            ]),
                            const SizedBox(height: 14),
                            TabBar(
                              controller: _tabController,
                              isScrollable: true,
                              indicatorColor: AppColors.danger,
                              indicatorWeight: 3,
                              indicatorSize: TabBarIndicatorSize.label,
                              labelStyle: AppText.body().copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                              unselectedLabelStyle: AppText.body().copyWith(fontSize: 13),
                              labelColor: AppColors.textPrimary,
                              unselectedLabelColor: AppColors.textDisabled,
                              tabs: const [
                                Tab(text: 'Overview'),
                                Tab(text: 'Sales & Revenue'),
                                Tab(text: 'Inventory'),
                                Tab(text: 'Top & Monthly'),
                              ],
                            ),
                          ]),
                        )),
                      ),
                    ),
                  ),
                ],
                body: TabBarView(
                  controller: _tabController,
                  children: [
                    _overviewTab(snapshot),
                    _salesRevenueTab(snapshot),
                    _inventoryTab(snapshot),
                    _topMonthlyTab(snapshot),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── TAB 1: Overview ─────────────────────────────────────────────────────
  Widget _overviewTab(ReportSnapshot s) {
    if (s.totalOrders == 0 && s.totalProducts == 0) return _emptyState('No Data Yet', Icons.bar_chart_rounded);

    return ListView(padding: const EdgeInsets.all(16), children: [
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.4,
        children: [
          _kpiCard('Total Revenue', 'Rs. ${_fmt(s.totalRevenue)}', Icons.trending_up_rounded,
              AppColors.danger, AppColors.dangerLight, '${s.totalOrders} orders'),
          _kpiCard('Products', '${s.totalProducts}', Icons.inventory_2_rounded,
              AppColors.primary, AppColors.primaryDeep, '${s.outOfStockCount} out of stock'),
          _kpiCard('Avg Order', 'Rs. ${_fmt(s.averageOrderValue)}', Icons.analytics_rounded,
              AppColors.pink, AppColors.danger, 'per transaction'),
          _kpiCard('Low Stock', '${s.lowStockCount}', Icons.warning_amber_rounded,
              AppColors.warning, AppColors.danger, 'items need restock'),
        ],
      ),
      const SizedBox(height: 24),
      _sectionHeader('Revenue Trend (Last 6 Months)'),
      const SizedBox(height: 12),
      _revenueLineChart(s),
      const SizedBox(height: 24),
      _sectionHeader('Sales by Status'),
      const SizedBox(height: 12),
      _statusPieChart(s),
    ]);
  }

  // ── TAB 2: Sales & Revenue ──────────────────────────────────────────────
  Widget _salesRevenueTab(ReportSnapshot s) {
    if (s.totalOrders == 0) return _emptyState('No Sales Data', Icons.receipt_long_outlined);

    return ListView(padding: const EdgeInsets.all(16), children: [
      _sectionHeader('Revenue Trend'),
      const SizedBox(height: 12),
      _revenueLineChart(s),
      const SizedBox(height: 24),
      _sectionHeader('Sales by Status'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _statusPieChart(s)),
      ]),
      const SizedBox(height: 16),
      ...s.statusBreakdown.entries.map((e) => _statusRow(e.key, e.value)),
      const SizedBox(height: 24),
      _sectionHeader('Revenue Summary'),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppGradients.danger,
          borderRadius: AppRadius.xlRadius,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Total Revenue', style: AppText.body(color: AppColors.textSecondary).copyWith(fontSize: 13)),
          Text('Rs. ${_fmt(s.totalRevenue)}', style: AppText.headline().copyWith(fontSize: 32, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('${s.totalOrders} total orders · Rs. ${_fmt(s.averageOrderValue)} average',
              style: AppText.body(color: AppColors.textSecondary).copyWith(fontSize: 12)),
        ]),
      ),
    ]);
  }

  // ── TAB 3: Inventory ────────────────────────────────────────────────────
  Widget _inventoryTab(ReportSnapshot s) {
    if (s.totalProducts == 0) return _emptyState('No Products', Icons.inventory_2_outlined);

    final inStock = s.totalProducts - s.lowStockCount - s.outOfStockCount;

    return ListView(padding: const EdgeInsets.all(16), children: [
      _sectionHeader('Stock Overview'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _stockSummaryCard('In Stock', inStock, AppColors.success)),
        const SizedBox(width: 10),
        Expanded(child: _stockSummaryCard('Low Stock', s.lowStockCount, AppColors.warning)),
        const SizedBox(width: 10),
        Expanded(child: _stockSummaryCard('Out of Stock', s.outOfStockCount, AppColors.danger)),
      ]),
      const SizedBox(height: 24),
      _sectionHeader('By Category'),
      const SizedBox(height: 12),
      _categoryBarChart(s),
      const SizedBox(height: 24),
      if (s.lowStockProducts.isNotEmpty) ...[
        _sectionHeader('⚠️ Low Stock Alerts'),
        const SizedBox(height: 12),
        ...s.lowStockProducts.map((p) => _alertRow(p, false)),
      ],
    ]);
  }

  // ── TAB 4: Top Products & Monthly Performance ───────────────────────────
  Widget _topMonthlyTab(ReportSnapshot s) {
    if (s.topProducts.isEmpty && s.monthlyPerformance.every((m) => m.orderCount == 0)) {
      return _emptyState('No Sales Yet', Icons.leaderboard_rounded);
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      _sectionHeader('Top Selling Products'),
      const SizedBox(height: 12),
      if (s.topProducts.isEmpty)
        _emptyInline('No products sold yet')
      else
        _topProductsBarChart(s),
      const SizedBox(height: 16),
      ...s.topProducts.take(5).toList().asMap().entries.map((e) =>
          _topProductRow(e.key + 1, e.value)),
      const SizedBox(height: 24),
      _sectionHeader('Monthly Performance'),
      const SizedBox(height: 12),
      _monthlyBarChart(s),
      const SizedBox(height: 16),
      ...s.monthlyPerformance.reversed.map((m) => _monthlyRow(m)),
    ]);
  }

  // ── CHARTS ───────────────────────────────────────────────────────────────

  Widget _revenueLineChart(ReportSnapshot s) {
    final points = s.monthlyPerformance;
    final maxRev = points.fold<double>(1, (m, p) => p.revenue > m ? p.revenue : m);

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.xlRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: LineChart(LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false,
            horizontalInterval: maxRev / 4,
            getDrawingHorizontalLine: (v) => FlLine(color: Colors.white.withValues(alpha: .05), strokeWidth: 1)),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 28,
            getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              if (idx < 0 || idx >= points.length) return const SizedBox();
              return Padding(padding: const EdgeInsets.only(top: 6), child: Text(
                  points[idx].label.split(' ')[0],
                  style: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 10)));
            },
          )),
        ),
        borderData: FlBorderData(show: false),
        minX: 0, maxX: (points.length - 1).toDouble(),
        minY: 0, maxY: maxRev * 1.2,
        lineBarsData: [
          LineChartBarData(
            spots: points.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.revenue)).toList(),
            isCurved: true, color: AppColors.danger, barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: AppColors.danger.withValues(alpha: .12)),
          ),
        ],
      )),
    );
  }

  Widget _statusPieChart(ReportSnapshot s) {
    final colors = {
      'Pending': AppColors.primary,
      'Processing': AppColors.warning,
      'Completed': AppColors.success,
      'Cancelled': AppColors.danger,
    };
    final total = s.statusBreakdown.values.fold<int>(0, (a, b) => a + b.count);

    if (total == 0) return _emptyInline('No sales recorded yet');

    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.xlRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: Row(children: [
        Expanded(child: PieChart(PieChartData(
          sectionsSpace: 2, centerSpaceRadius: 36,
          sections: s.statusBreakdown.entries.where((e) => e.value.count > 0).map((e) {
            final pct = e.value.count / total * 100;
            return PieChartSectionData(
              value: e.value.count.toDouble(),
              color: colors[e.key] ?? Colors.grey,
              title: '${pct.toStringAsFixed(0)}%',
              radius: 48,
              titleStyle: AppText.badge().copyWith(fontSize: 11),
            );
          }).toList(),
        ))),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: colors.entries.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: c.value, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(c.key, style: AppText.body(color: AppColors.textSecondary).copyWith(fontSize: 11)),
            ]),
          )).toList(),
        ),
      ]),
    );
  }

  Widget _categoryBarChart(ReportSnapshot s) {
    if (s.categoryBreakdown.isEmpty) return _emptyInline('No category data');
    final entries = s.categoryBreakdown.entries.toList();
    final maxCount = entries.fold<int>(1, (m, e) => e.value > m ? e.value : m);

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.xlRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: BarChart(BarChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(color: Colors.white.withValues(alpha: .05), strokeWidth: 1)),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 36,
            getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              if (idx < 0 || idx >= entries.length) return const SizedBox();
              return Padding(padding: const EdgeInsets.only(top: 6), child: Text(
                  entries[idx].key.length > 6 ? '${entries[idx].key.substring(0,6)}…' : entries[idx].key,
                  style: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 9)));
            },
          )),
        ),
        borderData: FlBorderData(show: false),
        maxY: maxCount * 1.3,
        barGroups: entries.asMap().entries.map((e) => BarChartGroupData(
          x: e.key, barRods: [BarChartRodData(
            toY: e.value.value.toDouble(), color: AppColors.primary,
            width: 18, borderRadius: AppRadius.smRadius,
          )],
        )).toList(),
      )),
    );
  }

  Widget _topProductsBarChart(ReportSnapshot s) {
    final top5 = s.topProducts.take(5).toList();
    final maxUnits = top5.fold<int>(1, (m, p) => p.unitsSold > m ? p.unitsSold : m);

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.xlRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: BarChart(BarChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(color: Colors.white.withValues(alpha: .05), strokeWidth: 1)),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 36,
            getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              if (idx < 0 || idx >= top5.length) return const SizedBox();
              final name = top5[idx].name;
              return Padding(padding: const EdgeInsets.only(top: 6), child: Text(
                  name.length > 7 ? '${name.substring(0,7)}…' : name,
                  style: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 9)));
            },
          )),
        ),
        borderData: FlBorderData(show: false),
        maxY: maxUnits * 1.3,
        barGroups: top5.asMap().entries.map((e) => BarChartGroupData(
          x: e.key, barRods: [BarChartRodData(
            toY: e.value.unitsSold.toDouble(),
            gradient: AppGradients.success,
            width: 22, borderRadius: AppRadius.smRadius,
          )],
        )).toList(),
      )),
    );
  }

  Widget _monthlyBarChart(ReportSnapshot s) {
    final points  = s.monthlyPerformance;
    final maxRev  = points.fold<double>(1, (m, p) => p.revenue > m ? p.revenue : m);

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.xlRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: BarChart(BarChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(color: Colors.white.withValues(alpha: .05), strokeWidth: 1)),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(
            showTitles: true, reservedSize: 28,
            getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              if (idx < 0 || idx >= points.length) return const SizedBox();
              return Padding(padding: const EdgeInsets.only(top: 6), child: Text(
                  points[idx].label.split(' ')[0],
                  style: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 10)));
            },
          )),
        ),
        borderData: FlBorderData(show: false),
        maxY: maxRev * 1.3,
        barGroups: points.asMap().entries.map((e) => BarChartGroupData(
          x: e.key, barRods: [BarChartRodData(
            toY: e.value.revenue,
            gradient: AppGradients.reportAccent,
            width: 18, borderRadius: AppRadius.smRadius,
          )],
        )).toList(),
      )),
    );
  }

  // ── Reusable widgets ─────────────────────────────────────────────────────
  Widget _kpiCard(String title, String value, IconData icon, Color c1, Color c2, String subtitle) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.xlRadius,
            border: Border.all(color: Colors.white.withValues(alpha: .06))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(gradient: LinearGradient(colors: [c1, c2]), borderRadius: AppRadius.mdRadius),
              child: Icon(icon, color: AppColors.textPrimary, size: 18)),
          const Spacer(),
          Text(value, style: AppText.title().copyWith(fontSize: 20, fontWeight: FontWeight.w700)),
          Text(title, style: AppText.caption(color: AppColors.textTertiary).copyWith(fontSize: 11)),
          Text(subtitle, style: AppText.caption(color: c1).copyWith(fontSize: 10)),
        ]),
      );

  Widget _sectionHeader(String title) => Text(title, style: AppText.title().copyWith(fontSize: 15));

  Widget _statusRow(String status, StatusBucket bucket) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.mdRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .06))),
    child: Row(children: [
      Expanded(child: Text(status, style: AppText.body(color: AppColors.textSecondary).copyWith(fontSize: 13))),
      Text('${bucket.count} orders', style: AppText.caption(color: AppColors.textDisabled)),
      const SizedBox(width: 12),
      Text('Rs. ${_fmt(bucket.revenue)}', style: AppText.body().copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
    ]),
  );

  Widget _stockSummaryCard(String label, int count, Color color) => Container(
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
    decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: AppRadius.lgRadius,
        border: Border.all(color: color.withValues(alpha: .3))),
    child: Column(children: [
      Text('$count', style: AppText.title(color: color).copyWith(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(label, style: AppText.caption(color: color.withValues(alpha: .8)).copyWith(fontSize: 10), textAlign: TextAlign.center),
    ]),
  );

  Widget _alertRow(ProductModel p, bool isOut) {
    final color = isOut ? AppColors.danger : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: AppRadius.lgRadius,
          border: Border.all(color: color.withValues(alpha: .3))),
      child: Row(children: [
        Icon(isOut ? Icons.remove_circle_rounded : Icons.warning_amber_rounded, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text('${p.name}  ·  ${p.tagNumber}', style: AppText.body().copyWith(fontSize: 13))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: .2), borderRadius: AppRadius.smRadius),
          child: Text('${p.stock} left', style: AppText.badge(color: color).copyWith(fontSize: 11)),
        ),
      ]),
    );
  }

  Widget _topProductRow(int rank, TopProduct p) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.lgRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .06))),
    child: Row(children: [
      Container(width: 32, height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: rank == 1
                ? [AppColors.gold, AppColors.goldDeep]
                : [AppColors.success, AppColors.teal]),
            shape: BoxShape.circle),
          child: Center(child: Text('#$rank', style: AppText.badge().copyWith(fontSize: 12, fontWeight: FontWeight.w700)))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.name, style: AppText.body().copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
        Text('${p.unitsSold} units sold', style: AppText.caption(color: AppColors.textDisabled)),
      ])),
      Text('Rs. ${_fmt(p.revenue)}', style: AppText.body(color: AppColors.success).copyWith(fontWeight: FontWeight.w700, fontSize: 13)),
    ]),
  );

  Widget _monthlyRow(MonthlyPoint m) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.lgRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .06))),
    child: Row(children: [
      Expanded(child: Text(m.label, style: AppText.body().copyWith(fontSize: 13, fontWeight: FontWeight.w600))),
      Text('${m.orderCount} orders', style: AppText.caption(color: AppColors.textDisabled)),
      const SizedBox(width: 12),
      Text('Rs. ${_fmt(m.revenue)}', style: AppText.body(color: AppColors.danger).copyWith(fontWeight: FontWeight.w700, fontSize: 13)),
    ]),
  );

  Widget _emptyState(String label, IconData icon) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
          child: Icon(icon, color: AppColors.danger, size: 48)),
      const SizedBox(height: 16),
      Text(label, style: AppText.title().copyWith(fontSize: 18)),
    ],
  ));

  Widget _emptyInline(String msg) => Container(
    height: 120,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.xlRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .06))),
    child: Text(msg, style: AppText.body(color: AppColors.textDisabled).copyWith(fontSize: 13)),
  );

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}