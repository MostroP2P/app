import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/models/create_order_rules.dart';
import 'package:mostro/features/order/models/order_detail_rules.dart'
    show estimateSats;
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/order_side_provider.dart';
import 'package:mostro/features/order/widgets/amount_section.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/features/order/widgets/order_preview_bar.dart';
import 'package:mostro/features/order/widgets/payment_method_section.dart';
import 'package:mostro/features/order/widgets/price_section.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show refreshTrades;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/order_amount_limits.dart';
import 'package:mostro/shared/widgets/pill_segmented.dart';
import 'package:mostro/src/rust/api/orders.dart' as rust_orders;
import 'package:mostro/src/rust/api/types.dart';

/// Create order screen — Route `/add_order`. Handoff 5a/5b/5c.
///
/// `Buy BTC | Sell BTC` control, then three cards — amount, payment methods,
/// price — over a pinned bar with the live preview and the actions. Always
/// the full form: there are no presets, the user decides every field.
class AddOrderScreen extends ConsumerStatefulWidget {
  const AddOrderScreen({super.key, this.orderType = 'sell'});

  /// `'buy'` or `'sell'`, from the order book's create button. Only seeds
  /// [orderSideProvider]; the side can be switched on the screen.
  final String orderType;

  @override
  ConsumerState<AddOrderScreen> createState() => _AddOrderScreenState();
}

/// Returns the node's accepted `(min, max)` sats range when the entered
/// fixed-sats amount is outside the node's advertised limits, otherwise null.
///
/// Pure and testable. Fixed-sats orders only (#282). Uses [BigInt] to match
/// `NewOrderParams.amountSats`, so amounts beyond the signed 64-bit range are
/// still compared rather than silently failing open. Only enforces the range
/// when the node advertises BOTH a min and a max (they are published together
/// in practice); when either bound is absent, or the amount is not yet a
/// number, returns null so a valid order is never blocked and the daemon
/// remains the backstop.
@visibleForTesting
({int min, int max})? satsOutOfNodeRange(
  String fixedSatsStr,
  int? minOrder,
  int? maxOrder,
) {
  if (minOrder == null || maxOrder == null) return null;
  final sats = BigInt.tryParse(fixedSatsStr.trim());
  if (sats == null) return null;
  if (sats < BigInt.from(minOrder) || sats > BigInt.from(maxOrder)) {
    return (min: minOrder, max: maxOrder);
  }
  return null;
}

/// The amount [text] holds, or null when it is not one the form can submit.
///
/// `Infinity`, `-Infinity` and `NaN` all parse as doubles and would pass a
/// bare positivity check, only to throw in the sats conversion further down —
/// while the screen is building. [text] is the canonical form
/// (`canonicalAmount`), never the grouped text of the field.
@visibleForTesting
double? enteredAmount(String text) {
  final value = double.tryParse(text.trim());
  if (value == null || !value.isFinite || value <= 0) return null;
  return value;
}

/// Returns the node's accepted `(min, max)` sats range, and that range in
/// fiat, when a market-price order's amount prices outside it, otherwise null.
///
/// Pure and testable, like [satsOutOfNodeRange] above, which is the fixed-sats
/// counterpart. Takes every amount the daemon will price — one for a
/// single-amount order, both ends for a range order — because the daemon
/// prices each of them and rejects the order if any one is out of range
/// (`mostro/src/app/order.rs`). Fails open on anything it cannot judge; see
/// [fiatOutOfNodeRange].
@visibleForTesting
({int minSats, int maxSats, FiatAmountLimits limits})?
    marketAmountsOutOfNodeRange(
  List<String> fiatAmounts,
  int? minOrder,
  int? maxOrder,
  double? rate,
) {
  for (final amount in fiatAmounts) {
    final error = fiatOutOfNodeRange(amount, minOrder, maxOrder, rate);
    if (error != null) return error;
  }
  return null;
}

