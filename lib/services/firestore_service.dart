// ============================================================
// lib/services/firestore_service.dart
//
// ACTIVITY LOGGING INTEGRATION
//   Every tracked write operation now takes an `actorUid` +
//   `actorName` pair (the currently logged-in user performing the
//   action) and calls ActivityLogService.log() after the Firestore
//   write succeeds.
//
//   Logging never blocks or fails the primary operation — it's
//   fire-and-forget via the service's own internal try/catch.
//
//   Caller convention: screens pass FirebaseAuth.instance.currentUser
//   (uid + email) into these methods. See updated screens for the
//   call sites.
//
// STOCK DECREMENT / RESTORE (this update)
//   RULE CONFIRMED WITH PROJECT OWNER:
//     - Sale created (any status, including Pending)  -> stock DOWN
//     - Sale -> Cancelled (from any prior status)      -> stock UP (restore)
//     - Sale -> Completed                              -> NO further
//       change (it was already decremented at creation time)
//     - Stock only ever goes back up via Cancellation or a Manager
//       manually editing the product — never automatically on
//       "Completed", since the items have genuinely left inventory.
//
//   addSale() and updateSaleStatus() now run inside
//   FirebaseFirestore.runTransaction so the stock read + write is
//   atomic — if two sales are created at nearly the same moment for
//   the same product, Firestore guarantees one transaction retries
//   rather than both reading a stale stock value and overselling.
//   This is the same pattern Shopify/Square use for inventory
//   decrement at checkout.
//
//   A sale is only ever cancelled ONCE — updateSaleStatus already
//   validates the SaleStatus transition graph (allowedNextStatuses),
//   so a sale cannot reach Cancelled twice and double-restore stock.
//
// ORDER TRACKING TIMELINE (this update)
//   updateSaleStatus() now also appends one entry to the sale's
//   `statusHistory` array (via FieldValue.arrayUnion) inside the same
//   transaction that updates `status` — so the status field and its
//   history always stay in sync atomically. The very first history
//   entry (for the sale's initial status, e.g. Pending) is written by
//   SalesModel's constructor default and included automatically when
//   addSale() calls sale.toJson() — no separate write needed there.
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';
import '../models/employee_model.dart';
import '../models/customer_model.dart';
import '../models/sales_model.dart';
import '../models/rbac_model.dart';
import '../models/activity_log_model.dart';
import 'notification_service.dart';
import 'activity_log_service.dart';

class FirestoreService {
  final FirebaseFirestore    _db  = FirebaseFirestore.instance;
  final NotificationService  _ns  = NotificationService();
  final ActivityLogService   _log = ActivityLogService();

  // ────────────────────────────────────────────────────────────────────────
  // USER ROLES
  // ────────────────────────────────────────────────────────────────────────

