import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/notifications/models/notification_model.dart';

/// In-memory list of all app notifications.
///
/// Full persistence via Sembast is wired in a later phase.
final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, List<NotificationModel>>(
  (ref) => NotificationsNotifier(),
);

/// Count of unread notifications.
final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).where((n) => !n.isRead).length;
});

class NotificationsNotifier extends StateNotifier<List<NotificationModel>> {
  NotificationsNotifier() : super([]);

  void add(NotificationModel notification) {
    state = [notification, ...state];
  }

  void markAsRead(String id) {
    state = [
      for (final n in state)
        if (n.id == id) n.copyWith(isRead: true) else n,
    ];
  }

  void markAllAsRead() {
    state = [for (final n in state) n.copyWith(isRead: true)];
  }

  void delete(String id) {
    state = state.where((n) => n.id != id).toList();
  }

  void deleteAll() {
    state = [];
  }
}
