// filepath: lib/screens/widgets/payment_history_list.dart
// ============================================================
// lib/screens/widgets/payment_history_list.dart
//
// Reusable payment history list for a single sale. Drop into any
// sale-detail screen:
//
//   PaymentHistoryList(saleId: sale.id, saleTotalAmount: sale.totalAmount)
//
// Each row acts as a lightweight receipt: method, reference, amount,
// who recorded it, and when. Refund action available on completed
// payments only (mirrors PaymentService.refundPayment's own guard).
// ============================================================
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/payment_model.dart';
import '../../services/payment_service.dart';
import '../../theme/app_theme.dart';

class PaymentHistoryList extends StatelessWidget {
  final String saleId;
  final double saleTotalAmount;
  final bool allowRefund;

  const PaymentHistoryList({
    super.key,
    required this.saleId,
    required this.saleTotalAmount,
    this.allowRefund = false,
  });

  @override
  Widget build(BuildContext context) {
    final paymentService = PaymentService();

    return StreamBuilder<List<PaymentModel>>(
      stream: paymentService.getPaymentsForSale(saleId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final payments = snapshot.data ?? [];
        if (payments.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(
              child: Text(
                'No payments recorded yet.',
                style: AppText.subtitle(),
              ),
            ),
          );
        }

        return Column(
          children: payments
              .map((p) => _PaymentTile(
                    payment: p,
                    allowRefund: allowRefund,
                    onRefund: () => _confirmRefund(context, paymentService, p),
                  ))
              .toList(),
        );
      },
    );
  }

  Future<void> _confirmRefund(
    BuildContext context,
    PaymentService service,
    PaymentModel payment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
        title: Text('Refund Payment?', style: AppText.title()),
        content: Text(
          'Refund Rs. ${payment.amount.toStringAsFixed(0)} '
          '(${payment.method.value})? This cannot be undone.',
          style: AppText.body(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppText.body(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Refund', style: AppText.body(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await service.refundPayment(
        payment,
        actorUid:  user.uid,
        actorName: user.email ?? user.displayName ?? 'Unknown',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment refunded.', style: AppText.body()),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceFirst('Exception: ', ''),
              style: AppText.body(),
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }
}

class _PaymentTile extends StatelessWidget {
  final PaymentModel payment;
  final bool allowRefund;
  final VoidCallback onRefund;

  const _PaymentTile({
    required this.payment,
    required this.allowRefund,
    required this.onRefund,
  });

  Color get _statusColor {
    switch (payment.status) {
      case PaymentStatus.completed: return AppColors.success;
      case PaymentStatus.pending:   return AppColors.warning;
      case PaymentStatus.failed:    return AppColors.danger;
      case PaymentStatus.refunded:  return AppColors.textTertiary;
    }
  }

  IconData get _methodIcon {
    switch (payment.method) {
      case PaymentMethod.cash:         return Icons.payments_outlined;
      case PaymentMethod.bankTransfer: return Icons.account_balance_outlined;
      case PaymentMethod.jazzCash:     return Icons.phone_android_outlined;
      case PaymentMethod.easyPaisa:    return Icons.phone_android_outlined;
      case PaymentMethod.card:         return Icons.credit_card_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = payment.createdAt;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final dateStr = '${months[d.month - 1]} ${d.day}, ${d.year} • '
        '$hour12:${d.minute.toString().padLeft(2, '0')} $ampm';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: AppRadius.lgRadius,
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.15),
              borderRadius: AppRadius.mdRadius,
            ),
            child: Icon(_methodIcon, color: _statusColor, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Rs. ${payment.amount.toStringAsFixed(0)}',
                      style: AppText.title(),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor.withValues(alpha: 0.15),
                        borderRadius: AppRadius.fullRadius,
                      ),
                      child: Text(
                        payment.status.value,
                        style: AppText.badge(color: _statusColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${payment.method.value}'
                  '${payment.transactionRef.isNotEmpty ? ' • ${payment.transactionRef}' : ''}',
                  style: AppText.caption(),
                ),
                const SizedBox(height: 2),
                Text(dateStr, style: AppText.caption(color: AppColors.textFaint)),
                if (payment.notes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(payment.notes, style: AppText.caption()),
                ],
              ],
            ),
          ),
          if (allowRefund && payment.status == PaymentStatus.completed)
            IconButton(
              icon: const Icon(Icons.undo, color: AppColors.textTertiary, size: 20),
              tooltip: 'Refund',
              onPressed: onRefund,
            ),
        ],
      ),
    );
  }
}