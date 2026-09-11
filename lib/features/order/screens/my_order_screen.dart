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
import 'package:mostro/core/order_detail_palette.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/widgets/order_list_item.dart'
    show OrderCardFormats;
import 'package:mostro/features/order/models/create_order_rules.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/widgets/my_order_status_block.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;

/// Detail screen for an order created by the current user (handoff 6a/6b).
///
/// Three blocks with a hierarchy — the amount, the status (the only coloured
/// block, with the countdown), the fixed data — over `Close` / `Cancel`.
/// The screen is a view of the order already in the store plus the status
/// block's own timer; nothing here polls beyond what the trade status
/// provider already does.
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
  OrderStatus? _lastHandledStatus;

  /// The countdown reached zero under a status the daemon has not yet
  /// updated: the order is treated as expired without waiting for the relay.
  bool _ranOut = false;

  Future<void> _onCancel() async {
    final confirmed = await _confirmCancel(context);
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      await orders_api.cancelOrder(orderId: widget.orderId);
      // Force the trades list to reload from DB so the Canceled status shows.
      ref.invalidate(rawTradesProvider);
      if (!mounted) return;
      showOrderDetailSnackBar(
        context,
        AppLocalizations.of(context).orderCancelledSuccess,
      );
      context.go(AppRoute.home);
    } catch (e, stackTrace) {
      debugPrint('[MyOrderScreen] cancel failed: $e\n$stackTrace');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showOrderDetailSnackBar(
        context,
        localizedDaemonError(l10n, e, fallback: l10n.cancelOrderFailed),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _close() =>
      context.canPop() ? context.pop() : context.go(AppRoute.home);

  /// Navigates to the trade once the order becomes one. Invoice requests
  /// are not navigated from here: the app-wide TradeActionListener pushes
  /// the add/pay-invoice screen for the actionable role no matter which
  /// screen is open, and the counterparty's copy of those statuses is
  /// informational. An order that expired or was cancelled before anyone
  /// took it never became a trade: it stays here, in its final state, with
  /// `Close` as the only way out (handoff 6b).
  void _followStatus(OrderStatus? liveStatus) {
    if (liveStatus == null ||
        liveStatus == OrderStatus.pending ||
        liveStatus == _lastHandledStatus) {
      return;
    }
    final shouldNavigate = switch (liveStatus) {
      OrderStatus.waitingBuyerInvoice ||
      OrderStatus.waitingPayment ||
      OrderStatus.expired ||
      OrderStatus.canceled ||
      OrderStatus.canceledByAdmin ||
      OrderStatus.cooperativelyCanceled => false,
      _ => true,
    };
    _lastHandledStatus = liveStatus;
    if (!shouldNavigate) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Re-read the latest status; between build() and this callback the
      // provider may have emitted a newer value, in which case the intended
      // navigation is stale and the next build handles the new state.
      final latest = ref.read(tradeStatusProvider(widget.orderId)).valueOrNull;
      if (latest != null && latest != liveStatus) {
        _lastHandledStatus = null;
        return;
      }
      context.go(AppRoute.tradeDetailPath(widget.orderId));
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch the live trade status FIRST — before any early return — so the
    // provider stays subscribed even when the order book temporarily drops
    // the order (Kind 38383 set_orders replaces the list with only pending
    // orders, removing taken ones).
    final liveStatus =
        ref.watch(tradeStatusProvider(widget.orderId)).valueOrNull;
    // A relay event that moves the order is the one thing on this screen
    // that changes on its own: a nudge, and the status block cross-fades.
    ref.listen(tradeStatusProvider(widget.orderId), (previous, next) {
      final before = previous?.valueOrNull;
      final after = next.valueOrNull;
      if (before != null && after != null && before != after) {
        HapticFeedback.mediumImpact();
      }
    });

    var order = ref.watch(orderByIdProvider(widget.orderId));
    // Fallback to the persisted trade DB when the order is no longer in the
    // in-memory order book (e.g. it was taken and moved out of pending).
    if (order == null) {
      final tradeInfo = ref.watch(tradeInfoProvider(widget.orderId));
      if (tradeInfo.valueOrNull?.order != null) {
        order = OrderItem.fromInfo(tradeInfo.value!.order);
      } else if (tradeInfo.isLoading) {
        return Scaffold(
          appBar: AppBar(title: const Text('')),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
    }
    final l10n = AppLocalizations.of(context);
    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.orderNotFoundTitle)),
        body: Center(child: Text(l10n.orderNotFoundMessage)),
      );
    }

    _followStatus(liveStatus);

    final book = OrderBookPalette.of(context);
    final resolved = liveStatus ?? order.status;
    final status =
        _ranOut && resolved == OrderStatus.pending
            ? OrderStatus.expired
            : resolved;
    final isSelling = order.kind == 'sell';
    final flags = ref.watch(currencyFlagsProvider);

    return Scaffold(
      backgroundColor: book.bg,
      appBar: orderDetailAppBar(
        context,
        title: isSelling ? l10n.myOrderSellTitle : l10n.myOrderBuyTitle,
        onBack: _close,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          orderDetailSidePadding,
          0,
          orderDetailSidePadding,
          24,
        ),
        children: [
          _AmountBlock(order: order, flag: flags[order.fiatCode] ?? ''),
          const SizedBox(height: orderDetailBlockGap),
          MyOrderStatusBlock(
            order: order,
            status: status,
            onRanOut: () => setState(() => _ranOut = true),
          ),
          const SizedBox(height: orderDetailBlockGap),
          OrderDataCard(
            rows: [
              OrderPaymentMethodsRow(
                label: l10n.paymentMethodLabel,
                paymentMethod: order.paymentMethod,
              ),
              OrderDataRow(
                icon: Icons.calendar_today_outlined,
                label: l10n.orderDetailCreatedLabel,
                value: OrderDataValue(_formatDate(context, order.createdAt)),
              ),
              OrderIdRow(orderId: order.id),
            ],
          ),
        ],
      ),
      bottomNavigationBar: OrderDetailActionBar(
        child: Row(
          children: [
            Expanded(
              flex: 14,
              // Creating an order lands here; this is the way back to the
              // order book, which is where a driver continues from.
              child: OrderPrimaryButton(
                label: l10n.closeButtonLabel,
                onPressed: _close,
              ).withAutomationId(AutomationIds.orderConfirmHome),
            ),
            if (canCancelOrder(status)) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 10,
                child: _CancelButton(
                  busy: _cancelling,
                  onPressed: _cancelling ? null : _onCancel,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// `11 Sep 2026, 17:41` in the locale's own order.
  String _formatDate(BuildContext context, DateTime dt) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMd(locale).add_Hm().format(dt);
  }
}

// ── Amount block ──────────────────────────────────────────────────────────────

/// Side chip and currency chip over the amount, then the price line. The
/// currency lives in the chip and is not repeated beside the figure.
class _AmountBlock extends StatelessWidget {
  const _AmountBlock({required this.order, required this.flag});

  final OrderItem order;
  final String flag;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = OrderDetailPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final formats = OrderCardFormats.of(
      Localizations.localeOf(context).toString(),
    );
    final isSelling = order.kind == 'sell';

    return OrderDetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SideChip(
                label:
                    isSelling ? l10n.orderSideChipSell : l10n.orderSideChipBuy,
                color: isSelling ? pal.sellInk : pal.buyInk,
                fill: isSelling ? pal.sellChipBg : pal.buyChipBg,
                border: isSelling ? pal.sellChipBorder : pal.buyChipBorder,
              ),
              const Spacer(),
              OrderCurrencyChip(flag: flag, code: order.fiatCode),
            ],
          ),
          const SizedBox(height: 10),
          OrderAmountFigure(text: formats.amount(order)),
          const SizedBox(height: 10),
          _priceLine(l10n, formats, book),
        ],
      ),
    );
  }

  /// `Market price · +2.0% premium`, the figure coloured by whom it favours
  /// from the maker's side (the same rule as the create-order form), or
  /// `Fixed amount · for 4,000 sats`.
  Widget _priceLine(
    AppLocalizations l10n,
    OrderCardFormats formats,
    OrderBookPalette book,
  ) {
    final style = TextStyle(fontSize: 12, color: book.textTertiary);
    final String sentence;
    final String figure;
    final Color figureColor;
    if (order.hasFixedSats) {
      figure = l10n.satsAmount(formats.decimal.format(order.amountSats!.toInt()));
      sentence = l10n.orderFixedAmount(figure);
      figureColor = book.limeInk;
    } else {
      figure = formats.premiumPercent(order.premium);
      sentence = l10n.orderDetailMarketPremium(figure);
      final side = order.kind == 'sell' ? OrderType.sell : OrderType.buy;
      figureColor = switch (premiumFavour(side, order.premium)) {
        PremiumFavour.good => book.limeText,
        PremiumFavour.bad => book.yellowInk,
        PremiumFavour.zero => book.textBody,
      };
    }
    return Text.rich(
      TextSpan(
        children: figureSpans(
          sentence,
          figure,
          TextStyle(
            fontFamily: AppFonts.figures,
            fontWeight: FontWeight.w600,
            color: figureColor,
          ),
        ),
      ),
      style: style,
    );
  }
}