class _AddOrderScreenState extends ConsumerState<AddOrderScreen> {
  final _amountController = TextEditingController();
  final _minController = TextEditingController();
  final _maxController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Reset form providers so each new screen starts fresh.
    Future.microtask(() {
      ref.read(orderSideProvider.notifier).state =
          widget.orderType == 'buy' ? OrderType.buy : OrderType.sell;
      ref.read(selectedPaymentMethodsProvider.notifier).state = [];
      ref.read(customPaymentMethodsProvider.notifier).state = [];
      final defaultFiat =
          ref.read(settingsProvider).defaultFiatCode ?? 'USD';
      ref.read(selectedFiatCodeProvider.notifier).state = defaultFiat;
      ref.read(isMarketPriceProvider.notifier).state = true;
      ref.read(isRangeOrderProvider.notifier).state = false;
      ref.read(premiumValueProvider.notifier).state = 0.0;
      ref.read(fixedSatsProvider.notifier).state = '';
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  // ── Locale-aware amounts ──────────────────────────────────────────────────

  AmountSymbols _symbols(BuildContext context) {
    final symbols = NumberFormat.decimalPattern(_locale(context)).symbols;
    return (group: symbols.GROUP_SEP, decimal: symbols.DECIMAL_SEP);
  }

  String _locale(BuildContext context) =>
      Localizations.localeOf(context).toString();

  String? _canonical(String text, AmountSymbols symbols) => canonicalAmount(
        text,
        groupSeparator: symbols.group,
        decimalSeparator: symbols.decimal,
      );

  /// Toggles range mode, keeping the figure the user already typed: the
  /// single amount becomes the minimum and vice versa. The maximum is cleared
  /// on the way back to single so a later return to range cannot resurrect a
  /// bound from an earlier attempt. A range order can't carry a fixed sats
  /// price (Mostro prices it at market with a premium), so entering range
  /// mode forces Market and clears any fixed sats.
  void _onRangeChanged(bool isRange) {
    if (isRange == ref.read(isRangeOrderProvider)) return;
    setState(() {
      if (isRange) {
        _minController.text = _amountController.text;
      } else {
        _amountController.text = _minController.text;
        _maxController.clear();
      }
    });
    ref.read(isRangeOrderProvider.notifier).state = isRange;
    if (isRange) {
      ref.read(isMarketPriceProvider.notifier).state = true;
      ref.read(fixedSatsProvider.notifier).state = '';
    }
  }

  // ── Validation ────────────────────────────────────────────────────────────

  /// Canonical amount strings in play: `[amount]` or `[min, max]`.
  List<String?> _amounts(bool isRange, AmountSymbols symbols) => isRange
      ? [
          _canonical(_minController.text, symbols),
          _canonical(_maxController.text, symbols),
        ]
      : [_canonical(_amountController.text, symbols)];

  /// The deposit notice with the core's estimate when the order's sats can
  /// be told — fixed sats, or the fiat at the node's rate; a range is sized
  /// on its maximum, as the daemon does (docs/ANTI_ABUSE_BOND.md §2.8) — and
  /// without a figure otherwise. An estimate only: the daemon sends the bolt11.
  String _bondNotice(
    AppLocalizations l10n, {
    required String locale,
    required bool isMarket,
    required String fixedSatsStr,
    required List<String?> amounts,
    required double? rate,
    required double premium,
  }) {
    final sats = !isMarket && fixedSatsStr.isNotEmpty
        ? int.tryParse(fixedSatsStr)
        : estimateSats(
            fiat: double.tryParse(amounts.last ?? '') ?? 0,
            rate: rate,
            premium: isMarket ? premium : 0,
          );
    final estimate = sats == null || sats <= 0
        ? null
        : ref.watch(bondEstimateProvider(sats)).valueOrNull;
    if (estimate == null) return l10n.createOrderBondNotice;
    return l10n.createOrderBondNoticeEstimate(
      NumberFormat.decimalPattern(locale).format(estimate),
    );
  }

  /// [marketAmountsOutOfNodeRange] over whichever amount fields are in play.
  ({int minSats, int maxSats, FiatAmountLimits limits})? _fiatRangeError(
    MostroInstance? node,
    double? rate,
    List<String?> amounts,
  ) =>
      marketAmountsOutOfNodeRange(
        amounts.whereType<String>().toList(),
        node?.minOrderAmount,
        node?.maxOrderAmount,
        rate,
      );

  /// The out-of-range message to show in the preview bar, or null when the
  /// entered amount is fine — or cannot be checked at all, in which case the
  /// daemon stays the only authority.
  String? _rangeWarning({
    required AppLocalizations l10n,
    required ({int min, int max})? satsRangeError,
    required ({int minSats, int maxSats, FiatAmountLimits limits})?
        fiatRangeError,
    required String fiatCode,
  }) {
    if (satsRangeError != null) {
      return l10n.orderAmountOutOfRange(satsRangeError.min, satsRangeError.max);
    }
    if (fiatRangeError == null) return null;
    // The sats bounds mean nothing to most users, so a market-price range is
    // shown in the currency they typed in. Sats are the fallback for when the
    // whole valid range is under one fiat unit, leaving no enterable whole
    // number to name.
    final limits = fiatRangeError.limits;
    return limits.isDisplayable
        ? l10n.orderAmountOutOfRangeFiat(
            limits.minFiat,
            limits.maxFiat,
            fiatCode,
          )
        : l10n.orderAmountOutOfRange(
            fiatRangeError.minSats,
            fiatRangeError.maxSats,
          );
  }

  bool _amountsValid(bool isRange, List<String?> amounts) {
    if (isRange) {
      final min = amounts[0] == null ? null : enteredAmount(amounts[0]!);
      final max = amounts[1] == null ? null : enteredAmount(amounts[1]!);
      return min != null && max != null && min < max;
    }
    return amounts[0] != null && enteredAmount(amounts[0]!) != null;
  }

  bool _checkValid({
    required List<String> methods,
    required bool isMarket,
    required String fixedSatsStr,
    required bool isRange,
    required List<String?> amounts,
  }) {
    if (methods.isEmpty) return false;
    if (!isMarket) {
      final sats = BigInt.tryParse(fixedSatsStr);
      if (sats == null || sats <= BigInt.zero) return false;
    }
    return _amountsValid(isRange, amounts);
  }

  // ── Preview ───────────────────────────────────────────────────────────────

  /// The preview sentence, or null while there is no valid amount.
  List<PreviewFragment>? _preview({
    required AppLocalizations l10n,
    required String locale,
    required OrderType side,
    required bool isRange,
    required List<String?> amounts,
    required String fiatCode,
    required bool isMarket,
    required double premium,
    required String fixedSatsStr,
    required int? expirationHours,
  }) {
    if (!_amountsValid(isRange, amounts)) return null;
    final fiat = NumberFormat('#,##0.##', locale);
    final amountText = isRange
        ? '${fiat.format(double.parse(amounts[0]!))} – '
            '${fiat.format(double.parse(amounts[1]!))} $fiatCode'
        : '${fiat.format(double.parse(amounts[0]!))} $fiatCode';
    final amount = markPreview(amountText, PreviewRole.amount);
    final active = expirationHours == null
        ? ''
        : l10n.previewActiveSuffix(
            markPreview(l10n.durationHours(expirationHours), PreviewRole.duration),
          );
    final isSell = side == OrderType.sell;

    final String sentence;
    if (!isMarket) {
      final sats = BigInt.tryParse(fixedSatsStr);
      if (sats == null || sats <= BigInt.zero) return null;
      final satsText = markPreview(
        l10n.satsAmount(NumberFormat.decimalPattern(locale).format(sats.toInt())),
        PreviewRole.sats,
      );
      sentence = isSell
          ? l10n.previewSellFixed(satsText, amount, active)
          : l10n.previewBuyFixed(satsText, amount, active);
    } else if (premium.round() == 0) {
      sentence = isSell
          ? l10n.previewSellMarketExact(amount, active)
          : l10n.previewBuyMarketExact(amount, active);
    } else {
      final premiumText = markPreview(formatPremium(premium), PreviewRole.premium);
      sentence = isSell
          ? l10n.previewSellMarket(amount, premiumText, active)
          : l10n.previewBuyMarket(amount, premiumText, active);
    }
    return previewFragments(sentence);
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final symbols = _symbols(context);
    final methods = ref.read(allPaymentMethodsProvider);
    final isMarket = ref.read(isMarketPriceProvider);
    final isRange = ref.read(isRangeOrderProvider);
    final fixedSatsStr = ref.read(fixedSatsProvider);
    final amounts = _amounts(isRange, symbols);
    // Defence in depth: the submit button is already disabled when invalid or
    // out of the node's sats range, but re-check here so no code path submits
    // an out-of-range fixed-sats order (#282).
    final node = ref.read(mostroNodeProvider).valueOrNull;
    final fiatCode = ref.read(selectedFiatCodeProvider);
    final outOfRange = !isMarket && !isRange && fixedSatsStr.isNotEmpty
        ? satsOutOfNodeRange(
            fixedSatsStr, node?.minOrderAmount, node?.maxOrderAmount)
        : null;
    final fiatOutOfRange = isMarket
        ? _fiatRangeError(
            node,
            ref.read(exchangeRateProvider(fiatCode)).valueOrNull,
            amounts,
          )
        : null;
    final valid = _checkValid(
      methods: methods,
      isMarket: isMarket,
      fixedSatsStr: fixedSatsStr,
      isRange: isRange,
      amounts: amounts,
    );
    if (_submitting || !valid || outOfRange != null || fiatOutOfRange != null) {
      return;
    }
    setState(() => _submitting = true);

    try {
      final premium = isMarket ? ref.read(premiumValueProvider) : 0.0;
      final side = ref.read(orderSideProvider);

      final params = NewOrderParams(
        kind: side == OrderType.buy ? OrderKind.buy : OrderKind.sell,
        fiatAmount: isRange ? null : double.tryParse(amounts[0]!),
        fiatAmountMin: isRange ? double.tryParse(amounts[0]!) : null,
        fiatAmountMax: isRange ? double.tryParse(amounts[1]!) : null,
        fiatCode: fiatCode,
        paymentMethod: methods.join(','),
        premium: premium,
        amountSats: (!isMarket && fixedSatsStr.isNotEmpty)
            ? BigInt.tryParse(fixedSatsStr)
            : null,
      );

      final order = await rust_orders.createOrder(params: params);

      refreshTrades(ref);

      if (!mounted) return;
      // A bond node parks the order behind the maker's deposit: it is not
      // published until the bond is paid (docs/ANTI_ABUSE_BOND.md §6.2).
      if (order.status == OrderStatus.waitingMakerBond) {
        context.go(AppRoute.payBondPath(order.id));
        return;
      }
      context.go(AppRoute.myOrderPath(order.id));
    } catch (e) {
      if (!mounted) return;
      // CantDo rejections from Mostro arrive as errors from createOrder.
      // Strip the Rust error prefix for a cleaner message.
      final raw = e.toString();
      final anyhowMatch = RegExp(r'^.*?AnyhowException\((.+)\)$').firstMatch(raw);
      final msg = anyhowMatch != null ? anyhowMatch.group(1)! : raw;
      // The daemon never answered: show the localized "no response" message
      // instead of the raw marker. The order was not created.
      final display =
          localizedDaemonError(AppLocalizations.of(context), msg, fallback: msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(display)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final create = CreateOrderPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = _locale(context);
    final symbols = _symbols(context);

    final side = ref.watch(orderSideProvider);
    final methods = ref.watch(allPaymentMethodsProvider);
    final isMarket = ref.watch(isMarketPriceProvider);
    final isRange = ref.watch(isRangeOrderProvider);
    final fixedSatsStr = ref.watch(fixedSatsProvider);
    final fiatCode = ref.watch(selectedFiatCodeProvider);
    final premium = ref.watch(premiumValueProvider);
    final node = ref.watch(mostroNodeProvider).valueOrNull;
    final amounts = _amounts(isRange, symbols);

    final satsRangeError = (!isMarket && !isRange && fixedSatsStr.isNotEmpty)
        ? satsOutOfNodeRange(
            fixedSatsStr, node?.minOrderAmount, node?.maxOrderAmount)
        : null;
    // Watched rather than read on submit, so the fetch is already in flight by
    // the time an amount is typed. Null while it is — and for good when the
    // node publishes no rate — which fails the check open (#337).
    final rate = ref.watch(exchangeRateProvider(fiatCode)).valueOrNull;
    final fiatRangeError =
        isMarket ? _fiatRangeError(node, rate, amounts) : null;
    // The quick chips approximate 10/25/50/100 USD in the chosen currency.
    // Both rates are BTC prices, so their ratio is the currency's USD rate.
    final usdRate = ref.watch(exchangeRateProvider('USD')).valueOrNull;
    final fiatPerUsd = rate != null && usdRate != null && usdRate > 0
        ? rate / usdRate
        : null;

    final isValid = _checkValid(
          methods: methods,
          isMarket: isMarket,
          fixedSatsStr: fixedSatsStr,
          isRange: isRange,
          amounts: amounts,
        ) &&
        satsRangeError == null &&
        fiatRangeError == null;
    final rangeWarning = _rangeWarning(
      l10n: l10n,
      satsRangeError: satsRangeError,
      fiatRangeError: fiatRangeError,
      fiatCode: fiatCode,
    );
    // A node that bonds makers asks for a deposit before publishing
    // (docs/ANTI_ABUSE_BOND.md §6.2): said here, before the tap.
    final bondNotice = makerBondApplies(
          policy: node?.bondPolicy,
          applyTo: node?.bondApplyTo,
        )
        ? _bondNotice(
            l10n,
            locale: locale,
            isMarket: isMarket,
            fixedSatsStr: fixedSatsStr,
            amounts: amounts,
            rate: rate,
            premium: premium,
          )
        : null;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, size: 22, color: palette.textBody),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Text(
          l10n.newOrderTitle,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: palette.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          PillSegmented<OrderType>(
            selected: side,
            segments: [
              PillSegment(
                value: OrderType.buy,
                label: l10n.tabBuyBtc,
                automationId: AutomationIds.orderCreateSideBuy,
              ),
              PillSegment(
                value: OrderType.sell,
                label: l10n.tabSellBtc,
                automationId: AutomationIds.orderCreateSideSell,
              ),
            ],
            activeStyleOf: (value) => value == OrderType.sell
                ? PillActiveStyle(
                    fill: create.sellActiveBg,
                    border: create.sellActiveBorder,
                    ink: create.sellInk,
                  )
                : PillActiveStyle(
                    fill: palette.tabActiveFill,
                    border: palette.tabActiveBorder,
                    ink: palette.limeInk,
                  ),
            onSelected: (value) =>
                ref.read(orderSideProvider.notifier).state = value,
          ),
          const SizedBox(height: 14),
          _Card(
            child: AmountSection(
              amountController: _amountController,
              minController: _minController,
              maxController: _maxController,
              symbols: symbols,
              fiatFormat: NumberFormat('#,##0.##', locale),
              quickAmounts: quickAmounts(fiatPerUsd),
              hasError: fiatRangeError != null,
              onChanged: () => setState(() {}),
              onRangeChanged: _onRangeChanged,
            ),
          ),
          const SizedBox(height: 12),
          const _Card(child: PaymentMethodSection()),
          const SizedBox(height: 12),
          const _Card(child: PriceSection()),
        ],
      ),
      // Pinned: rises with the keyboard so the preview stays in view.
      bottomNavigationBar: OrderPreviewBar(
        fragments: rangeWarning == null
            ? _preview(
                l10n: l10n,
                locale: locale,
                side: side,
                isRange: isRange,
                amounts: amounts,
                fiatCode: fiatCode,
                isMarket: isMarket,
                premium: premium,
                fixedSatsStr: fixedSatsStr,
                expirationHours: node?.expirationHours,
              )
            : null,
        error: rangeWarning,
        notice: bondNotice,
        premiumFavour: premiumFavour(side, premium),
        canSubmit: isValid,
        isSubmitting: _submitting,
        onCancel: () => context.pop(),
        onSubmit: _submit,
      ),
    );
  }
}

/// Section card: padding 14, radius 18, hairline border.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}
