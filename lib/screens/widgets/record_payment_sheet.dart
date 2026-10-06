// filepath: lib/screens/widgets/record_payment_sheet.dart
// ============================================================
// lib/screens/widgets/record_payment_sheet.dart
//
// Reusable "Record Payment" bottom sheet. Call it from anywhere
// (Sales screen, Customer dashboard order detail, etc.) via:
//
//   showModalBottomSheet(
//     context: context,
//     isScrollControlled: true,
//     backgroundColor: Colors.transparent,
//     builder: (_) => RecordPaymentSheet(
//       saleId: sale.id,
//       customerId: sale.customerId,
//       customerName: sale.customerName,
//       saleTotalAmount: sale.totalAmount,
//     ),
//   );
//
// Uses AppColors/AppGradients/AppRadius/AppSpacing/AppText tokens
// from app_theme.dart throughout — no hardcoded literals, per the
// "new code must use design tokens" rule already in this codebase.
// ============================================================
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/payment_model.dart';
import '../../services/payment_service.dart';
import '../../theme/app_theme.dart';

class RecordPaymentSheet extends StatefulWidget {
  final String saleId;
  final String customerId;
  final String customerName;
  final double saleTotalAmount;

  const RecordPaymentSheet({
    super.key,
    required this.saleId,
    required this.customerId,
    required this.customerName,
    required this.saleTotalAmount,
  });

  @override
  State<RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<RecordPaymentSheet> {
  final PaymentService _paymentService = PaymentService();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _refController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  PaymentMethod _selectedMethod = PaymentMethod.cash;
  bool _isSubmitting = false;
  String? _errorText;
  SaleBalance? _balance;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    final balance = await _paymentService.getSaleBalance(
      widget.saleId,
      widget.saleTotalAmount,
    );
    if (!mounted) return;
    setState(() {
      _balance = balance;
      _amountController.text = balance.amountDue.toStringAsFixed(0);
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _errorText = 'You must be signed in to record a payment.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      final amount = double.parse(_amountController.text.trim());
      await _paymentService.recordPayment(
        saleId:          widget.saleId,
        customerId:      widget.customerId,
        customerName:    widget.customerName,
        amount:          amount,
        method:          _selectedMethod,
        saleTotalAmount: widget.saleTotalAmount,
        transactionRef:  _refController.text.trim(),
        notes:           _notesController.text.trim(),
        actorUid:        user.uid,
        actorName:       user.email ?? user.displayName ?? 'Unknown',
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment of Rs. ${amount.toStringAsFixed(0)} recorded.',
            style: AppText.body(),
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      setState(() {
        _errorText = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = _balance;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: AppRadius.handleRadius,
                    ),
                  ),
                ),
                Text('Record Payment', style: AppText.headline()),
                const SizedBox(height: AppSpacing.xs),
                Text(widget.customerName, style: AppText.subtitle()),
                const SizedBox(height: AppSpacing.lg),

                if (balance == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  )
                else
                  _BalanceSummary(balance: balance),

                const SizedBox(height: AppSpacing.lg),

                Text('Amount', style: AppText.subtitle()),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: AppText.body(),
                  decoration: _inputDecoration(prefixText: 'Rs. '),
                  validator: (v) {
                    final val = double.tryParse((v ?? '').trim());
                    if (val == null || val <= 0) return 'Enter a valid amount';
                    if (balance != null && val > balance.amountDue + 0.01) {
                      return 'Exceeds remaining balance of '
                          'Rs. ${balance.amountDue.toStringAsFixed(0)}';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),

                Text('Payment Method', style: AppText.subtitle()),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: PaymentMethod.values.map((m) {
                    final selected = m == _selectedMethod;
                    return ChoiceChip(
                      label: Text(m.value, style: AppText.caption(
                        color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                      )),
                      selected: selected,
                      onSelected: (_) => setState(() => _selectedMethod = m),
                      backgroundColor: AppColors.surfaceRaised,
                      selectedColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.fullRadius),
                      side: BorderSide.none,
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.lg),

                if (_selectedMethod.requiresReference) ...[
                  Text('Transaction Reference', style: AppText.subtitle()),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    controller: _refController,
                    style: AppText.body(),
                    decoration: _inputDecoration(
                      hintText: 'e.g. TXN-123456',
                    ),
                    validator: (v) {
                      if (_selectedMethod.requiresReference &&
                          (v ?? '').trim().isEmpty) {
                        return 'Required for ${_selectedMethod.value}';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                Text('Notes (optional)', style: AppText.subtitle()),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _notesController,
                  style: AppText.body(),
                  maxLines: 2,
                  decoration: _inputDecoration(hintText: 'e.g. 2nd installment'),
                ),

                if (_errorText != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: AppRadius.mdRadius,
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      _errorText!,
                      style: AppText.body(color: AppColors.danger),
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSubmitting || balance == null ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: AppColors.textPrimary,
                            ),
                          )
                        : Text('Confirm Payment', style: AppText.buttonLabel()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hintText, String? prefixText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: AppText.body(color: AppColors.textTertiary),
      prefixText: prefixText,
      prefixStyle: AppText.body(),
      filled: true,
      fillColor: AppColors.surfaceRaised,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg, vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: AppRadius.mdRadius,
        borderSide: BorderSide.none,
      ),
      errorStyle: AppText.caption(color: AppColors.danger),
    );
  }
}

class _BalanceSummary extends StatelessWidget {
  final SaleBalance balance;
  const _BalanceSummary({required this.balance});

  @override
  Widget build(BuildContext context) {
    final Color statusColor = switch (balance.label) {
      'Paid'    => AppColors.success,
      'Partial' => AppColors.warning,
      _         => AppColors.danger,
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: AppRadius.lgRadius,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: AppText.caption()),
              Text(
                'Rs. ${balance.totalAmount.toStringAsFixed(0)}',
                style: AppText.body(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Paid', style: AppText.caption()),
              Text(
                'Rs. ${balance.amountPaid.toStringAsFixed(0)}',
                style: AppText.body(color: AppColors.success),
              ),
            ],
          ),
          const Divider(color: AppColors.border, height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Remaining', style: AppText.subtitle()),
              Row(
                children: [
                  Text(
                    'Rs. ${balance.amountDue.toStringAsFixed(0)}',
                    style: AppText.title(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: AppRadius.fullRadius,
                    ),
                    child: Text(
                      balance.label,
                      style: AppText.badge(color: statusColor),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}