import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../theme/app_theme.dart';
import '../../models/sales_model.dart';
import '../../models/product_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/skeletons.dart';
import '../inventory/inventory_screen.dart';
import '../employees/employee_screen.dart';
import '../customers/customer_screen.dart';
import '../sales/sales_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../notifications/notifications_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  final _fs   = FirestoreService();
  final _ns   = NotificationService();
  final _user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _ns.checkLowStock();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _homeTab(),
            const InventoryScreen(),
            const SalesScreen(),
            const CustomerScreen(),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _bottomNav(),
    );
  }

  // ── Home Tab ─────────────────────────────────────────────────────────────
  Widget _homeTab() {
    return StreamBuilder<List<SalesModel>>(
      stream: _fs.getSales(),
      builder: (ctx, salesSnap) {
        return StreamBuilder<List<ProductModel>>(
          stream: _fs.getProducts(),
          builder: (ctx, prodSnap) {
            // Show skeleton while either stream hasn't emitted its first value.
            // Once at least one has data, show real content (avoids re-triggering
            // the skeleton on subsequent Firestore updates).
            final salesWaiting = salesSnap.connectionState == ConnectionState.waiting;
            final prodWaiting  = prodSnap.connectionState  == ConnectionState.waiting;
            if (salesWaiting && prodWaiting) return const SkeletonDashboard();

            final sales    = salesSnap.data ?? [];
            final products = prodSnap.data  ?? [];

            final totalRevenue  = sales.fold<double>(0, (s, x) => s + x.totalAmount);
            final completedSales = sales.where((s) => s.status == SaleStatus.completed).length;
            final lowStock      = products.where((p) => p.stock > 0 && p.stock < 10).length;
            final outOfStock    = products.where((p) => p.stock == 0).length;

            return SingleChildScrollView(
              child: Column(children: [
                _header(totalRevenue, sales.length),
                _kpiRow(products.length, lowStock, outOfStock, completedSales),
                _revenueChart(sales),
                _salesStatusChart(sales),
                _topProductsChart(sales, products),
                _quickAccess(),
                _recentSales(sales),
                const SizedBox(height: 24),
              ]),
            );
          },
        );
      },
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header(double totalRevenue, int totalOrders) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0D1B2A), Color(0xFF1B263B), Color(0xFF415A77)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .15)),
              child: const Icon(Icons.dry_cleaning_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Text('FabricFlow', style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          StreamBuilder<int>(
            stream: _ns.getUnreadCount(),
            builder: (ctx, snap) {
              final count = snap.data ?? 0;
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                child: Stack(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .15)),
                    child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 20),
                  ),
                  if (count > 0)
                    Positioned(right: 0, top: 0, child: Container(
                      width: 16, height: 16,
                      decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                      child: Center(child: Text('$count', style: GoogleFonts.poppins(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700))),
                    )),
                ]),
              );
            },
          ),
        ]),
        const SizedBox(height: 20),
        Text('$_greeting 👋', style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 2),
        Text(_user?.email?.split('@').first ?? 'Manager',
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Row(children: [
          _headerStat('Total Revenue', 'Rs. ${_formatNum(totalRevenue)}', Icons.trending_up_rounded),
          const SizedBox(width: 12),
          _headerStat('Total Orders', '$totalOrders', Icons.receipt_long_rounded),
        ]),
      ]),
    );
  }

  Widget _headerStat(String label, String value, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .15)),
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10)),
          Text(value, style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        ])),
      ]),
    ),
  );

  // ── KPI Row ───────────────────────────────────────────────────────────────
  Widget _kpiRow(int products, int lowStock, int outOfStock, int completed) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(children: [
        _kpiCard('Products', '$products', Icons.inventory_2_rounded, AppGradients.primary,
            sub: '$outOfStock out of stock'),
        const SizedBox(width: 10),
        _kpiCard('Low Stock', '$lowStock', Icons.warning_amber_rounded,
            const LinearGradient(colors: [Color(0xFFFFB347), Color(0xFFFF6B6B)]),
            sub: 'items need restock'),
        const SizedBox(width: 10),
        _kpiCard('Completed', '$completed', Icons.check_circle_rounded, AppGradients.success,
            sub: 'sales this month'),
      ]),
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, LinearGradient gradient, {String sub = ''}) =>
      Expanded(child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .06)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(height: 10),
          Text(value, style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
          Text(label, style: GoogleFonts.poppins(color: AppColors.textTertiary, fontSize: 10)),
          if (sub.isNotEmpty)
            Text(sub, style: GoogleFonts.poppins(color: AppColors.primary, fontSize: 9)),
        ]),
      ));

  // ── Revenue Trend Chart ───────────────────────────────────────────────────
  Widget _revenueChart(List<SalesModel> sales) {
    // Group sales by day (last 7 days)
    final now = DateTime.now();
    final days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
    final data = days.map((day) {
      final total = sales
          .where((s) => s.date.year == day.year && s.date.month == day.month && s.date.day == day.day)
          .fold<double>(0, (sum, s) => sum + s.totalAmount);
      return total;
    }).toList();

    final maxY = data.isEmpty ? 1000.0 : (data.reduce((a, b) => a > b ? a : b) * 1.3).clamp(100.0, double.infinity);

    return _chartCard(
      title: 'Revenue — Last 7 Days',
      icon: Icons.trending_up_rounded,
      child: SizedBox(
        height: 180,
        child: LineChart(LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withValues(alpha: .05), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 44,
              getTitlesWidget: (v, _) => Text(_formatNum(v), style: GoogleFonts.poppins(color: AppColors.textDisabled, fontSize: 9)),
            )),
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 22,
              getTitlesWidget: (v, _) {
                final d = days[v.toInt()];
                return Text('${d.day}/${d.month}', style: GoogleFonts.poppins(color: AppColors.textDisabled, fontSize: 9));
              },
            )),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0, maxX: 6, minY: 0, maxY: maxY,
          lineBarsData: [LineChartBarData(
            spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
            isCurved: true,
            gradient: AppGradients.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 4, color: AppColors.primary, strokeWidth: 2, strokeColor: AppColors.surface),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [AppColors.primary.withValues(alpha: .3), AppColors.primary.withValues(alpha: .0)],
              ),
            ),
          )],
        )),
      ),
    );
  }

  // ── Sales Status Pie Chart ────────────────────────────────────────────────
  Widget _salesStatusChart(List<SalesModel> sales) {
    final pending    = sales.where((s) => s.status == SaleStatus.pending).length;
    final processing = sales.where((s) => s.status == SaleStatus.processing).length;
    final completed  = sales.where((s) => s.status == SaleStatus.completed).length;
    final cancelled  = sales.where((s) => s.status == SaleStatus.cancelled).length;
    final total = sales.length;

    if (total == 0) return const SizedBox.shrink();

    return _chartCard(
      title: 'Sales by Status',
      icon: Icons.donut_large_rounded,
      child: Row(children: [
        SizedBox(
          height: 160, width: 160,
          child: PieChart(PieChartData(
            sectionsSpace: 3,
            centerSpaceRadius: 40,
            sections: [
              if (pending > 0)    _pieSection(pending,    total, AppColors.primary,   'Pending'),
              if (processing > 0) _pieSection(processing, total, AppColors.warning,   'Processing'),
              if (completed > 0)  _pieSection(completed,  total, AppColors.tealLight, 'Completed'),
              if (cancelled > 0)  _pieSection(cancelled,  total, AppColors.danger,    'Cancelled'),
            ],
          )),
        ),
        const SizedBox(width: 20),
        Expanded(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pending > 0)    _legend('Pending',    AppColors.primary,   pending),
            if (processing > 0) _legend('Processing', AppColors.warning,   processing),
            if (completed > 0)  _legend('Completed',  AppColors.tealLight, completed),
            if (cancelled > 0)  _legend('Cancelled',  AppColors.danger,    cancelled),
          ],
        )),
      ]),
    );
  }

  PieChartSectionData _pieSection(int count, int total, Color color, String title) =>
      PieChartSectionData(
        value: count.toDouble(),
        color: color,
        radius: 40,
        showTitle: false,
      );

  Widget _legend(String label, Color color, int count) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 12))),
      Text('$count', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );

  // ── Top Products Bar Chart ────────────────────────────────────────────────
  Widget _topProductsChart(List<SalesModel> sales, List<ProductModel> products) {
    if (sales.isEmpty) return const SizedBox.shrink();

    // Count quantity sold per product
    final Map<String, double> sold = {};
    for (final sale in sales) {
      for (final item in sale.items) {
        final name = item['productName'] as String? ?? 'Unknown';
        sold[name] = (sold[name] ?? 0) + ((item['quantity'] as num?)?.toDouble() ?? 0);
      }
    }

    final sorted = sold.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top5   = sorted.take(5).toList();
    if (top5.isEmpty) return const SizedBox.shrink();

    final maxY = top5.first.value * 1.3;

    return _chartCard(
      title: 'Top Products by Units Sold',
      icon: Icons.bar_chart_rounded,
      child: SizedBox(
        height: 200,
        child: BarChart(BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                '${top5[group.x].key}\n${rod.toY.toInt()} units',
                GoogleFonts.poppins(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 30,
              getTitlesWidget: (v, _) {
                final name = top5[v.toInt()].key;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(name.length > 7 ? '${name.substring(0,7)}..' : name,
                      style: GoogleFonts.poppins(color: AppColors.textDisabled, fontSize: 9)),
                );
              },
            )),
            leftTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 30,
              getTitlesWidget: (v, _) => Text('${v.toInt()}', style: GoogleFonts.poppins(color: AppColors.textDisabled, fontSize: 9)),
            )),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withValues(alpha: .05), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: top5.asMap().entries.map((e) => BarChartGroupData(
            x: e.key,
            barRods: [BarChartRodData(
              toY: e.value.value,
              width: 20,
              borderRadius: BorderRadius.circular(6),
              gradient: AppGradients.primary,
            )],
          )).toList(),
        )),
      ),
    );
  }

  // ── Quick Access ──────────────────────────────────────────────────────────
  Widget _quickAccess() {
    final items = [
      _QuickItem('Inventory', Icons.inventory_2_rounded,  AppGradients.primary,  const InventoryScreen()),
      _QuickItem('Employees', Icons.badge_rounded,        AppGradients.success,  const EmployeeScreen()),
      _QuickItem('Customers', Icons.people_alt_rounded,   AppGradients.customer, const CustomerScreen()),
      _QuickItem('Sales',     Icons.receipt_long_rounded, AppGradients.danger,   const SalesScreen()),
      _QuickItem('Reports',   Icons.bar_chart_rounded,    AppGradients.reportAccent, const ReportsScreen()),
      _QuickItem('Settings',  Icons.settings_rounded,     AppGradients.manager,  const SettingsScreen()),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Quick Access', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.1,
          ),
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final item = items[i];
            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => item.screen)),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: .06)),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(gradient: item.gradient, borderRadius: BorderRadius.circular(14)),
                    child: Icon(item.icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(height: 8),
                  Text(item.label, style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            );
          },
        ),
      ]),
    );
  }

  // ── Recent Sales ──────────────────────────────────────────────────────────
  Widget _recentSales(List<SalesModel> sales) {
    final recent = [...sales]..sort((a, b) => b.date.compareTo(a.date));
    final top5   = recent.take(5).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Recent Sales', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          GestureDetector(
            onTap: () => setState(() => _selectedIndex = 2),
            child: Text('View All', style: GoogleFonts.poppins(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 12),
        if (top5.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text('No sales yet', style: GoogleFonts.poppins(color: AppColors.textDisabled))),
          )
        else
          ...top5.map((s) {
            final statusColor = switch (s.status) {
              SaleStatus.completed  => AppColors.tealLight,
              SaleStatus.processing => AppColors.warning,
              SaleStatus.cancelled  => AppColors.danger,
              SaleStatus.pending    => AppColors.primary,
            };
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: .06)),
              ),
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.receipt_rounded, color: statusColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.customerName, style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('${s.date.day}/${s.date.month}/${s.date.year}', style: GoogleFonts.poppins(color: AppColors.textDisabled, fontSize: 11)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Rs. ${_formatNum(s.totalAmount)}', style: GoogleFonts.poppins(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: .15), borderRadius: BorderRadius.circular(6)),
                    child: Text(s.status.value, style: GoogleFonts.poppins(color: statusColor, fontSize: 9, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ]),
            );
          }),
      ]),
    );
  }

  // ── Chart Card Wrapper ────────────────────────────────────────────────────
  Widget _chartCard({required String title, required IconData icon, required Widget child}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: .06)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(title, style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 16),
            child,
          ]),
        ),
      );

  // ── Bottom Nav ────────────────────────────────────────────────────────────
  Widget _bottomNav() {
    final items = [
      [Icons.home_rounded,          'Home'],
      [Icons.inventory_2_rounded,   'Inventory'],
      [Icons.shopping_cart_rounded, 'Sales'],
      [Icons.people_rounded,        'Customers'],
      [Icons.settings_rounded,      'Settings'],
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: .08))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final sel = _selectedIndex == i;
              return GestureDetector(
                onTap: () => setState(() => _selectedIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primary.withValues(alpha: .15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(items[i][0] as IconData, color: sel ? AppColors.primary : AppColors.textDisabled, size: 24),
                    const SizedBox(height: 4),
                    Text(items[i][1] as String, style: GoogleFonts.poppins(
                      fontSize: 10, color: sel ? AppColors.primary : AppColors.textDisabled,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    )),
                  ]),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _formatNum(double v) {
    if (v >= 1000000) return '${(v/1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v/1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _QuickItem {
  final String label;
  final IconData icon;
  final LinearGradient gradient;
  final Widget screen;
  const _QuickItem(this.label, this.icon, this.gradient, this.screen);
}