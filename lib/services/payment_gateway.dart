// ============================================================
// lib/services/payment_gateway.dart
//
// GATEWAY ABSTRACTION LAYER
//
// WHY THIS FILE EXISTS:
// This mirrors how Stripe's own SDK separates "PaymentIntent" (the
// universal contract) from "PaymentMethod processors" (the actual
// rails — card, bank, wallet). Today FabricFlow only has ONE real
// implementation: ManualPaymentGateway, which just marks a payment
// completed instantly because cash/bank-transfer happen outside the
// app. When a real JazzCash/EasyPaisa/Stripe merchant account is
// available, you add:
//
//   class JazzCashGateway implements PaymentGateway { ... }
//
// ...call its real HTTP API inside `processPayment`, and switch ONE
// line in PaymentGatewayRegistry. PaymentService, the UI, and the
// PaymentModel schema do NOT change. That is the entire point of
// this layer existing.
// ============================================================
import '../models/payment_model.dart';

/// Result of attempting to process a payment through a gateway.
/// Deliberately mirrors the shape of a real gateway's response
/// (success flag, gateway-assigned reference, raw payload) so a real
/// integration slots in without changing this contract.
class GatewayResult {
  final bool                 success;
  final String                transactionRef;
  final String                message;
  final Map<String, dynamic>  rawResponse;

  const GatewayResult({
    required this.success,
    required this.transactionRef,
    this.message     = '',
    this.rawResponse = const {},
  });
}

/// The contract every payment gateway must satisfy — manual today,
/// real APIs in the future. NEVER call a specific gateway class
/// directly from UI/service code; always go through this interface
/// via PaymentGatewayRegistry so swapping implementations later is a
/// one-line change.
abstract class PaymentGateway {
  /// Unique id stored on PaymentModel.gatewayId, e.g. 'manual',
  /// 'jazzcash_api', 'easypaisa_api', 'stripe_api'.
  String get id;

  /// Which PaymentMethod values this gateway is able to process.
  /// ManualPaymentGateway accepts all of them (it just records what
  /// the customer says they used); a real JazzCashGateway would only
  /// declare PaymentMethod.jazzCash.
  List<PaymentMethod> get supportedMethods;

  Future<GatewayResult> processPayment({
    required double          amount,
    required PaymentMethod   method,
    required String          transactionRef,
    Map<String, dynamic>     metadata = const {},
  });
}

/// Default gateway used for every payment today. It does not call any
/// external API — it simply validates and confirms the payment was
/// recorded, exactly like how a cashier manually marks an invoice
/// paid in any real ERP (Zoho, Tally, QuickBooks all support this
/// "manual/offline payment" mode alongside real gateways).
class ManualPaymentGateway implements PaymentGateway {
  @override
  String get id => PaymentModel.manualGatewayId;

  @override
  List<PaymentMethod> get supportedMethods => PaymentMethod.values;

  @override
  Future<GatewayResult> processPayment({
    required double        amount,
    required PaymentMethod method,
    required String        transactionRef,
    Map<String, dynamic>   metadata = const {},
  }) async {
    if (amount <= 0) {
      return const GatewayResult(
        success: false,
        transactionRef: '',
        message: 'Payment amount must be greater than zero.',
      );
    }
    if (method.requiresReference && transactionRef.trim().isEmpty) {
      return GatewayResult(
        success: false,
        transactionRef: '',
        message:
            'A transaction reference is required for ${method.value} payments.',
      );
    }

    final ref = transactionRef.trim().isNotEmpty
        ? transactionRef.trim()
        : 'CASH-${DateTime.now().millisecondsSinceEpoch}';

    return GatewayResult(
      success: true,
      transactionRef: ref,
      message: 'Recorded manually.',
      rawResponse: const {'mode': 'manual'},
    );
  }
}

// ── STUBS FOR FUTURE REAL INTEGRATIONS ───────────────────────────────────
// Intentionally left as commented skeletons rather than half-finished
// classes — an incomplete class that throws UnimplementedError would
// pass `flutter analyze` but crash at runtime if ever accidentally
// selected. Uncomment and complete one of these when real merchant
// credentials are available; register it in PaymentGatewayRegistry.
//
// class JazzCashGateway implements PaymentGateway {
//   final String merchantId;
//   final String password;
//   final String integritySalt;
//   JazzCashGateway({required this.merchantId, required this.password, required this.integritySalt});
//
//   @override
//   String get id => 'jazzcash_api';
//
//   @override
//   List<PaymentMethod> get supportedMethods => [PaymentMethod.jazzCash];
//
//   @override
//   Future<GatewayResult> processPayment({
//     required double amount,
//     required PaymentMethod method,
//     required String transactionRef,
//     Map<String, dynamic> metadata = const {},
//   }) async {
//     // POST to JazzCash's REST API here, parse response, return GatewayResult.
//     throw UnimplementedError('Plug in real JazzCash API call here.');
//   }
// }
//
// class StripeGateway implements PaymentGateway {
//   final String secretKey;
//   StripeGateway({required this.secretKey});
//
//   @override
//   String get id => 'stripe_api';
//
//   @override
//   List<PaymentMethod> get supportedMethods => [PaymentMethod.card];
//
//   @override
//   Future<GatewayResult> processPayment({
//     required double amount,
//     required PaymentMethod method,
//     required String transactionRef,
//     Map<String, dynamic> metadata = const {},
//   }) async {
//     // Call Stripe's PaymentIntents API here.
//     throw UnimplementedError('Plug in real Stripe API call here.');
//   }
// }

/// Central lookup so PaymentService never has to know which concrete
/// gateway class is in use — it just asks the registry "give me the
/// active gateway for this method".
class PaymentGatewayRegistry {
  PaymentGatewayRegistry._();

  static final PaymentGateway _manual = ManualPaymentGateway();

  // To go live with a real gateway later:
  //   1. Finish one of the stub classes above.
  //   2. Add it to this map, e.g. PaymentMethod.jazzCash: JazzCashGateway(...).
  //   3. Nothing else in the app needs to change.
  static final Map<PaymentMethod, PaymentGateway> _activeGateways = {
    PaymentMethod.cash:         _manual,
    PaymentMethod.bankTransfer: _manual,
    PaymentMethod.jazzCash:     _manual, // swap with JazzCashGateway(...) when ready
    PaymentMethod.easyPaisa:    _manual, // swap with EasyPaisaGateway(...) when ready
    PaymentMethod.card:         _manual, // swap with StripeGateway(...) when ready
  };

  static PaymentGateway gatewayFor(PaymentMethod method) =>
      _activeGateways[method] ?? _manual;
}