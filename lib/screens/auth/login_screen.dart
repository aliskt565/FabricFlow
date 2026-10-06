import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../dashboard/dashboard_screen.dart';
import '../employees/employee_dashboard_screen.dart';
import '../customers/customer_dashboard_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _auth         = FirebaseAuth.instance;
  final _fs           = FirestoreService();

  late AnimationController _anim;
  late Animation<double>  _fade;
  late Animation<Offset>  _slide;

  bool   _loading      = false;
  bool   _showPassword = false;
  String _error        = '';

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 800))..forward();
    _fade  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, .06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
  }

  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _anim.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailCtrl.text.trim();
    final pass  = _passwordCtrl.text.trim();
    setState(() { _loading = true; _error = ''; });

    try {
      await _auth.signOut();

      final cred = await _auth.signInWithEmailAndPassword(
          email: email, password: pass);
      final uid = cred.user?.uid;
      if (uid == null) {
        setState(() { _loading = false; _error = 'Login failed. Try again.'; });
        return;
      }

      final role = await _fs.getUserRole(uid);
      if (!mounted) return;
      setState(() => _loading = false);

      Widget dest;
      if (role == 'Manager') {
        dest = const DashboardScreen();
      } else if (role == 'Employee')  dest = const EmployeeDashboardScreen();
      else if (role == 'Customer')  dest = const CustomerDashboardScreen();
      else {
        setState(() => _error = 'Account role not configured. Contact admin.');
        await _auth.signOut();
        return;
      }

      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => dest), (r) => false);

    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = switch (e.code) {
          'user-not-found'    => 'No account found with this email.',
          'wrong-password'    => 'Incorrect password.',
          'invalid-credential'=> 'Invalid email or password.',
          'too-many-requests' => 'Too many attempts. Try later.',
          'user-disabled'     => 'This account has been disabled.',
          _                   => 'Login failed: ${e.message}',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Something went wrong.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final emailRegex = RegExp(r'^[\w.+\-]+@[a-zA-Z\d\-]+\.[a-zA-Z\d.\-]+$');

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width:  double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppGradients.authBackgroundDeep,
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 28, right: 28,
                  bottom: mq.viewInsets.bottom + 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: mq.size.height
                        - mq.padding.top
                        - mq.padding.bottom,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          children: [
                            const SizedBox(height: 52),
                            Container(
                              width: 88, height: 88,
                              decoration: BoxDecoration(
                                gradient: AppGradients.primary,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(
                                  color: AppColors.primary.withValues(alpha: .4),
                                  blurRadius: 30, offset: const Offset(0, 10))],
                              ),
                              child: const Icon(Icons.dry_cleaning_rounded,
                                  color: AppColors.textPrimary, size: 42),
                            ),
                            const SizedBox(height: 22),
                            Text('FabricFlow',
                                style: AppText.headline().copyWith(
                                    fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text('Smart Clothing ERP',
                                style: AppText.caption(color: AppColors.textDisabled)
                                    .copyWith(fontSize: 13)),
                            const SizedBox(height: 44),

                            _formField(
                              controller: _emailCtrl,
                              label: 'Email Address',
                              icon:  Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Email is required';
                                if (!emailRegex.hasMatch(v.trim())) return 'Enter a valid email address';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            _formField(
                              controller: _passwordCtrl,
                              label: 'Password',
                              icon:  Icons.lock_outline_rounded,
                              obscure: !_showPassword,
                              suffix: IconButton(
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: AppColors.textDisabled, size: 20),
                                onPressed: () =>
                                    setState(() => _showPassword = !_showPassword),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Password is required';
                                if (v.length < 6) return 'Password must be at least 6 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),

                            if (_error.isNotEmpty)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.danger.withValues(alpha: .1),
                                  borderRadius: AppRadius.mdRadius,
                                  border: Border.all(
                                      color: AppColors.danger.withValues(alpha: .4)),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.error_outline_rounded,
                                      color: AppColors.danger, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(_error,
                                      style: AppText.body(color: AppColors.danger)
                                          .copyWith(fontSize: 13))),
                                ]),
                              ),
                            if (_error.isNotEmpty) const SizedBox(height: 14),

                            GestureDetector(
                              onTap: _loading ? null : _login,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 17),
                                decoration: BoxDecoration(
                                  gradient: _loading ? null : AppGradients.primary,
                                  color: _loading ? Colors.white12 : null,
                                  borderRadius: AppRadius.lgRadius,
                                  boxShadow: _loading ? [] : [BoxShadow(
                                    color: AppColors.primary.withValues(alpha: .4),
                                    blurRadius: 20, offset: const Offset(0, 8))],
                                ),
                                child: Center(
                                  child: _loading
                                      ? const SizedBox(width: 22, height: 22,
                                          child: CircularProgressIndicator(
                                              color: AppColors.textPrimary, strokeWidth: 2.5))
                                      : Text('Sign In', style: AppText.buttonLabel().copyWith(fontSize: 16)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            Row(mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('New customer? ',
                                    style: AppText.body(color: AppColors.textDisabled).copyWith(fontSize: 14)),
                                GestureDetector(
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute(
                                          builder: (_) => const SignupScreen())),
                                  child: Text('Create Account',
                                      style: AppText.buttonLabel(color: AppColors.primary).copyWith(fontSize: 14)),
                                ),
                              ],
                            ),
                          ],
                        ),

                        Padding(
                          padding: const EdgeInsets.only(top: 32),
                          child: Text('© 2026 FabricFlow',
                              style: AppText.caption(color: AppColors.textFaint)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscure,
        validator: validator,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        style: AppText.body(),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppText.caption(color: AppColors.textDisabled).copyWith(fontSize: 13),
          errorStyle: AppText.caption(color: AppColors.danger).copyWith(fontSize: 11),
          prefixIcon: Icon(icon, color: AppColors.textDisabled, size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
          focusedErrorBorder: OutlineInputBorder(
              borderRadius: AppRadius.lgRadius,
              borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        ),
      );
}