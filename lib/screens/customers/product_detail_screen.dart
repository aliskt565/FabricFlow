// ============================================================
// lib/screens/customer/product_detail_screen.dart
//
// Full-screen product detail page — replaces the old bottom-sheet
// modal that lived inline in CustomerDashboardScreen._openProduct().
//
// WHY A FULL SCREEN INSTEAD OF A BOTTOM SHEET:
//   A bottom sheet caps at ~82% of screen height and competes for
//   space with its own header/footer chrome. Once this page needs
//   to also show "Related Products" (this step) and, in upcoming
//   steps, ratings/reviews and a wishlist toggle, that space runs
//   out fast. A dedicated route (like Shopify, Amazon, Daraz) gives
//   the full viewport, a proper back-button affordance, and makes
//   each future addition (reviews, image gallery, etc.) a section
//   appended to this screen rather than a fight for sheet height.
//
// Uses the real product image (imageUrl) when present, falling back
// to the category icon tile — same fallback pattern as the Admin
// Inventory screen's _productThumbnail.
// ============================================================
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/product_model.dart';
import '../../models/sales_model.dart';
import '../../models/customer_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';

class ProductDetailScreen extends StatefulWidget {
  final ProductModel product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _fs   = FirestoreService();
  final _auth = FirebaseAuth.instance;

  int  _qty          = 1;
  bool _placingOrder = false;

  String get _uid   => _auth.currentUser?.uid   ?? '';
  String get _email => _auth.currentUser?.email ?? '';
  String get _name  => _email.split('@').first;