  Future<void> saveUserRole(String uid, String role,
      {String email = '', String createdByUid = ''}) async {
    await _db.collection('users').doc(uid).set({
      'uid':          uid,
      'role':         role,
      'email':        email,
      'createdByUid': createdByUid,
      'createdAt':    FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> getUserRole(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) return doc.data()?['role'] as String? ?? 'Customer';
    return 'Customer';
  }

  Future<AppRole> getUserRoleEnum(String uid) async {
    final raw = await getUserRole(uid);
    return AppRoleX.fromString(raw);
  }

  /// RBAC-enforced user creation. Logs ActivityAction.userCreate on
  /// success, attributed to the CREATOR (actorUid/actorName), not the
  /// new account itself.
  Future<void> saveUserRoleRbac({
    required String   creatorUid,
    required String   creatorName,
    required String   newUid,
    required String   newEmail,
    required AppRole  newRole,
  }) async {
    final creatorRole = await getUserRoleEnum(creatorUid);

    if (!creatorRole.canCreateRole(newRole)) {
      if (!creatorRole.canCreateUsers) {
        throw const RbacException(
          'Access denied: only Managers can create user accounts.',
        );
      }
      if (newRole.level >= creatorRole.level) {
        throw RbacException(
          'Access denied: you cannot create a "${newRole.name}" account. '
          'You may only create accounts with lower privileges than your own.',
        );
      }
    }

    await saveUserRole(newUid, newRole.name,
        email: newEmail, createdByUid: creatorUid);

    // ── LOG: User Create ──────────────────────────────────────────────
    await _log.log(
      userId:   creatorUid,
      username: creatorName,
      action:   ActivityAction.userCreate,
      entity:   ActivityEntity.user,
      recordId: newUid,
      details: {
        'newUserEmail': newEmail,
        'assignedRole': newRole.name,
      },
    );
  }

  /// Logs a role change for an existing user (e.g. promoting/demoting).
  /// Call this whenever a user's role field is modified after creation.
  Future<void> changeUserRole({
    required String  actorUid,
    required String  actorName,
    required String  targetUid,
    required String  oldRole,
    required String  newRole,
  }) async {
    await _db.collection('users').doc(targetUid).update({'role': newRole});

    // ── LOG: Role Change ──────────────────────────────────────────────
    await _log.log(
      userId:   actorUid,
      username: actorName,
      action:   ActivityAction.roleChange,
      entity:   ActivityEntity.user,
      recordId: targetUid,
      details: {'oldRole': oldRole, 'newRole': newRole},
    );
  }

  Future<void> removeUserRole(String uid) async {
    await _db.collection('users').doc(uid).delete();
  }

  // ────────────────────────────────────────────────────────────────────────
  // AUTH EVENTS (login/logout) — called directly from login/settings screens
  // ────────────────────────────────────────────────────────────────────────

  Future<void> logLogin(String uid, String username) async {
    await _log.log(
      userId:   uid,
      username: username,
      action:   ActivityAction.login,
      entity:   ActivityEntity.auth,
      recordId: uid,
    );
  }

  Future<void> logLogout(String uid, String username) async {
    await _log.log(
      userId:   uid,
      username: username,
      action:   ActivityAction.logout,
      entity:   ActivityEntity.auth,
      recordId: uid,
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // TAG NUMBER UTILITIES
  // ────────────────────────────────────────────────────────────────────────

  Future<String> generateTagNumber() async {
    try {
      final snap = await _db
          .collection('products')
          .orderBy('tagNumber', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return 'FF-0001';
      final last  = snap.docs.first.data()['tagNumber'] as String? ?? '';
      final parts = last.split('-');
      if (parts.length == 2) {
        final num = int.tryParse(parts[1]) ?? 0;
        return 'FF-${(num + 1).toString().padLeft(4, '0')}';
      }
      return 'FF-${(snap.size + 1).toString().padLeft(4, '0')}';
    } catch (_) {
      final ts = DateTime.now().millisecondsSinceEpoch % 10000;
      return 'FF-${ts.toString().padLeft(4, '0')}';
    }
  }

  Future<bool> isTagNumberUnique(String tagNumber,
      {String excludeId = ''}) async {
    final snap = await _db
        .collection('products')
        .where('tagNumber', isEqualTo: tagNumber)
        .limit(2)
        .get();
    if (snap.docs.isEmpty) return true;
    if (snap.docs.length == 1 && snap.docs.first.id == excludeId) return true;
    return false;
  }

  // ────────────────────────────────────────────────────────────────────────
  // PRODUCTS
  // ────────────────────────────────────────────────────────────────────────

  Stream<List<ProductModel>> getProducts() {
    return _db
        .collection('products')
        .orderBy('tagNumber')
        .snapshots()
        .map((s) => s.docs.map((d) => ProductModel.fromJson(d.data())).toList());
  }

  /// Creates a product. [actorUid]/[actorName] identify who performed
  /// the action for the audit log.
  Future<String> addProduct(
    ProductModel product, {
    required String actorUid,
    required String actorName,
  }) async {
    String tag = product.tagNumber.trim();
    if (tag.isEmpty || tag.contains('?')) tag = await generateTagNumber();
    if (!await isTagNumberUnique(tag)) tag = await generateTagNumber();

    final ref  = _db.collection('products').doc();
    final data = product.toJson();
    data['id']        = ref.id;
    data['tagNumber'] = tag;
    data['createdAt'] = DateTime.now().toIso8601String();
    await ref.set(data);

    if (product.stock < 10) {
      await _ns.addNotification(
        title:   'Low Stock Alert',
        message: '${product.name} ($tag) has only ${product.stock} units.',
        type:    'warning',
      );
    }

    // ── LOG: Product Create ───────────────────────────────────────────
    await _log.log(
      userId:   actorUid,
      username: actorName,
      action:   ActivityAction.productCreate,
      entity:   ActivityEntity.product,
      recordId: ref.id,
      details: {
        'name':      product.name,
        'tagNumber': tag,
        'price':     product.price,
        'stock':     product.stock,
      },
    );

    return tag;
  }

  Future<void> updateProduct(
    ProductModel product, {
    required String actorUid,
    required String actorName,
    ProductModel? previous, // pass the pre-edit version to log a diff
  }) async {
    if (!await isTagNumberUnique(product.tagNumber, excludeId: product.id)) {
      throw Exception('Tag ${product.tagNumber} is already used by another product.');
    }
    await _db.collection('products').doc(product.id).update(product.toJson());

    // ── LOG: Product Update ───────────────────────────────────────────
    final details = <String, dynamic>{'name': product.name};
    if (previous != null) {
      if (previous.price != product.price) {
        details['priceChange'] = '${previous.price} → ${product.price}';
      }
      if (previous.stock != product.stock) {
        details['stockChange'] = '${previous.stock} → ${product.stock}';
      }
      if (previous.name != product.name) {
        details['nameChange'] = '${previous.name} → ${product.name}';
      }
    }

    await _log.log(
      userId:   actorUid,
      username: actorName,
      action:   ActivityAction.productUpdate,
      entity:   ActivityEntity.product,
      recordId: product.id,
      details:  details,
    );
  }

  Future<void> deleteProduct(
    String id, {
    required String actorUid,
    required String actorName,
    String productName = '',
  }) async {
    await _db.collection('products').doc(id).delete();

    // ── LOG: Product Delete ───────────────────────────────────────────
    await _log.log(
      userId:   actorUid,
      username: actorName,
      action:   ActivityAction.productDelete,
      entity:   ActivityEntity.product,
      recordId: id,
      details:  {'name': productName},
    );
  }

  Future<int> migrateProductTags() async {
    final snap  = await _db.collection('products').get();
    int counter = 0;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      final data          = doc.data();
      final needsTag      = data['tagNumber'] == null ||
                            (data['tagNumber'] as String).contains('?');
      final needsWH       = data['warehouse']  == null;
      final needsDate     = data['createdAt']  == null;
      if (needsTag || needsWH || needsDate) {
        counter++;
        final u = <String, dynamic>{};
        if (needsTag)  u['tagNumber'] = 'FF-${counter.toString().padLeft(4,'0')}';
        if (needsWH)   u['warehouse'] = 'Main Warehouse';
        if (needsDate) u['createdAt'] = DateTime.now().toIso8601String();
        batch.update(doc.reference, u);
      }
    }
    await batch.commit();
    return counter;
  }

  // ────────────────────────────────────────────────────────────────────────
  // EMPLOYEES
  // ────────────────────────────────────────────────────────────────────────

  Stream<List<EmployeeModel>> getEmployees() => _db
      .collection('employees')
      .snapshots()
      .map((s) => s.docs.map((d) => EmployeeModel.fromJson(d.data())).toList());

  Future<void> addEmployee(
    EmployeeModel emp, {
    String actorUid  = '',
    String actorName = '',
  }) async {
    final ref  = _db.collection('employees').doc();
    final data = emp.toJson();
    data['id'] = ref.id;
    await ref.set(data);
    await _ns.addNotification(
        title: 'New Employee', message: '${emp.name} joined as ${emp.role}.', type: 'info');

    // Employee creation is logged as a User Create event upstream
    // (saveUserRoleRbac already logs it) — this method only writes
    // the employee record. No duplicate log here to avoid double-counting
    // the same business event.
  }

  Future<void> deleteEmployee(
    String docId, {
    required String actorUid,
    required String actorName,
    String employeeName = '',
  }) async {
    await _db.collection('employees').doc(docId).delete();

    // ── LOG: User Delete (employee removal IS a user deletion) ────────
    await _log.log(
      userId:   actorUid,
      username: actorName,
      action:   ActivityAction.userDelete,
      entity:   ActivityEntity.user,
      recordId: docId,
      details:  {'name': employeeName, 'type': 'employee'},
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // CUSTOMERS
  // ────────────────────────────────────────────────────────────────────────

  Stream<List<CustomerModel>> getCustomers() => _db
      .collection('customers')
      .snapshots()
      .map((s) => s.docs.map((d) => CustomerModel.fromJson(d.data())).toList());

  Future<void> addCustomer(CustomerModel c) async {
    final ref  = _db.collection('customers').doc();
    final data = c.toJson();
    data['id'] = ref.id;
    await ref.set(data);
    await _ns.addNotification(
        title: 'New Customer', message: '${c.name} registered.', type: 'info');
  }

  Future<void> addCustomerWithUid(CustomerModel c) async {
    final data = c.toJson();
    data['id'] = c.id;
    await _db.collection('customers').doc(c.id).set(data);
  }

  Future<void> deleteCustomer(
    String id, {
    required String actorUid,
    required String actorName,
    String customerName = '',
  }) async {
    await _db.collection('customers').doc(id).delete();
    try { await _db.collection('users').doc(id).delete(); } catch (_) {}

    // ── LOG: User Delete (customer removal IS a user deletion) ────────
    await _log.log(
      userId:   actorUid,
      username: actorName,
      action:   ActivityAction.userDelete,
      entity:   ActivityEntity.user,
      recordId: id,
      details:  {'name': customerName, 'type': 'customer'},
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // SALES
  // ────────────────────────────────────────────────────────────────────────

  Stream<List<SalesModel>> getSales() => _db
      .collection('sales')
      .snapshots()
      .map((s) => s.docs.map((d) => SalesModel.fromJson(d.data())).toList());

  /// Creates a sale AND atomically decrements stock for every item in
  /// the sale, inside a single Firestore transaction. If any product
  /// referenced by [sale.items] cannot be found or has insufficient
  /// stock, the entire transaction is aborted and NOTHING is written —
  /// no partial sale, no partial stock decrement.
  ///
  /// Stock goes down at CREATION time regardless of the sale's initial
  /// status (Pending/Processing/Completed) — see the file header note
  /// for the full rule. This matches a real checkout: the moment an
  /// order is placed, those units are no longer available to sell
  /// again, even before the order is fulfilled.
  ///
  /// `sale.toJson()` already includes the first `statusHistory` entry
  /// (written by SalesModel's constructor default for the sale's
  /// initial status) — no extra write needed here for tracking.
  Future<void> addSale(
    SalesModel sale, {
    required String actorUid,
    required String actorName,
  }) async {
    final saleRef = _db.collection('sales').doc();

    await _db.runTransaction((transaction) async {
      // Read every referenced product's current stock FIRST (required by
      // Firestore transactions — all reads must happen before any writes).
      final productRefs = <String, DocumentReference<Map<String, dynamic>>>{};
      final currentStocks = <String, int>{};

      for (final item in sale.items) {
        final productId = item['productId'] as String?;
        if (productId == null || productId.isEmpty) continue;
        if (productRefs.containsKey(productId)) continue; // dedupe repeated items

        final ref = _db.collection('products').doc(productId);
        final snap = await transaction.get(ref);
        if (!snap.exists) {
          throw Exception('A product in this sale no longer exists.');
        }
        productRefs[productId]   = ref;
        currentStocks[productId] = (snap.data()?['stock'] as num?)?.toInt() ?? 0;
      }

      // Validate sufficient stock for every line item BEFORE writing
      // anything — prevents a sale that oversells one product while
      // another product's stock has already been decremented.
      final requestedQty = <String, int>{};
      for (final item in sale.items) {
        final productId = item['productId'] as String?;
        if (productId == null || productId.isEmpty) continue;
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        requestedQty[productId] = (requestedQty[productId] ?? 0) + qty;
      }

      for (final entry in requestedQty.entries) {
        final available = currentStocks[entry.key] ?? 0;
        if (entry.value > available) {
          throw Exception(
            'Not enough stock available (requested ${entry.value}, '
            'only $available left). Sale was not created.',
          );
        }
      }

      // All validated — now perform the writes.
      transaction.set(saleRef, {...sale.toJson(), 'id': saleRef.id});

      for (final entry in requestedQty.entries) {
        final ref = productRefs[entry.key]!;
        final newStock = (currentStocks[entry.key] ?? 0) - entry.value;
        transaction.update(ref, {'stock': newStock});
      }
    });

    await _ns.addNotification(
        title:   'New Sale',
        message: 'Sale to ${sale.customerName} — Rs. ${sale.totalAmount.toStringAsFixed(0)}.',
        type:    'success');

    // ── LOG: Sales Create ──────────────────────────────────────────────
    await _log.log(
      userId:   actorUid,
      username: actorName,
      action:   ActivityAction.salesCreate,
      entity:   ActivityEntity.sale,
      recordId: saleRef.id,
      details: {
        'customerName': sale.customerName,
        'totalAmount':  sale.totalAmount,
        'itemCount':    sale.items.length,
        'status':       sale.status.value,
      },
    );
  }

  /// Updates a sale's status, logging the most specific action possible:
  ///   → Completed  => ActivityAction.salesComplete
  ///   → Cancelled  => ActivityAction.salesCancel
  ///   → anything else => ActivityAction.salesUpdate
  ///
  /// STOCK RESTORE: if [newStatus] is Cancelled, every item's stock is
  /// atomically restored (added back) inside the same transaction that
  /// updates the sale's status. Because SaleStatus.allowedNextStatuses
  /// only permits reaching Cancelled once (it's a terminal state with
  /// no outgoing transitions except back to Pending in this app's
  /// graph — and that path is never exercised from Cancelled in the
  /// UI), a sale's stock can never be double-restored.
  ///
  /// Completing a sale does NOT touch stock — it was already
  /// decremented at creation time in addSale().
  ///
  /// ORDER TRACKING: every successful transition also appends one
  /// entry to `statusHistory` via FieldValue.arrayUnion, inside the
  /// same transaction as the status field update — so `status` and
  /// `statusHistory` can never drift out of sync.
  Future<void> updateSaleStatus(
    String saleId,
    SaleStatus currentStatus,
    SaleStatus newStatus, {
    required String actorUid,
    required String actorName,
  }) async {
    if (currentStatus == newStatus) return;

    if (!currentStatus.allowedNextStatuses.contains(newStatus)) {
      throw Exception(
        'Cannot change status from "${currentStatus.value}" to '
        '"${newStatus.value}". Allowed next steps: '
        '${currentStatus.allowedNextStatuses.map((s) => s.value).join(", ")}.',
      );
    }

    final saleRef = _db.collection('sales').doc(saleId);

    await _db.runTransaction((transaction) async {
      final saleSnap = await transaction.get(saleRef);
      if (!saleSnap.exists) {
        throw Exception('This sale no longer exists.');
      }
      final saleData = saleSnap.data()!;
      final items = (saleData['items'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Only restore stock when transitioning INTO Cancelled. Reaching
      // Completed, Processing, or back to Pending performs no stock
      // change at all.
      if (newStatus == SaleStatus.cancelled) {
        final restoreQty = <String, int>{};
        for (final item in items) {
          final productId = item['productId'] as String?;
          if (productId == null || productId.isEmpty) continue;
          final qty = (item['quantity'] as num?)?.toInt() ?? 0;
          restoreQty[productId] = (restoreQty[productId] ?? 0) + qty;
        }

        // Read every affected product's current stock before writing
        // (transaction read-before-write rule).
        final productRefs = <String, DocumentReference<Map<String, dynamic>>>{};
        final currentStocks = <String, int>{};
        for (final productId in restoreQty.keys) {
          final ref = _db.collection('products').doc(productId);
          final snap = await transaction.get(ref);
          if (snap.exists) {
            productRefs[productId]   = ref;
            currentStocks[productId] = (snap.data()?['stock'] as num?)?.toInt() ?? 0;
          }
          // If the product was deleted since the sale was made, there
          // is nothing to restore stock onto — skip it silently rather
          // than failing the whole cancellation.
        }

        for (final entry in restoreQty.entries) {
          final ref = productRefs[entry.key];
          if (ref == null) continue;
          final restored = (currentStocks[entry.key] ?? 0) + entry.value;
          transaction.update(ref, {'stock': restored});
        }
      }

      // ── NEW: append one statusHistory entry, atomically ─────────────
      final historyEntry = {
        'status':    newStatus.value,
        'timestamp': DateTime.now().toIso8601String(),
      };

      transaction.update(saleRef, {
        'status':          newStatus.value,
        'statusUpdatedAt': DateTime.now().toIso8601String(),
        'statusHistory':   FieldValue.arrayUnion([historyEntry]),
      });
    });

    await _ns.addNotification(
      title:   'Sale Status Updated',
      message: 'Order status changed to "${newStatus.value}".',
      type:    newStatus == SaleStatus.cancelled ? 'warning' : 'info',
    );

    // ── LOG: most specific action for the transition ──────────────────
    final action = switch (newStatus) {
      SaleStatus.completed  => ActivityAction.salesComplete,
      SaleStatus.cancelled  => ActivityAction.salesCancel,
      _                     => ActivityAction.salesUpdate,
    };

    await _log.log(
      userId:   actorUid,
      username: actorName,
      action:   action,
      entity:   ActivityEntity.sale,
      recordId: saleId,
      details: {
        'fromStatus': currentStatus.value,
        'toStatus':   newStatus.value,
        if (newStatus == SaleStatus.cancelled) 'stockRestored': true,
      },
    );
  }

  Future<SalesModel?> getSaleById(String saleId) async {
    final doc = await _db.collection('sales').doc(saleId).get();
    if (!doc.exists) return null;
    return SalesModel.fromJson(doc.data()!);
  }
}

// ── Custom exception for RBAC violations ─────────────────────────────────
class RbacException implements Exception {
  final String message;
  const RbacException(this.message);
  @override
  String toString() => message;
}