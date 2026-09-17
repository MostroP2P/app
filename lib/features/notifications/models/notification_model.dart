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

  /// A slashed bond's share is claimable, or was paid (docs/ANTI_ABUSE_BOND.md §8.5).
  bondClaim,
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
      detail: (json['detail'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as String),
      ),
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

  /// A payout claim to act on, or one that was paid. [id] is stable per
  /// claim — the issuing node and the slash anchor, not just the order: a
  /// later slash, or another node, is another claim — and per phase, so the
  /// daemon's cadence retries never add a second record; a re-prompt
  /// carries a fresh [updatedAt] and does.
  factory NotificationModel.bondClaim({
    required String orderId,
    required String nodePubkey,
    required int slashedAt,
    required int amountSats,
    required bool completed,
    required int updatedAt,
  }) {
    final claimId = 'bond-claim-$orderId-$nodePubkey-$slashedAt';
    return NotificationModel(
      id: completed ? '$claimId-completed' : '$claimId-pending-$updatedAt',
      type: NotificationType.bondClaim,
      title: '',
      message: '',
      timestamp: DateTime.now(),
      orderId: orderId,
      detail: {
        _bondAmountKey: '$amountSats',
        _claimStateKey: completed ? _claimStatePaid : _claimStatePending,
      },
    );
  }

  /// A trade status change (issue #474). [status] and [reason] are the
  /// bridge enums' names — stable, locale-independent — and the copy is
  /// resolved at render time. The id is the order and the status (and the
  /// reason, when there is one), so a replay of the same transition, or the
  /// same status re-emitted to refresh a screen, adds nothing.
  factory NotificationModel.tradeStatus({
    required String orderId,
    required String status,
    String? reason,
    required DateTime at,
  }) {
    return NotificationModel(
      id: 'trade-$orderId-$status${reason == null ? '' : '-$reason'}',
      type: NotificationType.tradeUpdate,
      title: '',
      message: '',
      timestamp: at,
      orderId: orderId,
      detail: {
        _tradeStatusKey: status,
        if (reason != null) _tradeReasonKey: reason,
      },
    );
  }

  /// The one card a trade's chat keeps: [count] messages the user has not
  /// seen on it, the latest at [at]. The solver's messages keep their own
  /// card, since they matter differently.
  factory NotificationModel.chatMessages({
    required String tradeId,
    required bool fromSolver,
    required int count,
    required DateTime at,
  }) {
    return NotificationModel(
      id: chatCardId(tradeId, fromSolver: fromSolver),
      type: NotificationType.message,
      title: '',
      message: '',
      timestamp: at,
      orderId: tradeId,
      detail: {_chatCountKey: '$count', if (fromSolver) _chatSolverKey: 'true'},
    );
  }

  /// The id of a trade's chat card; see [NotificationModel.chatMessages].
  static String chatCardId(String tradeId, {required bool fromSolver}) =>
      'chat-$tradeId${fromSolver ? '-solver' : ''}';

  /// A chat card holding the dispute solver's messages, which open the
  /// trade rather than the peer chat.
  bool get isSolverChatCard => _isChatCard && _chatFromSolver;

  /// Classification for the Disputes filter, including persisted status cards
  /// whose type stays tradeUpdate so tapping still opens the trade detail.
  bool get isDisputeNotification =>
      type == NotificationType.dispute ||
      isSolverChatCard ||
      (_isTradeStatus &&
          const {
            'dispute',
            'canceledByAdmin',
            'settledByAdmin',
            'completedByAdmin',
          }.contains(detail?[_tradeStatusKey]));

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
  static const _claimStateKey = 'claim';
  static const _claimStatePending = 'pending';
  static const _claimStatePaid = 'paid';
  static const _tradeStatusKey = 'tradeStatus';
  static const _tradeReasonKey = 'tradeReason';
  static const _chatCountKey = 'chatCount';
  static const _chatSolverKey = 'chatSolver';

  bool get _isBondSlashed => type == NotificationType.bondSlashed;

  /// Built by [NotificationModel.tradeStatus]. Older `tradeUpdate` records
  /// carry no status and keep rendering their stored copy.
  bool get _isTradeStatus =>
      type == NotificationType.tradeUpdate &&
      detail?.containsKey(_tradeStatusKey) == true;
  bool get _isChatCard =>
      type == NotificationType.message &&
      detail?.containsKey(_chatCountKey) == true;
  bool get _chatFromSolver => detail?[_chatSolverKey] == 'true';

  /// Messages counted on a chat card since the user last read it; 0 for
  /// other notifications.
  int get chatUnreadCount =>
      _isChatCard ? int.tryParse(detail?[_chatCountKey] ?? '') ?? 0 : 0;

  String _tradeTitle(AppLocalizations l10n) =>
      switch (detail?[_tradeStatusKey]) {
        'waitingBuyerInvoice' => l10n.tradeCardWaitingBuyerInvoiceTitle,
        'waitingPayment' => l10n.tradeCardWaitingPaymentTitle,
        'waitingTakerBond' => l10n.tradeCardWaitingTakerBondTitle,
        'active' => l10n.tradeCardActiveTitle,
        'fiatSent' => l10n.tradeCardFiatSentTitle,
        'settledHoldInvoice' => l10n.tradeCardSettledHoldInvoiceTitle,
        'success' => l10n.tradeCardSuccessTitle,
        'canceled' => l10n.tradeCardCanceledTitle,
        'expired' => l10n.tradeCardExpiredTitle,
        'cooperativelyCanceled' => l10n.tradeCardCooperativelyCanceledTitle,
        'dispute' => l10n.tradeCardDisputeTitle,
        'canceledByAdmin' => l10n.tradeCardCanceledByAdminTitle,
        'settledByAdmin' => l10n.tradeCardSettledByAdminTitle,
        'completedByAdmin' => l10n.tradeCardCompletedByAdminTitle,
        _ => l10n.tradeCardUpdatedTitle,
      };

  String _tradeMessage(AppLocalizations l10n) =>
      switch (detail?[_tradeStatusKey]) {
        'waitingBuyerInvoice' => l10n.tradeCardWaitingBuyerInvoiceMessage,
        'waitingPayment' => l10n.tradeCardWaitingPaymentMessage,
        'waitingTakerBond' => l10n.tradeCardWaitingTakerBondMessage,
        'active' => l10n.tradeCardActiveMessage,
        'fiatSent' => l10n.tradeCardFiatSentMessage,
        'settledHoldInvoice' => l10n.tradeCardSettledHoldInvoiceMessage,
        'success' => l10n.tradeCardSuccessMessage,
        'canceled' => switch (detail?[_tradeReasonKey]) {
          'makerCanceled' => l10n.tradeCardCanceledByMakerMessage,
          'bondLostRace' => l10n.tradeCardCanceledBondLostRaceMessage,
          'bondExpired' => l10n.tradeCardCanceledBondExpiredMessage,
          _ => l10n.tradeCardCanceledMessage,
        },
        'expired' => l10n.tradeCardExpiredMessage,
        'cooperativelyCanceled' => l10n.tradeCardCooperativelyCanceledMessage,
        'dispute' => l10n.tradeCardDisputeMessage,
        'canceledByAdmin' => l10n.tradeCardCanceledByAdminMessage,
        'settledByAdmin' => l10n.tradeCardSettledByAdminMessage,
        'completedByAdmin' => l10n.tradeCardCompletedByAdminMessage,
        _ => l10n.tradeCardUpdatedMessage,
      };

  /// The sats the daemon reported forfeited in a bond-slashed notice — the
  /// slice actually lost, which for a partially filled range order is less
  /// than the bond locked (docs/ANTI_ABUSE_BOND.md §2.8). Null for other
  /// types or a record without it.
  int? get bondSlashedAmountSats =>
      _isBondSlashed ? int.tryParse(detail?[_bondAmountKey] ?? '') : null;
  bool get _isBondClaim => type == NotificationType.bondClaim;
  bool get _claimPaid => detail?[_claimStateKey] == _claimStatePaid;

  /// Title for display, localized at render time for bond notices and
  /// falling back to the stored [title] for other types.
  String resolvedTitle(AppLocalizations l10n) {
    if (_isTradeStatus) return _tradeTitle(l10n);
    if (_isChatCard) {
      return _chatFromSolver ? l10n.chatCardSolverTitle : l10n.chatCardTitle;
    }
    if (_isBondSlashed) return l10n.bondSlashedTitle;
    if (_isBondClaim) {
      return _claimPaid ? l10n.bondClaimPaidTitle : l10n.bondClaimNewTitle;
    }
    return title;
  }

  /// Message for display (see [resolvedTitle]).
  String resolvedMessage(AppLocalizations l10n) {
    if (_isTradeStatus) return _tradeMessage(l10n);
    if (_isChatCard) {
      return _chatFromSolver
          ? l10n.chatCardSolverMessage(chatUnreadCount)
          : l10n.chatCardMessage(chatUnreadCount);
    }
    if (_isBondClaim) {
      final amount = detail?[_bondAmountKey] ?? '0';
      return _claimPaid
          ? l10n.bondClaimPaidMessage(amount)
          : l10n.bondClaimNewMessage(amount);
    }
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
    // Their stored keys are markers for the copy, not rows to show.
    if (_isTradeStatus || _isChatCard) return const {};
    if (!_isBondSlashed) return detail ?? const {};
    final d = detail ?? const {};
    final amount = d[_bondAmountKey] ?? '0';
    final fiatCode = d[_bondFiatCodeKey];
    final fiatAmount = d[_bondFiatAmountKey];
    final paymentMethod = d[_bondPaymentMethodKey];
    return {
      l10n.bondSlashedDetailOrder: orderId ?? '',
      l10n.bondSlashedDetailAmount: '$amount sats',
      l10n.bondSlashedDetailCause:
          d[_bondCauseKey] == _bondCauseDispute
              ? l10n.bondSlashedCauseDispute
              : l10n.bondSlashedCauseTimeout,
      if (fiatCode != null && fiatAmount != null)
        l10n.bondSlashedDetailFiat: '$fiatAmount $fiatCode',
      if (paymentMethod != null && paymentMethod.isNotEmpty)
        l10n.bondSlashedDetailPaymentMethod: paymentMethod,
    };
  }
}
