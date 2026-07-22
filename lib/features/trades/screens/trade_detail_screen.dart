import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/src/rust/api/disputes.dart' as disputes_api;
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/features/trades/widgets/release_confirmation_dialog.dart';
import 'package:mostro/shared/widgets/mostro_reactive_button.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';

/// Trade detail screen — Route `/trade_detail/:orderId`.
///
/// One explicit next action per state-machine state: a single primary CTA,
/// secondary/destructive actions collapsed behind the app-bar overflow menu,
/// a persistent chat chip, a contextual timer (what expires + consequence),
/// and a step timeline of the trade.
class TradeDetailScreen extends ConsumerStatefulWidget {
  const TradeDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<TradeDetailScreen> createState() => _TradeDetailScreenState();
}

/// Default trade countdown duration (matches Mostro daemon default).
const _kCountdownSeconds = 900; // 15 minutes

/// Type-safe trade status for the detail screen.
/// Will map to/from Rust bridge TradeStep when wired.
enum TradeStatus {
  /// Status not yet resolved (initial loading state — no actions shown).
  loading('Loading'),
  /// Order published but not yet taken by a counterpart.
  pending('Pending'),
  /// Buyer must submit Lightning invoice (waitingBuyerInvoice).
  waitingInvoice('Waiting Invoice'),
  /// Seller must pay hold invoice (waitingPayment).
  waitingPayment('Waiting Payment'),
  active('Active'),
  fiatSent('Fiat Sent'),
  completed('Completed'),
  cancelled('Cancelled'),
  disputed('Disputed'),
  /// Trade completed; counterpart rating prompt shown.
  /// Maps to `Action.rate` / `Action.rateUser` from the Rust bridge.
  pendingRating('Rate'),
  /// Rating has been submitted (or skipped).
  /// Maps to `Action.rateReceived` — no further actions shown.
  rated('Rated');

  const TradeStatus(this.label);
  final String label;
}

/// Localized display label for the trade status pill.
extension TradeStatusL10n on TradeStatus {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
        TradeStatus.loading => l10n.tradeStatusLoading,
        TradeStatus.pending => l10n.tradeFilterPending,
        TradeStatus.waitingInvoice => l10n.tradeFilterWaitingInvoice,
        TradeStatus.waitingPayment => l10n.tradeFilterWaitingPayment,
        TradeStatus.active => l10n.tradeStatusActive,
        TradeStatus.fiatSent => l10n.tradeStatusFiatSent,
        TradeStatus.completed => l10n.tradeStatusCompleted,
        TradeStatus.cancelled => l10n.tradeStatusCancelled,
        TradeStatus.disputed => l10n.tradeStatusDisputed,
        TradeStatus.pendingRating => l10n.tradeStatusRate,
        TradeStatus.rated => l10n.tradeStatusRated,
      };
}

/// Overflow-menu actions (cancel / dispute / release collapsed behind ⋮).
enum _MenuAction { cancel, dispute, release }

class _TradeDetailScreenState extends ConsumerState<TradeDetailScreen> {
  Timer? _countdownTimer;
  Duration _remaining = const Duration(seconds: _kCountdownSeconds);
  int _totalCountdownSeconds = _kCountdownSeconds;

