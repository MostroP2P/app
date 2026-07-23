import 'package:uuid/uuid.dart';

import 'package:mostro/l10n/app_localizations.dart';

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

  /// Bond-slashed notification. Only stable, locale-independent data is stored;
  /// the user-facing title, message and detail labels are localized at render
  /// time via [resolvedTitle] / [resolvedMessage] / [resolvedDetail], so a
  /// language change is reflected without rebuilding stored records.
  ///
  /// [id] must be the source gift-wrap event id: the daemon replays stored
  /// history on reconnect/restart, so keying the record on it makes the
  /// upserting store idempotent — one slash yields exactly one notification.
  factory NotificationModel.bondSlashed({
    required String id,
    required String orderId,
    required int amountSats,
    required bool disputeCause,
    String? fiatCode,
    int? fiatAmount,
    String? paymentMethod,
  }) {
    return NotificationModel(
      id: id,
      type: NotificationType.bondSlashed,
      title: '',
      message: '',
      timestamp: DateTime.now(),
      orderId: orderId,
      detail: {
        // Stable keys and raw values — never localized labels. The amount is
        // stored without a "sats" suffix so the group-card sats heuristic does
        // not surface the bond amount as the trade amount.
        _bondAmountKey: '$amountSats',
        _bondCauseKey: disputeCause ? _bondCauseDispute : _bondCauseTimeout,
        if (fiatCode != null && fiatAmount != null) ...{
          _bondFiatCodeKey: fiatCode,
          _bondFiatAmountKey: '$fiatAmount',
        },
        if (paymentMethod != null && paymentMethod.isNotEmpty)
          _bondPaymentMethodKey: paymentMethod,
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

  // ── Bond-slashed rendering ──────────────────────────────────────────────────
  // Stable, locale-independent keys/values persisted by [bondSlashed]. Localized
  // labels are produced at render time by the resolved* accessors below.
  static const _bondAmountKey = 'bondAmountSats';
  static const _bondCauseKey = 'cause';
  static const _bondFiatCodeKey = 'fiatCode';
  static const _bondFiatAmountKey = 'fiatAmount';
  static const _bondPaymentMethodKey = 'paymentMethod';
  static const _bondCauseDispute = 'dispute';
  static const _bondCauseTimeout = 'timeout';

  bool get _isBondSlashed => type == NotificationType.bondSlashed;

  /// Title for display, localized at render time for bond-slashed notices and
  /// falling back to the stored [title] for other types.
  String resolvedTitle(AppLocalizations l10n) =>
      _isBondSlashed ? l10n.bondSlashedTitle : title;

  /// Message for display (see [resolvedTitle]).
  String resolvedMessage(AppLocalizations l10n) {
    if (!_isBondSlashed) return message;
    final amount = detail?[_bondAmountKey] ?? '0';
    final id = orderId ?? '';
    return detail?[_bondCauseKey] == _bondCauseDispute
        ? l10n.bondSlashedMessageDispute(amount, id)
        : l10n.bondSlashedMessageTimeout(amount, id);
  }

  /// Detail rows for display, built from the stable stored keys and localized at
  /// render time (see [resolvedTitle]).
  Map<String, String> resolvedDetail(AppLocalizations l10n) {
    if (!_isBondSlashed) return detail ?? const {};
    final d = detail ?? const {};
    final amount = d[_bondAmountKey] ?? '0';
    final fiatCode = d[_bondFiatCodeKey];
    final fiatAmount = d[_bondFiatAmountKey];
    final paymentMethod = d[_bondPaymentMethodKey];
    return {
      l10n.bondSlashedDetailOrder: orderId ?? '',
      l10n.bondSlashedDetailAmount: '$amount sats',
      l10n.bondSlashedDetailCause: d[_bondCauseKey] == _bondCauseDispute
          ? l10n.bondSlashedCauseDispute
          : l10n.bondSlashedCauseTimeout,
      if (fiatCode != null && fiatAmount != null)
        l10n.bondSlashedDetailFiat: '$fiatAmount $fiatCode',
      if (paymentMethod != null && paymentMethod.isNotEmpty)
        l10n.bondSlashedDetailPaymentMethod: paymentMethod,
    };
  }
}