  Future<void> _buy() async {
    setState(() => _placingOrder = true);
    try {
      final customers = await _fs.getCustomers().first;
      final match = customers.cast<CustomerModel?>()
          .firstWhere((c) => c!.id == _uid, orElse: () => null);
      final customerName = match?.name ?? _name;

      await _fs.addSale(
        SalesModel(
          id: '', customerId: _uid, customerName: customerName,
          items: [{
            'productId':   widget.product.id,
            'productName': widget.product.name,
            'quantity':    _qty,
            'price':       widget.product.price,
          }],
          totalAmount: widget.product.price * _qty,
          date: DateTime.now(),
          status: SaleStatus.pending,
        ),
        actorUid:  _uid,
        actorName: _email.isNotEmpty ? _email : 'Customer',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.textPrimary, size: 20),
          const SizedBox(width: 10),
          Text('Order placed! Check your orders tab.', style: AppText.body()),
        ]),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
      ));
      Navigator.of(context).pop(true); // true signals "order placed" to caller
    } catch (e) {
      if (!mounted) return;
      setState(() => _placingOrder = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Order failed: $e'.replaceFirst('Exception: ', ''), style: AppText.body()),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: AppColors.background,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                backgroundColor: Colors.black45,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _heroImage(p),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(p.name, style: AppText.headline().copyWith(fontSize: 22))),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: (p.stock > 0 ? AppColors.success : AppColors.danger).withValues(alpha: .15),
                        borderRadius: AppRadius.mdRadius,
                      ),
                      child: Text(
                        p.stock > 0 ? '${p.stock} in stock' : 'Out of stock',
                        style: AppText.badge(color: p.stock > 0 ? AppColors.success : AppColors.danger)
                            .copyWith(fontSize: 11),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceRaised,
                      borderRadius: AppRadius.smRadius,
                    ),
                    child: Text(p.category, style: AppText.caption().copyWith(fontSize: 11)),
                  ),
                  const SizedBox(height: 14),
                  Text('Rs. ${p.price.toStringAsFixed(0)}',
                      style: AppText.headline(color: AppColors.magentaPale)
                          .copyWith(fontSize: 30, fontWeight: FontWeight.w800)),

                  if (p.description.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Description',
                        style: AppText.caption(color: AppColors.textTertiary).copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Text(p.description,
                        style: AppText.body(color: AppColors.textSecondary).copyWith(height: 1.6)),
                  ],

                  if (p.stock > 0) ...[
                    const SizedBox(height: 24),
                    _quantitySelector(p),
                  ],

                  const SizedBox(height: 28),
                  _relatedProductsSection(p),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: p.stock > 0
              ? GestureDetector(
                  onTap: _placingOrder ? null : _buy,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      gradient: AppGradients.customer,
                      borderRadius: AppRadius.xlRadius,
                      boxShadow: [
                        BoxShadow(color: AppColors.magenta.withValues(alpha: .4), blurRadius: 20, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_placingOrder)
                          const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                        else ...[
                          const Icon(Icons.shopping_bag_rounded, color: AppColors.textPrimary, size: 20),
                          const SizedBox(width: 10),
                          Text('Buy Now  ·  Rs. ${(p.price * _qty).toStringAsFixed(0)}',
                              style: AppText.buttonLabel().copyWith(fontSize: 16)),
                        ],
                      ],
                    ),
                  ),
                )
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: AppRadius.xlRadius),
                  child: Center(
                    child: Text('Out of Stock',
                        style: AppText.body(color: AppColors.textDisabled).copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _heroImage(ProductModel p) {
    if (p.imageUrl.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            p.imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (ctx, child, progress) => progress == null
                ? child
                : Container(
                    color: AppColors.surface,
                    child: const Center(child: CircularProgressIndicator(color: AppColors.magenta)),
                  ),
            errorBuilder: (ctx, err, st) => _placeholderHero(p),
          ),
          // Gradient scrim so the back button stays legible over any photo
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: .35), Colors.transparent, Colors.transparent],
                stops: const [0.0, 0.3, 1.0],
              ),
            ),
          ),
        ],
      );
    }
    return _placeholderHero(p);
  }

  Widget _placeholderHero(ProductModel p) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppColors.magenta.withValues(alpha: .3), AppColors.purpleDeep.withValues(alpha: .2)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
    ),
    child: Center(child: Icon(_catIcon(p.category), color: AppColors.magentaPale, size: 110)),
  );

  Widget _quantitySelector(ProductModel p) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: AppRadius.lgRadius,
      border: Border.all(color: AppColors.border),
    ),
    child: Row(children: [
      Text('Quantity', style: AppText.body(color: AppColors.textTertiary)),
      const Spacer(),
      _qBtn(Icons.remove_rounded, _qty > 1, () => setState(() => _qty--)),
      Container(
        width: 44, height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.smRadius),
        child: Text('$_qty', style: AppText.title().copyWith(fontSize: 16)),
      ),
      _qBtn(Icons.add_rounded, _qty < p.stock, () => setState(() => _qty++), add: true),
      const SizedBox(width: 16),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('Total', style: AppText.caption(color: AppColors.textDisabled)),
        Text('Rs. ${(p.price * _qty).toStringAsFixed(0)}',
            style: AppText.body().copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
      ]),
    ]),
  );

  Widget _qBtn(IconData icon, bool enabled, VoidCallback onTap, {bool add = false}) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(
      width: 38, height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        gradient: enabled && add ? AppGradients.customer : null,
        color: enabled && !add ? AppColors.surface : !enabled ? Colors.white.withValues(alpha: .05) : null,
        borderRadius: AppRadius.mdRadius,
      ),
      child: Icon(icon, size: 20, color: enabled ? AppColors.textPrimary : AppColors.textFaint),
    ),
  );

  // ── Related Products — same category, excludes self, in-stock only ────
  Widget _relatedProductsSection(ProductModel current) {
    return StreamBuilder<List<ProductModel>>(
      stream: _fs.getProducts(),
      builder: (ctx, snap) {
        final related = (snap.data ?? [])
            .where((p) => p.id != current.id && p.category == current.category && p.stock > 0)
            .take(6)
            .toList();
        if (related.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You May Also Like', style: AppText.title().copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: related.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) => _relatedCard(related[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _relatedCard(ProductModel p) => GestureDetector(
    onTap: () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)),
      );
    },
    child: Container(
      width: 140,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: p.imageUrl.isNotEmpty
                  ? Image.network(
                      p.imageUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, st) => _relatedPlaceholder(p),
                    )
                  : _relatedPlaceholder(p),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      style: AppText.body().copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const Spacer(),
                  Text('Rs. ${p.price.toStringAsFixed(0)}',
                      style: AppText.body(color: AppColors.magentaPale).copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _relatedPlaceholder(ProductModel p) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [AppColors.magenta.withValues(alpha: .25), AppColors.purpleDeep.withValues(alpha: .15)]),
    ),
    child: Icon(_catIcon(p.category), color: AppColors.magentaPale, size: 36),
  );

  IconData _catIcon(String cat) => switch (cat.toLowerCase()) {
    'shirts'      => Icons.checkroom_rounded,
    'pants'       => Icons.straighten_rounded,
    'dresses'     => Icons.dry_cleaning_rounded,
    'jackets'     => Icons.ac_unit_rounded,
    'accessories' => Icons.watch_rounded,
    'shoes'       => Icons.roller_skating_rounded,
    _             => Icons.category_rounded,
  };
}