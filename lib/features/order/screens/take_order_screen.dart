import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/widgets/range_amount_modal.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';

/// Take order screen — displays order details and allows the user
/// to take (buy or sell) the order.
///
/// Routes: `/take_sell/:orderId` and `/take_buy/:orderId`.
class TakeOrderScreen extends ConsumerStatefulWidget {
  const TakeOrderScreen({
    super.key,
    required this.orderId,
    required this.isBuying,
  });

  /// The order being viewed.
  final String orderId;

  /// `true` if the taker is buying BTC (taking a sell order).
  final bool isBuying;

  @override
  ConsumerState<TakeOrderScreen> createState() => _TakeOrderScreenState();
}

class _TakeOrderScreenState extends ConsumerState<TakeOrderScreen> {
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  bool _submitting = false;

  OrderItem? get _order {
    final orders = ref.read(orderBookProvider);
    try {
      return orders.firstWhere((o) => o.id == widget.orderId);
    } catch (_) {
      return null;
    }
  }

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
    final order = _order;
    if (order?.expiresAt == null) return;

    _remaining = order!.expiresAt!.difference(DateTime.now());
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = order.expiresAt!.difference(DateTime.now());
        if (_remaining.isNegative) {
          _countdownTimer?.cancel();
          _remaining = Duration.zero;
        }
      });
    });
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return '00:00:00';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _onTakeOrder() async {
    final order = _order;
    if (order == null || _submitting) return;

    // Range orders: show amount modal first.
    if (order.isRange) {
      final amount = await showRangeAmountModal(
        context: context,
        min: order.fiatAmountMin!,
        max: order.fiatAmountMax!,
        currencyCode: order.fiatCode,
      );
      if (amount == null || !mounted) return;
    }

    setState(() => _submitting = true);

    try {
      // TODO (Phase 8+): Call take_order() via Rust bridge.
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      // Navigate based on role:
      // Buyer → add invoice screen; Seller → pay invoice screen.
      if (widget.isBuying) {
        context.push(AppRoute.addInvoicePath(widget.orderId));
      } else {
        context.push(AppRoute.payInvoicePath(widget.orderId));
      }
    } catch (e) {
      if (!mounted) return;
      final message = e.toString();
      if (message.contains('OrderAlreadyTaken')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order has already been taken')),
        );
        context.go(AppRoute.home);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $message')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final flags = ref.watch(currencyFlagsProvider);

    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order Not Found')),
        body: const Center(child: Text('This order is no longer available.')),
      );
    }

    final flag = flags[order.fiatCode] ?? '';
    final title = widget.isBuying ? 'SELL ORDER DETAILS' : 'BUY ORDER DETAILS';
    final actionLabel = widget.isBuying ? 'Buy' : 'Sell';
    final premiumPositive = order.premium >= 0;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Card 1: Description + fiat/currency/price/premium
          _InfoCard(
            color: cardBg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order.displayAmount} ${order.fiatCode} $flag',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Market Price (${premiumPositive ? '+' : ''}${order.premium.toStringAsFixed(1)}%)',
                  style: TextStyle(
                    color: premiumPositive ? green : colors?.sellColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Card 2: Payment method
          _InfoCard(
            color: cardBg,
            child: Row(
              children: [
                Icon(Icons.payment_outlined, size: 18, color: textSec),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    order.paymentMethod,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Card 3: Creation date
          _InfoCard(
            color: cardBg,
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 18, color: textSec),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  _formatDate(order.createdAt),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Card 4: Order ID with copy
          _InfoCard(
            color: cardBg,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    order.id,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: order.id));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Order ID copied'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy order ID',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Card 5: Creator reputation
          _InfoCard(
            color: cardBg,
            child: Row(
              children: [
                const Icon(Icons.star, size: 16, color: Colors.amber),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  order.rating.toStringAsFixed(1),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(width: AppSpacing.lg),
                Icon(Icons.person_outline, size: 16, color: textSec),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${order.tradeCount}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(width: AppSpacing.lg),
                Icon(Icons.calendar_month_outlined, size: 16, color: textSec),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${order.daysActive}d',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Countdown timer
          if (_remaining > Duration.zero) ...[
            Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: _remaining.inSeconds /
                          (24 * 3600), // proportion of 24h
                      strokeWidth: 4,
                      color: green,
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
        ],
      ),

      // Bottom: Close + Buy/Sell
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: green,
                    side: BorderSide(color: green),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _onTakeOrder,
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(actionLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: child,
    );
  }
}
