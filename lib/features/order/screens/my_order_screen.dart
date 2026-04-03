import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;

/// Detail screen for an order created by the current user.
///
/// Shows the same order information as [TakeOrderScreen] but replaces the
/// Buy/Sell action with a Cancel button that sends a cancel message to the
/// Mostro node.
///
/// Route: `/my_order/:orderId`
class MyOrderScreen extends ConsumerStatefulWidget {
  const MyOrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<MyOrderScreen> createState() => _MyOrderScreenState();
}

class _MyOrderScreenState extends ConsumerState<MyOrderScreen> {
  bool _cancelling = false;

  Future<void> _onCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel order'),
        content: const Text(
          'Are you sure you want to cancel this order? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await orders_api.cancelOrder(orderId: widget.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cancel request sent')),
      );
      context.go(AppRoute.home);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel: $e')),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(orderBookProvider).valueOrNull ?? [];
    final order = orders.where((o) => o.id == widget.orderId).firstOrNull;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final sellColor = colors?.sellColor ?? const Color(0xFFFF8A8A);
    final flags = ref.watch(currencyFlagsProvider);

    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order Not Found')),
        body: const Center(child: Text('This order is no longer available.')),
      );
    }

    final flag = flags[order.fiatCode] ?? '';
    final isSelling = order.kind == 'sell';
    final title = isSelling ? 'YOUR SELL ORDER' : 'YOUR BUY ORDER';
    final premiumPositive = order.premium >= 0;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Card 1: Amount + currency + premium
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
                    color: premiumPositive ? green : sellColor,
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

          // Status indicator
          _InfoCard(
            color: cardBg,
            child: Row(
              children: [
                Icon(Icons.pending_outlined, size: 18, color: green),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Waiting for a taker',
                  style: theme.textTheme.bodyMedium!.copyWith(color: green),
                ),
              ],
            ),
          ),
        ],
      ),

      // Bottom bar: Close + Cancel
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
                  onPressed: _cancelling ? null : _onCancel,
                  style: FilledButton.styleFrom(
                    backgroundColor: sellColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: sellColor.withValues(alpha: 0.3),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: _cancelling
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Cancel order'),
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
