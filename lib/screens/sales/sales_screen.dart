// ============================================================
// lib/screens/sales/sales_screen.dart
//
// BUG FIX SUMMARY (Sales Completion Status):
//
// ROOT CAUSE:
//   1. FirestoreService.updateSaleStatus() existed but was NEVER called
//      anywhere in the UI. There was no button/menu to change a sale's
//      status after creation — every sale was created with a hardcoded
//      status: 'Completed' and frozen forever.
//   2. Status was a raw String compared with `==` in multiple files.
//      Any casing drift ("completed" vs "Completed") would silently
//      break filters with no error shown.
//   3. The "Processing" status (required by spec) did not exist
//      anywhere in the codebase — filters and the switch-statement
//      only handled 3 of the 4 required statuses.
//
// FIX:
//   - Added a status-change menu (PopupMenuButton) on every sale card.
//   - New sales now default to SaleStatus.pending (not "Completed"),
//     matching a real order lifecycle: Pending → Processing →
//     Completed, with Cancelled reachable from Pending/Processing/
//     Completed.
//   - Status filter chips now cover all 4 statuses + "All".
//   - Uses the typed SaleStatus enum throughout — no more raw strings,
//     no more silent casing mismatches.
//   - Status change calls FirestoreService.updateSaleStatus() which
//     validates the transition and writes the canonical string to
//     Firestore, then the StreamBuilder picks up the change and the
//     UI updates immediately (real-time, no manual refresh needed).
//
// THEME MIGRATION: all hardcoded Color(0xFF...) literals replaced with
// AppColors/AppGradients/AppRadius/AppText tokens. _statusMeta map kept
// as a static const Map (AppColors values are themselves static const,
// so this remains a valid compile-time constant).
//
// PAYMENT TRACKING INTEGRATION:
//   - Every sale card now shows a live "Paid / Partial / Unpaid" badge
//     next to the status badge, computed from PaymentService.watchSaleBalance.
//   - "Record Payment" action opens RecordPaymentSheet, which validates
//     amount against the remaining balance and writes through
//     PaymentService (gateway-abstracted — manual today, real
//     JazzCash/EasyPaisa/Stripe later with zero changes here).
//   - Expanded card now shows full payment history via PaymentHistoryList,
//     with refund enabled (Manager/Employee context).
// ============================================================
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/sales_model.dart';
import '../../models/product_model.dart';
import '../../models/customer_model.dart';
import '../../models/payment_model.dart';
import '../../services/firestore_service.dart';
import '../../services/payment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/skeletons.dart';
import '../widgets/record_payment_sheet.dart';
import '../widgets/payment_history_list.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final FirestoreService      _fs         = FirestoreService();
  final PaymentService        _ps         = PaymentService();

  // ── Activity log actor identity ─────────────────────────────────────────
  String get _actorUid  => FirebaseAuth.instance.currentUser?.uid   ?? '';
  String get _actorName => FirebaseAuth.instance.currentUser?.email ?? 'Unknown';
  final TextEditingController _searchCtrl = TextEditingController();

  String     _searchQuery    = '';
  SaleStatus? _statusFilter; // null = "All"

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  List<SalesModel> _filter(List<SalesModel> sales) => sales.where((s) {
    final matchSearch = _searchQuery.isEmpty ||
        s.customerName.toLowerCase().contains(_searchQuery.toLowerCase());
    final matchStatus = _statusFilter == null || s.status == _statusFilter;
    return matchSearch && matchStatus;
  }).toList();

  // ── Status visuals — single source of truth for color/icon/label ──────
  static const _statusMeta = <SaleStatus, _StatusMeta>{
    SaleStatus.pending:    _StatusMeta(AppColors.primary, Icons.schedule_rounded),
    SaleStatus.processing: _StatusMeta(AppColors.warning, Icons.autorenew_rounded),
    SaleStatus.completed:  _StatusMeta(AppColors.success, Icons.check_circle_rounded),
    SaleStatus.cancelled:  _StatusMeta(AppColors.danger,  Icons.cancel_rounded),
  };

  // ── Status change handler — calls the FIXED service method ────────────
  Future<void> _changeStatus(SalesModel sale, SaleStatus newStatus) async {
    try {
      await _fs.updateSaleStatus(
        sale.id,
        sale.status,
        newStatus,
        actorUid:  _actorUid,
        actorName: _actorName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            Icon(_statusMeta[newStatus]!.icon, color: AppColors.textPrimary, size: 18),
            const SizedBox(width: 8),
            Text('Status updated to "${newStatus.value}"', style: AppText.body()),
          ]),
          backgroundColor: _statusMeta[newStatus]!.color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
        ));
      }
    } catch (e) {
      // Illegal transition or network error — shown clearly, never silent
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e', style: AppText.body()),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
        ));
      }
    }
  }

  // ── Record Payment handler — opens RecordPaymentSheet ─────────────────
  void _openRecordPayment(SalesModel sale) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecordPaymentSheet(
        saleId: sale.id,
        customerId: sale.customerId,
        customerName: sale.customerName,
        saleTotalAmount: sale.totalAmount,
      ),
    );
  }

  // ── Add sale dialog ─────────────────────────────────────────────────────
  void _showAddSaleDialog() {
    String? selCustId;
    String? selCustName;
    Map<String, int> selItems = {};
    List<ProductModel>  products  = [];
    List<CustomerModel> customers = [];
    bool isLoading   = true;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setM) {
          if (isLoading) {
            Future.wait([
              _fs.getProducts().first,
              _fs.getCustomers().first,
            ]).then((r) {
              setM(() {
                products   = r[0] as List<ProductModel>;
                customers  = r[1] as List<CustomerModel>;
                isLoading  = false;
              });
            });
          }

          double total = 0;
          for (final e in selItems.entries) {
            final p = products.where((x) => x.id == e.key).firstOrNull;
            if (p != null) total += p.price * e.value;
          }

          return Container(
            height: MediaQuery.of(context).size.height * .85,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(children: [
              Padding(padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: AppColors.textFaint,
                        borderRadius: AppRadius.handleRadius))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        gradient: AppGradients.primary,
                        borderRadius: AppRadius.mdRadius),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: AppColors.textPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('New Sale', style: AppText.title()),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary)),
                ]),
              ),
              const Divider(color: AppColors.border, height: 1),
              Expanded(child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Select Customer',
                            style: AppText.caption(color: AppColors.textTertiary).copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                              color: AppColors.surfaceRaised,
                              borderRadius: AppRadius.lgRadius,
                              border: Border.all(color: AppColors.border)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selCustId,
                              hint: Text('Choose a customer', style: AppText.body(color: AppColors.textDisabled)),
                              dropdownColor: AppColors.surface,
                              style: AppText.body(),
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textTertiary),
                              isExpanded: true,
                              items: customers.map((c) => DropdownMenuItem(
                                  value: c.id, child: Text(c.name))).toList(),
                              onChanged: (v) {
                                final c = customers.firstWhere((x) => x.id == v);
                                setM(() { selCustId = v; selCustName = c.name; });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text('Select Products',
                            style: AppText.caption(color: AppColors.textTertiary).copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 10),
                        ...products.map((p) {
                          final qty = selItems[p.id] ?? 0;
                          final sel = qty > 0;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.danger.withValues(alpha: .1) : AppColors.surfaceRaised,
                              borderRadius: AppRadius.lgRadius,
                              border: Border.all(color: sel ? AppColors.danger.withValues(alpha: .4) : AppColors.border),
                            ),
                            child: Row(children: [
                              Container(width: 42, height: 42,
                                decoration: BoxDecoration(color: AppColors.surface,
                                    borderRadius: AppRadius.mdRadius),
                                child: const Icon(Icons.checkroom_rounded, color: AppColors.primary, size: 20)),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name, style: AppText.body().copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
                                Text('Rs. ${p.price.toStringAsFixed(0)} · Stock: ${p.stock}',
                                    style: AppText.caption(color: AppColors.textTertiary)),
                              ])),
                              Row(children: [
                                _qtyBtn(Icons.remove_rounded, qty > 0, () => setM(() {
                                  if (qty == 1) {
                                    selItems.remove(p.id);
                                  } else {
                                    selItems[p.id] = qty - 1;
                                  }
                                })),
                                Container(width: 32, alignment: Alignment.center,
                                    child: Text('$qty', style: AppText.body(
                                        color: qty > 0 ? AppColors.textPrimary : AppColors.textDisabled,
                                      ).copyWith(fontWeight: FontWeight.w600, fontSize: 15))),
                                _qtyBtn(Icons.add_rounded, qty < p.stock,
                                    () => setM(() => selItems[p.id] = qty + 1), active: true),
                              ]),
                            ]),
                          );
                        }),
                      ]),
                    )),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                    color: AppColors.background, border: Border(top: BorderSide(color: AppColors.border))),
                child: Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Total Amount', style: AppText.caption(color: AppColors.textTertiary)),
                    Text('Rs. ${total.toStringAsFixed(0)}',
                        style: AppText.headline(color: AppColors.danger).copyWith(fontSize: 22)),
                  ]),
                  const SizedBox(width: 16),
                  Expanded(child: ElevatedButton(
                    onPressed: (isSubmitting || selCustId == null || selItems.isEmpty) ? null : () async {
                      setM(() => isSubmitting = true);
                      Navigator.pop(ctx);
                      final items = selItems.entries.map((e) {
                        final p = products.firstWhere((x) => x.id == e.key);
                        return {'productId': e.key, 'productName': p.name,
                                'quantity': e.value, 'price': p.price};
                      }).toList();

                      // ── FIX: new sales start as PENDING, not "Completed" ──
                      // A real order lifecycle starts pending and moves
                      // through Processing → Completed (or Cancelled) via
                      // the status menu on the sale card.
                      final sale = SalesModel(
                        id: '', customerId: selCustId!, customerName: selCustName!,
                        items: items, totalAmount: total, date: DateTime.now(),
                        status: SaleStatus.pending,
                      );
                      await _fs.addSale(
                        sale,
                        actorUid:  _actorUid,
                        actorName: _actorName,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: (selCustId == null || selItems.isEmpty) ? Colors.white12 : AppColors.danger,
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
                    ),
                    child: Text(isSubmitting ? 'Processing...' : 'Create Sale (Pending)',
                        style: AppText.buttonLabel().copyWith(fontSize: 15)),
                  )),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _qtyBtn(IconData icon, bool enabled, VoidCallback? onTap, {bool active = false}) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(width: 28, height: 28,
      decoration: BoxDecoration(
        color: !enabled ? Colors.white.withValues(alpha: .05)
            : active ? AppColors.danger.withValues(alpha: .2) : AppColors.surface,
        borderRadius: AppRadius.smRadius),
      child: Icon(icon, size: 16,
          color: !enabled ? AppColors.textFaint : active ? AppColors.danger : AppColors.textTertiary)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 130, pinned: true, floating: false,
            backgroundColor: AppColors.background, elevation: 0,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Sales', style: AppText.headline()),
                    Text('Track your transactions',
                        style: AppText.caption(color: AppColors.textTertiary).copyWith(fontSize: 13)),
                  ]),
                  StreamBuilder<List<SalesModel>>(
                    stream: _fs.getSales(),
                    builder: (context, snap) {
                      final sales = snap.data ?? [];
                      final total = sales.fold<double>(0, (s, x) => s + x.totalAmount);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                            gradient: AppGradients.danger,
                            borderRadius: AppRadius.xlRadius),
                        child: Text('Rs. ${total.toStringAsFixed(0)}', style: AppText.buttonLabel().copyWith(fontSize: 13)),
                      );
                    },
                  ),
                ]),
              )),
            ),
          ),
        ],
        body: Column(children: [
          Container(
            color: AppColors.background,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(children: [
              Container(
                decoration: BoxDecoration(color: AppColors.surface,
                    borderRadius: AppRadius.lgRadius, border: Border.all(color: AppColors.border)),
                child: TextField(
                  controller: _searchCtrl,
                  style: AppText.body(),
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search by customer name...',
                    hintStyle: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textDisabled),
                    suffixIcon: _searchQuery.isNotEmpty ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: AppColors.textDisabled, size: 20),
                        onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); }) : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // ── FIX: status filter now covers all 4 statuses ──────────
              SizedBox(height: 36, child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _statusChip(null, 'All', AppColors.textTertiary, Icons.list_rounded),
                  ..._statusMeta.entries.map((e) =>
                      _statusChip(e.key, e.key.value, e.value.color, e.value.icon)),
                ],
              )),
            ]),
          ),
          Expanded(child: StreamBuilder<List<SalesModel>>(
            stream: _fs.getSales(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SingleChildScrollView(
                  padding: EdgeInsets.only(top: 8, bottom: 100),
                  child: SkeletonListView(count: 5),
                );
              }
              if (!snap.hasData || snap.data!.isEmpty) return _emptyState();
              final filtered = _filter(snap.data!);
              if (filtered.isEmpty) return _noResults();
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                itemCount: filtered.length,
                itemBuilder: (context, i) => _saleCard(filtered[i]),
              );
            },
          )),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSaleDialog,
        backgroundColor: AppColors.danger,
        icon: const Icon(Icons.add_rounded, color: AppColors.textPrimary),
        label: Text('New Sale', style: AppText.buttonLabel()),
      ),
    );
  }

  Widget _statusChip(SaleStatus? status, String label, Color color, IconData icon) {
    final isSelected = _statusFilter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _statusFilter = status),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: .2) : AppColors.surface,
            borderRadius: AppRadius.xlRadius,
            border: Border.all(color: isSelected ? color : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: isSelected ? color : AppColors.textDisabled),
            const SizedBox(width: 5),
            Text(label, style: AppText.caption(
                color: isSelected ? color : AppColors.textTertiary,
              ).copyWith(fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
          ]),
        ),
      ),
    );
  }

  // ── Live Paid/Partial/Unpaid badge — feeds PaymentService balance ─────
  Widget _paymentBadge(SalesModel sale) {
    return StreamBuilder<SaleBalance>(
      stream: _ps.watchSaleBalance(sale.id, sale.totalAmount),
      builder: (context, snap) {
        final balance = snap.data;
        if (balance == null) {
          return const SizedBox(
            width: 46, height: 14,
            child: Center(child: SizedBox(
              width: 10, height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textFaint),
            )),
          );
        }
        final color = switch (balance.label) {
          'Paid'    => AppColors.success,
          'Partial' => AppColors.warning,
          _         => AppColors.danger,
        };
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: AppRadius.smRadius),
          child: Text(balance.label, style: AppText.badge(color: color).copyWith(fontSize: 10)),
        );
      },
    );
  }

  // ── Sale card with WORKING status-change menu + payment tracking ──────
  Widget _saleCard(SalesModel sale) {
    final meta = _statusMeta[sale.status]!;
    final date = sale.date;
    final dateStr = '${date.day}/${date.month}/${date.year}  '
        '${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.xlRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [meta.color.withValues(alpha: .3), meta.color.withValues(alpha: .1)]),
              borderRadius: AppRadius.mdRadius),
            child: Icon(Icons.receipt_rounded, color: meta.color, size: 22),
          ),
          title: Text(sale.customerName, style: AppText.body().copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(dateStr, style: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 11)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Rs. ${sale.totalAmount.toStringAsFixed(0)}',
                  style: AppText.body(color: AppColors.danger).copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                // ── Live payment status badge ───────────────────────────
                _paymentBadge(sale),
                const SizedBox(width: 6),
                // ── THE FIX: tappable status badge opens a working menu ──
                PopupMenuButton<SaleStatus>(
                  tooltip: 'Change status',
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
                  offset: const Offset(0, 30),
                  itemBuilder: (ctx) => sale.status.allowedNextStatuses.map((next) {
                    final nextMeta = _statusMeta[next]!;
                    return PopupMenuItem(
                      value: next,
                      child: Row(children: [
                        Icon(nextMeta.icon, color: nextMeta.color, size: 16),
                        const SizedBox(width: 10),
                        Text('Mark as ${next.value}', style: AppText.body().copyWith(fontSize: 13)),
                      ]),
                    );
                  }).toList(),
                  onSelected: (next) => _changeStatus(sale, next),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: meta.color.withValues(alpha: .15), borderRadius: AppRadius.smRadius),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(meta.icon, color: meta.color, size: 10),
                      const SizedBox(width: 3),
                      Text(sale.status.value, style: AppText.badge(color: meta.color).copyWith(fontSize: 10)),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_down_rounded, color: meta.color, size: 12),
                    ]),
                  ),
                ),
              ]),
            ]),
          ]),
          children: [
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            Text('Items Purchased', style: AppText.caption(color: AppColors.textTertiary).copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            ...sale.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Icon(Icons.fiber_manual_record, color: AppColors.primary, size: 8),
                const SizedBox(width: 8),
                Expanded(child: Text(item['productName'] ?? 'Product', style: AppText.body(color: AppColors.textSecondary).copyWith(fontSize: 13))),
                Text('x${item['quantity']}', style: AppText.caption(color: AppColors.textTertiary)),
                const SizedBox(width: 12),
                Text('Rs. ${((item['price'] as num) * (item['quantity'] as num)).toStringAsFixed(0)}',
                    style: AppText.body().copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            )),
            const Divider(color: AppColors.border),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Total', style: AppText.caption(color: AppColors.textTertiary).copyWith(fontWeight: FontWeight.w500)),
              Text('Rs. ${sale.totalAmount.toStringAsFixed(0)}',
                  style: AppText.body(color: AppColors.danger).copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 16),

            // ── Payments section ──────────────────────────────────────
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Payments', style: AppText.caption(color: AppColors.textTertiary).copyWith(fontWeight: FontWeight.w500)),
              GestureDetector(
                onTap: () => _openRecordPayment(sale),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: AppGradients.success,
                    borderRadius: AppRadius.smRadius,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.add_card_rounded, color: AppColors.textPrimary, size: 14),
                    const SizedBox(width: 6),
                    Text('Record Payment', style: AppText.buttonLabel().copyWith(fontSize: 12)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            PaymentHistoryList(
              saleId: sale.id,
              saleTotalAmount: sale.totalAmount,
              allowRefund: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
        child: const Icon(Icons.receipt_long_outlined, color: AppColors.danger, size: 48)),
    const SizedBox(height: 16),
    Text('No Sales Yet', style: AppText.title().copyWith(fontSize: 18)),
    const SizedBox(height: 8),
    Text('Tap + to record your first sale', style: AppText.body(color: AppColors.textDisabled)),
  ]));

  Widget _noResults() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.search_off_rounded, color: AppColors.danger, size: 56),
    const SizedBox(height: 16),
    Text('No Results Found', style: AppText.title().copyWith(fontSize: 18)),
    const SizedBox(height: 8),
    TextButton(
      onPressed: () { _searchCtrl.clear(); setState(() { _searchQuery = ''; _statusFilter = null; }); },
      child: Text('Clear Filters', style: AppText.buttonLabel(color: AppColors.danger)),
    ),
  ]));
}

class _StatusMeta {
  final Color color;
  final IconData icon;
  const _StatusMeta(this.color, this.icon);
}