/// `SELLING BTC` / `BUYING BTC` capsule.
class _SideChip extends StatelessWidget {
  const _SideChip({
    required this.label,
    required this.color,
    required this.fill,
    required this.border,
  });

  final String label;
  final Color color;
  final Color fill;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        semanticsLabel: label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}

// ── Cancel ────────────────────────────────────────────────────────────────────

/// Outlined coral `Cancel`; a spinner while the relay confirms.
class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final pal = OrderDetailPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: pal.danger,
        disabledForegroundColor: pal.danger,
        side: BorderSide(color: pal.dangerBorder),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      child:
          busy
              ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: pal.danger,
                ),
              )
              : Text(l10n.cancel),
    ).withAutomationId(AutomationIds.tradeCancel);
  }
}

/// The confirmation sheet: never cancel in a single tap.
Future<bool?> _confirmCancel(BuildContext context) {
  final book = OrderBookPalette.of(context);
  final pal = OrderDetailPalette.of(context);
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: book.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: pal.sheetHandle,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.cancelOrderSheetTitle,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: book.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.cancelOrderSheetBody,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: book.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: book.sell,
                  foregroundColor: book.onSell,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(l10n.yesCancelButtonLabel),
              ).withAutomationId(AutomationIds.tradeCancelConfirm),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: book.textSecondary,
                  textStyle: const TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: Text(l10n.goBackButtonLabel),
              ),
            ],
          ),
        ),
      );
    },
  );
}
