import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/employee_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/skeletons.dart';

class EmployeeScreen extends StatefulWidget {
  const EmployeeScreen({super.key});
  @override
  State<EmployeeScreen> createState() => _EmployeeScreenState();
}

class _EmployeeScreenState extends State<EmployeeScreen> {
  final FirestoreService _fs = FirestoreService();

  // ── Activity log actor identity ─────────────────────────────────────────
  String get _actorUid  => FirebaseAuth.instance.currentUser?.uid   ?? '';
  String get _actorName => FirebaseAuth.instance.currentUser?.email ?? 'Unknown';
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedRole = 'All';
  final List<String> _roles = ['All', 'Manager', 'Employee'];

  List<EmployeeModel> _filter(List<EmployeeModel> list) {
    return list.where((e) {
      final q = _searchQuery.toLowerCase();
      final matchSearch = _searchQuery.isEmpty ||
          e.name.toLowerCase().contains(q) ||
          e.email.toLowerCase().contains(q) ||
          e.phone.toLowerCase().contains(q);
      final matchRole = _selectedRole == 'All' || e.role == _selectedRole;
      return matchSearch && matchRole;
    }).toList();
  }

  void _showAddDialog() {
    final formKey    = GlobalKey<FormState>();
    final nameCtrl   = TextEditingController();
    final emailCtrl  = TextEditingController();
    final phoneCtrl  = TextEditingController();
    final salaryCtrl = TextEditingController();
    String role      = 'Employee';
    bool   loading   = false;

    // RFC 5322-lite email check
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
              child: SingleChildScrollView(child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: AppColors.textFaint,
                        borderRadius: AppRadius.handleRadius))),
                  const SizedBox(height: 20),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: AppGradients.manager,
                        borderRadius: AppRadius.mdRadius),
                      child: const Icon(Icons.person_add_rounded,
                          color: AppColors.textPrimary, size: 20)),
                    const SizedBox(width: 12),
                    Text('Add New Employee', style: AppText.title()),
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
                  _formField(salaryCtrl, 'Monthly Salary *', Icons.payments_outlined,
                    type: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Salary is required';
                      final n = double.tryParse(v.trim());
                      if (n == null) return 'Must be a number';
                      if (n <= 0) return 'Must be greater than 0';
                      return null;
                    }),
                  const SizedBox(height: 14),
                  // Role selector
                  Text('Role', style: AppText.caption(color: AppColors.textTertiary).copyWith(fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(children: ['Manager', 'Employee'].map((r) {
                    final sel = role == r;
                    return Expanded(child: GestureDetector(
                      onTap: () => setM(() => role = r),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: EdgeInsets.only(right: r == 'Manager' ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: sel
                              ? (r == 'Manager' ? AppGradients.manager : AppGradients.success)
                              : null,
                          color: sel ? null : AppColors.surfaceRaised,
                          borderRadius: AppRadius.mdRadius,
                          border: Border.all(color: sel
                              ? Colors.transparent : AppColors.border)),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(r == 'Manager'
                                ? Icons.manage_accounts_rounded
                                : Icons.badge_rounded,
                              color: sel ? AppColors.textPrimary : AppColors.textDisabled,
                              size: 18),
                            const SizedBox(width: 6),
                            Text(r, style: AppText.body(
                                color: sel ? AppColors.textPrimary : AppColors.textDisabled,
                              ).copyWith(fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
                          ],
                        ),
                      ),
                    ));
                  }).toList()),
                  const SizedBox(height: 24),
                  SizedBox(width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading ? null : () async {
                        if (!formKey.currentState!.validate()) return;
                        setM(() => loading = true);
                        Navigator.pop(ctx);
                        await _fs.addEmployee(EmployeeModel(
                          id: '', name: nameCtrl.text.trim(), role: role,
                          email: emailCtrl.text.trim(),
                          phone: phoneCtrl.text.trim(),
                          salary: salaryCtrl.text.trim(),
                        ));
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppColors.indigo,
                        shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.lgRadius)),
                      child: loading
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: AppColors.textPrimary, strokeWidth: 2))
                          : Text('Add Employee', style: AppText.buttonLabel().copyWith(fontSize: 15)),
                    )),
                  const SizedBox(height: 8),
                ],
              )),
            ),
          ),
        ),
      ),
    );
  }

  /// Delete employee document AND their users/ role so they lose access.
  Future<void> _deleteEmployee(EmployeeModel emp) async {
    // 1. Delete from employees collection
    await _fs.deleteEmployee(
      emp.id,
      actorUid:     _actorUid,
      actorName:    _actorName,
      employeeName: emp.name,
    );

    // 2. Try to find the users/ document by email and delete it too
    try {
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: emp.email)
          .limit(1)
          .get();
      for (final doc in usersSnap.docs) {
        await doc.reference.delete();
      }
    } catch (_) {
      // If users/ doc has no email field or doesn't exist, ignore
    }
  }

  void _confirmDelete(EmployeeModel emp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: AppRadius.xlRadius),
        title: Text('Remove Employee', style: AppText.title()),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remove ${emp.name} from the team?',
                style: AppText.body(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text('This will also revoke their login access.',
                style: AppText.caption(color: AppColors.danger)),
          ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppText.body(color: AppColors.textTertiary))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteEmployee(emp);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${emp.name} removed', style: AppText.body()),
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
                  borderRadius: AppRadius.smRadius)),
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
              background: SafeArea(child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Employees', style: AppText.headline()),
                        Text('Manage your team',
                            style: AppText.caption(color: AppColors.textTertiary).copyWith(fontSize: 13)),
                      ]),
                    StreamBuilder<List<EmployeeModel>>(
                      stream: _fs.getEmployees(),
                      builder: (ctx, snap) {
                        final n = snap.data?.length ?? 0;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: AppGradients.manager,
                            borderRadius: AppRadius.xlRadius),
                          child: Text('$n Members', style: AppText.buttonLabel().copyWith(fontSize: 13)),
                        );
                      },
                    ),
                  ],
                ),
              )),
            ),
          ),
        ],
        body: Column(children: [
          // Search + filter
          Container(
            color: AppColors.background,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.lgRadius,
                  border: Border.all(color: AppColors.border)),
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
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: _roles.map((r) {
                final sel = _selectedRole == r;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedRole = r),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: sel ? AppGradients.manager : null,
                        color: sel ? null : AppColors.surface,
                        borderRadius: AppRadius.xlRadius,
                        border: Border.all(color: sel
                            ? Colors.transparent : AppColors.border)),
                      child: Text(r, style: AppText.caption(
                          color: sel ? AppColors.textPrimary : AppColors.textTertiary,
                        ).copyWith(fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
                    ),
                  ),
                );
              }).toList()),
            ]),
          ),
          // List
          Expanded(child: StreamBuilder<List<EmployeeModel>>(
            stream: _fs.getEmployees(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SingleChildScrollView(
                  padding: EdgeInsets.only(top: 8, bottom: 100),
                  child: SkeletonListView(count: 4),
                );
              }
              if (!snap.hasData || snap.data!.isEmpty) return _empty();
              final list = _filter(snap.data!);
              if (list.isEmpty) return _noResults();
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                itemCount: list.length,
                itemBuilder: (ctx, i) => _card(list[i]),
              );
            },
          )),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: AppColors.indigo,
        icon: const Icon(Icons.person_add_rounded, color: AppColors.textPrimary),
        label: Text('Add Employee', style: AppText.buttonLabel()),
      ),
    );
  }

  Widget _card(EmployeeModel emp) {
    final isManager = emp.role == 'Manager';
    final color = isManager ? AppColors.indigo : AppColors.success;
    final gradient = isManager ? AppGradients.manager : AppGradients.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.xlRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .06))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          // Avatar
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              gradient: gradient,
              shape: BoxShape.circle),
            child: Center(child: Text(
              emp.name.isNotEmpty ? emp.name[0].toUpperCase() : '?',
              style: AppText.title().copyWith(fontSize: 20, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(emp.name,
                    style: AppText.body().copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .15),
                    borderRadius: AppRadius.smRadius),
                  child: Text(emp.role, style: AppText.badge(color: color).copyWith(fontSize: 11)),
                ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.email_outlined,
                    color: AppColors.textDisabled, size: 12),
                const SizedBox(width: 4),
                Expanded(child: Text(emp.email,
                    style: AppText.caption(color: AppColors.textTertiary),
                    overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.phone_outlined,
                    color: AppColors.textDisabled, size: 12),
                const SizedBox(width: 4),
                Text(emp.phone.isEmpty ? 'N/A' : emp.phone,
                    style: AppText.caption(color: AppColors.textTertiary)),
                const Spacer(),
                Text('Rs. ${emp.salary}/mo',
                    style: AppText.body(color: AppColors.success).copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ],
          )),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _confirmDelete(emp),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: .15),
                borderRadius: AppRadius.mdRadius),
              child: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger, size: 18)),
          ),
        ]),
      ),
    );
  }

  Widget _formField(
    TextEditingController c,
    String label,
    IconData icon, {
    TextInputType type = TextInputType.text,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: c,
        keyboardType: type,
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
              borderSide: const BorderSide(color: AppColors.indigo, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
          focusedErrorBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
        ),
      );

  Widget _empty() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
            color: AppColors.surface, shape: BoxShape.circle),
        child: const Icon(Icons.group_outlined,
            color: AppColors.indigo, size: 48)),
      const SizedBox(height: 16),
      Text('No Employees Yet', style: AppText.title().copyWith(fontSize: 18)),
      const SizedBox(height: 8),
      Text('Tap + to add your first team member',
          style: AppText.body(color: AppColors.textDisabled)),
    ],
  ));

  Widget _noResults() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.person_search_rounded,
          color: AppColors.indigo, size: 56),
      const SizedBox(height: 16),
      Text('No Results', style: AppText.title().copyWith(fontSize: 18)),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () {
          _searchCtrl.clear();
          setState(() { _searchQuery = ''; _selectedRole = 'All'; });
        },
        child: Text('Clear Filters', style: AppText.buttonLabel(color: AppColors.indigo)),
      ),
    ],
  ));
}