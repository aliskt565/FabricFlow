// ============================================================
// lib/services/payment_service.dart
//
// PAYMENT TRACKING SERVICE
//
// Mirrors FirestoreService's conventions exactly:
//   - actorUid/actorName passed in by the caller (screens pass
//     FirebaseAuth.instance.currentUser.uid / .email)
//   - logging is fire-and-forget via ActivityLogService, never
//     blocks or fails the primary write
//   - all writes go through a single _db reference
//
// BALANCE INVARIANT:
//   A sale's paid amount is NEVER stored as a field — it is always
//   computed live by summing PaymentModel records with
//   status == PaymentStatus.completed for that saleId. This is what
//   makes partial payments, refunds, and failed-then-retried payments
//   all correct by construction instead of requiring manual
//   reconciliation logic scattered across the app.
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/payment_model.dart';
import '../models/activity_log_model.dart';
import 'payment_gateway.dart';
import 'activity_log_service.dart';
import 'notification_service.dart';

class PaymentService {
  final FirebaseFirestore   _db  = FirebaseFirestore.instance;
  final ActivityLogService  _log = ActivityLogService();
  final NotificationService _ns  = NotificationService();

  // ────────────────────────────────────────────────────────────────────────
  // READS
  // ────────────────────────────────────────────────────────────────────────

