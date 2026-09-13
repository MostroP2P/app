import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/core/order_detail_palette.dart';
import 'package:mostro/features/about/models/mostro_instance.dart' as instance;
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/widgets/order_list_item.dart'
    show OrderCardFormats;
import 'package:mostro/features/order/models/order_detail_rules.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/features/order/widgets/range_amount_modal.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show refreshTrades;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/src/rust/api/settings.dart' as settings_api;
import 'package:mostro/src/rust/api/types.dart';

/// What the single button is doing.
enum TakeOrderCta { idle, loading, unavailable }

/// Take-order screen (handoff 7a): someone else's order, seen by whoever
/// decides whether to take it.
///
/// Amount → counterparty → data → one action. The screen is a view of the
/// order in the book plus a countdown, the node's market rate for the sats
/// estimate, and the state of the button. If the relay retires the order
/// while the screen is open, the button dies in place; the user is never
/// thrown out with an error.
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
  static const _rateRefresh = Duration(seconds: 30);

  /// Drives only the app-bar countdown. A notifier rather than screen state:
  /// under an hour this ticks every second, and rebuilding the whole screen
  /// for it means re-running the entire order layout once a second.
  final ValueNotifier<Duration> _remaining = ValueNotifier(Duration.zero);
  Timer? _countdown;
  Timer? _rateTimer;
  TakeOrderCta _cta = TakeOrderCta.idle;

  /// The order as last seen in the book, kept so the screen can show it
  /// unavailable in place once the relay drops it.
  OrderItem? _lastOrder;
  double? _selectedAmount;

  @override
  void initState() {
    super.initState();
    // Defense in depth (#268): if the user already participates in this
    // order (deep link, stale book entry, back navigation), Take Order
    // must not offer to take it again — land on the trade instead.
    _redirectIfParticipant();
    _rateTimer = Timer.periodic(_rateRefresh, (_) {
      final code = _lastOrder?.fiatCode;
      if (code != null && mounted) ref.invalidate(exchangeRateProvider(code));
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _rateTimer?.cancel();
    _remaining.dispose();
    super.dispose();
  }

  Future<void> _redirectIfParticipant() async {
    final role = await ref.read(tradeRoleLookupProvider)(widget.orderId);
    if (!mounted || role == null) return;
    context.go(AppRoute.tradeDetailPath(widget.orderId));
  }

  /// (Re)starts the countdown for [order]. Repaints once a minute above an
  /// hour, once a second under it; at zero the button dies in place.
  void _syncCountdown(OrderItem order) {
    _countdown?.cancel();
    _countdown = null;
    final expiresAt = order.expiresAt;
    if (expiresAt == null) return;
    final left = expiresAt.difference(clock.now());
    if (left <= Duration.zero) {
      _remaining.value = Duration.zero;
      if (_cta != TakeOrderCta.unavailable) {
        setState(() => _cta = TakeOrderCta.unavailable);
      }
      return;
    }
    _remaining.value = left;
    _countdown = Timer(countdownTick(left), () {
      if (mounted) _syncCountdown(order);
    });
  }

  Future<void> _onTakeOrder() async {
    final order = _lastOrder;
    if (order == null || _cta != TakeOrderCta.idle) return;

    // Serialize with the async initState redirect: a participant racing the
    // role lookup must never dispatch a second take (which the daemon would
    // reject and strand them on home instead of their trade).
    final role = await ref.read(tradeRoleLookupProvider)(widget.orderId);
    if (!mounted) return;
    if (role != null) {
      context.go(AppRoute.tradeDetailPath(widget.orderId));
      return;
    }

    // Range orders: the amount is asked first.
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

    setState(() => _cta = TakeOrderCta.loading);
    try {
      final trade = await ref.read(takeOrderActionProvider)(
        orderId: widget.orderId,
        role: widget.isBuying ? TradeRole.buyer : TradeRole.seller,
        fiatAmount: _selectedAmount,
      );
      if (!mounted) return;

      // Bust the trades cache so My Trades picks up the newly saved trade.
      refreshTrades(ref);
      // Record the user's role so TradeDetailScreen can read it.
      ref
          .read(tradeRoleProvider.notifier)
          .update((map) => {...map, widget.orderId: widget.isBuying});

      // Straight to the Lightning step. The stack is rebuilt with the trade
      // detail as its base so back/close from the invoice screen lands on
      // the trade, never back here offering an already-taken order (#268).
      // The node asks for an anti-abuse bond first: the Lightning step of
      // the trade only opens once it locks (docs/ANTI_ABUSE_BOND.md §6.1).
      if (trade.order.status == OrderStatus.waitingTakerBond) {
        context.go(AppRoute.tradeDetailPath(widget.orderId));
        context.push(AppRoute.payBondPath(widget.orderId));
      } else if (widget.isBuying) {
        // With a default LN address Mostro pays it directly and the buyer
        // skips the add-invoice step.
        final settings = await settings_api.getSettings();
        if (!mounted) return;
        context.go(AppRoute.tradeDetailPath(widget.orderId));
        if (settings.defaultLightningAddress == null) {
          context.push(AppRoute.addInvoicePath(widget.orderId));
        }
      } else {
        context.go(AppRoute.tradeDetailPath(widget.orderId));
        context.push(AppRoute.payInvoicePath(widget.orderId));
      }
    } catch (e) {
      if (!mounted) return;
      _showTakeError(e);
    } finally {
      if (mounted && _cta == TakeOrderCta.loading) {
        setState(() => _cta = TakeOrderCta.idle);
      }
    }
  }

  /// takeOrder waits for the daemon's reply: an error here means the trade
  /// was NOT created (CantDo rejection, unsupported bond, timeout).
  void _showTakeError(Object e) {
    final l10n = AppLocalizations.of(context);
    final raw = e.toString();
    final anyhow = RegExp(r'^.*?AnyhowException\((.+)\)$').firstMatch(raw);
    final msg = anyhow != null ? anyhow.group(1)! : raw;
    if (msg.contains('OrderAlreadyTaken')) {
      // Someone else got there first: the button dies in place.
      setState(() => _cta = TakeOrderCta.unavailable);
      showOrderDetailSnackBar(context, l10n.orderAlreadyTaken);
      return;
    }
    // Every shared daemon marker (timeout, storage, node capability /
    // protocol) maps centrally.
    final display = localizedDaemonError(l10n, msg, fallback: msg);
    showOrderDetailSnackBar(context, display);
  }

  /// What this node will ask the taker to lock before the trade starts
  /// (docs/ANTI_ABUSE_BOND.md §8.1), or null when it asks nothing of takers.
  /// The figure is the core's estimate (`estimate_bond_sats`), sized on the
  /// order's sats when fixed or on the node's rate otherwise; without either
  /// the note still says a deposit is due, just without a figure.
  String? _bondNotice(AppLocalizations l10n, OrderItem order) {
    final node = ref.watch(mostroNodeProvider).valueOrNull;
    if (node == null || node.bondPolicy != instance.BondPolicy.enabled) {
      return null;
    }
    if (node.bondApplyTo != instance.BondApplyTo.take &&
        node.bondApplyTo != instance.BondApplyTo.both) {
      return null;
    }
    final sats =
        order.amountSats?.toInt() ??
        estimateSats(
          fiat: order.fiatAmount ?? order.fiatAmountMin ?? 0,
          rate: ref.watch(exchangeRateProvider(order.fiatCode)).valueOrNull,
          premium: order.premium,
        );
    final estimate =
        sats == null || sats <= 0
            ? null
            : ref.watch(bondEstimateProvider(sats)).valueOrNull;
    if (estimate == null) return l10n.takeOrderBondNotice;
    final formats = OrderCardFormats.of(
      Localizations.localeOf(context).toString(),
    );
    return l10n.takeOrderBondNoticeEstimate(formats.decimal.format(estimate));
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(orderByIdProvider(widget.orderId));
    // The same stream that updates the book marks the order unavailable:
    // once it leaves the pending book, or its status moves on, the button
    // dies in place instead of the screen being replaced by an error.
    ref.listen(orderByIdProvider(widget.orderId), (previous, next) {
      final gone = next == null || next.status != OrderStatus.pending;
      if (gone && _cta != TakeOrderCta.loading) {
        setState(() => _cta = TakeOrderCta.unavailable);
      } else if (next != null && next.expiresAt != previous?.expiresAt) {
        _syncCountdown(next);
      }
    });
    if (live != null && _lastOrder == null) {
      // First sight of the order: start the clock once the frame is built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncCountdown(live);
      });
    }
    if (live != null) _lastOrder = live;
    final order = live ?? _lastOrder;
    final l10n = AppLocalizations.of(context);

    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.orderNotFoundTitle)),
        body: Center(child: Text(l10n.orderNotFoundMessage)),
      );
    }

    final book = OrderBookPalette.of(context);
    final flags = ref.watch(currencyFlagsProvider);
    final privacyMode = ref.watch(privacyModeProvider);
    final isUnavailable =
        _cta == TakeOrderCta.unavailable ||
        live == null ||
        live.status != OrderStatus.pending;
    final cta = isUnavailable ? TakeOrderCta.unavailable : _cta;

    return Scaffold(
      backgroundColor: book.bg,
      appBar: orderDetailAppBar(
        context,
        title: widget.isBuying ? l10n.tabBuyBtc : l10n.tabSellBtc,
        onBack:
            () => context.canPop() ? context.pop() : context.go(AppRoute.home),
        trailing: ValueListenableBuilder<Duration>(
          valueListenable: _remaining,
          builder:
              (context, remaining, _) =>
                  _Countdown(remaining: remaining, isClosed: isUnavailable),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          orderDetailSidePadding,
          0,
          orderDetailSidePadding,
          24,
        ),
        children: [
          _AmountBlock(
            order: order,
            isBuying: widget.isBuying,
            flag: flags[order.fiatCode] ?? '',
          ),
          if (!privacyMode) ...[
            const SizedBox(height: orderDetailBlockGap),
            _CounterpartyCard(order: order),
          ],
          const SizedBox(height: orderDetailBlockGap),
          OrderDataCard(
            rows: [
              OrderPaymentMethodsRow(
                label:
                    widget.isBuying
                        ? l10n.takeOrderPayWithLabel
                        : l10n.takeOrderPaidWithLabel,
                paymentMethod: order.paymentMethod,
              ),
              OrderDataRow(
                icon: Icons.calendar_today_outlined,
                label: l10n.takeOrderPublishedLabel,
                value: OrderDataValue(orderRelativeTime(l10n, order.createdAt)),
              ),
              OrderIdRow(orderId: order.id),
            ],
          ),
        ],
      ),
      bottomNavigationBar: OrderDetailActionBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.shield_outlined,
                    size: 14,
                    color: book.textTertiary,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    [
                      widget.isBuying
                          ? l10n.takeOrderNoteBuyer
                          : l10n.takeOrderNoteSeller,
                      _bondNotice(l10n, order),
                    ].nonNulls.join(' '),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: book.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _TakeButton(state: cta, onPressed: _onTakeOrder),
          ],
        ),
      ),
    );
  }
}

