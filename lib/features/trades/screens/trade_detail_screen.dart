import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/widgets/release_confirmation_dialog.dart';
import 'package:mostro/features/trades/widgets/trade_info_cards.dart';
import 'package:mostro/shared/widgets/mostro_reactive_button.dart';

/// Trade detail screen — Route `/trade_detail/:orderId`.
///
/// Shows trade summary, payment method, dates, order ID, instructions,
/// countdown timer, and role-based action buttons.
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

class _TradeDetailScreenState extends ConsumerState<TradeDetailScreen> {
  Timer? _countdownTimer;
  Duration _remaining = const Duration(seconds: _kCountdownSeconds);

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
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

  static TradeStatus _mapOrderStatus(OrderStatus s) {
    switch (s) {
      case OrderStatus.active:
        return TradeStatus.active;
      case OrderStatus.fiatSent:
        return TradeStatus.fiatSent;
      case OrderStatus.settledHoldInvoice:
      case OrderStatus.success:
      case OrderStatus.completedByAdmin:
      case OrderStatus.settledByAdmin:
        return TradeStatus.pendingRating;
      case OrderStatus.canceled:
      case OrderStatus.canceledByAdmin:
      case OrderStatus.expired:
        return TradeStatus.cancelled;
      case OrderStatus.dispute:
        return TradeStatus.disputed;
      default:
        return TradeStatus.loading;
    }
  }

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

