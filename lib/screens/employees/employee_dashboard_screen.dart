// ============================================================
// lib/screens/employee_dashboard/employee_dashboard_screen.dart
//
// UI/UX REDESIGN — brought up to the same visual standard as
// DashboardScreen (Manager/Admin), while keeping the Employee role's
// actual permissions completely unchanged (view-only on Inventory &
// Sales, no Reports/Settings/Employees access).
//
// WHAT CHANGED FROM THE PREVIOUS VERSION:
//   - Header: richer multi-stop gradient (teal family, distinct from
//     Manager's navy) with two header stat chips, matching the
//     Admin dashboard's header density instead of a flat avatar row.
//   - KPI row: switched from generic 2x2 stat grid to Admin-style
//     gradient-icon-chip cards with a sub-label line for context.
//   - NEW: compact 7-day sales trend chart (fl_chart), giving the
//     Employee a glanceable read on business activity without
//     exposing manager-level analytics (matches how Square/Shopify
//     POS staff views show a small trend, not full reports).
//   - Quick Access: switched to the Admin's 3-column gradient-tile
//     grid pattern instead of two wide cards.
//   - Recent Sales: redesigned rows to match Admin's status-colored
//     icon chip + badge layout.
//   - Inventory/Sales tabs: now show SkeletonListView during the
//     initial load instead of a bare CircularProgressIndicator.
//   - Profile tab: permissions list redesigned as colored allow/deny
//     pills instead of emoji bullet text, plus a cleaner avatar ring.
//   - No business logic, no permission, and no data-source changes —
//     this is a pure visual/UX upgrade on top of the same streams.
// ============================================================
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/product_model.dart';
import '../../models/sales_model.dart';
import '../../models/customer_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/skeletons.dart';
import '../auth/login_screen.dart';

class EmployeeDashboardScreen extends StatefulWidget {
  const EmployeeDashboardScreen({super.key});

  @override
  State<EmployeeDashboardScreen> createState() =>
      _EmployeeDashboardScreenState();
}

