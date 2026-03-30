/// In-app notification record.
enum NotificationType {
  orderUpdate,
  tradeUpdate,
  payment,
  dispute,
  cancellation,
  message,
  system,
}

class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.orderId,
    this.disputeId,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final String? orderId;
  final String? disputeId;

  NotificationModel copyWith({
    bool? isRead,
    String? title,
    String? message,
  }) {
    return NotificationModel(
      id: id,
      type: type,
      title: title ?? this.title,
      message: message ?? this.message,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      orderId: orderId,
      disputeId: disputeId,
    );
  }
}
