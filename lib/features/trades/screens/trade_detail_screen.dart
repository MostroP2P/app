import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/rate/providers/rating_providers.dart';
import 'package:mostro/features/trades/models/trade_status.dart';
import 'package:mostro/features/trades/models/trade_view.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/features/trades/widgets/dispute_confirmation_dialog.dart';
import 'package:mostro/features/trades/widgets/release_confirmation_sheet.dart';
import 'package:mostro/features/trades/widgets/trade_action_bar.dart';
import 'package:mostro/features/trades/widgets/trade_chat_card.dart';
import 'package:mostro/features/trades/widgets/trade_completed_card.dart';
import 'package:mostro/features/trades/widgets/trade_countdown.dart';
import 'package:mostro/features/trades/widgets/trade_step_block.dart';
import 'package:mostro/features/trades/widgets/trade_timeline.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/shared/widgets/counterpart_reputation_row.dart';
import 'package:mostro/shared/widgets/mostro_reactive_button.dart';
import 'package:mostro/src/rust/api/disputes.dart' as disputes_api;
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/reputation.dart' as reputation_api;

export 'package:mostro/features/trades/models/trade_status.dart';

/// Trade screen — Route `/trade_detail/:orderId`. Handoff 8a–8e.
///
/// One screen with five states, not five screens: app bar → chat (once the
/// trade is active) → step block → reputation (while the fiat leg is open) →
/// timeline → id and date, over a pinned action bar. When the user has
/// something to do there is one lime button; when they only wait, none.
/// [TradeView] holds the status → layout mapping.
class TradeDetailScreen extends ConsumerStatefulWidget {
  const TradeDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<TradeDetailScreen> createState() => _TradeDetailScreenState();
}

/// Default trade countdown duration (matches Mostro daemon default).
const _kCountdownSeconds = 900; // 15 minutes

/// Overflow-menu actions (currently just sharing the order).
enum _OverflowAction { shareOrder }

class _TradeDetailScreenState extends ConsumerState<TradeDetailScreen> {
  Timer? _tick;

  /// Drives only the countdown. A notifier rather than screen state: it
  /// ticks every second under an hour, and this build method lays out the
  /// entire screen — chat, step, reputation, timeline, actions.
  final ValueNotifier<Duration> _remaining = ValueNotifier(
    const Duration(seconds: _kCountdownSeconds),
  );

  /// The window as measured when the screen loaded — the fallback for the
  /// countdown bar when the node does not advertise its expiration.
  Duration _loadedWindow = const Duration(seconds: _kCountdownSeconds);

  /// Star picked on the completed card, 0 until the user taps one.
  int _selectedRating = 0;