// ── App bar countdown ─────────────────────────────────────────────────────────

/// Clock + time left; amber under an hour, coral under five minutes.
/// `Closed` once the order is gone, `Expired` once the clock ran out.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.remaining, required this.isClosed});

  final Duration remaining;
  final bool isClosed;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = OrderDetailPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final figures = TextStyle(
      fontFamily: AppFonts.figures,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: book.textTertiary,
    );
    if (isClosed) return Text(l10n.takeOrderClosed, style: figures);
    if (remaining <= Duration.zero) {
      return Text(l10n.orderStatusExpired, style: figures);
    }
    final color = switch (countdownTone(remaining)) {
      CountdownTone.calm => book.limeIcon,
      CountdownTone.warning => book.yellowInk,
      CountdownTone.urgent => pal.danger,
    };
    final text = formatRemaining(remaining);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule_rounded, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          text,
          semanticsLabel: l10n.timeRemainingLabel(text),
          style: figures.copyWith(color: color),
        ),
      ],
    );
  }
}

// ── Amount block ──────────────────────────────────────────────────────────────

/// `You pay 1,000 ARS` over `You receive ≈ 8,420 sats`, then the price
/// line. The `≈` is not decorative: until the order is taken the market
/// price keeps moving.
class _AmountBlock extends ConsumerWidget {
  const _AmountBlock({
    required this.order,
    required this.isBuying,
    required this.flag,
  });

