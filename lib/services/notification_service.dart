import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';

class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Get all notifications
  Stream<List<NotificationModel>> getNotifications() {
    return _db
        .collection('notifications')
        .orderBy('time', descending: true)
        .limit(20)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => NotificationModel.fromJson(d.data()))
            .toList());
  }

  // Get unread count
  Stream<int> getUnreadCount() {
    return _db
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  // Mark as read
  Future<void> markAsRead(String id) async {
    await _db.collection('notifications').doc(id).update({'isRead': true});
  }

  // Mark all as read
  Future<void> markAllAsRead() async {
    final batch = _db.batch();
    final unread = await _db
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .get();
    for (var doc in unread.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  // Add notification
  Future<void> addNotification({
    required String title,
    required String message,
    required String type,
  }) async {
    final ref = _db.collection('notifications').doc();
    await ref.set({
      'id': ref.id,
      'title': title,
      'message': message,
      'type': type,
      'isRead': false,
      'time': DateTime.now().toString().substring(0, 16),
    });
  }

  // Check low stock and auto notify
  Future<void> checkLowStock() async {
    final products = await _db.collection('products').get();
    for (var doc in products.docs) {
      final data = doc.data();
      final stock = data['stock'] ?? 0;
      final name = data['name'] ?? '';
      if (stock < 10) {
        // Check if notification already exists
        final existing = await _db
            .collection('notifications')
            .where('type', isEqualTo: 'low_stock')
            .where('message', isEqualTo: '$name has only $stock items left!')
            .get();
        if (existing.docs.isEmpty) {
          await addNotification(
            title: '⚠️ Low Stock Alert',
            message: '$name has only $stock items left!',
            type: 'low_stock',
          );
        }
      }
    }
  }
}