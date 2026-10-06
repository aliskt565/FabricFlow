// ============================================================
// lib/screens/settings/settings_screen.dart
//
// RBAC changes:
//   + Loads creator's own role on open via getUserRoleEnum()
//   + Role selector shows ONLY roles below creator's privilege
//   + "Create New User" tile hidden entirely for non-Managers
//   + saveUserRoleRbac() replaces saveUserRole() — enforces
//     privilege check server-side in FirestoreService
//   + Clear RbacException message shown in error banner
//
// THEME MIGRATION: all hardcoded colors replaced with AppColors/
// AppGradients/AppRadius/AppText. One new gradient added to
// app_theme.dart during this migration: AppGradients.settingsHeader
// (navyDeep → navyMid), found only here for the profile header.
// ============================================================
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../models/rbac_model.dart';
import '../../models/employee_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirestoreService _fs   = FirestoreService();
  final FirebaseAuth     _auth = FirebaseAuth.instance;

  AppRole _myRole     = AppRole.employee; // safe default until loaded
  bool    _roleLoaded = false;

  String get _uid   => _auth.currentUser?.uid   ?? '';
  String get _email => _auth.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    _loadMyRole();
  }

  Future<void> _loadMyRole() async {
    if (_uid.isEmpty) return;
    final role = await _fs.getUserRoleEnum(_uid);
    if (mounted) setState(() { _myRole = role; _roleLoaded = true; });
  }

  // ── Secondary-app user creation (keeps admin logged in) ──────────────
  Future<void> _createUserKeepAdmin({
    required String  email,
    required String  password,
    required AppRole role,
    required String  name,
    required String  phone,
    required double  salary,
  }) async {
    final secondaryApp = await Firebase.initializeApp(
      name:    'secondaryForUserCreation',
      options: Firebase.app().options,
    );

    String? newUid;
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final cred = await secondaryAuth.createUserWithEmailAndPassword(
          email: email, password: password);
      newUid = cred.user!.uid;
      await secondaryAuth.signOut();

      // ── RBAC-enforced role assignment ─────────────────────────────────
      // Throws RbacException if creator doesn't have enough privilege.
      await _fs.saveUserRoleRbac(
        creatorUid:  _uid,
        creatorName: _email.isNotEmpty ? _email : 'Manager',
        newUid:      newUid,
        newEmail:    email,
        newRole:     role,
      );

      // Add to employees collection for Manager/Employee roles
      if (role == AppRole.employee || role == AppRole.manager) {
        await _fs.addEmployee(EmployeeModel(
          id: '', name: name, role: role.name,
          email: email, phone: phone, salary: salary.toString(),
        ));
      }
    } catch (e) {
      // If role save failed, try to clean up the orphan Auth account
      if (newUid != null) {
        try { await _fs.removeUserRole(newUid); } catch (_) {}
      }
      rethrow;
    } finally {
      await secondaryApp.delete();
    }
  }

  // ── Create user dialog ────────────────────────────────────────────────
  void _showCreateUserDialog() {
    // Determine which roles this user is allowed to create
    final allowed = _myRole.creatableRoles;

    // Should never reach here for non-Managers, but double-check
    if (allowed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Access denied: your role (${_myRole.name}) cannot create users.',
          style: AppText.body(),
        ),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
      ));
      return;
    }

    final emailCtrl    = TextEditingController();
    final passwordCtrl = TextEditingController();
    final nameCtrl     = TextEditingController();
    final phoneCtrl    = TextEditingController();
    final salaryCtrl   = TextEditingController();
    AppRole selRole    = allowed.first;  // default to lowest allowed role
    bool    showPw     = false;
    bool    loading    = false;
    String  errorMsg   = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.textFaint,
                      borderRadius: AppRadius.handleRadius),
                )),
                const SizedBox(height: 20),

                // Header
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary,
                      borderRadius: AppRadius.mdRadius,
                    ),
                    child: const Icon(Icons.person_add_rounded,
                        color: AppColors.textPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Create New User', style: AppText.title().copyWith(fontSize: 17)),
                      Text(
                        'You can create: ${allowed.map((r) => r.name).join(', ')}',
                        style: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 11),
                      ),
                    ],
                  )),
                ]),
                const SizedBox(height: 24),

                // Fields
                _field(nameCtrl,  'Full Name',       Icons.person_outline_rounded),
                const SizedBox(height: 14),
                _field(emailCtrl, 'Email Address',   Icons.email_outlined,
                    type: TextInputType.emailAddress),
                const SizedBox(height: 14),

                // Password
                TextField(
                  controller: passwordCtrl,
                  obscureText: !showPw,
                  style: AppText.body(),
                  decoration: InputDecoration(
                    labelText: 'Password (min 6 chars)',
                    labelStyle: AppText.caption(color: AppColors.textTertiary).copyWith(fontSize: 13),
                    prefixIcon: const Icon(Icons.lock_outline_rounded,
                        color: AppColors.textDisabled, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        showPw ? Icons.visibility_off_outlined
                               : Icons.visibility_outlined,
                        color: AppColors.textDisabled, size: 20),
                      onPressed: () => setM(() => showPw = !showPw),
                    ),
                    filled: true, fillColor: AppColors.surfaceRaised,
                    border: OutlineInputBorder(
                        borderRadius: AppRadius.lgRadius,
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: AppRadius.lgRadius,
                        borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: AppRadius.lgRadius,
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 14),
                _field(phoneCtrl,  'Phone Number',
                    Icons.phone_outlined, type: TextInputType.phone),
                const SizedBox(height: 14),
                _field(salaryCtrl, 'Monthly Salary (Rs.)',
                    Icons.payments_outlined, type: TextInputType.number),
                const SizedBox(height: 16),

                // ── Role selector — only shows ALLOWED roles ────────────
                Text('Assign Role', style: AppText.caption(color: AppColors.textTertiary).copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                // Permission info banner
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .08),
                    borderRadius: AppRadius.mdRadius,
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: .25)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.shield_rounded,
                        color: AppColors.primary, size: 15),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'As a ${_myRole.name}, you can only create roles '
                      'with lower privileges than your own.',
                      style: AppText.caption(color: AppColors.primary).copyWith(fontSize: 11),
                    )),
                  ]),
                ),
                const SizedBox(height: 10),

                // Role buttons — only the allowed ones
                Row(children: allowed.asMap().entries.map((entry) {
                  final idx  = entry.key;
                  final role = entry.value;
                  final sel  = selRole == role;
                  final colors = _roleColors(role);

                  return Expanded(child: GestureDetector(
                    onTap: () => setM(() => selRole = role),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: EdgeInsets.only(
                          right: idx < allowed.length - 1 ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: sel
                            ? LinearGradient(colors: colors)
                            : null,
                        color: sel ? null : AppColors.surfaceRaised,
                        borderRadius: AppRadius.mdRadius,
                        border: Border.all(
                            color: sel ? Colors.transparent : AppColors.border),
                      ),
                      child: Column(children: [
                        Icon(_roleIcon(role),
                            color: sel ? AppColors.textPrimary : AppColors.textDisabled,
                            size: 20),
                        const SizedBox(height: 4),
                        Text(role.name,
                            style: AppText.caption(
                                color: sel ? AppColors.textPrimary : AppColors.textDisabled,
                              ).copyWith(
                                fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                                fontSize: 13)),
                        Text('Level ${role.level}',
                            style: AppText.caption(
                                color: sel ? AppColors.textSecondary : AppColors.textFaint,
                              ).copyWith(fontSize: 10)),
                      ]),
                    ),
                  ));
                }).toList()),

                // Error banner
                if (errorMsg.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _errorBanner(errorMsg),
                ],
                const SizedBox(height: 24),

                // Submit
                SizedBox(width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : () async {
                      if (nameCtrl.text.trim().isEmpty) {
                        setM(() => errorMsg = 'Full name is required.');
                        return;
                      }
                      final emailVal = emailCtrl.text.trim();
                      if (emailVal.isEmpty) {
                        setM(() => errorMsg = 'Email is required.');
                        return;
                      }
                      // Basic email format check
                      final emailRe = RegExp(
                          r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
                      if (!emailRe.hasMatch(emailVal)) {
                        setM(() => errorMsg =
                            'Please enter a valid email address.');
                        return;
                      }
                      if (passwordCtrl.text.trim().length < 6) {
                        setM(() => errorMsg =
                            'Password must be at least 6 characters.');
                        return;
                      }
                      setM(() { loading = true; errorMsg = ''; });

                      try {
                        await _createUserKeepAdmin(
                          email:    emailVal,
                          password: passwordCtrl.text.trim(),
                          role:     selRole,
                          name:     nameCtrl.text.trim(),
                          phone:    phoneCtrl.text.trim(),
                          salary:   double.tryParse(salaryCtrl.text) ?? 0,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _snack(
                          '${selRole.name} account created!',
                          AppColors.success);
                      } on FirebaseAuthException catch (e) {
                        setM(() {
                          loading  = false;
                          errorMsg = switch (e.code) {
                            'email-already-in-use' =>
                                'This email is already registered.',
                            'invalid-email' =>
                                'Please enter a valid email address.',
                            'weak-password' =>
                                'Password is too weak (min 6 characters).',
                            _ => 'Auth error: ${e.message}',
                          };
                        });
                      } on RbacException catch (e) {
                        // RBAC violation — shown clearly to user
                        setM(() { loading = false; errorMsg = e.message; });
                      } catch (e) {
                        setM(() {
                          loading  = false;
                          errorMsg = 'Something went wrong: $e';
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.lgRadius),
                    ),
                    child: loading
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: AppColors.textPrimary, strokeWidth: 2.5))
                        : Text('Create Account', style: AppText.buttonLabel().copyWith(fontSize: 15)),
                  )),
                const SizedBox(height: 8),
              ],
            )),
          ),
        ),
      ),
    );
  }

  // ── Change password ───────────────────────────────────────────────────
  void _showChangePwDialog() {
    final newPw  = TextEditingController();
    final confPw = TextEditingController();
    bool showN = false, showC = false, loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.xlRadius),
          title: Row(children: [
            const Icon(Icons.lock_reset_rounded,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            Text('Change Password', style: AppText.title()),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _pwField(newPw,  'New Password',     showN,
                () => setD(() => showN = !showN)),
            const SizedBox(height: 12),
            _pwField(confPw, 'Confirm Password', showC,
                () => setD(() => showC = !showC)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: AppText.body(color: AppColors.textTertiary))),
            ElevatedButton(
              onPressed: loading ? null : () async {
                if (newPw.text.length < 6) {
                  _snack('Min 6 characters required', AppColors.danger); return;
                }
                if (newPw.text != confPw.text) {
                  _snack('Passwords do not match', AppColors.danger); return;
                }
                setD(() => loading = true);
                try {
                  await _auth.currentUser?.updatePassword(newPw.text.trim());
                  if (ctx.mounted) Navigator.pop(ctx);
                  _snack('Password updated!', AppColors.success);
                } catch (e) {
                  setD(() => loading = false);
                  _snack('Error: $e', AppColors.danger);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.smRadius),
              ),
              child: loading
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: AppColors.textPrimary, strokeWidth: 2))
                  : Text('Update', style: AppText.buttonLabel()),
            ),
          ],
        ),
      ),
    );
  }

  // ── Logout ────────────────────────────────────────────────────────────
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlRadius),
        title: Row(children: [
          const Icon(Icons.logout_rounded, color: AppColors.danger, size: 22),
          const SizedBox(width: 10),
          Text('Logout', style: AppText.title()),
        ]),
        content: Text('Are you sure you want to logout from FabricFlow?',
            style: AppText.body(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: AppText.body(color: AppColors.textTertiary))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _auth.signOut();
              if (mounted) Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (r) => false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.smRadius),
            ),
            child: Text('Logout', style: AppText.buttonLabel()),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Show loading until role is fetched
    if (!_roleLoaded) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(
            color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(slivers: [
        // ── Profile header ──────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 210,
          pinned: true,
          backgroundColor: AppColors.background,
          elevation: 0,
          automaticallyImplyLeading: false,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: AppGradients.settingsHeader,
              ),
              child: SafeArea(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(children: [
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: _roleColors(_myRole)),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(
                            color: _roleColors(_myRole).first.withValues(alpha: .4),
                            blurRadius: 20, offset: const Offset(0, 8))],
                        ),
                        child: Center(child: Text(
                          _email.isNotEmpty ? _email[0].toUpperCase() : 'U',
                          style: AppText.headline().copyWith(fontSize: 26),
                        )),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_myRole.name, style: AppText.title().copyWith(fontSize: 20)),
                          Text(_email,
                              style: AppText.body(color: AppColors.textSecondary).copyWith(fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                        ],
                      )),
                      // Role badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: .2),
                          borderRadius: AppRadius.xlRadius,
                          border: Border.all(
                              color: AppColors.success.withValues(alpha: .5)),
                        ),
                        child: Row(children: [
                          Icon(_roleIcon(_myRole),
                              color: AppColors.success, size: 14),
                          const SizedBox(width: 5),
                          Text('Lv ${_myRole.level}',
                              style: AppText.badge(color: AppColors.success).copyWith(fontSize: 12)),
                        ]),
                      ),
                    ]),
                  ],
                ),
              )),
            ),
          ),
        ),

        SliverList(delegate: SliverChildListDelegate([
          Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── User Management — ONLY shown to Managers ──────────────
              if (_myRole.canCreateUsers) ...[
                _sectionLabel('USER MANAGEMENT'),
                const SizedBox(height: 10),
                _tile(
                  icon:     Icons.person_add_rounded,
                  color:    AppColors.primary,
                  title:    'Create New User',
                  subtitle: 'Allowed roles: '
                      '${_myRole.creatableRoles.map((r) => r.name).join(', ')}',
                  onTap:    _showCreateUserDialog,
                ),
                const SizedBox(height: 24),
              ],

              // ── If not Manager, show access info ─────────────────────
              if (!_myRole.canCreateUsers) ...[
                _sectionLabel('ACCESS'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadius.lgRadius,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: .06)),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: .15),
                        borderRadius: AppRadius.mdRadius),
                      child: const Icon(Icons.lock_outline_rounded,
                          color: AppColors.warning, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('User Management Restricted',
                            style: AppText.body().copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(
                          'Only Managers can create and manage user accounts.',
                          style: AppText.caption(color: AppColors.textDisabled)),
                      ],
                    )),
                  ]),
                ),
                const SizedBox(height: 24),
              ],

              // ── Account ────────────────────────────────────────────────
              _sectionLabel('ACCOUNT'),
              const SizedBox(height: 10),
              _tile(
                icon:     Icons.lock_reset_rounded,
                color:    AppColors.teal,
                title:    'Change Password',
                subtitle: 'Update your login password',
                onTap:    _showChangePwDialog,
              ),
              const SizedBox(height: 8),
              _tile(
                icon:        Icons.logout_rounded,
                color:       AppColors.danger,
                title:       'Logout',
                subtitle:    'Sign out of FabricFlow',
                onTap:       _showLogoutDialog,
                destructive: true,
              ),
              const SizedBox(height: 24),

              // ── About ──────────────────────────────────────────────────
              _sectionLabel('ABOUT'),
              const SizedBox(height: 10),
              _infoRow(Icons.apps_rounded,        AppColors.pink,    'App Name',     'FabricFlow'),
              const SizedBox(height: 8),
              _infoRow(Icons.info_outline_rounded, AppColors.primary, 'Version',      '1.0.0'),
              const SizedBox(height: 8),
              _infoRow(Icons.business_rounded,    AppColors.success, 'Organisation',  'Clothing ERP'),
              const SizedBox(height: 8),
              _infoRow(Icons.school_rounded,      AppColors.warning, 'Project Type',  'Final Year Project'),
              const SizedBox(height: 8),
              _infoRow(Icons.flutter_dash_rounded, AppColors.flutterBlue, 'Built With',   'Flutter + Firebase'),
              const SizedBox(height: 36),

              // ── RBAC Info ──────────────────────────────────────────────
              _sectionLabel('PERMISSIONS'),
              const SizedBox(height: 10),
              _rbacSummaryCard(),
              const SizedBox(height: 36),

              Center(child: Text(
                '© 2026 FabricFlow — Smart Clothing ERP',
                style: AppText.caption(color: AppColors.textFaint))),
              const SizedBox(height: 32),
            ],
          )),
        ])),
      ]),
    );
  }

  // ── RBAC summary card ─────────────────────────────────────────────────
  Widget _rbacSummaryCard() {
    final perms = <_PermRow>[
      _PermRow('Create Users',      _myRole.canCreateUsers),
      _PermRow('Manage Inventory',  _myRole.canWriteInventory),
      _PermRow('Record Sales',      _myRole.canWriteSales),
      _PermRow('Manage Employees',  _myRole.canWriteEmployees),
      _PermRow('Manage Customers',  _myRole.canWriteCustomers),
      _PermRow('View Reports',      _myRole.canReadReports),
      _PermRow('Access Settings',   _myRole.canReadSettings),
      _PermRow('Browse Products',   _myRole.canBrowseProducts),
      _PermRow('Place Orders',      _myRole.canPlaceOrders),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.shield_rounded,
              color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Text('Your Permissions (${_myRole.name})',
              style: AppText.body().copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 14),
        ...perms.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(
              p.allowed
                  ? Icons.check_circle_rounded
                  : Icons.cancel_rounded,
              color: p.allowed
                  ? AppColors.success
                  : AppColors.textFaint,
              size: 16,
            ),
            const SizedBox(width: 10),
            Text(p.label,
                style: AppText.body(
                    color: p.allowed ? AppColors.textSecondary : AppColors.textFaint,
                  ).copyWith(fontSize: 13)),
          ]),
        )),
      ]),
    );
  }

  // ── Small helpers ─────────────────────────────────────────────────────
  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: AppText.body()),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
    ));
  }

  List<Color> _roleColors(AppRole r) {
    switch (r) {
      case AppRole.manager:  return [AppColors.primary, AppColors.primaryDeep];
      case AppRole.employee: return [AppColors.teal, AppColors.tealLight];
      case AppRole.customer: return [AppColors.magenta, AppColors.magentaLight];
    }
  }

  IconData _roleIcon(AppRole r) {
    switch (r) {
      case AppRole.manager:  return Icons.manage_accounts_rounded;
      case AppRole.employee: return Icons.badge_rounded;
      case AppRole.customer: return Icons.person_rounded;
    }
  }

  Widget _sectionLabel(String t) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(t, style: AppText.caption(color: AppColors.textDisabled)
        .copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.4)),
  );

  Widget _tile({
    required IconData     icon,
    required Color        color,
    required String       title,
    required String       subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.lgRadius,
            border: Border.all(color: destructive
                ? AppColors.danger.withValues(alpha: .2)
                : Colors.white.withValues(alpha: .06)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .15),
                borderRadius: AppRadius.mdRadius),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppText.body(
                        color: destructive ? AppColors.danger : AppColors.textPrimary,
                      ).copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(subtitle, style: AppText.caption(color: AppColors.textDisabled)),
              ],
            )),
            Icon(Icons.chevron_right_rounded,
                color: destructive
                    ? AppColors.danger.withValues(alpha: .5)
                    : AppColors.textFaint),
          ]),
        ),
      );

  Widget _infoRow(IconData icon, Color color, String label, String value) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .06)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .15),
              borderRadius: AppRadius.mdRadius),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: AppText.caption(color: AppColors.textTertiary))),
          Text(value, style: AppText.body().copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _errorBanner(String msg) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.danger.withValues(alpha: .1),
      borderRadius: AppRadius.mdRadius,
      border: Border.all(color: AppColors.danger.withValues(alpha: .4)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded,
          color: AppColors.danger, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(msg, style: AppText.caption(color: AppColors.danger).copyWith(fontSize: 12))),
    ]),
  );

  Widget _field(TextEditingController c, String label, IconData icon,
      {TextInputType type = TextInputType.text}) =>
      TextField(
        controller: c, keyboardType: type,
        style: AppText.body(),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppText.caption(color: AppColors.textTertiary).copyWith(fontSize: 13),
          prefixIcon: Icon(icon, color: AppColors.textDisabled, size: 20),
          filled: true, fillColor: AppColors.surfaceRaised,
          border: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: const BorderSide(
                  color: AppColors.primary, width: 1.5)),
        ),
      );

  Widget _pwField(TextEditingController c, String label, bool visible,
      VoidCallback toggle) =>
      TextField(
        controller: c, obscureText: !visible,
        style: AppText.body(),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppText.caption(color: AppColors.textTertiary).copyWith(fontSize: 13),
          prefixIcon: const Icon(Icons.lock_outline_rounded,
              color: AppColors.textDisabled, size: 20),
          suffixIcon: IconButton(
            icon: Icon(
              visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: AppColors.textDisabled, size: 20),
            onPressed: toggle,
          ),
          filled: true, fillColor: AppColors.surfaceRaised,
          border: OutlineInputBorder(
              borderRadius: AppRadius.mdRadius,
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.mdRadius,
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.mdRadius,
              borderSide: const BorderSide(
                  color: AppColors.primary, width: 1.5)),
        ),
      );
}

class _PermRow {
  final String label;
  final bool   allowed;
  const _PermRow(this.label, this.allowed);
}