  String _getInstructionText(bool isBuyer, TradeStatus status) {
    if (isBuyer) {
      if (status == TradeStatus.active) {
        return 'Send the fiat payment to the seller, then tap "Fiat Sent".';
      } else if (status == TradeStatus.fiatSent) {
        return 'Fiat payment marked as sent. Waiting for the seller '
            'to confirm receipt and release your sats.';
      }
    } else {
      // Seller
      if (status == TradeStatus.active) {
        return 'Contact the buyer with payment instructions.';
      } else if (status == TradeStatus.fiatSent) {
        return 'The buyer has confirmed they sent the fiat payment. '
            'Once you verify receipt, release the sats.';
      }
    }
    if (status == TradeStatus.disputed) {
      return 'A dispute resolver has been assigned. '
          'They will contact you through the app.';
    }
    if (status == TradeStatus.pendingRating) {
      return 'The trade completed successfully. '
          'Rate your counterpart to help build trust in the community.';
    }
    if (status == TradeStatus.rated) {
      return 'Thank you for your rating!';
    }
    return 'Trade in progress.';
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return '00:00:00';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Shared style for destructive (cancel / dispute) outlined buttons.
  ButtonStyle _destructiveOutlineStyle(Color destructiveRed) =>
      OutlinedButton.styleFrom(
        foregroundColor: destructiveRed,
        side: BorderSide(color: destructiveRed),
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      );

  /// RELEASE button — shared between the Disputed and Fiat-Sent seller flows.
  Widget _buildReleaseButton(Color green) {
    return MostroReactiveButton(
      label: 'RELEASE',
      backgroundColor: green,
      icon: Icons.lock_open,
      onPressed: () async {
        final confirmed = await showReleaseConfirmationDialog(context);
        if (confirmed != true || !context.mounted) return;
        try {
          await orders_api.releaseOrder(orderId: widget.orderId);
          if (context.mounted) {
            context.push(AppRoute.rateUserPath(widget.orderId));
          }
        } catch (e, st) {
          debugPrint('[TradeDetailScreen] releaseOrder error: $e\n$st');
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).releaseFailed)),
          );
        }
      },
      onError: (e) {
        debugPrint('[TradeDetailScreen] releaseOrder onError: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).releaseFailed)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);

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
    final orderStatus = ref.watch(tradeStatusProvider(widget.orderId)).valueOrNull
        ?? OrderStatus.pending;
    final status = _mapOrderStatus(orderStatus);

    // Look up order details from the live order book.
    final allOrders = ref.watch(orderBookProvider).valueOrNull ?? [];
    final order = allOrders.where((o) => o.id == widget.orderId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ORDER DETAILS'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoute.home),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Card 1: Trade summary
          TradeInfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isBuyer
                      ? 'You are buying sats'
                      : 'You are selling sats',
                  style: theme.textTheme.headlineSmall,
                ),
                if (order != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${order.displayAmount} ${order.fiatCode}',
                    style: TextStyle(color: green, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Order ${widget.orderId}',
                  style: TextStyle(color: textSec, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Card 2: Payment method
          TradeInfoCard(
            child: Row(
              children: [
                Icon(Icons.payment_outlined, size: 18, color: textSec),
                const SizedBox(width: AppSpacing.sm),
                Text(order?.paymentMethod ?? '—', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Card 3: Creation date
          TradeInfoCard(
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 18, color: textSec),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  order != null ? _formatDate(order.createdAt) : '—',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Card 4: Order ID
          OrderIdCard(orderId: widget.orderId),
          const SizedBox(height: AppSpacing.sm),

          // Card 5: Instructions + status
          InstructionsCard(
            text: _getInstructionText(isBuyer, status),
            statusLabel: status.label,
          ),
          const SizedBox(height: AppSpacing.xl),

          // Countdown
          if (_remaining > Duration.zero) ...[
            Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: (_remaining.inSeconds / _kCountdownSeconds)
                          .clamp(0.0, 1.0),
                      strokeWidth: 4,
                      color: _remaining.inMinutes < 5
                          ? colors?.destructiveRed ?? const Color(0xFFD84D4D)
                          : green,
                      backgroundColor:
                          colors?.backgroundInput ?? const Color(0xFF252A3A),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Time remaining: ${_formatDuration(_remaining)}',
                    style: TextStyle(color: textSec, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],

          // Action buttons (buyer flow — T060)
          if (isBuyer && status == TradeStatus.active) ...[
            MostroReactiveButton(
              label: 'FIAT SENT',
              backgroundColor: green,
              icon: Icons.send,
              onPressed: () async {
                await orders_api.sendFiatSent(orderId: widget.orderId);
              },
              onError: (e) {
                debugPrint('[TradeDetailScreen] sendFiatSent onError: $e');
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.of(context).fiatSentFailed)),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cancelOrder,
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('CANCEL'),
                    style: _destructiveOutlineStyle(
                      colors?.destructiveRed ?? const Color(0xFFD84D4D),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      );
                    },
                    icon: const Icon(Icons.gavel, size: 16),
                    label: const Text('DISPUTE'),
                    style: _destructiveOutlineStyle(
                      colors?.destructiveRed ?? const Color(0xFFD84D4D),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: () =>
                  context.push(AppRoute.chatRoomPath(widget.orderId)),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('CONTACT'),
              style: FilledButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
            ),
          ],

          // ── Seller: Active — CLOSE + CANCEL + DISPUTE + CONTACT ──
          if (!isBuyer && status == TradeStatus.active) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: green,
                      side: BorderSide(color: green),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: const Text('CLOSE'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cancelOrder,
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('CANCEL'),
                    style: _destructiveOutlineStyle(
                      colors?.destructiveRed ?? const Color(0xFFD84D4D),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      );
                    },
                    icon: const Icon(Icons.gavel, size: 16),
                    label: const Text('DISPUTE'),
                    style: _destructiveOutlineStyle(
                      colors?.destructiveRed ?? const Color(0xFFD84D4D),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: () =>
                  context.push(AppRoute.chatRoomPath(widget.orderId)),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('CONTACT'),
              style: FilledButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
            ),
          ],

          // ── Disputed — CLOSE + CONTACT + CANCEL + RELEASE + VIEW DISPUTE ──
          if (status == TradeStatus.disputed) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: green,
                      side: BorderSide(color: green),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: const Text('CLOSE'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.push(AppRoute.chatRoomPath(widget.orderId)),
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('CONTACT'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: green,
                      side: BorderSide(color: green),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // CANCEL + RELEASE only available to the seller during a dispute.
            if (!isBuyer) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cancelOrder,
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('CANCEL'),
                    style: _destructiveOutlineStyle(
                      colors?.destructiveRed ?? const Color(0xFFD84D4D),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _buildReleaseButton(green)),
              ],
            ),
            ], // end if (!isBuyer)
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
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
              icon: const Icon(Icons.gavel, size: 16),
              label: const Text('VIEW DISPUTE'),
              style: FilledButton.styleFrom(
                backgroundColor: colors?.destructiveRed ?? const Color(0xFFD84D4D),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
            ),
          ],

          // ── Seller: Fiat Sent — CLOSE + RELEASE + CANCEL + DISPUTE + CONTACT ──
          if (!isBuyer && status == TradeStatus.fiatSent) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: green,
                      side: BorderSide(color: green),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: const Text('CLOSE'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _buildReleaseButton(green)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cancelOrder,
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('CANCEL'),
                    style: _destructiveOutlineStyle(
                      colors?.destructiveRed ?? const Color(0xFFD84D4D),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      );
                    },
                    icon: const Icon(Icons.gavel, size: 16),
                    label: const Text('DISPUTE'),
                    style: _destructiveOutlineStyle(
                      colors?.destructiveRed ?? const Color(0xFFD84D4D),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: () =>
                  context.push(AppRoute.chatRoomPath(widget.orderId)),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: const Text('CONTACT'),
              style: FilledButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
            ),
          ],

          // ── Pending rating — RATE + CLOSE ─────────────────────────────
          if (status == TradeStatus.pendingRating) ...[
            FilledButton.icon(
              onPressed: () =>
                  context.push(AppRoute.rateUserPath(widget.orderId)),
              icon: const Icon(Icons.star_outline, size: 16),
              label: const Text('RATE'),
              style: FilledButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () => context.pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: green,
                side: BorderSide(color: green),
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              child: const Text('CLOSE'),
            ),
          ],

          // ── Rated — CLOSE only (no further actions) ───────────────────
          if (status == TradeStatus.rated) ...[
            OutlinedButton(
              onPressed: () => context.pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: green,
                side: BorderSide(color: green),
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
              ),
              child: const Text('CLOSE'),
            ),
          ],
        ],
      ),
    );
  }
}
