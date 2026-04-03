import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart';

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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dl10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(dl10n.cancelOrderDialogTitle),
          content: Text(dl10n.cancelOrderDialogContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(dl10n.noButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(dl10n.yesCancelButtonLabel),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await orders_api.cancelOrder(orderId: widget.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cancelRequestSent)),
      );
      context.go(AppRoute.home);
    } catch (e, stackTrace) {
      debugPrint('[MyOrderScreen] cancel failed: $e\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cancelOrderFailed)),
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
      final l10nNull = AppLocalizations.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(l10nNull.orderNotFoundTitle)),
        body: Center(child: Text(l10nNull.orderNotFoundMessage)),
      );
    }

    final l10n = AppLocalizations.of(context);
    final flag = flags[order.fiatCode] ?? '';
    final isSelling = order.kind == 'sell';
    final title = isSelling ? l10n.myOrderSellTitle : l10n.myOrderBuyTitle;
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
                      SnackBar(
                        content: Text(l10n.orderIdCopied),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: l10n.copyOrderIdTooltip,
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
            child: Builder(builder: (ctx) {
              final status = _statusInfo(ctx, order.status);
              return Row(
                children: [
                  Icon(status.icon, size: 18, color: status.color),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    status.label,
                    style: theme.textTheme.bodyMedium!
                        .copyWith(color: status.color),
                  ),
                ],
              );
            }),
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
                  child: Text(l10n.closeButtonLabel),
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
                      : Text(l10n.cancelOrderButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ({String label, IconData icon, Color color}) _statusInfo(
    BuildContext ctx,
    OrderStatus status,
  ) {
    final l10n = AppLocalizations.of(ctx);
    final colors = Theme.of(ctx).extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final sellColor = colors?.sellColor ?? const Color(0xFFFF8A8A);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);

    return switch (status) {
      OrderStatus.pending => (
          label: l10n.orderStatusWaitingForTaker,
          icon: Icons.pending_outlined,
          color: green,
        ),
      OrderStatus.waitingBuyerInvoice => (
          label: l10n.orderStatusWaitingBuyerInvoice,
          icon: Icons.receipt_outlined,
          color: green,
        ),
      OrderStatus.waitingPayment => (
          label: l10n.orderStatusWaitingPayment,
          icon: Icons.hourglass_empty_outlined,
          color: green,
        ),
      OrderStatus.inProgress || OrderStatus.active => (
          label: l10n.orderStatusInProgress,
          icon: Icons.sync_outlined,
          color: green,
        ),
      OrderStatus.expired => (
          label: l10n.orderStatusExpired,
          icon: Icons.timer_off_outlined,
          color: sellColor,
        ),
      OrderStatus.canceled ||
      OrderStatus.canceledByAdmin => (
          label: l10n.tradeStatusCancelled,
          icon: Icons.cancel_outlined,
          color: sellColor,
        ),
      OrderStatus.success ||
      OrderStatus.settledHoldInvoice ||
      OrderStatus.settledByAdmin ||
      OrderStatus.completedByAdmin => (
          label: l10n.tradeStatusCompleted,
          icon: Icons.check_circle_outline,
          color: green,
        ),
      OrderStatus.dispute => (
          label: l10n.tradeStatusDisputed,
          icon: Icons.gavel_outlined,
          color: sellColor,
        ),
      _ => (
          label: l10n.orderStatusInProgress,
          icon: Icons.info_outline,
          color: textSec,
        ),
    };
  }

  String _formatDate(DateTime dt) {
    return DateFormat.yMd().add_jm().format(dt);
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
