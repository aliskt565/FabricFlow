// ============================================================
// lib/main.dart
//
// RBAC changes:
//   + Uses AppRole enum from rbac_model.dart
//   + Route guard on session restore — each role routed strictly
//   + Unrecognised / missing role → forced logout → LoginScreen
// ============================================================
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/rbac_model.dart';
import 'theme/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/employees/employee_dashboard_screen.dart';
import 'screens/customers/customer_dashboard_screen.dart';
import 'services/firestore_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const FabricFlowApp());
}

class FabricFlowApp extends StatelessWidget {
  const FabricFlowApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FabricFlow',
      debugShowCheckedModeBanner: false,
      // Day 1, Item 2: was a hand-built ThemeData duplicating the exact
      // two hex values already centralized in AppTheme — now points at
      // the single source of truth instead.
      theme: AppTheme.dark,
      home: const _AppEntryPoint(),
    );
  }
}

class _AppEntryPoint extends StatefulWidget {
  const _AppEntryPoint();
  @override
  State<_AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<_AppEntryPoint>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(const Duration(milliseconds: 1400), _resolveSession);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _resolveSession() async {
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) { _goTo(const LoginScreen()); return; }

    try {
      // ── RBAC-aware session restore ──────────────────────────────────
      final role = await FirestoreService().getUserRoleEnum(user.uid);

      if (!mounted) return;

      Widget dest;
      switch (role) {
        case AppRole.manager:
          dest = const DashboardScreen();          // full access
          break;
        case AppRole.employee:
          dest = const EmployeeDashboardScreen();  // limited — view only
          break;
        case AppRole.customer:
          dest = const CustomerDashboardScreen();  // shop + orders
          break;
      }
      _goTo(dest);
    } catch (_) {
      // Network error — force re-login
      if (mounted) {
        await FirebaseAuth.instance.signOut();
        _goTo(const LoginScreen());
      }
    }
  }

  void _goTo(Widget s) => Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => s));

  // Day 1, Item 2: fully migrated to AppTheme tokens — main.dart is
  // small and self-contained, so unlike the larger screens (deferred
  // to incremental migration, see file header), it made sense to
  // finish this one completely rather than half-migrate it.
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.authBgStart,
    body: FadeTransition(
      opacity: _fade,
      child: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppGradients.authBackground,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: AppColors.primary.withValues(alpha: .5),
                blurRadius: 40, offset: const Offset(0, 12))],
            ),
            child: const Icon(Icons.dry_cleaning_rounded,
                color: AppColors.textPrimary, size: 50),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('FabricFlow',
              style: AppText.headline().copyWith(fontSize: 32, letterSpacing: 1.2)),
          const SizedBox(height: AppSpacing.sm),
          Text('Smart Clothing ERP',
              style: AppText.caption(color: AppColors.textDisabled)),
          const SizedBox(height: 52),
          const SizedBox(width: 26, height: 26,
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2.5)),
        ]),
      ),
    ),
  );
}