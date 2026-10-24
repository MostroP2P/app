import 'package:uuid/uuid.dart';

import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart'
    show AnnouncementInfo, AnnouncementSeverity;

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
    this.nodePubkey,
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

  /// The node of the trade the card is about, recorded when it was raised
  /// (#811): the row may be gone by the time the card is shown. Null on a
  /// card raised before nodes were recorded, or for a trade whose node is
  /// unknown — both read as the active node's.
  final String? nodePubkey;

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
      nodePubkey: nodePubkey,
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
      'nodePubkey': nodePubkey,
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
      nodePubkey: json['nodePubkey'] as String?,
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
    String? nodePubkey,
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
      nodePubkey: nodePubkey,
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
    String? nodePubkey,
  }) {
    return NotificationModel(
      id: chatCardId(tradeId, fromSolver: fromSolver),
      type: NotificationType.message,
      title: '',
      message: '',
      timestamp: at,
      orderId: tradeId,
      detail: {_chatCountKey: '$count', if (fromSolver) _chatSolverKey: 'true'},
      nodePubkey: nodePubkey,
    );
  }

  /// The id of a trade's chat card; see [NotificationModel.chatMessages].
  static String chatCardId(String tradeId, {required bool fromSolver}) =>
      'chat-$tradeId${fromSolver ? '-solver' : ''}';

  /// A chat card holding the dispute solver's messages, which open the
  /// trade rather than the peer chat.
  bool get isSolverChatCard => _isChatCard && _chatFromSolver;

  /// The trade's chat card, peer or solver: see [NotificationModel.chatMessages].
  bool get isChatCard => _isChatCard;

  /// The trade status a status card announces (the bridge enum's name, e.g.
  /// `fiatSent`); null for any other notice, and for older status records.
  String? get tradeStatus => _isTradeStatus ? (detail?[_tradeStatusKey]) : null;

  /// Why the status changed, when the card says (e.g.
  /// `cooperativeCancelRequestedByPeer`).
  String? get tradeReason => _isTradeStatus ? (detail?[_tradeReasonKey]) : null;

  /// A payout claim that was paid, rather than one still to claim.
  bool get isBondClaimPaid => _isBondClaim && _claimPaid;

  /// False for chat notices, which only their chat screen marks read: opening
  /// the trade is not reading its messages. Mirrored by the store's filter in
  /// `SembastNotificationsStore.markRead`.
  bool get readsWithTrade => type != NotificationType.message;

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

  /// A project announcement (specs/006-announcement-channel §6.2). The id is
  /// the announcement's address, so a correction — a new revision at the
  /// same address — replaces the card and starts unread. Every locale rides
  /// in [detail] and the copy is picked at render time by
  /// [resolvedTitle] / [resolvedMessage]; [title] and [message] hold the
  /// English copy for a reader that cannot resolve a locale.
  factory NotificationModel.announcement(AnnouncementInfo info) {
    final english =
        info.texts.where((t) => t.locale == 'en').firstOrNull ??
        info.texts.first;
    return NotificationModel(
      id: info.address,
      type: NotificationType.system,
      title: english.title,
      message: english.body,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        platformInt64ToInt(info.createdAt) * 1000,
      ),
      isRead: info.read,
      detail: {
        _announcementKey: info.revision,
        _severityKey: info.severity.name,
        if (info.url case final url?) _urlKey: url,
        for (final text in info.texts) ...{
          '$_localePrefix${text.locale}:title': text.title,
          '$_localePrefix${text.locale}:body': text.body,
        },
      },
    );
  }

  /// A card built by [NotificationModel.announcement].
  bool get isAnnouncement =>
      type == NotificationType.system &&
      detail?.containsKey(_announcementKey) == true;

  /// `<created_at>:<event id>` of the revision the card shows; null for any
  /// other notice. Two cards of one address with different revisions are
  /// two texts, and the newer one is unread again (§5.3).
  String? get announcementRevision =>
      isAnnouncement ? detail![_announcementKey] : null;

  /// How loudly the card is painted (§3.4). A stored level this build does
  /// not know reads as `warning`, the same rule Rust applies on the wire.
  AnnouncementSeverity? get announcementSeverity =>
      isAnnouncement
          ? AnnouncementSeverity.values
                  .where((s) => s.name == detail![_severityKey])
                  .firstOrNull ??
              AnnouncementSeverity.warning
          : null;

  /// A `critical` announcement: sorts first, turns the bell's dot red, and
  /// stays listed once dismissed until it expires (§3.4).
  bool get isCriticalAnnouncement =>
      announcementSeverity == AnnouncementSeverity.critical;

  /// The announcement's one action link, `https` only, already checked by
  /// Rust; null when it has none or the card is not an announcement.
  String? get announcementUrl => isAnnouncement ? detail![_urlKey] : null;

  /// The level's label, so the distinction survives without colour (§3.4).
  String? announcementLevelLabel(AppLocalizations l10n) =>
      switch (announcementSeverity) {
        null => null,
        AnnouncementSeverity.info => l10n.announcementLevelInfo,
        AnnouncementSeverity.warning => l10n.announcementLevelWarning,
        AnnouncementSeverity.critical => l10n.announcementLevelCritical,
      };

  /// The copy for the locale on screen. Rust guarantees every supported
  /// locale is present (§3.2); the English stored in [title] / [message]
  /// is the fallback for a locale this build added since.
  String? _announcementText(AppLocalizations l10n, String field) {
    final language = l10n.localeName.split(RegExp('[_-]')).first.toLowerCase();
    return detail?['$_localePrefix$language:$field'];
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
  static const _claimStateKey = 'claim';
  static const _claimStatePending = 'pending';
  static const _claimStatePaid = 'paid';
  static const _tradeStatusKey = 'tradeStatus';
  static const _tradeReasonKey = 'tradeReason';
  static const _chatCountKey = 'chatCount';
  static const _chatSolverKey = 'chatSolver';
  static const _announcementKey = 'announcement';
  static const _severityKey = 'severity';
  static const _urlKey = 'url';
  static const _localePrefix = 'loc:';

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

  /// A cooperative-cancel request changes no status (protocol `cancel.md`),
  /// so its card is told apart by the reason, not the status it rode on.
  String? _cancelRequestTitle(
    AppLocalizations l10n,
  ) => switch (detail?[_tradeReasonKey]) {
    'cooperativeCancelRequestedByMe' => l10n.tradeCardCancelRequestedByMeTitle,
    'cooperativeCancelRequestedByPeer' =>
      l10n.tradeCardCancelRequestedByPeerTitle,
    _ => null,
  };

  String? _cancelRequestMessage(AppLocalizations l10n) =>
      switch (detail?[_tradeReasonKey]) {
        'cooperativeCancelRequestedByMe' =>
          l10n.tradeCardCancelRequestedByMeMessage,
        'cooperativeCancelRequestedByPeer' =>
          l10n.tradeCardCancelRequestedByPeerMessage,
        _ => null,
      };

  /// The node asks for a new invoice because it could not pay the one it
  /// had (#823): the status of a first request, told apart by the reason.
  bool get _payoutFailed => detail?[_tradeReasonKey] == 'payoutFailed';

  /// The node published the user's order: a `pending` the book's own
  /// bucket never is, told apart by the reason.
  bool get _orderPublished => detail?[_tradeReasonKey] == 'orderPublished';

  String _tradeTitle(AppLocalizations l10n) =>
      _cancelRequestTitle(l10n) ??
      (_payoutFailed ? l10n.tradeCardPayoutFailedTitle : null) ??
      (_orderPublished ? l10n.tradeCardOrderPublishedTitle : null) ??
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
      _cancelRequestMessage(l10n) ??
      (_payoutFailed ? l10n.tradeCardPayoutFailedMessage : null) ??
      (_orderPublished ? l10n.tradeCardOrderPublishedMessage : null) ??
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
    if (isAnnouncement) return _announcementText(l10n, 'title') ?? title;
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
    if (isAnnouncement) return _announcementText(l10n, 'body') ?? message;
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
    if (_isTradeStatus || _isChatCard || isAnnouncement) return const {};
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
