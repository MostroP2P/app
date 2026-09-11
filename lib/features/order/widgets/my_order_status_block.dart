import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_detail_palette.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/models/order_detail_rules.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/features/trades/screens/trade_detail_screen.dart'
    show TradeStatusMachineName, tradeStatusFromOrderStatus;
import 'package:mostro/l10n/app_localizations.dart';

/// The one coloured block of the maker's own order (handoff 6b): a dot, the
/// status, and on the right what the state has to say — the time left while
/// the order is alive, how long ago it died once it is not.
///
/// Owns the countdown and the pulse; the screen around it never repaints for
/// a tick. A change of family cross-fades over 200 ms.
class MyOrderStatusBlock extends StatefulWidget {
  const MyOrderStatusBlock({
    super.key,
    required this.order,
    required this.status,
    this.onRanOut,
  });

  final OrderItem order;

  /// The live status, which may be newer than [order]'s own.
  final OrderStatus status;

  /// Called when the countdown of a still-pending order reaches zero, so
  /// the screen can drop `Cancel` without waiting for the relay.
  final VoidCallback? onRanOut;

  @override
  State<MyOrderStatusBlock> createState() => _MyOrderStatusBlockState();
}

class _MyOrderStatusBlockState extends State<MyOrderStatusBlock>
    with SingleTickerProviderStateMixin {
  static const _pulse = Duration(milliseconds: 1600);
  static const _fade = Duration(milliseconds: 200);

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: _pulse,
  );
  late final Animation<double> _dotOpacity = Tween(
    begin: 1.0,
    end: 0.35,
  ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

  Timer? _tick;
  Duration _remaining = Duration.zero;

  /// Set when the countdown ran out under a status the daemon has not yet
  /// updated, so the block reads `Expired` without waiting for the relay.
  bool _ranOut = false;

  bool get _isWaiting => widget.status == OrderStatus.pending && !_ranOut;

  @override
  void initState() {
    super.initState();
    _syncCountdown();
    _syncPulse();
  }

  @override
  void didUpdateWidget(MyOrderStatusBlock old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status ||
        old.order.expiresAt != widget.order.expiresAt) {
      _ranOut = false;
      _syncCountdown();
    }
    _syncPulse();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _syncPulse() {
    if (_isWaiting) {
      if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    } else {
      _pulseController
        ..stop()
        ..value = 0;
    }
  }

  /// A countdown runs while the order waits for a taker: `expiresAt` is the
  /// pending order's lifetime, not a trade-stage deadline, so it is shown for
  /// no other status. It repaints once a minute above an hour, once a second
  /// under it, and stops at zero.
  void _syncCountdown() {
    _tick?.cancel();
    _tick = null;
    final expiresAt = widget.order.expiresAt;
    if (expiresAt == null || !_hasCountdown(widget.status)) {
      _remaining = Duration.zero;
      return;
    }
    _remaining = expiresAt.difference(clock.now());
    if (_remaining <= Duration.zero) {
      _remaining = Duration.zero;
      if (widget.status == OrderStatus.pending && !_ranOut) {
        _ranOut = true;
        final onRanOut = widget.onRanOut;
        if (onRanOut != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) onRanOut();
          });
        }
      }
      return;
    }
    _tick = Timer(countdownTick(_remaining), () {
      if (!mounted) return;
      setState(_syncCountdown);
      _syncPulse();
    });
  }

  static bool _hasCountdown(OrderStatus status) =>
      status == OrderStatus.pending;

  @override
  Widget build(BuildContext context) {
    final pal = OrderDetailPalette.of(context);
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final status = _ranOut ? OrderStatus.expired : widget.status;
    final family = statusFamily(status);
    final colors = statusColors(pal, family);
    final aside = _aside(l10n, status, colors.aside);

    return AnimatedSwitcher(
      duration: _fade,
      child: Container(
        key: ValueKey(family),
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _dot(colors.dot, pal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    statusLabel(l10n, status),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (aside != null) aside,
              ],
            ),
            if (_isWaiting) ...[
              const SizedBox(height: 11),
              _progressBar(pal),
              const SizedBox(height: 11),
              Text(
                l10n.myOrderWaitingNote(
                  orderRelativeTime(l10n, widget.order.createdAt),
                ),
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: book.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    ).withAutomationId(
      AutomationIds.orderStatus,
      label: tradeStatusFromOrderStatus(status).machineName,
    );
  }

  /// The 9-dp dot; while waiting it pulses inside a still ring.
  Widget _dot(Color color, OrderDetailPalette pal) {
    final dot = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!_isWaiting) return dot;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: pal.statusWaitRing),
      ),
      child: FadeTransition(opacity: _dotOpacity, child: dot),
    );
  }

  Widget _progressBar(OrderDetailPalette pal) {
    final progress = orderLifeProgress(
      createdAt: widget.order.createdAt,
      expiresAt: widget.order.expiresAt,
      now: clock.now(),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 3,
        width: double.infinity,
        child: ColoredBox(
          color: pal.progressTrack,
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: progress,
            child: ColoredBox(color: pal.progressFill),
          ),
        ),
      ),
    );
  }

  /// Right-hand text of the row: the countdown while alive, how long ago
  /// the order expired once it did, nothing otherwise.
  Widget? _aside(AppLocalizations l10n, OrderStatus status, Color color) {
    if (_hasCountdown(status) && _remaining > Duration.zero) {
      return Text(
        formatRemaining(_remaining),
        semanticsLabel: l10n.timeRemainingLabel(formatRemaining(_remaining)),
        style: TextStyle(
          fontFamily: AppFonts.figures,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      );
    }
    final expiresAt = widget.order.expiresAt;
    if (status == OrderStatus.expired && expiresAt != null) {
      return Text(
        orderRelativeTime(l10n, expiresAt),
        style: TextStyle(fontSize: 12, color: color),
      );
    }
    return null;
  }
}

