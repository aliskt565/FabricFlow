// ============================================================
// lib/services/activity_log_service.dart
//
// Central write/read API for the activity_logs collection.
// All other services (FirestoreService, auth screens) call into
// this rather than writing to Firestore directly, so the schema
// stays consistent everywhere.
// ============================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/activity_log_model.dart';

class ActivityLogService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _collection = 'activity_logs';

  // ── Write ────────────────────────────────────────────────────────────────

  /// Logs a single activity event. Never throws to the caller — logging
  /// failures must not block the actual business operation (e.g. if
  /// writing the log fails, the product should still get deleted).
  Future<void> log({
    required String         userId,
    required String         username,
    required ActivityAction action,
    required ActivityEntity entity,
    required String         recordId,
    Map<String, dynamic>    details = const {},
  }) async {
    try {
      final ref  = _db.collection(_collection).doc();
      final data = ActivityLogModel(
        id:       ref.id,
        userId:   userId,
        username: username,
        action:   action,
        entity:   entity,
        recordId: recordId,
        details:  details,
      ).toJson();

      // Add the trusted server timestamp alongside the client one.
      // We sort by this in queries — it can't be spoofed by a client
      // with a wrong device clock.
      data['serverTimestamp'] = FieldValue.serverTimestamp();

      await ref.set(data);
    } catch (e) {
      // Swallow — logging is best-effort and must never break the
      // primary action (delete/create/login etc).
      // ignore: avoid_print
      print('ActivityLogService.log failed: $e');
    }
  }

  // ── Read ─────────────────────────────────────────────────────────────────

  /// Real-time stream of the most recent [limit] logs, newest first.
  Stream<List<ActivityLogModel>> getRecentLogs({int limit = 100}) {
    return _db
        .collection(_collection)
        .orderBy('serverTimestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => ActivityLogModel.fromJson(d.data())).toList());
  }

  /// Logs filtered to one entity (e.g. only "Sale" activity).
  Stream<List<ActivityLogModel>> getLogsByEntity(
      ActivityEntity entity, {int limit = 100}) {
    return _db
        .collection(_collection)
        .where('entity', isEqualTo: entity.value)
        .orderBy('serverTimestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => ActivityLogModel.fromJson(d.data())).toList());
  }

  /// Logs filtered to one user (their personal activity history).
  Stream<List<ActivityLogModel>> getLogsByUser(
      String userId, {int limit = 100}) {
    return _db
        .collection(_collection)
        .where('userId', isEqualTo: userId)
        .orderBy('serverTimestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => ActivityLogModel.fromJson(d.data())).toList());
  }

  /// Logs filtered to a specific record (full history of one product,
  /// one sale, or one user account).
  Stream<List<ActivityLogModel>> getLogsByRecord(
      String recordId, {int limit = 100}) {
    return _db
        .collection(_collection)
        .where('recordId', isEqualTo: recordId)
        .orderBy('serverTimestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => ActivityLogModel.fromJson(d.data())).toList());
  }

  /// One-time fetch (non-stream) for export/reporting use cases.
  Future<List<ActivityLogModel>> fetchLogsInRange(
      DateTime from, DateTime to) async {
    final snap = await _db
        .collection(_collection)
        .where('serverTimestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('serverTimestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(to))
        .orderBy('serverTimestamp', descending: true)
        .get();
    return snap.docs.map((d) => ActivityLogModel.fromJson(d.data())).toList();
  }
}
