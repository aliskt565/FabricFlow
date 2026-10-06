import 'package:flutter/material.dart';
import '../../models/customer_model.dart';
import '../../models/sales_model.dart';
import '../../services/firestore_service.dart';
import '../../services/customer_insights_service.dart';
import '../../theme/app_theme.dart';

class CustomerInsightsScreen extends StatelessWidget {
  final CustomerModel customer;
  const CustomerInsightsScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    final fs  = FirestoreService();
    final svc = CustomerInsightsService();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: StreamBuilder<List<SalesModel>>(
        stream: fs.getSales(),
        builder: (ctx, snap) {
          final snapshot = svc.build(customer.id, snap.data ?? []);

          return CustomScrollView(slivers: [
            // ── Header ──────────────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              backgroundColor: AppColors.background,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF0B4D3B), Color(0xFF11998E)],
                    ),
                  ),
                  child: SafeArea(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        width: 72, height: 72,
                        decoration: const BoxDecoration(
                          gradient: AppGradients.success,
                          shape: BoxShape.circle,
                        ),
                        child: Center(child: Text(
                          customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                          style: AppText.headline().copyWith(fontSize: 28),
                        )),
                      ),
                      const SizedBox(height: 12),
                      Text(customer.name, style: AppText.headline().copyWith(fontSize: 20)),
                      const SizedBox(height: 4),
                      Text(customer.email, style: AppText.caption(color: Colors.white60).copyWith(fontSize: 13)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .15),
                          borderRadius: AppRadius.xlRadius,
                        ),
                        child: Text('Customer Profile',
                            style: AppText.caption(color: Colors.white).copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  )),
                ),
              ),
            ),

            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── KPI Cards ──────────────────────────────────────────
                Row(children: [
                  _kpiCard('Lifetime Value',
                      'Rs. ${_fmt(snapshot.lifetimeValue)}',
                      Icons.payments_rounded, AppGradients.success),
                  const SizedBox(width: 10),
                  _kpiCard('Total Orders',
                      '${snapshot.totalOrders}',
                      Icons.receipt_long_rounded, AppGradients.primary),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _kpiCard('Avg Order Value',
                      'Rs. ${_fmt(snapshot.averageOrderValue)}',
                      Icons.analytics_rounded, AppGradients.danger),
                  const SizedBox(width: 10),
                  _kpiCard('Last Active',
                      snapshot.daysSinceLastOrder == null
                          ? 'Never'
                          : '${snapshot.daysSinceLastOrder}d ago',
                      Icons.access_time_rounded,
                      snapshot.daysSinceLastOrder == null || snapshot.daysSinceLastOrder! > 60
                          ? const LinearGradient(colors: [Color(0xFFFF6B6B), Color(0xFFFFB347)])
                          : AppGradients.success),
                ]),
                const SizedBox(height: 24),

                // ── Customer Info ──────────────────────────────────────
                Text('Contact Info', style: AppText.title().copyWith(fontSize: 15)),
                const SizedBox(height: 12),
                _infoRow(Icons.email_outlined, 'Email', customer.email),
                const SizedBox(height: 8),
                _infoRow(Icons.phone_outlined, 'Phone',
                    customer.phone.isEmpty ? 'Not provided' : customer.phone),
                const SizedBox(height: 8),
                _infoRow(Icons.location_on_outlined, 'Address',
                    customer.address.isEmpty ? 'Not provided' : customer.address),
                const SizedBox(height: 24),

                // ── Status badge (last order) ──────────────────────────
                if (snapshot.lastOrderStatus != null) ...[
                  Text('Last Order Status', style: AppText.title().copyWith(fontSize: 15)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadius.lgRadius,
                      border: Border.all(color: Colors.white.withValues(alpha: .06)),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _statusColor(snapshot.lastOrderStatus!).withValues(alpha: .15),
                          borderRadius: AppRadius.mdRadius,
                        ),
                        child: Icon(_statusIcon(snapshot.lastOrderStatus!),
                            color: _statusColor(snapshot.lastOrderStatus!), size: 20),
                      ),
                      const SizedBox(width: 14),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(snapshot.lastOrderStatus!.value,
                            style: AppText.body().copyWith(
                                fontWeight: FontWeight.w600,
                                color: _statusColor(snapshot.lastOrderStatus!))),
                        Text('Most recent order',
                            style: AppText.caption(color: AppColors.textDisabled)),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Order History ──────────────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Order History', style: AppText.title().copyWith(fontSize: 15)),
                  Text('${snapshot.totalOrders} orders',
                      style: AppText.caption(color: AppColors.textDisabled)),
                ]),
                const SizedBox(height: 12),

                if (snap.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator(color: AppColors.teal))
                else if (snapshot.orders.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                        color: AppColors.surface, borderRadius: AppRadius.lgRadius),
                    child: Center(child: Column(children: [
                      const Icon(Icons.receipt_long_outlined,
                          color: AppColors.textDisabled, size: 40),
                      const SizedBox(height: 8),
                      Text('No orders yet',
                          style: AppText.body(color: AppColors.textDisabled)),
                    ])),
                  )
                else
                  ...snapshot.orders.map((order) => _orderCard(order)),

                const SizedBox(height: 32),
              ]),
            )),
          ]);
        },
      ),
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, LinearGradient gradient) =>
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
            decoration: BoxDecoration(gradient: gradient, borderRadius: AppRadius.smRadius),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(height: 10),
          Text(value, style: AppText.title().copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 10)),
        ]),
      ));

  Widget _infoRow(IconData icon, String label, String value) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.lgRadius,
      border: Border.all(color: Colors.white.withValues(alpha: .06)),
    ),
    child: Row(children: [
      Icon(icon, color: AppColors.teal, size: 18),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: AppText.body().copyWith(fontSize: 14, fontWeight: FontWeight.w500)),
      ])),
    ]),
  );

  Widget _orderCard(SalesModel order) {
    final color = _statusColor(order.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .15),
            borderRadius: AppRadius.mdRadius,
          ),
          child: Icon(Icons.receipt_rounded, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${order.items.length} item${order.items.length == 1 ? '' : 's'}',
              style: AppText.body().copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
          Text('${order.date.day}/${order.date.month}/${order.date.year}',
              style: AppText.caption(color: AppColors.textDisabled)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Rs. ${_fmt(order.totalAmount)}',
              style: AppText.body(color: AppColors.danger).copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .15),
              borderRadius: AppRadius.smRadius,
            ),
            child: Text(order.status.value,
                style: AppText.badge(color: color).copyWith(fontSize: 9)),
          ),
        ]),
      ]),
    );
  }

  Color _statusColor(SaleStatus s) => switch (s) {
    SaleStatus.completed  => AppColors.tealLight,
    SaleStatus.processing => AppColors.warning,
    SaleStatus.cancelled  => AppColors.danger,
    SaleStatus.pending    => AppColors.primary,
  };

  IconData _statusIcon(SaleStatus s) => switch (s) {
    SaleStatus.completed  => Icons.check_circle_rounded,
    SaleStatus.processing => Icons.autorenew_rounded,
    SaleStatus.cancelled  => Icons.cancel_rounded,
    SaleStatus.pending    => Icons.schedule_rounded,
  };

  String _fmt(double v) {
    if (v >= 1000000) return '${(v/1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v/1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}