import 'package:flutter/material.dart';
import '../../models/notification_model.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  IconData _getIcon(String type) {
    switch (type) {
      case 'low_stock':  return Icons.warning_amber_rounded;
      case 'new_sale':   return Icons.shopping_cart_rounded;
      case 'new_customer': return Icons.person_add_rounded;
      default:           return Icons.notifications_rounded;
    }
  }

  Color _getColor(String type) {
    switch (type) {
      case 'low_stock':    return AppColors.danger;
      case 'new_sale':     return AppColors.primary;
      case 'new_customer': return AppColors.teal;
      default:             return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = NotificationService();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('Notifications', style: AppText.title()),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
        actions: [
          TextButton(
            onPressed: () => service.markAllAsRead(),
            child: Text('Mark all read',
                style: AppText.caption(color: AppColors.primary).copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: StreamBuilder<List<NotificationModel>>(
        stream: service.getNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                      color: AppColors.surface, shape: BoxShape.circle),
                  child: const Icon(Icons.notifications_off_outlined,
                      size: 48, color: AppColors.textDisabled),
                ),
                const SizedBox(height: 16),
                Text('No notifications yet', style: AppText.title().copyWith(fontSize: 18)),
                const SizedBox(height: 8),
                Text('You\'re all caught up!',
                    style: AppText.body(color: AppColors.textDisabled)),
              ],
            ));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final n = snapshot.data![index];
              final color = _getColor(n.type);
              return GestureDetector(
                onTap: () => service.markAsRead(n.id),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: n.isRead
                        ? AppColors.surface
                        : color.withValues(alpha: .08),
                    borderRadius: AppRadius.lgRadius,
                    border: Border.all(
                      color: n.isRead
                          ? Colors.white.withValues(alpha: .06)
                          : color.withValues(alpha: .3),
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .15),
                        borderRadius: AppRadius.mdRadius,
                      ),
                      child: Icon(_getIcon(n.type), color: color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(child: Text(n.title,
                              style: AppText.body().copyWith(
                                  fontWeight: n.isRead
                                      ? FontWeight.w400
                                      : FontWeight.w600,
                                  fontSize: 14))),
                          if (!n.isRead)
                            Container(
                              width: 8, height: 8,
                              decoration: BoxDecoration(
                                  color: color, shape: BoxShape.circle),
                            ),
                        ]),
                        const SizedBox(height: 4),
                        Text(n.message,
                            style: AppText.caption(color: AppColors.textTertiary)
                                .copyWith(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(n.time,
                            style: AppText.caption(color: AppColors.textDisabled)
                                .copyWith(fontSize: 11)),
                      ],
                    )),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}