class _EmployeeDashboardScreenState extends State<EmployeeDashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  int _currentIndex = 0;

  String get _email => _auth.currentUser?.email ?? '';

  String _formatNum(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          _buildInventoryTab(),
          _buildSalesTab(),
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ─── Bottom Nav ──────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final items = [
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.inventory_2_rounded, 'label': 'Inventory'},
      {'icon': Icons.receipt_long_rounded, 'label': 'Sales'},
      {'icon': Icons.person_rounded, 'label': 'Profile'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -5)),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final isSelected = _currentIndex == i;
              return GestureDetector(
                onTap: () => setState(() => _currentIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.teal.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: AppRadius.lgRadius,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        items[i]['icon'] as IconData,
                        color: isSelected
                            ? AppColors.tealLight
                            : AppColors.textDisabled,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items[i]['label'] as String,
                        style: AppText.caption(
                          color: isSelected
                              ? AppColors.tealLight
                              : AppColors.textDisabled,
                        ).copyWith(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ─── Home Tab ────────────────────────────────────────────────────────────
  Widget _buildHomeTab() {
    return StreamBuilder<List<ProductModel>>(
      stream: _firestoreService.getProducts(),
      builder: (context, productSnap) {
        return StreamBuilder<List<SalesModel>>(
          stream: _firestoreService.getSales(),
          builder: (context, salesSnap) {
            return StreamBuilder<List<CustomerModel>>(
              stream: _firestoreService.getCustomers(),
              builder: (context, custSnap) {
                final productsWaiting =
                    productSnap.connectionState == ConnectionState.waiting;
                final salesWaiting =
                    salesSnap.connectionState == ConnectionState.waiting;
                if (productsWaiting && salesWaiting) {
                  return const SkeletonDashboard();
                }

                final products = productSnap.data ?? [];
                final sales = salesSnap.data ?? [];
                final customers = custSnap.data ?? [];

                final lowStock =
                    products.where((p) => p.stock > 0 && p.stock < 10).length;
                final today = DateTime.now();
                final todaySales = sales.where((s) =>
                    s.date.year == today.year &&
                    s.date.month == today.month &&
                    s.date.day == today.day);
                final todayRevenue = todaySales
                    .fold<double>(0, (sum, s) => sum + s.totalAmount);

                return SingleChildScrollView(
                  child: Column(children: [
                    _header(todayRevenue, todaySales.length),
                    _kpiRow(products.length, lowStock, customers.length),
                    _trendChart(sales),
                    _quickAccess(),
                    _recentSales(sales),
                    const SizedBox(height: 24),
                  ]),
                );
              },
            );
          },
        );
      },
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────────
  Widget _header(double todayRevenue, int todayOrders) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B2B26), Color(0xFF0B4D3B), Color(0xFF11998E)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25), width: 1.5),
              ),
              child: Center(
                child: Text(
                  _email.isNotEmpty ? _email[0].toUpperCase() : 'E',
                  style: AppText.title()
                      .copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$greeting 👋',
                      style: AppText.body(color: Colors.white60)
                          .copyWith(fontSize: 13)),
                  Text(
                    _email.isNotEmpty ? _email.split('@').first : 'Employee',
                    style: AppText.title().copyWith(fontSize: 19),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: AppRadius.xlRadius,
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.badge_rounded,
                    color: AppColors.textPrimary, size: 14),
                const SizedBox(width: 4),
                Text('Employee', style: AppText.badge().copyWith(fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            _headerStat('Today\'s Revenue', 'Rs. ${_formatNum(todayRevenue)}',
                Icons.trending_up_rounded),
            const SizedBox(width: 12),
            _headerStat(
                'Today\'s Orders', '$todayOrders', Icons.shopping_bag_rounded),
          ]),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: AppRadius.lgRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppText.caption(color: Colors.white54)
                          .copyWith(fontSize: 10)),
                  Text(value,
                      style: AppText.body()
                          .copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ]),
        ),
      );

  // ─── KPI Row ─────────────────────────────────────────────────────────────
  Widget _kpiRow(int products, int lowStock, int customers) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(children: [
        _kpiCard('Products', '$products', Icons.inventory_2_rounded,
            AppGradients.primary, sub: 'in catalog'),
        const SizedBox(width: 10),
        _kpiCard(
          'Low Stock',
          '$lowStock',
          Icons.warning_amber_rounded,
          const LinearGradient(
              colors: [AppColors.warning, AppColors.danger]),
          sub: 'need restock',
        ),
        const SizedBox(width: 10),
        _kpiCard('Customers', '$customers', Icons.people_alt_rounded,
            AppGradients.success, sub: 'registered'),
      ]),
    );
  }

  Widget _kpiCard(
    String label,
    String value,
    IconData icon,
    LinearGradient gradient, {
    String sub = '',
  }) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.lgRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    gradient: gradient, borderRadius: AppRadius.mdRadius),
                child: Icon(icon, color: AppColors.textPrimary, size: 16),
              ),
              const SizedBox(height: 10),
              Text(value,
                  style: AppText.title()
                      .copyWith(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(label,
                  style: AppText.caption(color: AppColors.textTertiary)
                      .copyWith(fontSize: 10)),
              if (sub.isNotEmpty)
                Text(sub,
                    style: AppText.caption(color: AppColors.tealLight)
                        .copyWith(fontSize: 9)),
            ],
          ),
        ),
      );

  // ─── 7-Day Mini Trend Chart ──────────────────────────────────────────────
  // Glanceable context only — no tooltips, no drill-down. Mirrors how
  // staff-facing POS dashboards (Square, Shopify POS) show a small trend
  // without exposing manager-level analytics.
  Widget _trendChart(List<SalesModel> sales) {
    final now = DateTime.now();
    final days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
    final data = days.map((day) {
      return sales
          .where((s) =>
              s.date.year == day.year &&
              s.date.month == day.month &&
              s.date.day == day.day)
          .fold<double>(0, (sum, s) => sum + s.totalAmount);
    }).toList();

    final maxY = data.isEmpty || data.every((v) => v == 0)
        ? 100.0
        : (data.reduce((a, b) => a > b ? a : b) * 1.3).clamp(100.0, double.infinity);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.xlRadius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.show_chart_rounded,
                  color: AppColors.tealLight, size: 18),
              const SizedBox(width: 8),
              Text('Sales — Last 7 Days',
                  style: AppText.body()
                      .copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: LineChart(LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, _) {
                        final d = days[v.toInt()];
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('${d.day}/${d.month}',
                              style: AppText.caption(color: AppColors.textFaint)
                                  .copyWith(fontSize: 9)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: data
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.key.toDouble(), e.value))
                        .toList(),
                    isCurved: true,
                    gradient: AppGradients.success,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.tealLight.withValues(alpha: 0.25),
                          AppColors.tealLight.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              )),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Quick Access ────────────────────────────────────────────────────────
  Widget _quickAccess() {
    final items = [
      _QuickItem('Inventory', Icons.inventory_2_rounded, AppGradients.primary,
          () => setState(() => _currentIndex = 1)),
      _QuickItem('Sales', Icons.receipt_long_rounded, AppGradients.danger,
          () => setState(() => _currentIndex = 2)),
      _QuickItem('Profile', Icons.person_rounded, AppGradients.success,
          () => setState(() => _currentIndex = 3)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Access',
              style: AppText.title().copyWith(fontSize: 16)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.1,
            ),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              return GestureDetector(
                onTap: item.onTap,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadius.lgRadius,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: item.gradient,
                          borderRadius: AppRadius.mdRadius,
                        ),
                        child: Icon(item.icon,
                            color: AppColors.textPrimary, size: 22),
                      ),
                      const SizedBox(height: 8),
                      Text(item.label,
                          style: AppText.body().copyWith(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── Recent Sales ────────────────────────────────────────────────────────
  Widget _recentSales(List<SalesModel> sales) {
    final recent = [...sales]..sort((a, b) => b.date.compareTo(a.date));
    final top5 = recent.take(5).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Sales',
                  style: AppText.title().copyWith(fontSize: 16)),
              GestureDetector(
                onTap: () => setState(() => _currentIndex = 2),
                child: Text('View All',
                    style: AppText.caption(color: AppColors.tealLight)
                        .copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (top5.isEmpty)
            _emptyCard('No sales recorded yet')
          else
            ...top5.map((s) => _recentSaleRow(s)),
        ],
      ),
    );
  }

  Widget _recentSaleRow(SalesModel sale) {
    final statusColor = switch (sale.status) {
      SaleStatus.completed => AppColors.tealLight,
      SaleStatus.processing => AppColors.warning,
      SaleStatus.cancelled => AppColors.danger,
      SaleStatus.pending => AppColors.primary,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: AppRadius.mdRadius,
          ),
          child: Icon(Icons.receipt_rounded, color: statusColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sale.customerName,
                  style: AppText.body()
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('${sale.date.day}/${sale.date.month}/${sale.date.year}',
                  style: AppText.caption(color: AppColors.textDisabled)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Rs. ${_formatNum(sale.totalAmount)}',
                style: AppText.body(color: AppColors.danger)
                    .copyWith(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: AppRadius.smRadius,
              ),
              child: Text(sale.status.value,
                  style: AppText.badge(color: statusColor).copyWith(fontSize: 9)),
            ),
          ],
        ),
      ]),
    );
  }

  // ─── Inventory Tab (View Only) ───────────────────────────────────────────
  Widget _buildInventoryTab() {
    final TextEditingController searchCtrl = TextEditingController();
    String searchQuery = '';

    return StatefulBuilder(
      builder: (context, setTabState) => Column(
        children: [
          Container(
            color: AppColors.background,
            padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Inventory',
                        style: AppText.headline().copyWith(fontSize: 24)),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        borderRadius: AppRadius.smRadius,
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.visibility_outlined,
                            color: AppColors.primary, size: 14),
                        const SizedBox(width: 4),
                        Text('View Only',
                            style: AppText.badge(color: AppColors.primary)
                                .copyWith(fontSize: 11)),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadius.lgRadius,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    controller: searchCtrl,
                    style: AppText.body(),
                    onChanged: (val) => setTabState(() => searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      hintStyle: AppText.caption(color: AppColors.textDisabled)
                          .copyWith(fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.textDisabled),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ProductModel>>(
              stream: _firestoreService.getProducts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SingleChildScrollView(
                    padding: EdgeInsets.only(top: 8, bottom: 100),
                    physics: NeverScrollableScrollPhysics(),
                    child: SkeletonListView(count: 6),
                  );
                }
                final all = snapshot.data ?? [];
                final products = searchQuery.isEmpty
                    ? all
                    : all
                        .where((p) =>
                            p.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
                            p.category.toLowerCase().contains(searchQuery.toLowerCase()))
                        .toList();

                if (products.isEmpty) {
                  return Center(
                    child: Text('No products found',
                        style: AppText.body(color: AppColors.textDisabled)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: products.length,
                  itemBuilder: (ctx, i) => _viewOnlyProductCard(products[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Sales Tab (View Only) ────────────────────────────────────────────────
  Widget _buildSalesTab() {
    return Column(
      children: [
        Container(
          color: AppColors.background,
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Sales', style: AppText.headline().copyWith(fontSize: 24)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smRadius,
                  border:
                      Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.visibility_outlined,
                      color: AppColors.danger, size: 14),
                  const SizedBox(width: 4),
                  Text('View Only',
                      style: AppText.badge(color: AppColors.danger)
                          .copyWith(fontSize: 11)),
                ]),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<SalesModel>>(
            stream: _firestoreService.getSales(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SingleChildScrollView(
                  padding: EdgeInsets.only(top: 8, bottom: 100),
                  physics: NeverScrollableScrollPhysics(),
                  child: SkeletonListView(count: 6),
                );
              }
              final sales = snapshot.data ?? [];
              if (sales.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          color: AppColors.danger, size: 56),
                      const SizedBox(height: 16),
                      Text('No sales yet',
                          style: AppText.title().copyWith(fontSize: 16)),
                    ],
                  ),
                );
              }

              final sorted = [...sales]..sort((a, b) => b.date.compareTo(a.date));

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                itemCount: sorted.length,
                itemBuilder: (ctx, i) => _viewOnlySaleCard(sorted[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Profile Tab ─────────────────────────────────────────────────────────
  Widget _buildProfileTab() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 230,
          pinned: true,
          backgroundColor: AppColors.background,
          automaticallyImplyLeading: false,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B2B26), Color(0xFF0B4D3B), Color(0xFF11998E)],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3), width: 2),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppGradients.success,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.teal.withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 8)),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _email.isNotEmpty ? _email[0].toUpperCase() : 'E',
                            style: AppText.headline().copyWith(fontSize: 30),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _email.isNotEmpty ? _email.split('@').first : 'Employee',
                      style: AppText.title().copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: AppRadius.xlRadius,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.badge_rounded,
                              color: AppColors.textPrimary, size: 14),
                          const SizedBox(width: 6),
                          Text('Employee',
                              style: AppText.badge().copyWith(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _profileRow(Icons.email_outlined, 'Email', _email),
                  const SizedBox(height: 8),
                  _profileRow(Icons.badge_outlined, 'Role', 'Employee'),
                  const SizedBox(height: 24),
                  Text('Your Access',
                      style: AppText.title().copyWith(fontSize: 15)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _permissionChip('View Inventory', true),
                      _permissionChip('View Sales', true),
                      _permissionChip('View Customers', true),
                      _permissionChip('Edit Products', false),
                      _permissionChip('Create Sales', false),
                      _permissionChip('Reports & Settings', false),
                    ],
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await _auth.signOut();
                        if (mounted) {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (route) => false,
                          );
                        }
                      },
                      icon: const Icon(Icons.logout_rounded,
                          color: AppColors.textPrimary),
                      label: Text('Logout',
                          style: AppText.buttonLabel().copyWith(fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppColors.danger,
                        shape:
                            RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
                      ),
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _permissionChip(String label, bool allowed) {
    final color = allowed ? AppColors.tealLight : AppColors.textFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: allowed
            ? AppColors.teal.withValues(alpha: 0.12)
            : AppColors.surface,
        borderRadius: AppRadius.fullRadius,
        border: Border.all(
            color: allowed
                ? AppColors.teal.withValues(alpha: 0.35)
                : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            allowed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(label,
              style: AppText.caption(
                color: allowed ? AppColors.textPrimary : AppColors.textDisabled,
              ).copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ─── Reusable Widgets ────────────────────────────────────────────────────
  Widget _viewOnlyProductCard(ProductModel product) {
    final isLow = product.stock > 0 && product.stock < 10;
    final isOut = product.stock == 0;
    final stockColor = isOut
        ? AppColors.danger
        : isLow
            ? AppColors.warning
            : AppColors.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: AppRadius.mdRadius,
          ),
          child: const Icon(Icons.checkroom_rounded,
              color: AppColors.primary, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name,
                  style: AppText.body()
                      .copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(product.category,
                  style: AppText.caption(color: AppColors.textDisabled)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Rs. ${product.price.toStringAsFixed(0)}',
                style: AppText.body(color: AppColors.primary)
                    .copyWith(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: stockColor.withValues(alpha: 0.15),
                borderRadius: AppRadius.smRadius,
              ),
              child: Text(
                isOut
                    ? 'Out of Stock'
                    : isLow
                        ? 'Low: ${product.stock}'
                        : '${product.stock} in stock',
                style: AppText.badge(color: stockColor).copyWith(fontSize: 10),
              ),
            ),
          ],
        ),
      ]),
    );
  }

  Widget _viewOnlySaleCard(SalesModel sale) {
    final statusColor = switch (sale.status) {
      SaleStatus.completed => AppColors.success,
      SaleStatus.processing => AppColors.warning,
      SaleStatus.cancelled => AppColors.danger,
      SaleStatus.pending => AppColors.primary,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: AppRadius.mdRadius,
          ),
          child: Icon(Icons.receipt_rounded, color: statusColor, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sale.customerName,
                  style: AppText.body()
                      .copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                  '${sale.items.length} items • ${sale.date.day}/${sale.date.month}/${sale.date.year}',
                  style: AppText.caption(color: AppColors.textDisabled)
                      .copyWith(fontSize: 11)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Rs. ${sale.totalAmount.toStringAsFixed(0)}',
                style: AppText.body(color: AppColors.danger)
                    .copyWith(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: AppRadius.smRadius,
              ),
              child: Text(sale.status.value,
                  style: AppText.badge(color: statusColor).copyWith(fontSize: 10)),
            ),
          ],
        ),
      ]),
    );
  }

  Widget _profileRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(children: [
        Icon(icon, color: AppColors.tealLight, size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Text(label,
              style: AppText.caption(color: AppColors.textTertiary)
                  .copyWith(fontSize: 13)),
        ),
        Text(value,
            style: AppText.body().copyWith(fontSize: 12, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _emptyCard(String msg) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgRadius,
        ),
        child: Center(
          child: Text(msg,
              style: AppText.body(color: AppColors.textDisabled).copyWith(fontSize: 13)),
        ),
      );
}

class _QuickItem {
  final String label;
  final IconData icon;
  final LinearGradient gradient;
  final VoidCallback onTap;
  const _QuickItem(this.label, this.icon, this.gradient, this.onTap);
}