/// Which box a status renders in (handoff 6b). Later states share a family
/// with the state they resemble: a completed trade is lime like waiting,
/// a dispute is coral like cancelled.
OrderStatusFamily statusFamily(OrderStatus status) => switch (status) {
  OrderStatus.pending ||
  OrderStatus.success ||
  OrderStatus.settledByAdmin ||
  OrderStatus.completedByAdmin => OrderStatusFamily.wait,
  OrderStatus.expired => OrderStatusFamily.dead,
  OrderStatus.canceled ||
  OrderStatus.canceledByAdmin ||
  OrderStatus.cooperativelyCanceled ||
  OrderStatus.dispute => OrderStatusFamily.cancel,
  _ => OrderStatusFamily.hold,
};

/// Status copy, from the model that already exists.
String statusLabel(AppLocalizations l10n, OrderStatus status) =>
    switch (status) {
      OrderStatus.pending => l10n.orderStatusWaitingForTaker,
      OrderStatus.waitingBuyerInvoice => l10n.orderStatusTakenWaitingInvoice,
      OrderStatus.waitingPayment => l10n.orderStatusTakenWaitingPayment,
      OrderStatus.expired => l10n.orderStatusExpired,
      OrderStatus.canceled ||
      OrderStatus.canceledByAdmin ||
      OrderStatus.cooperativelyCanceled => l10n.tradeStatusCancelled,
      OrderStatus.settledHoldInvoice => l10n.tradeStatusPayoutPending,
      OrderStatus.success ||
      OrderStatus.settledByAdmin ||
      OrderStatus.completedByAdmin => l10n.tradeStatusCompleted,
      OrderStatus.dispute => l10n.tradeStatusDisputed,
      _ => l10n.orderStatusInProgress,
    };

/// Whether the maker can still cancel from here. Only a pending order: the
/// daemon rejects `Action::Cancel` once a taker is in (the waiting states
/// have their own cancellation flow, from the trade), and there is nothing
/// to cancel once the order is dead.
bool canCancelOrder(OrderStatus status) => status == OrderStatus.pending;
