import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/product_model.dart';
import '../../services/firestore_service.dart';
import '../../services/cloudinary_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/skeletons.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _FilterState {
  String   category  = 'All';
  String   status    = 'All';
  String   warehouse = 'All';
  DateTime? dateFrom;
  DateTime? dateTo;

  bool get hasActiveFilters =>
      category  != 'All' || status != 'All' ||
      warehouse != 'All' || dateFrom != null || dateTo != null;

  int get activeCount {
    int c = 0;
    if (category  != 'All') c++;
    if (status    != 'All') c++;
    if (warehouse != 'All') c++;
    if (dateFrom  != null || dateTo != null) c++;
    return c;
  }

  void reset() {
    category = 'All'; status = 'All';
    warehouse = 'All'; dateFrom = null; dateTo = null;
  }

  _FilterState copyWith({
    String? category, String? status, String? warehouse,
    DateTime? dateFrom, DateTime? dateTo, bool clearDates = false,
  }) {
    final f = _FilterState();
    f.category  = category  ?? this.category;
    f.status    = status    ?? this.status;
    f.warehouse = warehouse ?? this.warehouse;
    f.dateFrom  = clearDates ? null : (dateFrom ?? this.dateFrom);
    f.dateTo    = clearDates ? null : (dateTo   ?? this.dateTo);
    return f;
  }
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService      _fs         = FirestoreService();
  final CloudinaryService     _cloudinary = CloudinaryService();
  final TextEditingController _searchCtrl = TextEditingController();
  late  AnimationController   _fabAnim;

  String get _actorUid  => FirebaseAuth.instance.currentUser?.uid   ?? '';
  String get _actorName => FirebaseAuth.instance.currentUser?.email ?? 'Unknown';

  String       _searchQuery = '';
  _FilterState _filters     = _FilterState();
  bool         _migrating   = false;

  static const _categories = ['All','Shirts','Pants','Dresses','Jackets','Accessories','Shoes','Other'];
  static const _warehouses = ['All','Main Warehouse','Store Front','Back Store','Online Fulfilment'];
  static const _statuses   = ['All','In Stock','Low Stock','Out of Stock'];

  @override
  void initState() {
    super.initState();
    _fabAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))..forward();
  }

  @override
  void dispose() { _searchCtrl.dispose(); _fabAnim.dispose(); super.dispose(); }

  List<ProductModel> _apply(List<ProductModel> all) {
    return all.where((p) {
      final q = _searchQuery.toLowerCase();
      final matchSearch = q.isEmpty ||
          p.name.toLowerCase().contains(q) || p.tagNumber.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) || p.warehouse.toLowerCase().contains(q);
      final matchCat = _filters.category == 'All' || p.category == _filters.category;
      bool matchStatus = true;
      if (_filters.status == 'In Stock')     matchStatus = p.stock >= 10;
      if (_filters.status == 'Low Stock')    matchStatus = p.stock > 0 && p.stock < 10;
      if (_filters.status == 'Out of Stock') matchStatus = p.stock == 0;
      final matchWH = _filters.warehouse == 'All' || p.warehouse == _filters.warehouse;
      bool matchDate = true;
      if (_filters.dateFrom != null) matchDate = matchDate && !p.createdAt.isBefore(_filters.dateFrom!);
      if (_filters.dateTo   != null) {
        final endOfDay = _filters.dateTo!.add(const Duration(hours: 23, minutes: 59, seconds: 59));
        matchDate = matchDate && !p.createdAt.isAfter(endOfDay);
      }
      return matchSearch && matchCat && matchStatus && matchWH && matchDate;
    }).toList();
  }

  Future<void> _openFilterDialog() async {
    _FilterState draft = _filters.copyWith();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                decoration: const BoxDecoration(
                  gradient: AppGradients.primary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(children: [
                  const Icon(Icons.tune_rounded, color: AppColors.textPrimary, size: 22),
                  const SizedBox(width: 10),
                  Text('Filter Products', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setD(() => draft.reset()),
                    child: Text('Reset All', style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 13)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                    padding: EdgeInsets.zero,
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  _filterDropdown(label: 'Category', icon: Icons.category_rounded, value: draft.category, items: _categories, onChanged: (v) => setD(() => draft.category = v!)),
                  const SizedBox(height: 14),
                  _filterDropdown(label: 'Stock Status', icon: Icons.layers_rounded, value: draft.status, items: _statuses, onChanged: (v) => setD(() => draft.status = v!)),
                  const SizedBox(height: 14),
                  _filterDropdown(label: 'Warehouse / Location', icon: Icons.warehouse_rounded, value: draft.warehouse, items: _warehouses, onChanged: (v) => setD(() => draft.warehouse = v!)),
                  const SizedBox(height: 14),
                  _dateRangeRow(ctx, draft, setD),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Cancel', style: GoogleFonts.poppins(color: AppColors.textTertiary)),
                  )),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: ElevatedButton(
                    onPressed: () { setState(() => _filters = draft); Navigator.pop(ctx); },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Apply Filters', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                  )),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _filterDropdown({
    required String label, required IconData icon, required String value,
    required List<String> items, required ValueChanged<String?> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(children: [
      Icon(icon, color: AppColors.textDisabled, size: 18),
      const SizedBox(width: 10),
      Expanded(child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true,
          dropdownColor: AppColors.surface,
          style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textTertiary),
          items: items.map((s) => DropdownMenuItem(
            value: s,
            child: Text(s, style: GoogleFonts.poppins(color: s == 'All' ? AppColors.textTertiary : AppColors.textPrimary, fontSize: 14)),
          )).toList(),
          onChanged: onChanged,
        ),
      )),
    ]),
  );

  Widget _dateRangeRow(BuildContext ctx, _FilterState draft, StateSetter setD) {
    String fmt(DateTime? d) => d == null ? 'Any' : '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.date_range_rounded, color: AppColors.textDisabled, size: 18),
          const SizedBox(width: 8),
          Text('Date Added Range', style: GoogleFonts.poppins(color: AppColors.textTertiary, fontSize: 13)),
          const Spacer(),
          if (draft.dateFrom != null || draft.dateTo != null)
            GestureDetector(
              onTap: () => setD(() { draft.dateFrom = null; draft.dateTo = null; }),
              child: Text('Clear', style: GoogleFonts.poppins(color: AppColors.primary, fontSize: 12)),
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _datePill(label: 'From', value: fmt(draft.dateFrom), onTap: () async {
            final d = await showDatePicker(
              context: ctx, initialDate: draft.dateFrom ?? DateTime.now(),
              firstDate: DateTime(2020), lastDate: DateTime.now(),
              builder: (ctx, child) => Theme(
                data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.primary)),
                child: child!,
              ),
            );
            if (d != null) setD(() => draft.dateFrom = d);
          })),
          const SizedBox(width: 10),
          Expanded(child: _datePill(label: 'To', value: fmt(draft.dateTo), onTap: () async {
            final d = await showDatePicker(
              context: ctx, initialDate: draft.dateTo ?? DateTime.now(),
              firstDate: DateTime(2020), lastDate: DateTime.now(),
              builder: (ctx, child) => Theme(
                data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.primary)),
                child: child!,
              ),
            );
            if (d != null) setD(() => draft.dateTo = d);
          })),
        ]),
      ]),
    );
  }

  Widget _datePill({required String label, required String value, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.poppins(color: AppColors.textDisabled, fontSize: 10)),
              Text(value, style: GoogleFonts.poppins(
                color: value == 'Any' ? AppColors.textDisabled : AppColors.textPrimary,
                fontSize: 13, fontWeight: value == 'Any' ? FontWeight.w400 : FontWeight.w600)),
            ])),
            const Icon(Icons.calendar_today_rounded, color: AppColors.primary, size: 14),
          ]),
        ),
      );

  Widget _imagePickerField({
    required File? pickedFile,
    required String existingImageUrl,
    required bool uploading,
    required VoidCallback onPick,
  }) {
    return GestureDetector(
      onTap: uploading ? null : onPick,
      child: Container(
        height: 140,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, style: BorderStyle.solid),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (pickedFile != null)
              Image.file(pickedFile, fit: BoxFit.cover)
            else if (existingImageUrl.isNotEmpty)
              Image.network(
                existingImageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (ctx, child, progress) =>
                    progress == null ? child : const Center(
                      child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                    ),
                errorBuilder: (ctx, err, st) => const Center(
                  child: Icon(Icons.broken_image_rounded, color: AppColors.textFaint, size: 32),
                ),
              )
            else
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_photo_alternate_rounded, color: AppColors.textDisabled, size: 32),
                  const SizedBox(height: 8),
                  Text('Tap to add product photo',
                      style: GoogleFonts.poppins(color: AppColors.textDisabled, fontSize: 12)),
                ],
              ),
            if (uploading)
              Container(
                color: Colors.black.withValues(alpha: .55),
                child: const Center(
                  child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2.5),
                ),
              ),
            if (!uploading && (pickedFile != null || existingImageUrl.isNotEmpty))
              Positioned(
                right: 8, top: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.edit_rounded, color: AppColors.textPrimary, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<File?> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  // ── NEW: Discount % field shared by Add/Edit dialogs ────────────────────
  Widget _discountField(TextEditingController discountCtrl) => TextFormField(
    controller: discountCtrl,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    validator: (v) {
      final t = v?.trim() ?? '';
      if (t.isEmpty) return null;
      final n = double.tryParse(t);
      if (n == null) return 'Must be a number';
      if (n < 0 || n >= 100) return 'Must be between 0\u201399';
      return null;
    },
    autovalidateMode: AutovalidateMode.onUserInteraction,
    style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
    decoration: InputDecoration(
      labelText: 'Discount % (optional)',
      hintText: 'e.g. 20',
      labelStyle: GoogleFonts.poppins(color: AppColors.textTertiary, fontSize: 13),
      hintStyle: GoogleFonts.poppins(color: AppColors.textFaint, fontSize: 13),
      errorStyle: GoogleFonts.poppins(color: AppColors.danger, fontSize: 11),
      prefixIcon: const Icon(Icons.local_offer_outlined, color: AppColors.textDisabled, size: 20),
      suffixText: '%',
      suffixStyle: GoogleFonts.poppins(color: AppColors.textDisabled, fontSize: 13),
      filled: true, fillColor: AppColors.surfaceRaised,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white12)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
    ),
  );

  double _computeOriginalPrice(double price, double discountPercent) {
    if (discountPercent <= 0) return 0;
    return price / (1 - discountPercent / 100);
  }

  void _showAddDialog() {
    final formKey      = GlobalKey<FormState>();
    final nameCtrl      = TextEditingController();
    final tagCtrl        = TextEditingController();
    final priceCtrl     = TextEditingController();
    final stockCtrl      = TextEditingController();
    final descCtrl       = TextEditingController();
    final discountCtrl   = TextEditingController();
    String selCategory  = 'Shirts';
    String selWarehouse = 'Main Warehouse';
    bool   loading   = false;
    bool   uploadingImage = false;
    File?  pickedImage;
    String errorMsg  = '';

    final tagRegex = RegExp(r'^[A-Za-z0-9\-]+$');

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                _handle(),
                const SizedBox(height: 20),
                _sheetHeader('Add New Product', Icons.add_box_rounded, AppColors.primary, AppColors.primaryDeep),
                const SizedBox(height: 24),
                _imagePickerField(
                  pickedFile: pickedImage,
                  existingImageUrl: '',
                  uploading: uploadingImage,
                  onPick: () async {
                    final file = await _pickImage();
                    if (file != null) setM(() => pickedImage = file);
                  },
                ),
                const SizedBox(height: 14),
                _formField(nameCtrl, 'Product Name *', Icons.inventory_2_outlined,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Product name is required' : null),
                const SizedBox(height: 14),
                _formField(tagCtrl, 'Tag Number (auto if blank)', Icons.tag_rounded, hint: 'e.g. FF-0042',
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isNotEmpty && !tagRegex.hasMatch(t)) return 'Only letters, digits, and hyphens allowed';
                    return null;
                  }),
                const SizedBox(height: 6),
                Padding(padding: const EdgeInsets.only(left: 4),
                  child: Text('Leave blank to auto-generate a unique tag', style: GoogleFonts.poppins(color: AppColors.textDisabled, fontSize: 11))),
                const SizedBox(height: 14),
                _labeledDropdown('Category', Icons.category_rounded, selCategory, _categories.where((c) => c != 'All').toList(), (v) => setM(() => selCategory = v!)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _formField(priceCtrl, 'Price (Rs.) *', Icons.attach_money_rounded, isNumber: true,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      final n = double.tryParse(v.trim());
                      if (n == null) return 'Must be a number';
                      if (n <= 0)    return 'Must be > 0';
                      return null;
                    })),
                  const SizedBox(width: 12),
                  Expanded(child: _formField(stockCtrl, 'Stock Qty *', Icons.numbers_rounded, isNumber: true,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      final n = int.tryParse(v.trim());
                      if (n == null) return 'Must be a whole number';
                      if (n < 0)    return 'Must be \u2265 0';
                      return null;
                    })),
                ]),
                const SizedBox(height: 14),
                _discountField(discountCtrl),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: discountCtrl,
                  builder: (ctx, _, __) {
                    final disc  = double.tryParse(discountCtrl.text.trim()) ?? 0;
                    final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
                    if (disc <= 0 || price <= 0) return const SizedBox.shrink();
                    final orig = _computeOriginalPrice(price, disc);
                    return Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        'Original price will show as Rs. ${orig.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(color: AppColors.warning, fontSize: 11),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _labeledDropdown('Warehouse / Location', Icons.warehouse_rounded, selWarehouse, _warehouses.where((w) => w != 'All').toList(), (v) => setM(() => selWarehouse = v!)),
                const SizedBox(height: 14),
                _formField(descCtrl, 'Description (optional)', Icons.notes_rounded, maxLines: 2),
                if (errorMsg.isNotEmpty) ...[const SizedBox(height: 12), _errorBanner(errorMsg)],
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: (loading || uploadingImage) ? null : () async {
                    if (!formKey.currentState!.validate()) return;
                    setM(() { loading = true; errorMsg = ''; });
                    try {
                      final tag = tagCtrl.text.trim().toUpperCase();
                      if (tag.isNotEmpty) {
                        final unique = await _fs.isTagNumberUnique(tag);
                        if (!unique) { setM(() { loading = false; errorMsg = 'Tag "$tag" is already in use.'; }); return; }
                      }

                      String uploadedUrl = '';
                      if (pickedImage != null) {
                        setM(() => uploadingImage = true);
                        uploadedUrl = await _cloudinary.uploadImage(pickedImage!);
                        setM(() => uploadingImage = false);
                      }

                      final sellPrice = double.tryParse(priceCtrl.text) ?? 0;
                      final discount  = double.tryParse(discountCtrl.text.trim()) ?? 0;
                      final origPrice = _computeOriginalPrice(sellPrice, discount);

                      final product = ProductModel(
                        id: '', tagNumber: tag, name: nameCtrl.text.trim(),
                        category: selCategory, price: sellPrice,
                        stock: int.tryParse(stockCtrl.text) ?? 0,
                        description: descCtrl.text.trim(), warehouse: selWarehouse,
                        imageUrl: uploadedUrl,
                        discountPercent: discount,
                        originalPrice: origPrice,
                      );
                      final assignedTag = await _fs.addProduct(product, actorUid: _actorUid, actorName: _actorName);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Row(children: [
                            const Icon(Icons.check_circle_rounded, color: AppColors.textPrimary, size: 18),
                            const SizedBox(width: 8),
                            Text('Product added! Tag: $assignedTag', style: GoogleFonts.poppins(color: AppColors.textPrimary)),
                          ]),
                          backgroundColor: AppColors.teal,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ));
                      }
                    } catch (e) {
                      setM(() { loading = false; uploadingImage = false; errorMsg = '$e'.replaceFirst('Exception: ', ''); });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2.5))
                      : Text('Add Product', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary)),
                )),
                const SizedBox(height: 8),
              ])),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditDialog(ProductModel product) {
    final formKey      = GlobalKey<FormState>();
    final nameCtrl      = TextEditingController(text: product.name);
    final tagCtrl        = TextEditingController(text: product.tagNumber);
    final priceCtrl     = TextEditingController(text: product.price.toStringAsFixed(0));
    final stockCtrl      = TextEditingController(text: product.stock.toString());
    final descCtrl       = TextEditingController(text: product.description);
    final discountCtrl   = TextEditingController(
        text: product.discountPercent > 0 ? product.discountPercent.toStringAsFixed(0) : '');
    String selCategory  = product.category;
    String selWarehouse = product.warehouse;
    bool   loading   = false;
    bool   uploadingImage = false;
    File?  pickedImage;
    String currentImageUrl = product.imageUrl;
    String errorMsg  = '';

    final tagRegex = RegExp(r'^[A-Za-z0-9\-]+$');

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                _handle(),
                const SizedBox(height: 20),
                _sheetHeader('Edit Product', Icons.edit_rounded, AppColors.teal, AppColors.tealLight),
                const SizedBox(height: 24),
                _imagePickerField(
                  pickedFile: pickedImage,
                  existingImageUrl: currentImageUrl,
                  uploading: uploadingImage,
                  onPick: () async {
                    final file = await _pickImage();
                    if (file != null) setM(() => pickedImage = file);
                  },
                ),
                const SizedBox(height: 14),
                _formField(nameCtrl, 'Product Name *', Icons.inventory_2_outlined,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Product name is required' : null),
                const SizedBox(height: 14),
                _formField(tagCtrl, 'Tag Number', Icons.tag_rounded,
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isNotEmpty && !tagRegex.hasMatch(t)) return 'Only letters, digits, and hyphens allowed';
                    return null;
                  }),
                const SizedBox(height: 6),
                Padding(padding: const EdgeInsets.only(left: 4),
                  child: Text('Original: ${product.tagNumber}', style: GoogleFonts.poppins(color: AppColors.textDisabled, fontSize: 11))),
                const SizedBox(height: 14),
                _labeledDropdown('Category', Icons.category_rounded, selCategory, _categories.where((c) => c != 'All').toList(), (v) => setM(() => selCategory = v!)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _formField(priceCtrl, 'Price (Rs.) *', Icons.attach_money_rounded, isNumber: true,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      final n = double.tryParse(v.trim());
                      if (n == null) return 'Must be a number';
                      if (n <= 0)    return 'Must be > 0';
                      return null;
                    })),
                  const SizedBox(width: 12),
                  Expanded(child: _formField(stockCtrl, 'Stock Qty *', Icons.numbers_rounded, isNumber: true,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      final n = int.tryParse(v.trim());
                      if (n == null) return 'Must be a whole number';
                      if (n < 0)    return 'Must be \u2265 0';
                      return null;
                    })),
                ]),
                const SizedBox(height: 14),
                _discountField(discountCtrl),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: discountCtrl,
                  builder: (ctx, _, __) {
                    final disc  = double.tryParse(discountCtrl.text.trim()) ?? 0;
                    final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
                    if (disc <= 0 || price <= 0) return const SizedBox.shrink();
                    final orig = _computeOriginalPrice(price, disc);
                    return Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        'Original price will show as Rs. ${orig.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(color: AppColors.warning, fontSize: 11),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _labeledDropdown('Warehouse / Location', Icons.warehouse_rounded, selWarehouse, _warehouses.where((w) => w != 'All').toList(), (v) => setM(() => selWarehouse = v!)),
                const SizedBox(height: 14),
                _formField(descCtrl, 'Description (optional)', Icons.notes_rounded, maxLines: 2),
                if (errorMsg.isNotEmpty) ...[const SizedBox(height: 12), _errorBanner(errorMsg)],
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Cancel', style: GoogleFonts.poppins(color: AppColors.textTertiary)),
                  )),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: ElevatedButton(
                    onPressed: (loading || uploadingImage) ? null : () async {
                      if (!formKey.currentState!.validate()) return;
                      setM(() { loading = true; errorMsg = ''; });
                      try {
                        String finalImageUrl = currentImageUrl;
                        if (pickedImage != null) {
                          setM(() => uploadingImage = true);
                          finalImageUrl = await _cloudinary.uploadImage(pickedImage!);
                          setM(() => uploadingImage = false);
                        }

                        final newTag = tagCtrl.text.trim().toUpperCase();
                        final sellPrice = double.tryParse(priceCtrl.text) ?? product.price;
                        final discount  = double.tryParse(discountCtrl.text.trim()) ?? 0;
                        final origPrice = _computeOriginalPrice(sellPrice, discount);

                        final updated = product.copyWith(
                          name: nameCtrl.text.trim(),
                          tagNumber: newTag.isEmpty ? product.tagNumber : newTag,
                          category: selCategory,
                          price: sellPrice,
                          stock: int.tryParse(stockCtrl.text) ?? product.stock,
                          description: descCtrl.text.trim(),
                          warehouse: selWarehouse,
                          imageUrl: finalImageUrl,
                          discountPercent: discount,
                          originalPrice: origPrice,
                        );
                        await _fs.updateProduct(updated, actorUid: _actorUid, actorName: _actorName, previous: product);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setM(() { loading = false; uploadingImage = false; errorMsg = '$e'.replaceFirst('Exception: ', ''); });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.teal,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                        : Text('Save Changes', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  )),
                ]),
                const SizedBox(height: 8),
              ])),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(ProductModel product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Product', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        content: RichText(
          text: TextSpan(
            style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 14),
            children: [
              const TextSpan(text: 'Delete '),
              TextSpan(text: product.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              TextSpan(text: '  (${product.tagNumber})', style: const TextStyle(color: AppColors.primary)),
              const TextSpan(text: '? This cannot be undone.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.poppins(color: AppColors.textTertiary))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _fs.deleteProduct(product.id, actorUid: _actorUid, actorName: _actorName, productName: product.name);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _migrationBanner(int untagged) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: .4)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(
          '$untagged product${untagged == 1 ? '' : 's'} without a Tag Number. Run migration to assign tags.',
          style: GoogleFonts.poppins(color: AppColors.warning, fontSize: 12),
        )),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _migrating ? null : _runMigration,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(8)),
            child: _migrating
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2))
                : Text('Fix Now', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Future<void> _runMigration() async {
    setState(() => _migrating = true);
    try {
      final count = await _fs.migrateProductTags();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Migration complete — $count products updated.', style: GoogleFonts.poppins(color: AppColors.textPrimary)),
          backgroundColor: AppColors.teal, behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Migration failed: $e', style: GoogleFonts.poppins(color: AppColors.textPrimary)),
          backgroundColor: AppColors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            expandedHeight: 130, pinned: true, floating: false,
            backgroundColor: AppColors.background, elevation: 0,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Inventory', style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text('Manage your products', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textTertiary)),
                  ]),
                  StreamBuilder<List<ProductModel>>(
                    stream: _fs.getProducts(),
                    builder: (ctx, snap) {
                      final n = snap.data?.length ?? 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(gradient: AppGradients.primary, borderRadius: BorderRadius.circular(20)),
                        child: Text('$n Products', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                      );
                    },
                  ),
                ]),
              )),
            ),
          ),
        ],
        body: StreamBuilder<List<ProductModel>>(
          stream: _fs.getProducts(),
          builder: (ctx, snap) {
            final allProducts = snap.data ?? [];
            final untagged = allProducts.where((p) => p.tagNumber.contains('?')).length;
            final filtered = _apply(allProducts);
            return Column(children: [
              if (untagged > 0) _migrationBanner(untagged),
              Container(
                color: AppColors.background,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(children: [
                  Expanded(child: Container(
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                    child: TextField(
                      controller: _searchCtrl,
                      style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Search name, tag, category…',
                        hintStyle: GoogleFonts.poppins(color: AppColors.textDisabled, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textDisabled),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, color: AppColors.textDisabled, size: 18),
                                onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); })
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  )),
                  const SizedBox(width: 10),
                  Stack(children: [
                    GestureDetector(
                      onTap: _openFilterDialog,
                      child: Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: _filters.hasActiveFilters ? AppColors.primary.withValues(alpha: .2) : AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _filters.hasActiveFilters ? AppColors.primary : AppColors.border),
                        ),
                        child: Icon(Icons.tune_rounded, color: _filters.hasActiveFilters ? AppColors.primary : AppColors.textTertiary, size: 22),
                      ),
                    ),
                    if (_filters.activeCount > 0)
                      Positioned(right: 2, top: 2, child: Container(
                        width: 16, height: 16,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        child: Center(child: Text('${_filters.activeCount}', style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 9, fontWeight: FontWeight.w700))),
                      )),
                  ]),
                ]),
              ),
              if (_filters.hasActiveFilters) _activeFilterSummary(),
              Expanded(child: _buildList(snap, filtered)),
            ]);
          },
        ),
      ),
      floatingActionButton: ScaleTransition(
        scale: CurvedAnimation(parent: _fabAnim, curve: Curves.elasticOut),
        child: FloatingActionButton.extended(
          onPressed: _showAddDialog,
          backgroundColor: AppColors.primary,
          icon: const Icon(Icons.add_rounded, color: AppColors.textPrimary),
          label: Text('Add Product', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ),
      ),
    );
  }

  Widget _activeFilterSummary() {
    final chips = <Widget>[];
    void addChip(String label, VoidCallback clear) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: clear,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withValues(alpha: .5)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: GoogleFonts.poppins(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              const Icon(Icons.close_rounded, color: AppColors.primary, size: 12),
            ]),
          ),
        ),
      ));
    }
    if (_filters.category  != 'All') addChip(_filters.category,  () => setState(() => _filters.category  = 'All'));
    if (_filters.status    != 'All') addChip(_filters.status,    () => setState(() => _filters.status    = 'All'));
    if (_filters.warehouse != 'All') addChip(_filters.warehouse, () => setState(() => _filters.warehouse = 'All'));
    if (_filters.dateFrom  != null || _filters.dateTo != null) {
      addChip('Date Range', () => setState(() { _filters.dateFrom = null; _filters.dateTo = null; }));
    }
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(children: [
        Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: chips))),
        TextButton(
          onPressed: () => setState(() => _filters.reset()),
          child: Text('Clear All', style: GoogleFonts.poppins(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _buildList(AsyncSnapshot<List<ProductModel>> snap, List<ProductModel> filtered) {
    if (snap.connectionState == ConnectionState.waiting) {
      return const SingleChildScrollView(
        padding: EdgeInsets.only(top: 8, bottom: 100),
        child: SkeletonListView(count: 6),
      );
    }
    if (!snap.hasData || snap.data!.isEmpty) return _emptyState();
    if (filtered.isEmpty) return _noResultsState();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) => _productCard(filtered[i], i),
    );
  }

  Widget _productCard(ProductModel p, int index) {
    final isLow = p.stock > 0 && p.stock < 10;
    final isOut = p.stock == 0;
    final color = isOut ? AppColors.danger : isLow ? AppColors.warning : AppColors.tealLight;
    final label = isOut ? 'Out of Stock' : isLow ? 'Low Stock' : 'In Stock';

    return AnimatedContainer(
      duration: Duration(milliseconds: 80 + index * 20),
      margin: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isOut ? AppColors.danger.withValues(alpha: .3)
                : isLow ? AppColors.warning.withValues(alpha: .3)
                : Colors.white.withValues(alpha: .06),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            _productThumbnail(p),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(p.name, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (p.hasDiscount) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)),
                    child: Text('${p.discountPercent.toStringAsFixed(0)}% OFF', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.danger)),
                  ),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(8)),
                  child: Text(label, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
                ),
              ]),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: p.tagNumber));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Tag ${p.tagNumber} copied', style: GoogleFonts.poppins(color: AppColors.textPrimary)),
                    backgroundColor: AppColors.primary, duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ));
                },
                child: Row(children: [
                  const Icon(Icons.tag_rounded, color: AppColors.primary, size: 13),
                  const SizedBox(width: 3),
                  Text(p.tagNumber, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  const Icon(Icons.copy_rounded, color: AppColors.primary, size: 11),
                ]),
              ),
              const SizedBox(height: 4),
              Row(children: [
                _pill(p.category, AppColors.surfaceRaised, AppColors.textTertiary),
                const SizedBox(width: 6),
                _pill(p.warehouse, AppColors.surfaceRaised, AppColors.textDisabled),
                const SizedBox(width: 6),
                Text('${p.stock} units', style: GoogleFonts.poppins(fontSize: 11, color: color)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Text('Rs. ${p.price.toStringAsFixed(0)}', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
                if (p.hasDiscount) ...[
                  const SizedBox(width: 8),
                  Text('Rs. ${p.originalPrice.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textDisabled, decoration: TextDecoration.lineThrough)),
                ],
              ]),
            ])),
            Column(children: [
              _actionBtn(Icons.edit_rounded, AppColors.teal, () => _showEditDialog(p)),
              const SizedBox(height: 8),
              _actionBtn(Icons.delete_outline_rounded, AppColors.danger, () => _confirmDelete(p)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _productThumbnail(ProductModel p) {
    if (p.imageUrl.isEmpty) {
      return Container(
        width: 54, height: 54,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: .25), AppColors.primaryDeep.withValues(alpha: .15)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(_catIcon(p.category), color: AppColors.primary, size: 26),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        p.imageUrl,
        width: 54, height: 54,
        fit: BoxFit.cover,
        loadingBuilder: (ctx, child, progress) => progress == null
            ? child
            : Container(
                width: 54, height: 54,
                color: AppColors.surfaceRaised,
                child: const Center(
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                  ),
                ),
              ),
        errorBuilder: (ctx, err, st) => Container(
          width: 54, height: 54,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: .25), AppColors.primaryDeep.withValues(alpha: .15)]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(_catIcon(p.category), color: AppColors.primary, size: 26),
        ),
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: GoogleFonts.poppins(fontSize: 10, color: fg), overflow: TextOverflow.ellipsis),
  );

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
      );

  Widget _handle() => Center(child: Container(
    width: 40, height: 4,
    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
  ));

  Widget _sheetHeader(String title, IconData icon, Color c1, Color c2) =>
      Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [c1, c2]), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: AppColors.textPrimary, size: 20),
        ),
        const SizedBox(width: 12),
        Text(title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ]);

  Widget _formField(
    TextEditingController c,
    String label,
    IconData icon, {
    bool isNumber = false,
    int maxLines = 1,
    String? hint,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: c,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label, hintText: hint,
          labelStyle: GoogleFonts.poppins(color: AppColors.textTertiary, fontSize: 13),
          hintStyle: GoogleFonts.poppins(color: AppColors.textFaint, fontSize: 13),
          errorStyle: GoogleFonts.poppins(color: AppColors.danger, fontSize: 11),
          prefixIcon: Icon(icon, color: AppColors.textDisabled, size: 20),
          filled: true, fillColor: AppColors.surfaceRaised,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white12)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
        ),
      );

  Widget _labeledDropdown(String label, IconData icon, String value, List<String> items, ValueChanged<String?> onChanged) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Icon(icon, color: AppColors.textDisabled, size: 18),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value, isExpanded: true,
              dropdownColor: AppColors.surface,
              style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textTertiary),
              items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: onChanged,
            ),
          )),
        ]),
      );

  Widget _errorBanner(String msg) => Container(
    width: double.infinity, padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.danger.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.danger.withValues(alpha: .4)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(msg, style: GoogleFonts.poppins(color: AppColors.danger, fontSize: 12))),
    ]),
  );

  Widget _emptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
      child: const Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 48)),
    const SizedBox(height: 16),
    Text('No Products Yet', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
    const SizedBox(height: 8),
    Text('Tap + to add your first product', style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textDisabled)),
  ]));

  Widget _noResultsState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.search_off_rounded, color: AppColors.primary, size: 56),
    const SizedBox(height: 16),
    Text('No Results Found', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
    const SizedBox(height: 8),
    Text('Try a different search or filter', style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textDisabled)),
    const SizedBox(height: 16),
    TextButton(
      onPressed: () { _searchCtrl.clear(); setState(() { _searchQuery = ''; _filters.reset(); }); },
      child: Text('Clear All Filters', style: GoogleFonts.poppins(color: AppColors.primary, fontWeight: FontWeight.w600)),
    ),
  ]));

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