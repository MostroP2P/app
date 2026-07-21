import 'package:uuid/uuid.dart';

/// In-app notification record.
enum NotificationType {
  orderUpdate,
  tradeUpdate,
  payment,
  dispute,
  cancellation,
  message,
  system,
  ratingReceived,
  paymentReceived,
  invoiceRequest,
  orderTaken,
  bondSlashed,
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
    this.detail,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final String? orderId;
  final String? disputeId;

  /// Optional key-value pairs shown in the card detail section.
  final Map<String, String>? detail;

  NotificationModel copyWith({
    bool? isRead,
    String? title,
    String? message,
    Map<String, String>? detail,
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
      detail: detail ?? this.detail,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'message': message,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'isRead': isRead,
      'orderId': orderId,
      'disputeId': disputeId,
      'detail': detail,
    };
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      type: NotificationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NotificationType.system,
      ),
      title: json['title'] as String,
      message: json['message'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      isRead: json['isRead'] as bool? ?? false,
      orderId: json['orderId'] as String?,
      disputeId: json['disputeId'] as String?,
      detail: (json['detail'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as String)),
    );
  }

  // ── Factory constructors ────────────────────────────────────────────────────

  factory NotificationModel.ratingReceived({
    required String orderId,
    required int score,
  }) {
    return NotificationModel(
      id: const Uuid().v4(),
      type: NotificationType.ratingReceived,
      title: 'Rating received',
      message: 'You received a $score-star rating for order $orderId.',
      timestamp: DateTime.now(),
      orderId: orderId,
      detail: {'Order': orderId, 'Score': '$score / 5'},
    );
  }

  factory NotificationModel.paymentReceived({
    required String orderId,
    required int sats,
  }) {
    return NotificationModel(
      id: const Uuid().v4(),
      type: NotificationType.paymentReceived,
      title: 'Payment received',
      message: 'You received $sats sats for order $orderId.',
      timestamp: DateTime.now(),
      orderId: orderId,
      detail: {'Order': orderId, 'Amount': '$sats sats'},
    );
  }

  factory NotificationModel.invoiceRequest({required String orderId}) {
    return NotificationModel(
      id: const Uuid().v4(),
      type: NotificationType.invoiceRequest,
      title: 'Invoice requested',
      message: 'Please add your Lightning invoice for order $orderId.',
      timestamp: DateTime.now(),
      orderId: orderId,
      detail: {'Order': orderId},
    );
  }

  factory NotificationModel.orderTaken({required String orderId}) {
    return NotificationModel(
      id: const Uuid().v4(),
      type: NotificationType.orderTaken,
      title: 'Order taken',
      message: 'Your order $orderId has been taken by a counterpart.',
      timestamp: DateTime.now(),
      orderId: orderId,
      detail: {'Order': orderId},
    );
  }

  factory NotificationModel.bondSlashed({
    required String orderId,
    required int amountSats,
    required bool disputeCause,
    String? fiatCode,
    int? fiatAmount,
    String? paymentMethod,
  }) {
    final causeText = disputeCause
        ? 'after a dispute resolution'
        : 'after a waiting-state timeout';
    return NotificationModel(
      id: const Uuid().v4(),
      type: NotificationType.bondSlashed,
      title: 'Bond slashed',
      message:
          'Your $amountSats-sat anti-abuse bond for order $orderId was '
          'forfeited $causeText. Your order status is unchanged.',
      timestamp: DateTime.now(),
      orderId: orderId,
      detail: {
        'Order': orderId,
        'Bond amount': '$amountSats sats',
        'Cause': disputeCause ? 'Dispute resolution' : 'Waiting-state timeout',
        if (fiatCode != null && fiatAmount != null)
          'Fiat': '$fiatAmount $fiatCode',
        if (paymentMethod != null && paymentMethod.isNotEmpty)
          'Payment method': paymentMethod,
      },
    );
  }

  factory NotificationModel.backupReminder() {
    return NotificationModel(
      id: const Uuid().v4(),
      type: NotificationType.system,
      title: 'Back up your account',
      message: 'Save your secret words to avoid losing access to your account.',
      timestamp: DateTime.now(),
    );
  }
}