  /// Generation of the latest `expiresAt` fetch: a status change starts a
  /// new one, and a slower, older response must not overwrite it.
  int _expiresAtRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadExpiresAt();
    _scheduleTick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _remaining.dispose();
    super.dispose();
  }

  /// Fetches the real `expiresAt` from the order and resets [_remaining].
  ///
  /// Falls back to the default [_kCountdownSeconds] when the field is null or
  /// the order is no longer available.
  Future<void> _loadExpiresAt() async {
    final request = ++_expiresAtRequest;
    try {
      final info = await orders_api.getOrder(orderId: widget.orderId);
      final raw = info?.expiresAt;
      if (raw == null || !mounted || request != _expiresAtRequest) return;
      final expiresAtSeconds = platformInt64ToInt(raw);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final diff = expiresAtSeconds - now;
      if (!mounted) return;
      setState(() {
        _loadedWindow = Duration(seconds: diff > 0 ? diff : _kCountdownSeconds);
      });
      _remaining.value = diff > 0 ? Duration(seconds: diff) : Duration.zero;
      _scheduleTick();
    } catch (e, st) {
      // Keep the default remaining time; the clock is not worth a dialog.
      debugPrint('[TradeDetailScreen] loadExpiresAt error: $e\n$st');
    }
  }

  /// Repaints every second under an hour and once a minute above it: the
  /// clock shows no seconds at that scale, so ticking faster decides nothing.
  void _scheduleTick() {
    _tick?.cancel();
    final remaining = _remaining.value;
    if (remaining <= Duration.zero) return;
    final step = nextCountdownTick(remaining);
    _tick = Timer(step, () {
      if (!mounted) return;
      final next = _remaining.value - step;
      _remaining.value = next <= Duration.zero ? Duration.zero : next;
      _scheduleTick();
    });
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  /// Set once the screen has decided to leave, so no rebuild in between
  /// navigates twice.
  bool _leaving = false;

  /// Back to home with [message], at most once.
  void _leave(String message) {
    if (_leaving || !mounted) return;
    _leaving = true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    context.go(AppRoute.home);
  }

  /// Whether a cancel in [status] ends the trade outright. Mirrors Rust's
  /// `cancellation_wipes_history`: before `active` mostrod cancels at once —
  /// a take hands the order back to the book, a maker's order dies — and the
  /// trade row is wiped. From `active` on it is a cooperative request, and
  /// `inProgress` may be either.
  static bool _cancelEndsTrade(TradeStatus status) => const {
    TradeStatus.pending,
    TradeStatus.waitingInvoice,
    TradeStatus.waitingPayment,
  }.contains(status);

  /// What a cancel in [status] does, as the confirmation dialog tells it.
  /// Before `active` mostrod cancels at once; from `active` on it is a
  /// cooperative request; `inProgress` only says the order was taken, so it
  /// may be either (#203).
  static String _cancelDialogContent(
    AppLocalizations l10n,
    TradeStatus status,
  ) {
    if (_cancelEndsTrade(status)) {
      return l10n.cancelTradeDialogContentNotStarted;
    }
    if (status == TradeStatus.inProgress) {
      return l10n.cancelTradeDialogContentMaybeStarted;
    }
    return l10n.cancelTradeDialogContent;
  }

  /// The trade's status now, from the live provider; [fallback] while it has
  /// no value yet. The status a callback was built with goes stale across an
  /// await: the seller's payment can land while the cancel dialog is open.
  TradeStatus _liveStatus(TradeStatus fallback) {
    final live = ref.read(tradeStatusProvider(widget.orderId)).valueOrNull;
    return live == null ? fallback : tradeStatusFromOrderStatus(live);
  }

  Future<void> _cancelOrder(TradeStatus status) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l10n.cancelTradeDialogTitle),
            // Follows the live status, so the copy the user confirms is the
            // cancel the daemon will apply.
            content: Consumer(
              builder: (context, dialogRef, child) {
                final live =
                    dialogRef
                        .watch(tradeStatusProvider(widget.orderId))
                        .valueOrNull;
                final now =
                    live == null ? status : tradeStatusFromOrderStatus(live);
                return Text(_cancelDialogContent(l10n, now));
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.noButtonLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.yesCancelButtonLabel),
              ).withAutomationId(AutomationIds.tradeCancelConfirm),
            ],
          ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      throw const MostroActionAborted();
    }
    try {
      await ref.read(cancelOrderActionProvider)(widget.orderId);
      ref.invalidate(rawTradesProvider);
      if (!mounted) return;
      // Decided on the status the cancel was sent in, not the one the button
      // was built with: a trade that went active meanwhile is a cooperative
      // request and stays open.
      if (_cancelEndsTrade(_liveStatus(status))) {
        // Nothing is left to follow here: leave, as the invoice screens do.
        _leave(l10n.cancelRequestSent);
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.cancelRequestSent)));
    } catch (e, st) {
      debugPrint('[TradeDetailScreen] cancelOrder error: $e\n$st');
      _showFailure(e, (l10n) => l10n.cancelRequestFailed);
      rethrow;
    }
  }

  /// No confirmation: marking the fiat as sent is reversible by dispute.
  Future<void> _markFiatSent() async {
    try {
      await orders_api.sendFiatSent(orderId: widget.orderId);
    } catch (e, st) {
      debugPrint('[TradeDetailScreen] sendFiatSent error: $e\n$st');
      _showFailure(e, (l10n) => l10n.fiatSentFailed);
      rethrow;
    }
  }

  /// Open a dispute for this trade, upsert into the local dispute notifier,
  /// and navigate to the dispute chat.
  Future<void> _openDispute() async {
    // #280: a dispute escalates to an admin and cannot be undone, so confirm
    // first.
    final confirmed = await showDisputeConfirmationDialog(context);
    if (!mounted) return;
    if (confirmed != true) {
      throw const MostroActionAborted();
    }
    try {
      final dispute = await disputes_api.openDispute(tradeId: widget.orderId);
      if (!mounted) return;
      final openedAt = platformInt64ToInt(dispute.openedAt);
      ref
          .read(disputeNotifierProvider.notifier)
          .upsert(
            DisputeItem(
              id: dispute.id,
              tradeId: dispute.tradeId,
              status: DisputeStatus.open,
              initiatedByMe: true,
              openedAt: openedAt,
            ),
          );
      if (!mounted) return;
      context.push(AppRoute.disputeDetailsPath(dispute.id));
    } catch (e, st) {
      debugPrint('[TradeDetailScreen] openDispute error: $e\n$st');
      _showFailure(e, (l10n) => l10n.openDisputeFailed);
      rethrow;
    }
  }

  /// Shared by the fiat-sent primary action and the disputed secondary row.
  /// The only action of this screen that asks for confirmation.
  Future<void> _releaseOrder() async {
    final confirmed = await showReleaseConfirmationSheet(context);
    if (!mounted) return;
    if (confirmed != true) {
      throw const MostroActionAborted();
    }
    try {
      await ref.read(releaseOrderActionProvider)(widget.orderId);
      if (!mounted) return;
      // Publishing release confirms neither escrow settlement nor payout. Stay
      // here until the live status reaches Success before offering rating.
      ref.invalidate(tradeStatusProvider(widget.orderId));
    } catch (e, st) {
      debugPrint('[TradeDetailScreen] releaseOrder error: $e\n$st');
      _showFailure(e, (l10n) => l10n.releaseFailed);
      rethrow;
    }
  }

  /// Sends the star picked on the completed card. The screen buckets a
  /// successful trade as "rate me" until a local rating exists, so the
  /// lookup is refreshed once the daemon accepts it (#327).
  Future<void> _submitRating() async {
    try {
      await reputation_api.submitRating(
        tradeId: widget.orderId,
        score: _selectedRating,
      );
      if (!mounted) return;
      ref.invalidate(tradeRatingProvider(widget.orderId));
    } catch (e, st) {
      debugPrint('[TradeDetailScreen] submitRating error: $e\n$st');
      _showFailure(e, (l10n) => l10n.ratingFailed);
      rethrow;
    }
  }

  void _showFailure(Object e, String Function(AppLocalizations) fallback) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(localizedDaemonError(l10n, e, fallback: fallback(l10n))),
      ),
    );
  }

  void _viewDispute() {
    final dispute = ref.read(disputeByTradeIdProvider(widget.orderId));
    if (dispute == null) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.disputeNotFoundForOrder),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    context.push(AppRoute.disputeDetailsPath(dispute.id));
  }

  void _close() => context.canPop() ? context.pop() : context.go(AppRoute.home);

  void _copyId() {
    Clipboard.setData(ClipboardData(text: widget.orderId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).orderIdCopied),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ── Status resolution ────────────────────────────────────────────────────

  /// Role: the in-memory map (set by TakeOrderScreen in this session) takes
  /// priority; the DB-backed provider covers trades reopened after a restart.
  ///
  /// Null while the DB lookup is unresolved or failed: the screen then holds
  /// `loading` rather than guessing a role, because a guessed role offers
  /// the other party's actions (a seller shown "add your invoice").
  bool? _isBuyer() {
    final roleMap = ref.watch(tradeRoleProvider);
    if (roleMap.containsKey(widget.orderId)) return roleMap[widget.orderId]!;
    final dbRole = ref.watch(tradeRoleFromDbProvider(widget.orderId));
    if (dbRole.hasError) {
      debugPrint(
        '[TradeDetailScreen] trade role lookup failed: ${dbRole.error}',
      );
    }
    return dbRole.valueOrNull;
  }

  /// [TradeStatus.loading] until the live status resolves, so the screen
  /// never flashes an action that the next frame would take away.
  ///
  /// The protocol has no "rated" order status — a successful trade stays
  /// successful once the rating is sent — so `rated` is only reachable by
  /// overlaying the local rating (#327). While that first lookup is
  /// unresolved the screen holds `loading` for the same reason; a refresh
  /// keeps the previous value, so a fresh rating never bounces through it.
  TradeStatus _status() {
    final live = ref.watch(tradeStatusProvider(widget.orderId));
    if (live.hasError && !live.hasValue) {
      debugPrint('[TradeDetailScreen] trade status failed: ${live.error}');
    }
    if (!live.hasValue) return TradeStatus.loading;
    final status = tradeStatusFromOrderStatus(live.value!);
    if (status != TradeStatus.pendingRating) return status;
    final rating = ref.watch(tradeRatingProvider(widget.orderId));
    if (rating.isLoading && !rating.hasValue) return TradeStatus.loading;
    return ref.watch(ratedByMeProvider(widget.orderId))
        ? TradeStatus.rated
        : TradeStatus.pendingRating;
  }

  /// The whole window the countdown bar fills: the node's advertised
  /// expiration when it is known and can contain the remaining time, else
  /// the remaining time measured on load.
  Duration _window(TradeStatus status) {
    final node = ref.watch(mostroNodeProvider).valueOrNull;
    final hours = node?.expirationHours;
    final seconds = node?.expirationSeconds;
    final advertised =
        status == TradeStatus.pending
            ? (hours == null ? null : Duration(hours: hours))
            : (seconds == null ? null : Duration(seconds: seconds));
    if (advertised != null && advertised >= _loadedWindow) return advertised;
    return _loadedWindow;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);

    // A step advanced by the relay: a nudge, the crossfades below, and a
    // fresh deadline — every step has its own expiration, owned by a
    // different party, so the clock loaded for the previous step is stale.
    ref.listen<AsyncValue<OrderStatus>>(tradeStatusProvider(widget.orderId), (
      previous,
      next,
    ) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      if (before != null && after != null && before != after) {
        HapticFeedback.mediumImpact();
        _loadExpiresAt();
      }
    });

    final role = _isBuyer();
    final status = role == null ? TradeStatus.loading : _status();
    final isBuyer = role ?? true;
    // A failed status subscription would otherwise look like a slow one.
    final loadFailed =
        status == TradeStatus.loading &&
        ref.watch(tradeStatusProvider(widget.orderId)).hasError;
    final canRate = !ref.watch(privacyModeProvider);
    final view = TradeView.of(
      status: status,
      isBuyer: isBuyer,
      canRate: canRate,
    );
    final order = ref.watch(orderByIdProvider(widget.orderId));
    // Counterpart reputation snapshot persisted from the daemon's follow-up
    // Peer DM (#305), via tradeInfoProvider: it refreshes on the TradeUpdate
    // the Rust side emits after persisting the snapshot.
    final tradeAsync = ref.watch(tradeInfoProvider(widget.orderId));
    final trade = tradeAsync.valueOrNull;
    final peerRating = trade?.peerRating;
    final room =
        ref
            .watch(chatRoomsNotifierProvider)
            .where((r) => r.orderId == widget.orderId)
            .firstOrNull;

    // No trade row and not the maker: this is no longer a trade of this
    // user's. A take lost before going active (its own cancel, a waiting
    // timeout, the maker cancelling) is wiped in Rust, and the order is
    // handed back to the public book, where it reads `pending` — which this
    // screen would render as the user's own published order, cancel button
    // included. Leave instead, as the invoice screens do; this also covers
    // arriving later from a notification or the chat header. Only on settled
    // reads of both the trades list and the order book: no answer yet is
    // neither an absent row nor a stranger's order (a cold start can resolve
    // the trades before the book's first emission).
    if (!_leaving &&
        ref.watch(orderBookProvider).hasValue &&
        !tradeAsync.isLoading &&
        tradeAsync.hasValue &&
        trade == null &&
        order?.isMine != true) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _leave(l10n.orderNoLongerActive),
      );
    }

    return Scaffold(
      backgroundColor: book.bg,
      appBar: AppBar(
        backgroundColor: book.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, size: 22, color: book.textBody),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: _close,
        ).withAutomationId(AutomationIds.appBarBack),
        titleSpacing: 0,
        title: Text(
          l10n.tradeScreenTitle,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: book.textPrimary,
          ),
        ),
        actions: [_buildOverflowMenu(book)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
        children: [
          _chatArea(view),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey(status),
              child:
                  view.isCompleted
                      ? _completedCard(
                        l10n,
                        status,
                        canRate,
                        order,
                        room?.displayHandle(l10n),
                      )
                      : _stepBlock(
                        l10n,
                        view,
                        status,
                        isBuyer,
                        order,
                        loadFailed: loadFailed,
                      ),
            ),
          ),
          if (view.showsReputation && peerRating != null) ...[
            const SizedBox(height: 12),
            CounterpartReputationRow(
              rating: peerRating,
              reviews: trade!.peerReviews ?? 0,
              days: trade.peerDays ?? 0,
              counterpartIsBuyer: !isBuyer,
            ),
          ],
          if (view.step >= 0) ...[
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: TradeTimeline(
                key: ValueKey(view.step),
                steps: _steps(l10n, isBuyer),
                current: view.step,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _idRow(l10n, book, order),
        ],
      ),
      bottomNavigationBar:
          view.hasActions ? _actionBar(l10n, view, status) : null,
    );
  }

  // ── Chat ─────────────────────────────────────────────────────────────────

  /// The chat card slides in once the trade is active (fade + 8dp, 220 ms);
  /// the lock line before it fades out (150 ms). Nothing in either state.
  Widget _chatArea(TradeView view) {
    final Widget child;
    if (view.showsChat) {
      child = TradeChatCard(
        key: const ValueKey('chat'),
        orderId: widget.orderId,
      );
    } else if (!view.isCompleted && view.step >= 0) {
      child = const TradeChatLockedLine(key: ValueKey('locked'));
    } else {
      child = const SizedBox.shrink(key: ValueKey('none'));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 150),
      switchInCurve: Curves.easeOut,
      transitionBuilder:
          (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.12),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
      child: child,
    );
  }

  // ── Step block ───────────────────────────────────────────────────────────

  Widget _stepBlock(
    AppLocalizations l10n,
    TradeView view,
    TradeStatus status,
    bool isBuyer,
    OrderItem? order, {
    required bool loadFailed,
  }) {
    final amount =
        order != null ? '${order.displayAmount} ${order.fiatCode}' : null;
    return TradeStepBlock(
      stepLabel:
          view.step >= 0 && view.step < kTradeStepCount
              ? l10n.stepIndicator(view.step + 1, kTradeStepCount)
              : null,
      chip: view.chip,
      chipLabel: _chipLabel(l10n, view.chip),
      title: _title(l10n, status, isBuyer, amount),
      body:
          loadFailed
              ? TextSpan(text: l10n.tradeLoadError)
              : _body(l10n, status, isBuyer, order?.paymentMethod),
      warning: view.showsReleaseWarning ? l10n.tradeReleaseIrreversible : null,
      countdown: view.showsTimer ? _countdown(l10n, view, status) : null,
      statusReadout: status.machineName,
    );
  }

  String _chipLabel(AppLocalizations l10n, TradeChip chip) => switch (chip) {
    TradeChip.waiting => l10n.tradeChipWaiting,
    TradeChip.active => l10n.tradeChipActive,
    TradeChip.yourTurn => l10n.tradeChipYourTurn,
    TradeChip.dispute => l10n.tradeChipDispute,
    TradeChip.none => '',
  };

  /// The one thing happening right now. The amount, when it appears, is set
  /// in the figures face.
  InlineSpan _title(
    AppLocalizations l10n,
    TradeStatus status,
    bool isBuyer,
    String? amount,
  ) {
    final figure = amount ?? l10n.theAgreedAmount;
    final text = switch (status) {
      TradeStatus.loading => l10n.tradeHeadlineLoading,
      TradeStatus.pending => l10n.tradeHeadlinePending,
      TradeStatus.waitingInvoice =>
        isBuyer
            ? l10n.tradeHeadlineWaitingInvoiceBuyer
            : l10n.tradeHeadlineWaitingInvoiceSeller,
      TradeStatus.waitingPayment =>
        isBuyer
            ? l10n.tradeHeadlineWaitingPaymentBuyer
            : l10n.tradeHeadlineWaitingPaymentSeller,
      TradeStatus.inProgress => l10n.tradeHeadlineInProgress,
      TradeStatus.active =>
        isBuyer
            ? l10n.tradeHeadlineActiveBuyer(figure)
            : l10n.tradeHeadlineActiveSeller(figure),
      TradeStatus.fiatSent =>
        isBuyer
            ? l10n.tradeHeadlineFiatSentBuyer
            : l10n.tradeHeadlineFiatSentSeller(figure),
      TradeStatus.payoutPending => l10n.tradeHeadlinePayoutPending,
      TradeStatus.disputed => l10n.tradeHeadlineDisputed,
      TradeStatus.cancelled => l10n.tradeHeadlineCancelled,
      TradeStatus.pendingRating ||
      TradeStatus.completed ||
      TradeStatus.rated => l10n.tradeCompletedTitle,
    };
    if (amount == null) return TextSpan(text: text);
    return emphasise(
      text,
      amount,
      const TextStyle(fontFamily: AppFonts.figures),
    );
  }

  /// What to do about it, with the payment method in the body face. The
  /// method-specific copy needs the order; without it the generic line.
  InlineSpan? _body(
    AppLocalizations l10n,
    TradeStatus status,
    bool isBuyer,
    String? method,
  ) {
    final book = OrderBookPalette.of(context);
    final keyData = TextStyle(
      color: book.textBody,
      fontWeight: FontWeight.w500,
    );
    final text = switch (status) {
      TradeStatus.loading => null,
      TradeStatus.pending => l10n.tradeInstructionPending,
      TradeStatus.waitingInvoice =>
        isBuyer
            ? l10n.tradeWaitingInvoiceBuyerInstruction
            : l10n.tradeWaitingInvoiceSellerInstruction,
      TradeStatus.waitingPayment =>
        isBuyer
            ? l10n.tradeBodyWaitingPaymentBuyer
            : l10n.tradeWaitingPaymentSellerInstruction,
      TradeStatus.inProgress => l10n.tradeInstructionInProgress,
      TradeStatus.active when method != null =>
        isBuyer
            ? l10n.tradeBodyActiveBuyer(method)
            : l10n.tradeBodyActiveSeller(method),
      TradeStatus.active =>
        isBuyer
            ? l10n.tradeInstructionActiveBuyer
            : l10n.tradeInstructionActiveSeller,
      TradeStatus.fiatSent when !isBuyer && method != null => l10n
          .tradeBodyFiatSentSeller(method),
      TradeStatus.fiatSent =>
        isBuyer
            ? l10n.tradeInstructionFiatSentBuyer
            : l10n.tradeInstructionFiatSentSeller,
      TradeStatus.payoutPending => l10n.tradeInstructionPayoutPending,
      TradeStatus.disputed => l10n.tradeInstructionDisputed,
      TradeStatus.cancelled => l10n.tradeInstructionCancelled,
      TradeStatus.pendingRating ||
      TradeStatus.completed ||
      TradeStatus.rated => null,
    };
    if (text == null) return null;
    if (method == null) return TextSpan(text: text);
    return emphasise(text, method, keyData);
  }

  /// The per-tick repaint reaches this builder only.
  Widget _countdown(AppLocalizations l10n, TradeView view, TradeStatus status) {
    final label = switch (view.timer) {
      TradeTimerOwner.user => l10n.tradeTimerYouHave,
      TradeTimerOwner.counterpart => l10n.tradeTimerTheyHave,
      TradeTimerOwner.order => l10n.tradeTimerOrderHas,
      TradeTimerOwner.none => '',
    };
    final note = switch (view.note) {
      TradeTimerNote.expiresCancels => l10n.tradeTimerWaitingInvoiceConsequence,
      TradeTimerNote.coordinateInChat => l10n.tradeTimerNoteCoordinate,
      TradeTimerNote.leavesBook => l10n.tradeTimerPendingConsequence,
      TradeTimerNote.none => null,
    };
    final total = _window(status);
    return ValueListenableBuilder<Duration>(
      valueListenable: _remaining,
      builder:
          (context, remaining, _) => TradeCountdown(
            remaining: remaining,
            total: total,
            label: label,
            isWaiting: view.timer != TradeTimerOwner.user,
            note: note,
          ),
    );
  }

  // ── Completed card ───────────────────────────────────────────────────────

  Widget _completedCard(
    AppLocalizations l10n,
    TradeStatus status,
    bool canRate,
    OrderItem? order,
    String? alias,
  ) {
    final rating = ref.watch(tradeRatingProvider(widget.orderId)).valueOrNull;
    final mine = rating != null && rating.isMine ? rating.score : null;
    final picking = status == TradeStatus.pendingRating && canRate;
    return TradeCompletedCard(
      amount: order != null ? '${order.displayAmount} ${order.fiatCode}' : null,
      paymentMethod: order?.paymentMethod,
      ratedAlias: alias ?? l10n.unknownPeerHandle,
      ratedScore: mine,
      selectedRating: picking ? _selectedRating : null,
      onRatingChanged:
          picking ? (star) => setState(() => _selectedRating = star) : null,
      statusReadout: status.machineName,
    );
  }

  // ── Timeline ─────────────────────────────────────────────────────────────

  /// Steps written from the user's side.
  List<String> _steps(AppLocalizations l10n, bool isBuyer) => [
    l10n.tradeStepOrderTaken,
    isBuyer ? l10n.tradeStepInvoiceBuyer : l10n.tradeStepInvoiceSeller,
    isBuyer ? l10n.tradeStepFiatBuyer : l10n.tradeStepFiatSeller,
    isBuyer ? l10n.tradeStepReleaseBuyer : l10n.tradeStepReleaseSeller,
    l10n.tradeStepRate,
  ];

  // ── ID and date ──────────────────────────────────────────────────────────

  /// Last row of the scroll; tapping anywhere on it copies the id.
  Widget _idRow(
    AppLocalizations l10n,
    OrderBookPalette book,
    OrderItem? order,
  ) {
    final faint = TextStyle(fontSize: 11, color: book.textFaint);
    return InkWell(
      onTap: _copyId,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Row(
          children: [
            Text(l10n.tradeIdLabel, style: faint),
            const SizedBox(width: 8),
            // The visible id is shortened; the readout carries the whole id.
            Text(
              _shortId(widget.orderId),
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: book.textTertiary,
              ),
            ).withAutomationId(AutomationIds.orderId, label: widget.orderId),
            const SizedBox(width: 8),
            Icon(Icons.copy_outlined, size: 13, color: book.textTertiary),
            const Spacer(),
            if (order != null)
              Text(_createdLabel(l10n, order.createdAt), style: faint),
          ],
        ),
      ),
    );
  }

  static String _shortId(String id) =>
      id.length <= 12
          ? id
          : '${id.substring(0, 5)}…${id.substring(id.length - 4)}';

  /// `created today 17:41`, or `created 11 Sep 2026, 17:41` in the locale's
  /// own order — the same format as the own-order screen.
  String _createdLabel(AppLocalizations l10n, DateTime dt) {
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return l10n.tradeCreatedTodayLabel(DateFormat.Hm(locale).format(dt));
    }
    return l10n.tradeCreatedAtLabel(
      DateFormat.yMMMd(locale).add_Hm().format(dt),
    );
  }

  // ── Action bar ───────────────────────────────────────────────────────────

  Widget _actionBar(AppLocalizations l10n, TradeView view, TradeStatus status) {
    final primary = switch (view.primary) {
      TradePrimaryAction.none => null,
      TradePrimaryAction.addInvoice => TradePrimarySpec(
        label: l10n.addLightningInvoiceButton,
        icon: Icons.receipt_long_outlined,
        automationId: AutomationIds.tradeAddInvoice,
        onPressed:
            () async => context.push(AppRoute.addInvoicePath(widget.orderId)),
      ),
      TradePrimaryAction.payHoldInvoice => TradePrimarySpec(
        label: l10n.payHoldInvoiceButton,
        icon: Icons.bolt,
        automationId: AutomationIds.tradePayInvoice,
        onPressed:
            () async => context.push(AppRoute.payInvoicePath(widget.orderId)),
      ),
      TradePrimaryAction.fiatSent => TradePrimarySpec(
        label: l10n.tradeFiatSentAction,
        icon: Icons.check,
        automationId: AutomationIds.tradeFiatSent,
        onPressed: _markFiatSent,
      ),
      TradePrimaryAction.release => TradePrimarySpec(
        label: l10n.confirmReleaseSatsButton,
        icon: Icons.lock_outline,
        automationId: AutomationIds.tradeRelease,
        onPressed: _releaseOrder,
      ),
      TradePrimaryAction.viewDispute => TradePrimarySpec(
        label: l10n.viewDisputeButton,
        icon: Icons.gavel,
        automationId: AutomationIds.tradeViewDispute,
        onPressed: () async => _viewDispute(),
      ),
      TradePrimaryAction.sendRating => TradePrimarySpec(
        label: l10n.tradeSendRatingAction,
        automationId: AutomationIds.tradeRateSubmit,
        onPressed: _selectedRating > 0 ? _submitRating : null,
      ),
      TradePrimaryAction.close => TradePrimarySpec(
        label: l10n.tradeCloseAction,
        automationId:
            view.isCompleted
                ? AutomationIds.tradeRateClose
                : AutomationIds.tradeClose,
        onPressed: () async => _close(),
      ),
    };

    final secondary = [
      for (final action in view.secondary)
        switch (action) {
          TradeSecondaryAction.cancel => TradeSecondarySpec(
            label:
                view.cancelIsFullWidth ? l10n.cancelTradeButton : l10n.cancel,
            automationId: AutomationIds.tradeCancel,
            onPressed: () => _cancelOrder(status),
            isDestructive: true,
          ),
          TradeSecondaryAction.dispute => TradeSecondarySpec(
            label: l10n.openDisputeButton,
            automationId: AutomationIds.tradeDispute,
            onPressed: _openDispute,
          ),
          TradeSecondaryAction.release => TradeSecondarySpec(
            label: l10n.releaseSatsButton,
            automationId: AutomationIds.tradeRelease,
            onPressed: _releaseOrder,
          ),
        },
    ];

    return TradeActionBar(
      primary: primary,
      secondary: secondary,
      closeLink: view.showsCloseLink ? _close : null,
      closeLabel: l10n.tradeCloseAction,
      closeAutomationId: AutomationIds.tradeRateClose,
    );
  }

  // ── Overflow menu (share order) ───────────────────────────────────────────

  /// Unconditional `⋮` menu — sharing an order is always a valid action,
  /// unlike the status-gated actions of the bar below.
  Widget _buildOverflowMenu(OrderBookPalette book) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<_OverflowAction>(
      icon: Icon(Icons.more_vert, color: book.textSecondary),
      onSelected: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.comingSoonMessage),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      itemBuilder:
          (_) => [
            PopupMenuItem(
              value: _OverflowAction.shareOrder,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.share, size: 18),
                title: Text(l10n.shareOrderButton),
                dense: true,
              ),
            ),
          ],
    );
  }
}

/// Wraps the first occurrence of [part] in [sentence] with [style], so the
/// translation decides the word order and the code the emphasis. The whole
/// sentence, unstyled, when [part] does not occur.
InlineSpan emphasise(String sentence, String part, TextStyle style) {
  final at = part.isEmpty ? -1 : sentence.indexOf(part);
  if (at < 0) return TextSpan(text: sentence);
  return TextSpan(
    children: [
      if (at > 0) TextSpan(text: sentence.substring(0, at)),
      TextSpan(text: part, style: style),
      if (at + part.length < sentence.length)
        TextSpan(text: sentence.substring(at + part.length)),
    ],
  );
}
