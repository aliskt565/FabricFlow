import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/customer_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/skeletons.dart';
import 'customer_insights_screen.dart';

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key});
  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  final FirestoreService _fs = FirestoreService();

  // ── Activity log actor identity ─────────────────────────────────────────
  String get _actorUid  => FirebaseAuth.instance.currentUser?.uid   ?? '';
  String get _actorName => FirebaseAuth.instance.currentUser?.email ?? 'Unknown';
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  List<CustomerModel> _filter(List<CustomerModel> list) {
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((c) =>
        c.name.toLowerCase().contains(q) ||
        c.email.toLowerCase().contains(q) ||
        c.phone.toLowerCase().contains(q)).toList();
  }

  // ── Add customer dialog ──────────────────────────────────────────────────
  void _showAddDialog() {
    final formKey     = GlobalKey<FormState>();
    final nameCtrl    = TextEditingController();
    final emailCtrl   = TextEditingController();
    final phoneCtrl   = TextEditingController();
    final addressCtrl = TextEditingController();
    bool isSubmitting = false;

    // RFC 5322-lite email check — sufficient for UX validation.
    final emailRegex = RegExp(r'^[\w.+\-]+@[a-zA-Z\d\-]+\.[a-zA-Z\d.\-]+$');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.textFaint,
                          borderRadius: AppRadius.handleRadius),
                    )),
                    const SizedBox(height: 20),
                    // Header
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: AppGradients.success,
                          borderRadius: AppRadius.mdRadius,
                        ),
                        child: const Icon(Icons.person_add_rounded,
                            color: AppColors.textPrimary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text('Add New Customer', style: AppText.title()),
                    ]),
                    const SizedBox(height: 24),
                    _formField(nameCtrl, 'Full Name *', Icons.person_outline_rounded,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Name is required';
                        if (v.trim().length < 2) return 'Name must be at least 2 characters';
                        return null;
                      }),
                    const SizedBox(height: 14),
                    _formField(emailCtrl, 'Email Address *', Icons.email_outlined,
                      type: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        if (!emailRegex.hasMatch(v.trim())) return 'Enter a valid email address';
                        return null;
                      }),
                    const SizedBox(height: 14),
                    _formField(phoneCtrl, 'Phone Number', Icons.phone_outlined,
                      type: TextInputType.phone,
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isNotEmpty && t.replaceAll(RegExp(r'[^0-9]'), '').length < 7) {
                          return 'Phone must have at least 7 digits';
                        }
                        return null;
                      }),
                    const SizedBox(height: 14),
                    _formField(addressCtrl, 'Address', Icons.location_on_outlined,
                        maxLines: 2),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setM(() => isSubmitting = true);
                                Navigator.pop(ctx);
                                await _fs.addCustomer(CustomerModel(
                                  id: '',
                                  name:    nameCtrl.text.trim(),
                                  email:   emailCtrl.text.trim(),
                                  phone:   phoneCtrl.text.trim(),
                                  address: addressCtrl.text.trim(),
                                ));
                              },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: AppColors.teal,
                          shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.lgRadius),
                        ),
                        child: isSubmitting
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    color: AppColors.textPrimary, strokeWidth: 2))
                            : Text('Add Customer',
                                style: AppText.buttonLabel().copyWith(fontSize: 15)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Customer detail sheet ────────────────────────────────────────────────
  void _showDetail(CustomerModel c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.textFaint,
                    borderRadius: AppRadius.handleRadius),
              ),
              const SizedBox(height: 24),
              // Avatar
              Container(
                width: 70, height: 70,
                decoration: const BoxDecoration(
                  gradient: AppGradients.success,
                  shape: BoxShape.circle,
                ),
                child: Center(child: Text(
                  c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                  style: AppText.headline().copyWith(fontSize: 26),
                )),
              ),
              const SizedBox(height: 14),
              Text(c.name, style: AppText.headline().copyWith(fontSize: 20)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: .15),
                  borderRadius: AppRadius.smRadius,
                ),
                child: Text('Customer',
                    style: AppText.caption(color: AppColors.success).copyWith(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 24),
              _detailRow(Icons.email_outlined,       'Email',   c.email),
              const SizedBox(height: 10),
              _detailRow(Icons.phone_outlined,       'Phone',   c.phone.isEmpty ? 'N/A' : c.phone),
              const SizedBox(height: 10),
              _detailRow(Icons.location_on_outlined, 'Address', c.address.isEmpty ? 'N/A' : c.address),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CustomerInsightsScreen(customer: c),
                    ));
                  },
                  icon: const Icon(Icons.insights_rounded, color: AppColors.textPrimary),
                  label: Text('View Insights', style: AppText.buttonLabel()),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
                  ),
                ),
              ),
                const SizedBox(height: 10),
              // Delete button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmDelete(c);
                  },
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger),
                  label: Text('Remove Customer',
                      style: AppText.buttonLabel(color: AppColors.danger)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.danger),
                    shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.lgRadius),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(CustomerModel c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlRadius),
        title: Text('Remove Customer', style: AppText.title()),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remove "${c.name}" from customers?',
                style: AppText.body(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text('Their login access will also be revoked.',
                style: AppText.caption(color: AppColors.danger)),
          ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppText.body(color: AppColors.textTertiary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // deleteCustomer in FirestoreService already removes
              // both the customers/ doc and the users/ role doc
              await _fs.deleteCustomer(
                c.id,
                actorUid:     _actorUid,
                actorName:    _actorName,
                customerName: c.name,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${c.name} removed', style: AppText.body()),
                  backgroundColor: AppColors.danger,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.mdRadius),
                ));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.smRadius),
            ),
            child: Text('Remove', style: AppText.buttonLabel()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            floating: false,
            backgroundColor: AppColors.background,
            elevation: 0,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Customers', style: AppText.headline()),
                          Text('Manage your customers',
                              style: AppText.caption(color: AppColors.textTertiary).copyWith(fontSize: 13)),
                        ],
                      ),
                      StreamBuilder<List<CustomerModel>>(
                        stream: _fs.getCustomers(),
                        builder: (ctx, snap) {
                          final count = snap.data?.length ?? 0;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: AppGradients.success,
                              borderRadius: AppRadius.xlRadius,
                            ),
                            child: Text('$count Customers',
                                style: AppText.buttonLabel().copyWith(fontSize: 13)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        body: Column(
          children: [
            // Search bar
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.lgRadius,
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: AppText.body(),
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search by name, email or phone...',
                    hintStyle: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 13),
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
              ),
            ),

            // List
            Expanded(
              child: StreamBuilder<List<CustomerModel>>(
                stream: _fs.getCustomers(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SingleChildScrollView(
                      padding: EdgeInsets.only(top: 8, bottom: 100),
                      child: SkeletonListView(count: 5),
                    );
                  }
                  if (!snap.hasData || snap.data!.isEmpty) {
                    return _empty();
                  }
                  final list = _filter(snap.data!);
                  if (list.isEmpty) return _noResults();

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: list.length,
                    itemBuilder: (ctx, i) => _card(list[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: AppColors.teal,
        icon: const Icon(Icons.person_add_rounded, color: AppColors.textPrimary),
        label: Text('Add Customer', style: AppText.buttonLabel()),
      ),
    );
  }

  // ── Customer card ────────────────────────────────────────────────────────
  Widget _card(CustomerModel c) {
    return GestureDetector(
      onTap: () => _showDetail(c),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.xlRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .06)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            // Avatar circle
            Container(
              width: 52, height: 52,
              decoration: const BoxDecoration(
                gradient: AppGradients.success,
                shape: BoxShape.circle,
              ),
              child: Center(child: Text(
                c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                style: AppText.title().copyWith(fontSize: 20),
              )),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(c.name,
                        style: AppText.body().copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: .12),
                        borderRadius: AppRadius.smRadius,
                      ),
                      child: Text('Customer',
                          style: AppText.badge(color: AppColors.success).copyWith(fontSize: 10)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.email_outlined,
                        color: AppColors.textDisabled, size: 12),
                    const SizedBox(width: 4),
                    Expanded(child: Text(c.email,
                        style: AppText.caption(color: AppColors.textTertiary),
                        overflow: TextOverflow.ellipsis)),
                  ]),
                  if (c.phone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.phone_outlined,
                          color: AppColors.textDisabled, size: 12),
                      const SizedBox(width: 4),
                      Text(c.phone, style: AppText.caption(color: AppColors.textTertiary)),
                    ]),
                  ],
                  if (c.address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.location_on_outlined,
                          color: AppColors.textDisabled, size: 12),
                      const SizedBox(width: 4),
                      Expanded(child: Text(c.address,
                          style: AppText.caption(color: AppColors.textTertiary),
                          overflow: TextOverflow.ellipsis)),
                    ]),
                  ],
                ],
              ),
            ),

            // Chevron
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textFaint, size: 20),
          ]),
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// [TextFormField] with inline validation — used inside the Add dialog [Form].
  Widget _formField(
    TextEditingController c,
    String label,
    IconData icon, {
    TextInputType type = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: c,
        keyboardType: type,
        maxLines: maxLines,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        style: AppText.body(),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppText.caption(color: AppColors.textTertiary).copyWith(fontSize: 13),
          errorStyle: AppText.caption(color: AppColors.danger).copyWith(fontSize: 11),
          prefixIcon: Icon(icon, color: AppColors.textDisabled, size: 20),
          filled: true,
          fillColor: AppColors.surfaceRaised,
          border: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: const BorderSide(color: AppColors.teal, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
          focusedErrorBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
        ),
      );

  Widget _detailRow(IconData icon, String label, String value) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: AppRadius.lgRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .06)),
        ),
        child: Row(children: [
          Icon(icon, color: AppColors.teal, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 11)),
              const SizedBox(height: 2),
              Text(value, style: AppText.body().copyWith(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          )),
        ]),
      );

  Widget _empty() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
            color: AppColors.surface, shape: BoxShape.circle),
        child: const Icon(Icons.people_outline,
            color: AppColors.teal, size: 48),
      ),
      const SizedBox(height: 16),
      Text('No Customers Yet', style: AppText.title().copyWith(fontSize: 18)),
      const SizedBox(height: 8),
      Text('Tap + to add your first customer',
          style: AppText.body(color: AppColors.textDisabled)),
    ]),
  );

  Widget _noResults() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.person_search_rounded,
          color: AppColors.teal, size: 56),
      const SizedBox(height: 16),
      Text('No Results Found', style: AppText.title().copyWith(fontSize: 18)),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () {
          _searchCtrl.clear();
          setState(() => _searchQuery = '');
        },
        child: Text('Clear Search', style: AppText.buttonLabel(color: AppColors.teal)),
      ),
    ]),
  );
}