  Stream<List<PaymentModel>> getPaymentsForSale(String saleId) {
    return _db
        .collection('payments')
        .where('saleId', isEqualTo: saleId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => PaymentModel.fromJson(d.data())).toList());
  }

  Stream<List<PaymentModel>> getPaymentsForCustomer(String customerId) {
    return _db
        .collection('payments')
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => PaymentModel.fromJson(d.data())).toList());
  }

  Stream<List<PaymentModel>> getAllPayments() {
    return _db
        .collection('payments')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => PaymentModel.fromJson(d.data())).toList());
  }

  /// One-time fetch (not a stream) used wherever a balance is needed
  /// synchronously — e.g. before allowing a new payment to be recorded,
  /// to validate it doesn't exceed the amount still due.
  Future<SaleBalance> getSaleBalance(String saleId, double totalAmount) async {
    final snap = await _db
        .collection('payments')
        .where('saleId', isEqualTo: saleId)
        .get();

    final payments = snap.docs
        .map((d) => PaymentModel.fromJson(d.data()))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final paid = payments
        .where((p) => p.status.countsTowardBalance)
        .fold<double>(0, (total, p) => total + p.amount);

    return SaleBalance(
      totalAmount: totalAmount,
      amountPaid:  paid,
      payments:    payments,
    );
  }

  /// Live version of the above, for screens that want the balance to
  /// update in real time as payments are recorded.
  Stream<SaleBalance> watchSaleBalance(String saleId, double totalAmount) {
    return getPaymentsForSale(saleId).map((payments) {
      final paid = payments
          .where((p) => p.status.countsTowardBalance)
          .fold<double>(0, (total, p) => total + p.amount);
      return SaleBalance(
        totalAmount: totalAmount,
        amountPaid:  paid,
        payments:    payments,
      );
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // WRITES
  // ────────────────────────────────────────────────────────────────────────

  /// Records a payment against a sale, routed through the gateway
  /// registered for the chosen [method]. Today every method routes to
  /// ManualPaymentGateway; plugging in a real gateway later requires
  /// no change to this method's signature or callers.
  ///
  /// Throws an [Exception] (with a user-presentable message) if the
  /// amount is invalid, exceeds the remaining balance, or the gateway
  /// rejects the payment (e.g. missing reference number).
  Future<PaymentModel> recordPayment({
    required String        saleId,
    required String        customerId,
    required String        customerName,
    required double        amount,
    required PaymentMethod method,
    required double        saleTotalAmount,
    String                 transactionRef = '',
    String                 notes          = '',
    required String        actorUid,
    required String        actorName,
  }) async {
    if (amount <= 0) {
      throw Exception('Payment amount must be greater than zero.');
    }

    final balance = await getSaleBalance(saleId, saleTotalAmount);
    if (amount > balance.amountDue + 0.01) {
      throw Exception(
        'Payment of Rs. ${amount.toStringAsFixed(0)} exceeds the remaining '
        'balance of Rs. ${balance.amountDue.toStringAsFixed(0)}.',
      );
    }

    final gateway = PaymentGatewayRegistry.gatewayFor(method);
    final result = await gateway.processPayment(
      amount:         amount,
      method:         method,
      transactionRef: transactionRef,
      metadata: {
        'saleId':     saleId,
        'customerId': customerId,
      },
    );

    if (!result.success) {
      throw Exception(result.message.isNotEmpty
          ? result.message
          : 'Payment could not be processed. Please try again.');
    }

    final ref  = _db.collection('payments').doc();
    final payment = PaymentModel(
      id:             ref.id,
      saleId:         saleId,
      customerId:     customerId,
      customerName:   customerName,
      amount:         amount,
      method:         method,
      gatewayId:      gateway.id,
      status:         PaymentStatus.completed,
      transactionRef: result.transactionRef,
      notes:          notes,
      gatewayResponse: result.rawResponse,
      recordedByUid:  actorUid,
      recordedByName: actorName,
    );

    await ref.set(payment.toJson());

    final newBalance = balance.amountPaid + amount;
    final remaining  = (saleTotalAmount - newBalance).clamp(0, saleTotalAmount);

    await _ns.addNotification(
      title: remaining <= 0.009 ? 'Payment Complete' : 'Partial Payment Received',
      message: remaining <= 0.009
          ? '$customerName fully paid Rs. ${saleTotalAmount.toStringAsFixed(0)}.'
          : '$customerName paid Rs. ${amount.toStringAsFixed(0)} '
            '(Rs. ${remaining.toStringAsFixed(0)} remaining).',
      type: 'success',
    );

    // ── LOG: Payment Record ─────────────────────────────────────────────
    await _log.log(
      userId:   actorUid,
      username: actorName,
      action:   ActivityAction.paymentRecord,
      entity:   ActivityEntity.payment,
      recordId: ref.id,
      details: {
        'saleId':         saleId,
        'customerName':   customerName,
        'amount':         amount,
        'method':         method.value,
        'gatewayId':      gateway.id,
        'transactionRef': result.transactionRef,
        'remainingDue':   remaining,
      },
    );

    return payment;
  }

  /// Marks a completed payment as refunded. Does NOT delete the
  /// original record — refunds are their own auditable event, exactly
  /// like Stripe/Shopify never delete a charge on refund, they create
  /// a linked refund event instead.
  Future<void> refundPayment(
    PaymentModel payment, {
    required String actorUid,
    required String actorName,
    String reason = '',
  }) async {
    if (payment.status != PaymentStatus.completed) {
      throw Exception('Only completed payments can be refunded.');
    }

    await _db.collection('payments').doc(payment.id).update({
      'status':    PaymentStatus.refunded.value,
      'updatedAt': DateTime.now().toIso8601String(),
      'notes': reason.trim().isNotEmpty
          ? '${payment.notes} [Refunded: $reason]'.trim()
          : payment.notes,
    });

    await _ns.addNotification(
      title:   'Payment Refunded',
      message: '${payment.customerName}\'s payment of '
          'Rs. ${payment.amount.toStringAsFixed(0)} was refunded.',
      type:    'warning',
    );

    // ── LOG: Payment Refund ─────────────────────────────────────────────
    await _log.log(
      userId:   actorUid,
      username: actorName,
      action:   ActivityAction.paymentRefund,
      entity:   ActivityEntity.payment,
      recordId: payment.id,
      details: {
        'saleId':       payment.saleId,
        'customerName': payment.customerName,
        'amount':       payment.amount,
        'reason':       reason,
      },
    );
  }
}