  final OrderItem order;
  final bool isBuying;
  final String flag;

  static const _fade = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final formats = OrderCardFormats.of(
      Localizations.localeOf(context).toString(),
    );
    final label = TextStyle(fontSize: 11, color: book.textTertiary);
    // Watched so the estimate follows the node's rate; the screen refreshes
    // it every 30 s. Null while loading or when the node publishes none.
    final rate =
        order.hasFixedSats
            ? null
            : ref.watch(exchangeRateProvider(order.fiatCode)).valueOrNull;

    return OrderDetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isBuying ? l10n.takeOrderYouPay : l10n.takeOrderYouReceive,
                style: label,
              ),
              const Spacer(),
              OrderCurrencyChip(flag: flag, code: order.fiatCode),
            ],
          ),
          const SizedBox(height: 10),
          OrderAmountFigure(text: formats.amount(order)),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: book.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                isBuying ? l10n.takeOrderYouReceive : l10n.takeOrderYouSend,
                style: label,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AnimatedSwitcher(
                    duration: _fade,
                    child: Text(
                      _satsText(l10n, formats, rate),
                      key: ValueKey(rate),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontFamily: AppFonts.figures,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: book.limeInk,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _footer(l10n, formats, book),
        ],
      ),
    );
  }

  /// `≈ 8,420 sats`; `from ≈ 8,420 sats` on a range (priced on its
  /// minimum); the exact figure on a fixed-sats order; a dash without a rate.
  String _satsText(
    AppLocalizations l10n,
    OrderCardFormats formats,
    double? rate,
  ) {
    if (order.hasFixedSats) {
      return l10n.satsAmount(formats.decimal.format(order.amountSats!.toInt()));
    }
    final fiat = order.isRange ? order.fiatAmountMin! : order.fiatAmount!;
    final sats = estimateSats(fiat: fiat, rate: rate, premium: order.premium);
    if (sats == null) return '—';
    final figure = '≈ ${l10n.satsAmount(formats.decimal.format(sats))}';
    return order.isRange ? l10n.takeOrderSatsFrom(figure) : figure;
  }

  /// The premium is coloured from the taker's side, like the order-book
  /// card — the inverse of the maker's rule on the create-order form.
  Widget _footer(
    AppLocalizations l10n,
    OrderCardFormats formats,
    OrderBookPalette book,
  ) {
    final style = TextStyle(
      fontSize: 11,
      height: 1.5,
      color: book.textTertiary,
    );
    if (order.hasFixedSats) {
      final sats = l10n.satsAmount(
        formats.decimal.format(order.amountSats!.toInt()),
      );
      final sentence =
          order.kind == 'sell'
              ? l10n.takeOrderFixedFooterSeller(sats)
              : l10n.takeOrderFixedFooterBuyer(sats);
      return Text.rich(
        TextSpan(
          children: figureSpans(
            sentence,
            sats,
            TextStyle(
              fontFamily: AppFonts.figures,
              fontWeight: FontWeight.w600,
              color: book.limeInk,
            ),
          ),
        ),
        style: style,
      );
    }
    final figure = formats.premiumPercent(order.premium);
    final color = switch (takerPremiumFavour(
      kind: order.kind,
      premium: order.premium,
    )) {
      PremiumSide.good => book.limeText,
      PremiumSide.bad => book.yellowInk,
      PremiumSide.zero => book.textBody,
    };
    return Text.rich(
      TextSpan(
        children: figureSpans(
          l10n.takeOrderMarketFooter(figure),
          figure,
          TextStyle(
            fontFamily: AppFonts.figures,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
      style: style,
    );
  }
}

// ── Counterparty ──────────────────────────────────────────────────────────────

/// Who is on the other side: rating avatar, role, trades and seniority —
/// the same figures as the order-book card. Informational: the app has no
/// profile view to open.
class _CounterpartyCard extends StatelessWidget {
  const _CounterpartyCard({required this.order});

  final OrderItem order;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = OrderDetailPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final formats = OrderCardFormats.of(
      Localizations.localeOf(context).toString(),
    );
    final isNew = order.tradeCount == 0;
    final figure = TextStyle(color: book.textBody, fontWeight: FontWeight.w500);
    final trades = formats.decimal.format(order.tradeCount);
    final days = formats.decimal.format(order.daysActive);

    return OrderDetailCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isNew ? pal.avatarNewBg : pal.avatarBg,
              border: Border.all(
                color: isNew ? pal.avatarNewBorder : pal.avatarBorder,
              ),
            ),
            child:
                isNew
                    ? Text(
                      l10n.reputationNew,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: book.textNew,
                      ),
                    )
                    : Text(
                      formats.rating.format(order.rating),
                      style: TextStyle(
                        fontFamily: AppFonts.figures,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: book.limeInk,
                      ),
                    ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 12,
                      color: order.rating > 0 ? book.yellow : book.starEmpty,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      order.kind == 'sell'
                          ? l10n.counterpartySeller
                          : l10n.counterpartyBuyer,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: book.textStrong,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    children: [
                      if (isNew)
                        TextSpan(text: l10n.reputationNoTrades)
                      else
                        ...figureSpans(
                          l10n.counterpartyTrades(order.tradeCount),
                          trades,
                          figure,
                        ),
                      const TextSpan(text: ' · '),
                      ...figureSpans(
                        l10n.counterpartyDaysOnMostro(order.daysActive),
                        days,
                        figure,
                      ),
                    ],
                  ),
                  style: TextStyle(fontSize: 11, color: book.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Take button ───────────────────────────────────────────────────────────────

/// `Take order`; `Taking…` with a spinner while the relay answers; `No
/// longer available`, dead in place, once the order is gone.
class _TakeButton extends StatelessWidget {
  const _TakeButton({required this.state, required this.onPressed});

  final TakeOrderCta state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = OrderDetailPalette.of(context);
    final l10n = AppLocalizations.of(context);
    const textStyle = TextStyle(
      fontFamily: AppFonts.ui,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    );
    final Widget button = switch (state) {
      TakeOrderCta.idle => OrderPrimaryButton(
        label: l10n.takeOrderButton,
        onPressed: onPressed,
        verticalPadding: 15,
      ),
      TakeOrderCta.loading => Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: pal.ctaLoadingBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: book.lime,
                backgroundColor: pal.ctaLoadingRing,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              l10n.takeOrderTaking,
              style: textStyle.copyWith(color: pal.ctaLoadingInk),
            ),
          ],
        ),
      ),
      TakeOrderCta.unavailable => Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pal.ctaDeadBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.ctaDeadBorder),
        ),
        child: Text(
          l10n.takeOrderUnavailable,
          style: textStyle.copyWith(color: pal.ctaDeadInk),
        ),
      ),
    };
    return Semantics(
      button: true,
      enabled: state == TakeOrderCta.idle,
      child: button,
    ).withAutomationId(AutomationIds.orderTakeConfirm);
  }
}
