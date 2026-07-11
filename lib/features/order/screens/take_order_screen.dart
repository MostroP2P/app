import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/widgets/range_amount_modal.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart' show refreshTrades;
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/settings.dart' as settings_api;
import 'package:mostro/src/rust/api/types.dart';

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
  double? _selectedAmount;

  @override
  void initState() {
    super.initState();
    // Try immediately in case the provider already has data.
    _tryStartCountdown();
    // If the provider is still loading, listen for the first value.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(orderBookProvider, (_, __) => _tryStartCountdown(),
          fireImmediately: true);
    });
  }

  void _tryStartCountdown() {
    if (_countdownTimer != null) return; // already running
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    final orders = ref.read(orderBookProvider).valueOrNull ?? [];
    final order = orders.where((o) => o.id == widget.orderId).firstOrNull;
    if (order?.expiresAt == null) return;

    final expiresAt = order!.expiresAt!;
    _remaining = expiresAt.difference(DateTime.now());
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = expiresAt.difference(DateTime.now());
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
    final orders = ref.read(orderBookProvider).valueOrNull ?? [];
    final order = orders.where((o) => o.id == widget.orderId).firstOrNull;
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
      _selectedAmount = amount;
    }

    setState(() => _submitting = true);

    try {
      // Dispatch take-order to Mostro via the Rust bridge.
      await orders_api.takeOrder(
        orderId: widget.orderId,
        role: widget.isBuying ? TradeRole.buyer : TradeRole.seller,
        fiatAmount: _selectedAmount,
      );

      if (!mounted) return;

      // Bust the trades cache so My Trades picks up the newly saved trade.
      refreshTrades(ref);

      // Record the user's role so TradeDetailScreen can read it.
      ref.read(tradeRoleProvider.notifier).update(
            (map) => {...map, widget.orderId: widget.isBuying},
          );

      if (widget.isBuying) {
        // Check whether a default LN address is configured. If yes, Mostro
        // will pay it directly and the buyer can skip the add-invoice step.
        final settings = await settings_api.getSettings();
        if (!mounted) return;
        if (settings.defaultLightningAddress != null) {
          // LN address was included in take-sell payload — go straight to trade.
          context.go(AppRoute.tradeDetailPath(widget.orderId));
        } else {
          context.push(AppRoute.addInvoicePath(widget.orderId));
        }
      } else {
        context.push(AppRoute.payInvoicePath(widget.orderId));
      }
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      // takeOrder now waits for the daemon's reply: errors here mean the
      // trade was NOT created (CantDo rejection, unsupported bond, timeout).
      // Strip the Rust error prefix for a cleaner message.
      final raw = e.toString();
      final anyhowMatch = RegExp(r'^.*?AnyhowException\((.+)\)$').firstMatch(raw);
      final msg = anyhowMatch != null ? anyhowMatch.group(1)! : raw;
      if (msg.contains('OrderAlreadyTaken')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.orderAlreadyTaken)),
        );
        context.go(AppRoute.home);
      } else {
        final display = msg.contains('NoDaemonResponse')
            ? l10n.sessionTimeoutMessage
            : msg.contains('BondRequired')
                ? l10n.bondRequired
                : msg;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(display)),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
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
    final flags = ref.watch(currencyFlagsProvider);
    final privacyMode = ref.watch(privacyModeProvider);

    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order Not Found')),
        body: const Center(child: Text('This order is no longer available.')),
      );
    }

    final flag = flags[order.fiatCode] ?? '';
    final title = widget.isBuying ? 'SELL ORDER DETAILS' : 'BUY ORDER DETAILS';
    final actionLabel = widget.isBuying ? 'BUY THESE SATS' : 'SELL SATS';
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
                  widget.isBuying
                      ? 'Someone is selling sats'
                      : 'Someone is buying sats',
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text.rich(
                  TextSpan(
                    text: 'for ',
                    style: TextStyle(color: textSec, fontSize: 14),
                    children: [
                      TextSpan(
                        text: '${order.displayAmount} ${order.fiatCode} $flag',
                        style: TextStyle(
                          color: colors?.textPrimary ?? Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const TextSpan(text: ' at market price'),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Premium: ${premiumPositive ? '+' : ''}${order.premium.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: premiumPositive ? green : colors?.sellColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

          // Card 5: Creator reputation — hidden in full privacy mode.
          // Rating step is skipped in trade_detail_screen.dart when privacy
          // mode is active.
          if (!privacyMode) ...[
            _InfoCard(
              color: cardBg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Creator reputation',
                    style: TextStyle(color: textSec, fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _ReputationStat(
                          value: order.rating.toStringAsFixed(1),
                          label: 'rating',
                          icon: Icons.star,
                          iconColor: Colors.amber,
                        ),
                      ),
                      Expanded(
                        child: _ReputationStat(
                          value: '${order.tradeCount}',
                          label: 'trades',
                        ),
                      ),
                      Expanded(
                        child: _ReputationStat(
                          value: '${order.daysActive}',
                          label: 'days active',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Contextual countdown: what expires and what happens then.
          if (_remaining > Duration.zero) ...[
            _InfoCard(
              color: cardBg,
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 72,
                          height: 72,
                          child: CircularProgressIndicator(
                            value: () {
                              if (order.expiresAt == null) return 0.0;
                              final lifetime = order.expiresAt!
                                  .difference(order.createdAt)
                                  .inSeconds;
                              if (lifetime <= 0) return 0.0;
                              return (_remaining.inSeconds / lifetime)
                                  .clamp(0.0, 1.0);
                            }(),
                            strokeWidth: 5,
                            color: green,
                            backgroundColor: colors?.backgroundInput ??
                                const Color(0xFF252A3A),
                          ),
                        ),
                        Text(
                          _formatDuration(_remaining),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TIME TO TAKE THIS ORDER',
                          style: TextStyle(
                            color: green,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text.rich(
                          TextSpan(
                            text: 'If it expires, the order is removed '
                                'from the book. ',
                            style: TextStyle(
                              color: textSec,
                              fontSize: 12,
                              height: 1.4,
                            ),
                            children: [
                              TextSpan(
                                text: "It won't affect your reputation.",
                                style: TextStyle(
                                  color: green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                  child: const Text('CLOSE'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 2,
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

/// One column of the 3-column creator-reputation block.
class _ReputationStat extends StatelessWidget {
  const _ReputationStat({
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: textSec, fontSize: 11)),
      ],
    );
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