  @override
  void initState() {
    super.initState();
    _loadExpiresAt();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// Fetches the real `expiresAt` from the order and resets [_remaining].
  ///
  /// Falls back to the default [_kCountdownSeconds] when the field is null or
  /// the order is no longer available.
  Future<void> _loadExpiresAt() async {
    try {
      final info = await orders_api.getOrder(orderId: widget.orderId);
      final raw = info?.expiresAt;
      if (raw == null || !mounted) return;
      // PlatformInt64 = int on native, BigInt on web.
      final expiresAtSeconds = raw is BigInt ? raw.toInt() : raw;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final diff = expiresAtSeconds - now;
      if (!mounted) return;
      setState(() {
        _totalCountdownSeconds = diff > 0 ? diff : _kCountdownSeconds;
        _remaining = diff > 0 ? Duration(seconds: diff) : Duration.zero;
      });
    } catch (_) {
      // Keep the default remaining time on error.
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        final next = _remaining - const Duration(seconds: 1);
        if (next.inSeconds <= 0) {
          _countdownTimer?.cancel();
          _remaining = Duration.zero;
        } else {
          _remaining = next;
        }
      });
    });
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  static TradeStatus _mapOrderStatus(OrderStatus s) => switch (s) {
    OrderStatus.pending => TradeStatus.pending,
    OrderStatus.waitingBuyerInvoice => TradeStatus.waitingInvoice,
    OrderStatus.waitingPayment => TradeStatus.waitingPayment,
    OrderStatus.active || OrderStatus.inProgress => TradeStatus.active,
    OrderStatus.fiatSent => TradeStatus.fiatSent,
    OrderStatus.settledHoldInvoice ||
    OrderStatus.success ||
    OrderStatus.completedByAdmin ||
    OrderStatus.settledByAdmin => TradeStatus.pendingRating,
    OrderStatus.canceled ||
    OrderStatus.canceledByAdmin ||
    OrderStatus.cooperativelyCanceled ||
    OrderStatus.expired => TradeStatus.cancelled,
    OrderStatus.dispute => TradeStatus.disputed,
  };

  Future<void> _cancelOrder() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cancelTradeDialogTitle),
        content: Text(l10n.cancelTradeDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.noButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.yesCancelButtonLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await orders_api.cancelOrder(orderId: widget.orderId);
      ref.invalidate(rawTradesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cancelRequestSent)),
      );
    } catch (e, st) {
      debugPrint('[TradeDetailScreen] cancelOrder error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cancelRequestFailed)),
      );
    }
  }

  /// Open a dispute for this trade, upsert into the local dispute notifier,
  /// and navigate to the dispute chat.
  Future<void> _openDispute() async {
    try {
      final dispute = await disputes_api.openDispute(tradeId: widget.orderId);
      if (!mounted) return;
      final raw = dispute.openedAt;
      // PlatformInt64 = int on native, BigInt on web.
      final openedAt = raw is BigInt ? raw.toInt() : raw;
      ref.read(disputeNotifierProvider.notifier).upsert(
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).openDisputeFailed)),
      );
    }
  }

  /// Confirm and release the sats (seller). Shared between the primary CTA
  /// in the fiat-sent state and the overflow menu in the disputed state.
  Future<void> _releaseOrder() async {
    final confirmed = await showReleaseConfirmationDialog(context);
    if (confirmed != true || !mounted) return;
    try {
      await orders_api.releaseOrder(orderId: widget.orderId);
      if (!mounted) return;
      if (ref.read(privacyModeProvider)) {
        context.go(AppRoute.home);
      } else {
        context.push(AppRoute.rateUserPath(widget.orderId));
      }
    } catch (e, st) {
      debugPrint('[TradeDetailScreen] releaseOrder error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).releaseFailed)),
      );
    }
  }

  String _getInstructionText(bool isBuyer, TradeStatus status) {
    final l10n = AppLocalizations.of(context);
    if (status == TradeStatus.waitingInvoice) {
      return isBuyer
          ? l10n.tradeWaitingInvoiceBuyerInstruction
          : l10n.tradeWaitingInvoiceSellerInstruction;
    }
    if (status == TradeStatus.waitingPayment) {
      return isBuyer
          ? l10n.tradeWaitingPaymentBuyerInstruction
          : l10n.tradeWaitingPaymentSellerInstruction;
    }
    if (isBuyer) {
      if (status == TradeStatus.active) {
        return l10n.tradeInstructionActiveBuyer;
      } else if (status == TradeStatus.fiatSent) {
        return l10n.tradeInstructionFiatSentBuyer;
      }
    } else {
      // Seller
      if (status == TradeStatus.active) {
        return l10n.tradeInstructionActiveSeller;
      } else if (status == TradeStatus.fiatSent) {
        return l10n.tradeInstructionFiatSentSeller;
      }
    }
    if (status == TradeStatus.disputed) {
      return l10n.tradeInstructionDisputed;
    }
    if (status == TradeStatus.pendingRating) {
      return l10n.tradeInstructionPendingRating;
    }
    if (status == TradeStatus.rated) {
      return l10n.tradeInstructionRated;
    }
    if (status == TradeStatus.pending) {
      return l10n.tradeInstructionPending;
    }
    if (status == TradeStatus.cancelled) {
      return l10n.tradeInstructionCancelled;
    }
    return l10n.tradeInstructionInProgress;
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return '00:00';
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (d.inHours > 0) return '${d.inHours}:$m:$s';
    return '$m:$s';
  }

  // ── State → copy mapping ─────────────────────────────────────────────────

  /// Headline of the state strip — the one thing happening right now.
  String _headline(bool isBuyer, TradeStatus status, OrderItem? order) {
    final l10n = AppLocalizations.of(context);
    final amount = order != null
        ? '${order.displayAmount} ${order.fiatCode}'
        : l10n.theAgreedAmount;
    return switch (status) {
      TradeStatus.pending => l10n.tradeHeadlinePending,
      TradeStatus.waitingInvoice => isBuyer
          ? l10n.tradeHeadlineWaitingInvoiceBuyer
          : l10n.tradeHeadlineWaitingInvoiceSeller,
      TradeStatus.waitingPayment => isBuyer
          ? l10n.tradeHeadlineWaitingPaymentBuyer
          : l10n.tradeHeadlineWaitingPaymentSeller,
      TradeStatus.active => isBuyer
          ? l10n.tradeHeadlineActiveBuyer(amount)
          : l10n.tradeHeadlineActiveSeller(amount),
      TradeStatus.fiatSent => isBuyer
          ? l10n.tradeHeadlineFiatSentBuyer
          : l10n.tradeHeadlineFiatSentSeller(amount),
      TradeStatus.disputed => l10n.tradeHeadlineDisputed,
      TradeStatus.pendingRating ||
      TradeStatus.completed => l10n.tradeHeadlineComplete,
      TradeStatus.rated => l10n.tradeHeadlineCompleteRated,
      TradeStatus.cancelled => l10n.tradeHeadlineCancelled,
      TradeStatus.loading => l10n.tradeHeadlineLoading,
    };
  }

  /// Contextual timer copy: what expires and what happens then.
  (String, String)? _timerContext(bool isBuyer, TradeStatus status) {
    final l10n = AppLocalizations.of(context);
    return switch (status) {
      TradeStatus.pending => (
          l10n.tradeTimerPendingLabel,
          l10n.tradeTimerPendingConsequence,
        ),
      TradeStatus.waitingInvoice => (
          isBuyer
              ? l10n.tradeTimerWaitingInvoiceLabelBuyer
              : l10n.tradeTimerWaitingInvoiceLabelSeller,
          l10n.tradeTimerWaitingInvoiceConsequence,
        ),
      TradeStatus.waitingPayment => (
          isBuyer
              ? l10n.tradeTimerWaitingPaymentLabelBuyer
              : l10n.tradeTimerWaitingPaymentLabelSeller,
          l10n.tradeTimerWaitingInvoiceConsequence,
        ),
      TradeStatus.active => (
          isBuyer
              ? l10n.tradeTimerActiveLabelBuyer
              : l10n.tradeTimerActiveLabelSeller,
          l10n.tradeTimerActiveConsequence,
        ),
      TradeStatus.fiatSent => (
          isBuyer
              ? l10n.tradeTimerFiatSentLabelBuyer
              : l10n.tradeTimerFiatSentLabelSeller,
          l10n.tradeTimerFiatSentConsequence,
        ),
      _ => null,
    };
  }

  /// Status pill colors — (background, text).
  (Color, Color) _statusPillColors(TradeStatus status) => switch (status) {
        TradeStatus.pending => AppColors.statusPending,
        TradeStatus.waitingInvoice ||
        TradeStatus.waitingPayment => AppColors.statusWaiting,
        TradeStatus.active => AppColors.statusActive,
        TradeStatus.fiatSent => AppColors.statusSettled,
        TradeStatus.pendingRating ||
        TradeStatus.completed ||
        TradeStatus.rated => AppColors.statusSuccess,
        TradeStatus.disputed => AppColors.statusDispute,
        _ => AppColors.statusInactive,
      };

  /// 0-based index of the current step in [_steps]; equals the list length
  /// once the trade is fully done.
  int _currentStep(TradeStatus status) => switch (status) {
        TradeStatus.pending => 0,
        TradeStatus.waitingInvoice || TradeStatus.waitingPayment => 1,
        TradeStatus.active => 2,
        TradeStatus.fiatSent => 3,
        TradeStatus.pendingRating || TradeStatus.completed => 4,
        TradeStatus.rated => 5,
        _ => -1, // disputed / cancelled / loading — timeline hidden
      };

  /// Step labels. Lightning setup is one step because the invoice/hold-invoice
  /// order depends on which side made the order.
  List<String> _steps(bool isBuyer) {
    final l10n = AppLocalizations.of(context);
    return [
      l10n.tradeStepOrderTaken,
      isBuyer ? l10n.tradeStepInvoiceBuyer : l10n.tradeStepInvoiceSeller,
      isBuyer ? l10n.tradeStepFiatBuyer : l10n.tradeStepFiatSeller,
      isBuyer ? l10n.tradeStepReleaseBuyer : l10n.tradeStepReleaseSeller,
      l10n.tradeStepRate,
    ];
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final l10n = AppLocalizations.of(context);

    // Derive role: in-memory map (set by TakeOrderScreen in this session) takes
    // priority; fall back to the DB-backed provider so reopened trades after an
    // app restart still show the correct buyer/seller actions.
    final roleMap = ref.watch(tradeRoleProvider);
    final bool isBuyer;
    if (roleMap.containsKey(widget.orderId)) {
      isBuyer = roleMap[widget.orderId]!;
    } else {
      final dbRole =
          ref.watch(tradeRoleFromDbProvider(widget.orderId)).valueOrNull;
      isBuyer = dbRole ?? true; // default to buyer while DB result is loading
    }

    // Derive trade status from the polled order status.
    // Use TradeStatus.loading while the provider hasn't resolved so the UI
    // doesn't flash the pending CTA before the real status is known.
    final tradeStatusAsync = ref.watch(tradeStatusProvider(widget.orderId));
    final status = tradeStatusAsync.hasValue
        ? _mapOrderStatus(tradeStatusAsync.value!)
        : TradeStatus.loading;

    // Look up order details from the live order book.
    final allOrders = ref.watch(orderBookProvider).valueOrNull ?? [];
    final order = allOrders.where((o) => o.id == widget.orderId).firstOrNull;

    final inFlight = const {
      TradeStatus.waitingInvoice,
      TradeStatus.waitingPayment,
      TradeStatus.active,
      TradeStatus.fiatSent,
      TradeStatus.disputed,
    }.contains(status);

    return Scaffold(
      appBar: AppBar(
        title: Text(inFlight ? l10n.activeTradeTitle : l10n.orderDetailsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoute.home),
        ),
        actions: [_buildOverflowMenu(status, isBuyer, colors)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Persistent chat chip — always-on access to the counterpart.
          if (inFlight) ...[
            _ChatChip(orderId: widget.orderId),
            const SizedBox(height: AppSpacing.md),
          ],

          // State strip: step pill + status pill + headline + instruction
          // + contextual timer.
          _buildStateStrip(theme, colors, isBuyer, status, order),
          const SizedBox(height: AppSpacing.lg),

          // Single primary CTA for the current state.
          ..._buildPrimaryAction(status, isBuyer, green, colors),

          // Step timeline.
          if (_currentStep(status) >= 0) ...[
            const SizedBox(height: AppSpacing.lg),
            _buildTimeline(theme, colors, isBuyer, status),
          ],

          // Compact meta footer: order ID + created date.
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    l10n.tradeIdShortLabel(_shortId(widget.orderId)),
                    style: TextStyle(
                      color: textSec,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.orderId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.orderIdCopied),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Icon(Icons.copy, size: 14, color: textSec),
                ),
                const Spacer(),
                if (order != null)
                  Text(
                    l10n.tradeCreatedAtLabel(_formatDate(order.createdAt)),
                    style: TextStyle(color: textSec, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _shortId(String id) =>
      id.length <= 14 ? id : '${id.substring(0, 8)}…${id.substring(id.length - 5)}';

  // ── Overflow menu (collapsed secondary/destructive actions) ──────────────

  Widget _buildOverflowMenu(
      TradeStatus status, bool isBuyer, AppColors? colors) {
    final red = colors?.destructiveRed ?? const Color(0xFFD84D4D);
    final l10n = AppLocalizations.of(context);

    final canCancel = const {
      TradeStatus.pending,
      TradeStatus.waitingInvoice,
      TradeStatus.waitingPayment,
      TradeStatus.active,
      TradeStatus.fiatSent,
    }.contains(status) ||
        (status == TradeStatus.disputed && !isBuyer);
    final canDispute =
        status == TradeStatus.active || status == TradeStatus.fiatSent;
    final canRelease = status == TradeStatus.disputed && !isBuyer;

    if (!canCancel && !canDispute && !canRelease) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<_MenuAction>(
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => switch (action) {
        _MenuAction.cancel => _cancelOrder(),
        _MenuAction.dispute => _openDispute(),
        _MenuAction.release => _releaseOrder(),
      },
      itemBuilder: (ctx) => [
        if (canRelease)
          PopupMenuItem(
            value: _MenuAction.release,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_open, size: 18),
              title: Text(l10n.releaseSatsMenuItem),
              dense: true,
            ),
          ),
        if (canCancel)
          PopupMenuItem(
            value: _MenuAction.cancel,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cancel_outlined, size: 18, color: red),
              title: Text(l10n.cancelOrderMenuItem, style: TextStyle(color: red)),
              dense: true,
            ),
          ),
        if (canDispute)
          PopupMenuItem(
            value: _MenuAction.dispute,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.gavel, size: 18, color: red),
              title: Text(l10n.openDisputeMenuItem, style: TextStyle(color: red)),
              dense: true,
            ),
          ),
      ],
    );
  }

  // ── State strip ──────────────────────────────────────────────────────────

  Widget _buildStateStrip(
    ThemeData theme,
    AppColors? colors,
    bool isBuyer,
    TradeStatus status,
    OrderItem? order,
  ) {
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final (pillBg, pillFg) = _statusPillColors(status);
    final currentStep = _currentStep(status);
    final totalSteps = _steps(isBuyer).length;
    final timerCtx = _timerContext(isBuyer, status);
    final showTimer = timerCtx != null && _remaining > Duration.zero;
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (currentStep >= 0)
                _Pill(
                  label: currentStep >= totalSteps
                      ? l10n.stepDoneLabel
                      : l10n.stepIndicator(currentStep + 1, totalSteps),
                  background: colors?.backgroundElevated ??
                      const Color(0xFF2A2D35),
                  foreground: textSec,
                ),
              if (currentStep >= 0) const SizedBox(width: AppSpacing.sm),
              _Pill(
                label: status.localizedLabel(l10n),
                background: pillBg,
                foreground: pillFg,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _headline(isBuyer, status, order),
            style: theme.textTheme.headlineMedium,
          ),
          if (order != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${order.displayAmount} ${order.fiatCode} · ${order.paymentMethod}',
              style: TextStyle(
                color: textSec,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            _getInstructionText(isBuyer, status),
            style: theme.textTheme.bodyMedium,
          ),
          if (showTimer) ...[
            const SizedBox(height: AppSpacing.lg),
            _buildContextualTimer(colors, timerCtx),
          ],
        ],
      ),
    );
  }

  /// Mini timer row: clock + remaining + label, progress bar, consequence.
  Widget _buildContextualTimer(AppColors? colors, (String, String) ctx) {
    final (label, consequence) = ctx;
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final amber = colors?.warningAmber ?? const Color(0xFFE89C3C);
    final red = colors?.destructiveRed ?? const Color(0xFFD84D4D);
    final track = colors?.backgroundInput ?? const Color(0xFF252A3A);

    final fraction = _totalCountdownSeconds > 0
        ? (_remaining.inSeconds / _totalCountdownSeconds).clamp(0.0, 1.0)
        : 0.0;
    // Lime → amber at <10% remaining → red at <2%.
    final timerColor = fraction < 0.02
        ? red
        : fraction < 0.10
            ? amber
            : green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule, size: 16, color: timerColor),
            const SizedBox(width: AppSpacing.sm),
            Text(
              _formatDuration(_remaining),
              style: TextStyle(
                color: timerColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: textSec, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 4,
            color: timerColor,
            backgroundColor: track,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          consequence,
          style: TextStyle(color: textSec, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  // ── Primary CTA ──────────────────────────────────────────────────────────

  /// One explicit next action per state. Waiting-on-counterpart states get a
  /// disabled button with a spinner instead of a tappable CTA.
  List<Widget> _buildPrimaryAction(
    TradeStatus status,
    bool isBuyer,
    Color green,
    AppColors? colors,
  ) {
    final red = colors?.destructiveRed ?? const Color(0xFFD84D4D);
    final l10n = AppLocalizations.of(context);

    FilledButton bigButton({
      required String label,
      required IconData icon,
      required VoidCallback onPressed,
      Color? background,
      Color? foreground,
    }) =>
        FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: background ?? green,
            foregroundColor: foreground ?? Colors.black,
            minimumSize: const Size.fromHeight(56),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
          ),
        );

    switch ((status, isBuyer)) {
      case (TradeStatus.waitingInvoice, true):
        return [
          bigButton(
            label: l10n.addLightningInvoiceButton,
            icon: Icons.receipt_long_outlined,
            onPressed: () =>
                context.push(AppRoute.addInvoicePath(widget.orderId)),
          ),
        ];
      case (TradeStatus.waitingPayment, false):
        return [
          bigButton(
            label: l10n.payHoldInvoiceButton,
            icon: Icons.bolt,
            onPressed: () =>
                context.push(AppRoute.payInvoicePath(widget.orderId)),
          ),
        ];
      case (TradeStatus.active, true):
        return [
          MostroReactiveButton(
            label: l10n.markFiatSentButton,
            backgroundColor: green,
            icon: Icons.check,
            onPressed: () async {
              await orders_api.sendFiatSent(orderId: widget.orderId);
            },
            onError: (e) {
              debugPrint('[TradeDetailScreen] sendFiatSent onError: $e');
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text(AppLocalizations.of(context).fiatSentFailed)),
              );
            },
          ),
        ];
      case (TradeStatus.fiatSent, false):
        return [
          MostroReactiveButton(
            label: l10n.confirmReleaseSatsButton,
            backgroundColor: green,
            icon: Icons.lock_open,
            onPressed: _releaseOrder,
            onError: (e) {
              debugPrint('[TradeDetailScreen] releaseOrder onError: $e');
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(AppLocalizations.of(context).releaseFailed)),
              );
            },
          ),
        ];
      case (TradeStatus.disputed, _):
        return [
          bigButton(
            label: l10n.viewDisputeButton,
            icon: Icons.gavel,
            background: red,
            foreground: Colors.white,
            onPressed: () {
              final dispute = ref.read(
                disputeByTradeIdProvider(widget.orderId),
              );
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
            },
          ),
        ];
      case (TradeStatus.pendingRating, _):
        return [
          bigButton(
            label: l10n.tradeStepRate,
            icon: Icons.star_outline,
            onPressed: () {
              if (ref.read(privacyModeProvider)) {
                context.go(AppRoute.home);
              } else {
                context.push(AppRoute.rateUserPath(widget.orderId));
              }
            },
          ),
        ];
      case (TradeStatus.rated, _) || (TradeStatus.cancelled, _):
        return [
          OutlinedButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(AppRoute.home),
            style: OutlinedButton.styleFrom(
              foregroundColor: green,
              side: BorderSide(color: green),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
            child: Text(l10n.closeRatingButton),
          ),
        ];
      // Waiting on the counterpart (or order still pending / loading):
      // disabled button with spinner so the "next action" is explicit.
      case (TradeStatus.waitingInvoice, false):
        return [_waitingButton(l10n.waitingForBuyer, colors)];
      case (TradeStatus.waitingPayment, true):
        return [_waitingButton(l10n.waitingForSeller, colors)];
      case (TradeStatus.active, false):
        return [_waitingButton(l10n.waitingForFiatPayment, colors)];
      case (TradeStatus.fiatSent, true):
        return [_waitingButton(l10n.waitingForSeller, colors)];
      case (TradeStatus.pending, _):
        return [_waitingButton(l10n.waitingForCounterpart, colors)];
      default:
        return const [];
    }
  }

  Widget _waitingButton(String label, AppColors? colors) {
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: colors?.backgroundCard ?? const Color(0xFF1E2230),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: textSec),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            label,
            style: TextStyle(
              color: textSec,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Step timeline ────────────────────────────────────────────────────────

  Widget _buildTimeline(
    ThemeData theme,
    AppColors? colors,
    bool isBuyer,
    TradeStatus status,
  ) {
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final elevated = colors?.backgroundElevated ?? const Color(0xFF2A2D35);
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final amber = colors?.warningAmber ?? const Color(0xFFE89C3C);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final textSubtle = colors?.textSubtle ?? const Color(0xFF9A9A9C);
    final l10n = AppLocalizations.of(context);

    final steps = _steps(isBuyer);
    final current = _currentStep(status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.yourTradeTimelineTitle,
            style: TextStyle(
              color: textSubtle,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < current
                        ? green
                        : i == current
                            ? amber
                            : elevated,
                  ),
                  alignment: Alignment.center,
                  child: i < current
                      ? const Icon(Icons.check, size: 14, color: Colors.black)
                      : i == current
                          ? Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                              ),
                            )
                          : null,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      steps[i],
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: i <= current
                            ? colors?.textPrimary ?? Colors.white
                            : textSec,
                        fontWeight:
                            i == current ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Small shared widgets ──────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Persistent chat chip: counterpart handle + unread badge, navigates to the
/// trade chat. Replaces the old ghost CONTACT button at the bottom.
class _ChatChip extends ConsumerWidget {
  const _ChatChip({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>();
    final purple = colors?.purpleButton ?? const Color(0xFF8359C2);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final l10n = AppLocalizations.of(context);

    final rooms = ref.watch(chatRoomsNotifierProvider);
    final room = rooms.where((r) => r.orderId == orderId).firstOrNull;

    final handle =
        room == null ? l10n.yourCounterpartFallback : room.displayHandle(l10n);
    final unread = room?.unreadCount ?? 0;

    return InkWell(
      onTap: () => context.push(AppRoute.chatRoomPath(orderId)),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              purple.withValues(alpha: 0.20),
              purple.withValues(alpha: 0.07),
            ],
          ),
          border: Border.all(color: purple.withValues(alpha: 0.27)),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            if (room != null)
              NymAvatar(
                iconIndex: room.peerIconIndex,
                colorHue: room.peerColorHue,
                size: 36,
              )
            else
              CircleAvatar(
                radius: 18,
                backgroundColor: purple.withValues(alpha: 0.3),
                child:
                    Icon(Icons.chat_bubble_outline, size: 18, color: purple),
              ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    handle,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    unread > 0
                        ? l10n.secureChatUnread(unread)
                        : l10n.secureChatEncrypted,
                    style: TextStyle(fontSize: 11, color: textSec),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (unread > 0) ...[
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: purple),
                child: Text(
                  '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Icon(Icons.chevron_right, color: purple),
          ],
        ),
      ),
    );
  }
}
