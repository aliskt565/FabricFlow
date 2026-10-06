// ignore_for_file: prefer_const_constructors
//
// UPDATE — Discounted Pricing display in _productCard:
//   - Discount badge ("X% OFF") added top-left on the product image,
//     next to the existing category pill (top-right) — only rendered
//     when p.hasDiscount is true.
//   - Price row now shows the discounted price + a struck-through
//     original price when a discount is active; falls back to the
//     plain price exactly as before when there's no discount.
//   Everything else in this file is unchanged from the previous step
//   (Product Detail Page navigation + Shop tab Sort).
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/product_model.dart';
import '../../models/sales_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import 'product_detail_screen.dart';

enum _SortOption { none, priceLowHigh, priceHighLow, newest }

extension on _SortOption {
  String get label => switch (this) {
    _SortOption.none         => 'Default',
    _SortOption.priceLowHigh => 'Price: Low to High',
    _SortOption.priceHighLow => 'Price: High to Low',
    _SortOption.newest       => 'Newest First',
  };

  IconData get icon => switch (this) {
    _SortOption.none         => Icons.sort_rounded,
    _SortOption.priceLowHigh => Icons.arrow_upward_rounded,
    _SortOption.priceHighLow => Icons.arrow_downward_rounded,
    _SortOption.newest       => Icons.fiber_new_rounded,
  };
}

