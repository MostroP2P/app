import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart' as rust_types;

// ── Order resolution ──────────────────────────────────────────────────────────

/// Resolves the order backing a chat room, for the sticky trade-state header.
///
/// Priority:
/// 1. Live order book entry ([orderBookProvider]).
/// 2. One-shot `getOrder()` from the in-memory book.
/// 3. Persisted trade DB (`listTrades()`), so taken/terminal trades still
///    resolve after the order leaves the book.
///
/// Returns `null` when no data is found so the header can hide itself.
/// Re-resolves whenever the live trade status changes.
final chatTradeOrderProvider =
    FutureProvider.family.autoDispose<OrderItem?, String>((ref, orderId) async {
  // Re-resolve when the polled status changes (e.g. active → fiatSent).
  ref.watch(tradeStatusProvider(orderId));

  final book = ref.watch(orderBookProvider).valueOrNull;
  final fromBook = book?.where((o) => o.id == orderId).firstOrNull;
  if (fromBook != null) return fromBook;

  try {
    final info = await orders_api.getOrder(orderId: orderId);
    if (info != null) return _toOrderItem(info);

    final trades = await orders_api.listTrades();
    final trade = trades.where((t) => t.order.id == orderId).firstOrNull;
    if (trade != null) return _toOrderItem(trade.order);
  } catch (e) {
    debugPrint('[TradeStateHeader] order lookup failed: $e');
  }
  return null;
});

OrderItem? _toOrderItem(rust_types.OrderInfo info) {
  try {
    return OrderItem.fromInfo(info);
  } on ArgumentError {
    // Malformed amount shape (neither fixed nor range) — degrade gracefully.
    return null;
  }
}

// ── TradeStateHeader ──────────────────────────────────────────────────────────

/// Compact trade-state card pinned below the chat app bar (UX proposal #6).
///
/// Row 1: status pill · "Buying/Selling N sats" · fiat amount.
/// Row 2: payment method · live countdown ("MM:SS left") · "View order ↗".
///
/// Tapping anywhere on the card navigates to the trade detail screen.
/// Hides itself entirely when the order cannot be resolved.
class TradeStateHeader extends ConsumerWidget {
  const TradeStateHeader({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(chatTradeOrderProvider(orderId)).valueOrNull;
    if (order == null) return const SizedBox.shrink();

    final colors = Theme.of(context).extension<AppColors>();
    final textTheme = Theme.of(context).textTheme;

    final cardColor = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final primary = colors?.textPrimary ?? const Color(0xFFFFFFFF);
    final secondary = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final amber = colors?.warningAmber ?? const Color(0xFFE89C3C);
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);

    // Live status overrides the snapshot baked into the resolved order.
    final liveStatus = ref.watch(tradeStatusProvider(orderId)).valueOrNull;
    final statusFilter = orderStatusToFilter(liveStatus ?? order.status);
    final (pillBg, pillFg) = _statusColors(statusFilter);

    // Buyer/seller role: in-memory map → persisted DB → derive from order.
    final isBuyer = ref.watch(tradeRoleProvider)[orderId] ??
        ref.watch(tradeRoleFromDbProvider(orderId)).valueOrNull ??
        _deriveIsBuyer(order);

    final roleWord = isBuyer ? 'Buying' : 'Selling';
    final amountLabel = order.amountSats != null
        ? '$roleWord ${_fmtSats(order.amountSats!)} sats'
        : '$roleWord Bitcoin';

    final dot = Text('·', style: textTheme.bodySmall?.copyWith(color: secondary));

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => context.push(AppRoute.tradeDetailPath(orderId)),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Row 1: status pill · amount · fiat ────────────────────
                Wrap(
                  spacing: 6,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: pillBg,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Text(
                        statusFilter.label,
                        style: textTheme.bodySmall?.copyWith(
                          color: pillFg,
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    dot,
                    Text(
                      amountLabel,
                      style: textTheme.bodySmall?.copyWith(
                        color: primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    dot,
                    Text(
                      '${order.displayAmount} ${order.fiatCode}',
                      style: textTheme.bodySmall?.copyWith(color: secondary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // ── Row 2: method · countdown · view order ────────────────
                Row(
                  children: [
                    if (order.paymentMethod.isNotEmpty) ...[
                      Icon(Icons.credit_card, size: 12, color: secondary),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          order.paymentMethod,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: secondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                    if (order.expiresAt != null)
                      _CountdownChip(
                        expiresAt: order.expiresAt!,
                        color: amber,
                        separatorColor: secondary,
                        showSeparator: order.paymentMethod.isNotEmpty,
                      ),
                    const Spacer(),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'View order',
                      style: textTheme.bodySmall?.copyWith(
                        color: green,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.north_east, size: 11, color: green),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Maps a [TradeStatusFilter] to (background, foreground) pill colors.
  static (Color, Color) _statusColors(TradeStatusFilter status) {
    return switch (status) {
      TradeStatusFilter.pending => AppColors.statusPending,
      TradeStatusFilter.waitingInvoice => AppColors.statusWaiting,
      TradeStatusFilter.waitingPayment => AppColors.statusWaiting,
      TradeStatusFilter.active => AppColors.statusActive,
      TradeStatusFilter.fiatSent => AppColors.statusActive,
      TradeStatusFilter.success => AppColors.statusSuccess,
      TradeStatusFilter.canceled => AppColors.statusInactive,
      TradeStatusFilter.dispute => AppColors.statusDispute,
      // `all` is a filter sentinel, not a real trade status.
      TradeStatusFilter.all => AppColors.statusInactive,
    };
  }

  /// Derives the local user's role from the order itself when no role record
  /// exists: the maker of a buy order buys; the taker of a sell order buys.
  static bool _deriveIsBuyer(OrderItem order) =>
      order.isMine ? order.kind == 'buy' : order.kind == 'sell';

  /// Formats a sats amount with thousands separators (e.g. "1,117").
  static String _fmtSats(BigInt sats) {
    final s = sats.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ── Countdown chip ────────────────────────────────────────────────────────────

/// Live "MM:SS left" countdown, ticking each second.
///
/// Renders nothing once the expiry has passed (the timer also stops then).
class _CountdownChip extends StatefulWidget {
  const _CountdownChip({
    required this.expiresAt,
    required this.color,
    required this.separatorColor,
    this.showSeparator = false,
  });

  final DateTime expiresAt;
  final Color color;
  final Color separatorColor;

  /// Whether to prefix a "·" separator (when a payment method precedes it).
  final bool showSeparator;

  @override
  State<_CountdownChip> createState() => _CountdownChipState();
}

class _CountdownChipState extends State<_CountdownChip> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      // Stop ticking once expired — the chip stays hidden from then on.
      if (!widget.expiresAt.isAfter(DateTime.now())) {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.expiresAt.difference(DateTime.now());
    if (remaining.inSeconds <= 0) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showSeparator) ...[
          const SizedBox(width: 6),
          Text(
            '·',
            style: textTheme.bodySmall?.copyWith(color: widget.separatorColor),
          ),
          const SizedBox(width: 6),
        ],
        Icon(Icons.schedule, size: 12, color: widget.color),
        const SizedBox(width: 3),
        Text(
          '${_fmtRemaining(remaining)} left',
          style: textTheme.bodySmall?.copyWith(
            color: widget.color,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  /// "MM:SS" under an hour, "H:MM:SS" above.
  static String _fmtRemaining(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return d.inHours > 0
        ? '${d.inHours}:${two(m)}:${two(s)}'
        : '${two(m)}:${two(s)}';
  }
}