class CustomerDashboardScreen extends StatefulWidget {
  const CustomerDashboardScreen({super.key});
  @override
  State<CustomerDashboardScreen> createState() =>
      _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen> {
  final _fs         = FirestoreService();
  final _auth       = FirebaseAuth.instance;
  final _searchCtrl = TextEditingController();

  int          _tabIndex    = 0;
  String       _searchQuery = '';
  String       _selectedCat = 'All';
  _SortOption  _sortOption  = _SortOption.none;

  static const _cats = [
    'All','Shirts','Pants','Dresses','Jackets','Accessories','Shoes','Other'
  ];

  String get _uid   => _auth.currentUser?.uid   ?? '';
  String get _email => _auth.currentUser?.email ?? '';
  String get _name  => _email.split('@').first;

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  // ── Navigate to full product detail page ───────────────────────────────
  void _openProduct(ProductModel p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)),
    ).then((orderPlaced) {
      if (orderPlaced == true && mounted) {
        setState(() => _tabIndex = 2);
      }
    });
  }

  List<ProductModel> _applySort(List<ProductModel> products) {
    final sorted = [...products];
    switch (_sortOption) {
      case _SortOption.priceLowHigh:
        sorted.sort((a, b) => a.price.compareTo(b.price));
        break;
      case _SortOption.priceHighLow:
        sorted.sort((a, b) => b.price.compareTo(a.price));
        break;
      case _SortOption.newest:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _SortOption.none:
        break;
    }
    return sorted;
  }

  void _openSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.textFaint, borderRadius: AppRadius.handleRadius),
            )),
            Text('Sort By', style: AppText.title().copyWith(fontSize: 17)),
            const SizedBox(height: 12),
            ..._SortOption.values.map((opt) {
              final selected = _sortOption == opt;
              return ListTile(
                onTap: () { setState(() => _sortOption = opt); Navigator.pop(ctx); },
                contentPadding: EdgeInsets.zero,
                leading: Icon(opt.icon, color: selected ? AppColors.magentaPale : AppColors.textDisabled, size: 20),
                title: Text(opt.label,
                    style: AppText.body(color: selected ? AppColors.textPrimary : AppColors.textSecondary)
                        .copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                trailing: selected ? const Icon(Icons.check_rounded, color: AppColors.magentaPale, size: 20) : null,
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Scaffold ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: IndexedStack(index: _tabIndex, children: [
      _homeTab(),
      _shopTab(),
      _ordersTab(),
      _profileTab(),
    ]),
    bottomNavigationBar: _bottomNav(),
  );

  // ── Bottom Nav ────────────────────────────────────────────────────────────
  Widget _bottomNav() {
    final items = [
      [Icons.home_rounded,         'Home'],
      [Icons.store_rounded,        'Shop'],
      [Icons.shopping_bag_rounded, 'Orders'],
      [Icons.person_rounded,       'Profile'],
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: .08))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3),
            blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (i) {
            final sel = _tabIndex == i;
            return GestureDetector(
              onTap: () => setState(() => _tabIndex = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: sel
                      ? AppColors.magenta.withValues(alpha: .15)
                      : Colors.transparent,
                  borderRadius: AppRadius.lgRadius,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(items[i][0] as IconData,
                      color: sel ? AppColors.magentaPale : AppColors.textDisabled,
                      size: 24),
                  const SizedBox(height: 4),
                  Text(items[i][1] as String,
                      style: AppText.caption(
                          color: sel
                              ? AppColors.magentaPale
                              : AppColors.textDisabled)
                          .copyWith(
                              fontSize: 11,
                              fontWeight: sel
                                  ? FontWeight.w600
                                  : FontWeight.w400)),
                ]),
              ),
            );
          }),
        ),
      )),
    );
  }

  // ── Home Tab ──────────────────────────────────────────────────────────────
  Widget _homeTab() => StreamBuilder<List<SalesModel>>(
    stream: _fs.getSales(),
    builder: (ctx, salesSnap) {
      final myOrders = (salesSnap.data ?? [])
          .where((s) => s.customerId == _uid).toList();
      final totalSpent = myOrders.fold<double>(0, (s, o) => s + o.totalAmount);
      final completed  = myOrders.where((o) => o.status == SaleStatus.completed).length;
      final pending    = myOrders.where((o) => o.status == SaleStatus.pending).length;

      return CustomScrollView(slivers: [
        // ── Header ──────────────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 240,
          pinned: true,
          backgroundColor: AppColors.background,
          automaticallyImplyLeading: false,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF4A148C), Color(0xFF880E4F)],
                ),
              ),
              child: SafeArea(child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row
                    Row(children: [
                      _avatar(_email, 46,
                          [AppColors.magenta, AppColors.magentaLight]),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_greeting,
                              style: AppText.caption(color: Colors.white60)
                                  .copyWith(fontSize: 12)),
                          Text(_name,
                              style: AppText.title().copyWith(fontSize: 17),
                              overflow: TextOverflow.ellipsis),
                        ],
                      )),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .15),
                          borderRadius: AppRadius.mdRadius),
                        child: Text('🛍️ Customer',
                            style: AppText.badge().copyWith(fontSize: 11)),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    // Stats row
                    Row(children: [
                      _headerStat('${myOrders.length}', 'Total Orders',
                          Icons.receipt_long_rounded),
                      const SizedBox(width: 10),
                      _headerStat(
                        totalSpent >= 1000
                            ? 'Rs.${(totalSpent / 1000).toStringAsFixed(1)}K'
                            : 'Rs.${totalSpent.toStringAsFixed(0)}',
                        'Total Spent', Icons.payments_rounded),
                    ]),
                  ],
                ),
              )),
            ),
          ),
        ),

        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Quick KPI row ──────────────────────────────────────────
              Row(children: [
                _kpiCard('Completed', '$completed',
                    Icons.check_circle_rounded, AppGradients.success),
                const SizedBox(width: 10),
                _kpiCard('Pending', '$pending',
                    Icons.schedule_rounded, AppGradients.primary),
                const SizedBox(width: 10),
                _kpiCard('Cancelled',
                    '${myOrders.where((o) => o.status == SaleStatus.cancelled).length}',
                    Icons.cancel_rounded, AppGradients.danger),
              ]),
              const SizedBox(height: 24),

              // ── Featured Products ──────────────────────────────────────
              _sectionRow('Featured Products',
                  () => setState(() => _tabIndex = 1)),
              const SizedBox(height: 14),
              StreamBuilder<List<ProductModel>>(
                stream: _fs.getProducts(),
                builder: (ctx, snap) {
                  final featured = (snap.data ?? [])
                      .where((p) => p.stock > 0).take(4).toList();
                  if (featured.isEmpty) return _emptyShop();
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, crossAxisSpacing: 12,
                      mainAxisSpacing: 12, childAspectRatio: .78),
                    itemCount: featured.length,
                    itemBuilder: (ctx, i) => _productCard(featured[i]),
                  );
                },
              ),
              const SizedBox(height: 24),

              // ── Recent Orders ──────────────────────────────────────────
              _sectionRow('Recent Orders',
                  () => setState(() => _tabIndex = 2)),
              const SizedBox(height: 14),
              if (myOrders.isEmpty)
                _emptyOrders(mini: true)
              else
                ...myOrders.take(3).map(_orderRow),
              const SizedBox(height: 80),
            ],
          ),
        )),
      ]);
    },
  );

  // ── Shop Tab ──────────────────────────────────────────────────────────────
  Widget _shopTab() => Column(children: [
    Container(
      color: AppColors.background,
      child: SafeArea(bottom: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Shop',
                style: AppText.headline().copyWith(fontSize: 24))),
            StreamBuilder<List<ProductModel>>(
              stream: _fs.getProducts(),
              builder: (ctx, snap) {
                final n = (snap.data ?? []).where((p) => p.stock > 0).length;
                return _pill('$n items', AppColors.magenta);
              },
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.mdRadius,
                border: Border.all(color: AppColors.border)),
              child: TextField(
                controller: _searchCtrl,
                style: AppText.body(),
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  hintStyle: AppText.caption(color: AppColors.textDisabled)
                      .copyWith(fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.textDisabled),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              color: AppColors.textDisabled, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          })
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            )),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _openSortSheet,
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _sortOption != _SortOption.none
                      ? AppColors.magenta.withValues(alpha: .2)
                      : AppColors.surface,
                  borderRadius: AppRadius.mdRadius,
                  border: Border.all(
                      color: _sortOption != _SortOption.none ? AppColors.magenta : AppColors.border),
                ),
                child: Icon(
                  _sortOption.icon,
                  color: _sortOption != _SortOption.none ? AppColors.magentaPale : AppColors.textTertiary,
                  size: 20,
                ),
              ),
            ),
          ]),
          if (_sortOption != _SortOption.none) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => setState(() => _sortOption = _SortOption.none),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.magenta.withValues(alpha: .15),
                    borderRadius: AppRadius.fullRadius,
                    border: Border.all(color: AppColors.magenta.withValues(alpha: .5)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_sortOption.label,
                        style: AppText.caption(color: AppColors.magentaPale).copyWith(fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    const Icon(Icons.close_rounded, color: AppColors.magentaPale, size: 12),
                  ]),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(height: 34, child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final cat = _cats[i];
              final sel = _selectedCat == cat;
              return GestureDetector(
                onTap: () => setState(() => _selectedCat = cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: sel ? AppGradients.customer : null,
                    color: sel ? null : AppColors.surface,
                    borderRadius: AppRadius.xlRadius,
                    border: Border.all(
                        color: sel ? Colors.transparent : AppColors.border)),
                  child: Text(cat, style: AppText.caption(
                      color: sel
                          ? AppColors.textPrimary
                          : AppColors.textTertiary)
                      .copyWith(
                          fontWeight: sel
                              ? FontWeight.w600
                              : FontWeight.w400)),
                ),
              );
            },
          )),
          const SizedBox(height: 12),
        ]),
      )),
    ),
    Expanded(child: StreamBuilder<List<ProductModel>>(
      stream: _fs.getProducts(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(
              color: AppColors.magenta));
        }
        var products =
            (snap.data ?? []).where((p) => p.stock > 0).toList();
        if (_selectedCat != 'All') {
          products = products
              .where((p) => p.category == _selectedCat)
              .toList();
        }
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          products = products
              .where((p) =>
                  p.name.toLowerCase().contains(q) ||
                  p.category.toLowerCase().contains(q))
              .toList();
        }
        products = _applySort(products);
        if (products.isEmpty) return _emptyShop();
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, crossAxisSpacing: 12,
            mainAxisSpacing: 12, childAspectRatio: .78),
          itemCount: products.length,
          itemBuilder: (ctx, i) => _productCard(products[i]),
        );
      },
    )),
  ]);

  // ── Orders Tab ────────────────────────────────────────────────────────────
  Widget _ordersTab() => StreamBuilder<List<SalesModel>>(
    stream: _fs.getSales(),
    builder: (ctx, snap) {
      final orders = (snap.data ?? [])
          .where((s) => s.customerId == _uid).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      final totalSpent =
          orders.fold<double>(0, (s, o) => s + o.totalAmount);

      return CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: AppColors.background,
          automaticallyImplyLeading: false,
          expandedHeight: 110,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF4A148C), Color(0xFF1A1F36)],
                ),
              ),
              child: SafeArea(child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('My Orders',
                            style: AppText.headline().copyWith(fontSize: 22)),
                        Text('${orders.length} total orders',
                            style: AppText.caption(
                                color: AppColors.textTertiary)),
                      ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('Total Spent',
                            style: AppText.caption(
                                color: Colors.white54).copyWith(fontSize: 11)),
                        Text(
                          totalSpent >= 1000
                              ? 'Rs. ${(totalSpent / 1000).toStringAsFixed(1)}K'
                              : 'Rs. ${totalSpent.toStringAsFixed(0)}',
                          style: AppText.title(color: AppColors.magentaPale)
                              .copyWith(fontSize: 18)),
                      ]),
                  ],
                ),
              )),
            ),
          ),
        ),
        orders.isEmpty
            ? SliverFillRemaining(child: _emptyOrders())
            : SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _orderDetailCard(orders[i]),
                    childCount: orders.length,
                  ),
                ),
              ),
      ]);
    },
  );

  // ── Profile Tab ───────────────────────────────────────────────────────────
  Widget _profileTab() => StreamBuilder<List<SalesModel>>(
    stream: _fs.getSales(),
    builder: (ctx, salesSnap) {
      final my = (salesSnap.data ?? [])
          .where((s) => s.customerId == _uid).toList();
      final spent = my.fold<double>(0, (s, o) => s + o.totalAmount);

      return CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 250,
          pinned: true,
          backgroundColor: AppColors.background,
          automaticallyImplyLeading: false,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF4A148C), Color(0xFF1A1F36)],
                ),
              ),
              child: SafeArea(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _avatar(_email, 84,
                      [AppColors.magenta, AppColors.magentaLight],
                      fontSize: 34),
                  const SizedBox(height: 14),
                  Text(_name,
                      style: AppText.headline().copyWith(fontSize: 22)),
                  const SizedBox(height: 4),
                  Text(_email,
                      style: AppText.caption(color: Colors.white54)
                          .copyWith(fontSize: 12)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.magenta.withValues(alpha: .25),
                      borderRadius: AppRadius.mdRadius),
                    child: Text('🛍️ Customer',
                        style: AppText.badge().copyWith(fontSize: 12)),
                  ),
                ],
              )),
            ),
          ),
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            // ── KPI cards ──────────────────────────────────────────────
            Row(children: [
              _profileKpi('${my.length}', 'Total Orders',
                  Icons.receipt_long_rounded, AppGradients.customer),
              const SizedBox(width: 10),
              _profileKpi(
                spent >= 1000
                    ? 'Rs.${(spent / 1000).toStringAsFixed(1)}K'
                    : 'Rs.${spent.toStringAsFixed(0)}',
                'Total Spent', Icons.payments_rounded, AppGradients.primary),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _profileKpi(
                '${my.where((o) => o.status == SaleStatus.completed).length}',
                'Completed', Icons.check_circle_rounded, AppGradients.success),
              const SizedBox(width: 10),
              _profileKpi(
                '${my.where((o) => o.status == SaleStatus.pending).length}',
                'Pending', Icons.schedule_rounded, AppGradients.danger),
            ]),
            const SizedBox(height: 24),

            // ── Info rows ──────────────────────────────────────────────
            Text('Account Details',
                style: AppText.title().copyWith(fontSize: 15),
                textAlign: TextAlign.left),
            const SizedBox(height: 12),
            _profileRow(Icons.email_outlined,    'Email',        _email),
            const SizedBox(height: 8),
            _profileRow(Icons.badge_outlined,    'Account Type', 'Customer'),
            const SizedBox(height: 8),
            _profileRow(Icons.store_rounded,     'Member Since', 'FabricFlow'),
            const SizedBox(height: 28),

            // ── Logout ─────────────────────────────────────────────────
            SizedBox(width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await _auth.signOut();
                  if (mounted) {
                    Navigator.pushAndRemoveUntil(context,
                        MaterialPageRoute(
                            builder: (_) => const LoginScreen()),
                        (r) => false);
                  }
                },
                icon: const Icon(Icons.logout_rounded,
                    color: AppColors.textPrimary),
                label: Text('Logout',
                    style: AppText.buttonLabel().copyWith(fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppColors.danger,
                  shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.lgRadius)),
              )),
            const SizedBox(height: 80),
          ]),
        )),
      ]);
    },
  );

  // ── Reusable Widgets ──────────────────────────────────────────────────────

  Widget _headerStat(String value, String label, IconData icon) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .1),
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .15)),
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppText.caption(color: Colors.white54)
                    .copyWith(fontSize: 10)),
            Text(value,
                style: AppText.body().copyWith(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ])),
      ]),
    ),
  );

  Widget _kpiCard(String label, String value, IconData icon,
      LinearGradient gradient) =>
      Expanded(child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .06)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: AppRadius.smRadius),
            child: Icon(icon, color: Colors.white, size: 14),
          ),
          const SizedBox(height: 8),
          Text(value, style: AppText.title().copyWith(
              fontSize: 18, fontWeight: FontWeight.w700)),
          Text(label,
              style: AppText.caption(color: AppColors.textDisabled)
                  .copyWith(fontSize: 9)),
        ]),
      ));

  Widget _profileKpi(String value, String label, IconData icon,
      LinearGradient gradient) =>
      Expanded(child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .06)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: AppRadius.smRadius),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(height: 10),
          Text(value, style: AppText.title().copyWith(
              fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label,
              style: AppText.caption(color: AppColors.textDisabled)
                  .copyWith(fontSize: 11)),
        ]),
      ));

  // ── UPDATED: discount badge + strikethrough price ──────────────────────
  Widget _productCard(ProductModel p) => GestureDetector(
    onTap: () => _openProduct(p),
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.xlRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: .2),
            blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: Container(
            width: double.infinity,
            decoration: p.imageUrl.isEmpty
                ? BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppColors.magenta.withValues(alpha: .25),
                      AppColors.purpleDeep.withValues(alpha: .15)]),
                  )
                : null,
            child: Stack(fit: StackFit.expand, children: [
              if (p.imageUrl.isNotEmpty)
                Image.network(
                  p.imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) => progress == null
                      ? child
                      : Container(
                          color: AppColors.surfaceRaised,
                          child: const Center(
                            child: SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(color: AppColors.magenta, strokeWidth: 2)),
                          ),
                        ),
                  errorBuilder: (ctx, err, st) => Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        AppColors.magenta.withValues(alpha: .25),
                        AppColors.purpleDeep.withValues(alpha: .15)]),
                    ),
                    child: Center(child: Icon(_catIcon(p.category), color: AppColors.magentaPale, size: 48)),
                  ),
                )
              else
                Center(child: Icon(_catIcon(p.category), color: AppColors.magentaPale, size: 48)),
              if (p.hasDiscount)
                Positioned(top: 8, left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: AppRadius.smRadius),
                    child: Text('${p.discountPercent.toStringAsFixed(0)}% OFF',
                        style: AppText.badge(color: AppColors.textPrimary)
                            .copyWith(fontSize: 9, fontWeight: FontWeight.w700)),
                  )),
              Positioned(top: 8, right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: AppRadius.smRadius),
                  child: Text(p.category,
                      style: AppText.caption(color: AppColors.textSecondary)
                          .copyWith(fontSize: 9)),
                )),
            ]),
          ),
        )),
        Expanded(flex: 2, child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name,
                style: AppText.body()
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('${p.stock} left',
                style: AppText.caption(color: AppColors.textDisabled)
                    .copyWith(fontSize: 10)),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: p.hasDiscount
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Rs. ${p.price.toStringAsFixed(0)}',
                            style: AppText.body(color: AppColors.magentaPale)
                                .copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
                        Text('Rs. ${p.originalPrice.toStringAsFixed(0)}',
                            style: AppText.caption(color: AppColors.textDisabled)
                                .copyWith(fontSize: 10, decoration: TextDecoration.lineThrough)),
                      ])
                    : Text('Rs. ${p.price.toStringAsFixed(0)}',
                        style: AppText.body(color: AppColors.magentaPale)
                            .copyWith(fontSize: 14, fontWeight: FontWeight.w700))),
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                      gradient: AppGradients.customer,
                      borderRadius: AppRadius.smRadius),
                  child: const Icon(Icons.add_rounded,
                      color: AppColors.textPrimary, size: 18),
                ),
              ]),
          ]),
        )),
      ]),
    ),
  );

  Widget _orderRow(SalesModel o) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.lgRadius,
      border: Border.all(color: Colors.white.withValues(alpha: .06))),
    child: Row(children: [
      Container(width: 42, height: 42,
        decoration: BoxDecoration(
          color: AppColors.magenta.withValues(alpha: .15),
          borderRadius: AppRadius.mdRadius),
        child: const Icon(Icons.shopping_bag_rounded,
            color: AppColors.magentaPale, size: 18)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${o.items.length} item(s)',
              style: AppText.body()
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
          Text('${o.date.day}/${o.date.month}/${o.date.year}',
              style: AppText.caption(color: AppColors.textDisabled)),
        ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('Rs. ${o.totalAmount.toStringAsFixed(0)}',
            style: AppText.body(color: AppColors.magentaPale)
                .copyWith(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: _statusColor(o.status).withValues(alpha: .15),
            borderRadius: AppRadius.smRadius),
          child: Text(o.status.value,
              style: AppText.badge(color: _statusColor(o.status))
                  .copyWith(fontSize: 9)),
        ),
      ]),
    ]),
  );

  Widget _orderDetailCard(SalesModel o) {
    final sc = _statusColor(o.status);
    final id = o.id.length > 6
        ? o.id.substring(0, 6).toUpperCase()
        : o.id.toUpperCase();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.xlRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.magenta.withValues(alpha: .2),
              borderRadius: AppRadius.mdRadius),
            child: const Icon(Icons.shopping_bag_rounded,
                color: AppColors.magentaPale, size: 20)),
          title: Text('Order #$id',
              style: AppText.body()
                  .copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${o.date.day}/${o.date.month}/${o.date.year}  '
            '${o.date.hour.toString().padLeft(2, '0')}:'
            '${o.date.minute.toString().padLeft(2, '0')}',
            style: AppText.caption(color: AppColors.textDisabled)),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Rs. ${o.totalAmount.toStringAsFixed(0)}',
                  style: AppText.body(color: AppColors.magentaPale)
                      .copyWith(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: sc.withValues(alpha: .15),
                  borderRadius: AppRadius.smRadius),
                child: Text(o.status.value,
                    style: AppText.badge(color: sc).copyWith(fontSize: 10)),
              ),
            ]),
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            ...o.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.magenta.withValues(alpha: .15),
                    borderRadius: AppRadius.smRadius),
                  child: const Icon(Icons.checkroom_rounded,
                      color: AppColors.magentaPale, size: 18)),
                const SizedBox(width: 10),
                Expanded(child: Text(
                    item['productName'] ?? 'Product',
                    style: AppText.body(color: AppColors.textSecondary)
                        .copyWith(fontSize: 13))),
                Text('x${item['quantity']}',
                    style: AppText.caption(
                        color: AppColors.textTertiary)),
                const SizedBox(width: 10),
                Text(
                  'Rs. ${((item['price'] as num) * (item['quantity'] as num)).toStringAsFixed(0)}',
                  style: AppText.body()
                      .copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            )),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String email, double size, List<Color> colors,
      {double fontSize = 22}) =>
      Container(
        width: size, height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(
              color: colors.first.withValues(alpha: .4),
              blurRadius: 16)]),
        child: Center(child: Text(
          email.isNotEmpty ? email[0].toUpperCase() : 'C',
          style: AppText.title().copyWith(
              fontSize: fontSize, fontWeight: FontWeight.w700))),
      );

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .2),
      borderRadius: AppRadius.mdRadius),
    child: Text(text,
        style: AppText.badge(color: color.withValues(alpha: .9))
            .copyWith(fontSize: 12)),
  );

  Widget _sectionRow(String title, VoidCallback onSeeAll) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: AppText.title()
            .copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
        GestureDetector(
          onTap: onSeeAll,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.magenta.withValues(alpha: .15),
              borderRadius: AppRadius.mdRadius),
            child: Text('View All',
                style: AppText.badge(color: AppColors.magentaPale)
                    .copyWith(fontSize: 12)),
          )),
      ]);

  Widget _profileRow(IconData icon, String label, String value) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .06))),
        child: Row(children: [
          Icon(icon, color: AppColors.magenta, size: 20),
          const SizedBox(width: 14),
          Expanded(child: Text(label,
              style: AppText.caption(color: AppColors.textTertiary))),
          Flexible(child: Text(value,
              style: AppText.body()
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis)),
        ]),
      );

  Widget _emptyShop() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
            color: AppColors.surface, shape: BoxShape.circle),
        child: const Icon(Icons.storefront_outlined,
            color: AppColors.magenta, size: 48)),
      const SizedBox(height: 12),
      Text('No products available',
          style: AppText.body()
              .copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
    ],
  ));

  Widget _emptyOrders({bool mini = false}) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(padding: EdgeInsets.all(mini ? 16 : 24),
        decoration: const BoxDecoration(
            color: AppColors.surface, shape: BoxShape.circle),
        child: Icon(Icons.shopping_bag_outlined,
            color: AppColors.magenta, size: mini ? 36 : 48)),
      const SizedBox(height: 14),
      Text('No orders yet',
          style: AppText.body(
              color: mini
                  ? AppColors.textDisabled
                  : AppColors.textPrimary)
              .copyWith(
                  fontSize: mini ? 14 : 18,
                  fontWeight: FontWeight.w600)),
      if (!mini) ...[
        const SizedBox(height: 8),
        Text('Shop now to place your first order',
            style: AppText.body(color: AppColors.textDisabled)
                .copyWith(fontSize: 13)),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => setState(() => _tabIndex = 1),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.magenta,
            shape: RoundedRectangleBorder(
                borderRadius: AppRadius.mdRadius)),
          child: Text('Go to Shop', style: AppText.buttonLabel()),
        ),
      ],
    ],
  ));

  Color _statusColor(SaleStatus s) => switch (s) {
    SaleStatus.completed  => AppColors.success,
    SaleStatus.processing => AppColors.warning,
    SaleStatus.pending    => AppColors.primary,
    SaleStatus.cancelled  => AppColors.danger,
  };

  IconData _catIcon(String cat) => switch (cat.toLowerCase()) {
    'shirts'      => Icons.checkroom_rounded,
    'pants'       => Icons.straighten_rounded,
    'dresses'     => Icons.dry_cleaning_rounded,
    'jackets'     => Icons.ac_unit_rounded,
    'accessories' => Icons.watch_rounded,
    'shoes'       => Icons.roller_skating_rounded,
    _             => Icons.category_rounded,
  };

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }
}