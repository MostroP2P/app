import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/widgets/order_preset_selector.dart';
import 'package:mostro/features/order/widgets/payment_method_section.dart';
import 'package:mostro/features/order/widgets/price_section.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show refreshTrades;
import 'package:mostro/shared/utils/order_amount_limits.dart';
import 'package:mostro/src/rust/api/orders.dart' as rust_orders;
import 'package:mostro/src/rust/api/types.dart';

/// Create order screen — Route `/add_order`.
///
/// 4 cards: order type + amount + currency, payment methods,
/// price type, premium slider. Bottom bar: Cancel + Submit.
class AddOrderScreen extends ConsumerStatefulWidget {
  const AddOrderScreen({super.key, this.orderType = 'sell'});

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
/// while the screen is building. Nothing filters the amount fields' input, so
/// a pasted value can be any of them.
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
  bool _isRange = false;
  bool _submitting = false;

  bool get _isBuy => widget.orderType == 'buy';

  @override
  void initState() {
    super.initState();
    // Reset form providers so each new screen starts fresh.
    Future.microtask(() {
      ref.read(selectedPaymentMethodsProvider.notifier).state = [];
      ref.read(customPaymentMethodProvider.notifier).state = '';
      final defaultFiat =
          ref.read(settingsProvider).defaultFiatCode ?? 'USD';
      ref.read(selectedFiatCodeProvider.notifier).state = defaultFiat;
      ref.read(isMarketPriceProvider.notifier).state = true;
      ref.read(isRangeOrderProvider.notifier).state = false;
      ref.read(premiumValueProvider.notifier).state = 0.0;
      ref.read(fixedSatsProvider.notifier).state = '';
      ref.read(selectedOrderPresetProvider.notifier).state =
          OrderPreset.custom;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  /// Toggles range mode. A range order can't carry a fixed sats price (Mostro
  /// prices it at market with a premium), so entering range mode forces Market
  /// and clears any fixed sats the user had typed. PriceSection watches
  /// [isRangeOrderProvider] to lock its toggle to Market while range is on.
  void _onRangeChanged(bool isRange) {
    setState(() => _isRange = isRange);
    ref.read(isRangeOrderProvider.notifier).state = isRange;
    if (isRange) {
      ref.read(isMarketPriceProvider.notifier).state = true;
      ref.read(fixedSatsProvider.notifier).state = '';
    }
  }

  /// [marketAmountsOutOfNodeRange] over whichever amount fields are in play.
  ({int minSats, int maxSats, FiatAmountLimits limits})? _fiatRangeError(
    MostroInstance? node,
    double? rate,
  ) =>
      marketAmountsOutOfNodeRange(
        _isRange
            ? [_minController.text, _maxController.text]
            : [_amountController.text],
        node?.minOrderAmount,
        node?.maxOrderAmount,
        rate,
      );

  /// The out-of-range warning to show under the price card, or null when the
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

  bool _checkValid(
    List<String> selectedMethods,
    String customMethod,
    bool isMarket,
    String fixedSatsStr,
  ) {
    final hasPayment = selectedMethods.isNotEmpty || customMethod.isNotEmpty;
    if (!hasPayment) return false;

    if (!isMarket) {
      final sats = BigInt.tryParse(fixedSatsStr);
      if (sats == null || sats <= BigInt.zero) return false;
    }

    if (_isRange) {
      final min = enteredAmount(_minController.text);
      final max = enteredAmount(_maxController.text);
      return min != null && max != null && min < max;
    } else {
      return enteredAmount(_amountController.text) != null;
    }
  }

  /// Prefills the form from the chosen preset. Presets are suggestions —
  /// the user can still review/edit everything before submitting.
  void _applyPreset(OrderPreset preset, OrderInfo? source) {
    ref.read(selectedOrderPresetProvider.notifier).state = preset;
    switch (preset) {
      case OrderPreset.express:
        if (source == null) return;
        final isRange =
            source.fiatAmountMin != null && source.fiatAmountMax != null;
        ref.read(isRangeOrderProvider.notifier).state = isRange;
        setState(() {
          _isRange = isRange;
          if (isRange) {
            _minController.text = _formatNum(source.fiatAmountMin!);
            _maxController.text = _formatNum(source.fiatAmountMax!);
            _amountController.clear();
          } else {
            _amountController.text = source.fiatAmount != null
                ? _formatNum(source.fiatAmount!)
                : '';
            _minController.clear();
            _maxController.clear();
          }
        });
        ref.read(selectedFiatCodeProvider.notifier).state = source.fiatCode;
        final methods = source.paymentMethod
            .split(',')
            .map((m) => m.trim())
            .where((m) => m.isNotEmpty)
            .toList();
        if (methods.isNotEmpty) {
          ref.read(selectedPaymentMethodsProvider.notifier).state = methods;
        }
        ref.read(isMarketPriceProvider.notifier).state = true;
        // Reuse the source order's premium as-is; it already passed validation.
        // Kept a whole percent to match the integer premium Mostro expects.
        ref.read(premiumValueProvider.notifier).state = source.premium
            .clamp(-kPremiumMaxMagnitude, kPremiumMaxMagnitude)
            .roundToDouble();
        ref.read(fixedSatsProvider.notifier).state = '';
      case OrderPreset.conservative:
        ref.read(isMarketPriceProvider.notifier).state = true;
        ref.read(premiumValueProvider.notifier).state = 0.0;
        ref.read(fixedSatsProvider.notifier).state = '';
      case OrderPreset.custom:
        // Full form as-is — nothing to prefill.
        break;
    }
  }

  static String _formatNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  /// "1234567" → "1,234,567" for sats display.
  static String _groupDigits(String s) {
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  Future<void> _submit() async {
    final selectedMethods = ref.read(selectedPaymentMethodsProvider);
    final customMethod = ref.read(customPaymentMethodProvider);
    final isMarket = ref.read(isMarketPriceProvider);
    final fixedSatsStr = ref.read(fixedSatsProvider);
    // Defence in depth: the submit button is already disabled when invalid or
    // out of the node's sats range, but re-check here so no code path submits
    // an out-of-range fixed-sats order (#282).
    final node = ref.read(mostroNodeProvider).valueOrNull;
    final fiatCode = ref.read(selectedFiatCodeProvider);
    final outOfRange = !isMarket && !_isRange && fixedSatsStr.isNotEmpty
        ? satsOutOfNodeRange(
            fixedSatsStr, node?.minOrderAmount, node?.maxOrderAmount)
        : null;
    final fiatOutOfRange = isMarket
        ? _fiatRangeError(
            node,
            ref.read(exchangeRateProvider(fiatCode)).valueOrNull,
          )
        : null;
    if (_submitting ||
        !_checkValid(selectedMethods, customMethod, isMarket, fixedSatsStr) ||
        outOfRange != null ||
        fiatOutOfRange != null) {
      return;
    }
    setState(() => _submitting = true);

    try {
      final isMarket = ref.read(isMarketPriceProvider);
      final premium = isMarket ? ref.read(premiumValueProvider) : 0.0;
      final fixedSatsStr = ref.read(fixedSatsProvider);

      // Sanitize and join payment methods (comma-separated, no special chars).
      final sanitized = customMethod
          .trim()
          .replaceAll(RegExp(r'[,"\\\[\]{}]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final allMethods = [
        ...selectedMethods,
        if (sanitized.isNotEmpty) sanitized,
      ];
      final paymentMethod = allMethods.join(',');

      final params = NewOrderParams(
        kind: _isBuy ? OrderKind.buy : OrderKind.sell,
        fiatAmount: _isRange ? null : double.tryParse(_amountController.text),
        fiatAmountMin:
            _isRange ? double.tryParse(_minController.text) : null,
        fiatAmountMax:
            _isRange ? double.tryParse(_maxController.text) : null,
        fiatCode: fiatCode,
        paymentMethod: paymentMethod,
        premium: premium,
        amountSats: (!isMarket && fixedSatsStr.isNotEmpty)
            ? BigInt.tryParse(fixedSatsStr)
            : null,
      );

      final order = await rust_orders.createOrder(params: params);

      refreshTrades(ref);

      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final inputBg = colors?.backgroundInput ?? const Color(0xFF252A3A);
    final selectedMethods = ref.watch(selectedPaymentMethodsProvider);
    final customMethod = ref.watch(customPaymentMethodProvider);
    final isMarket = ref.watch(isMarketPriceProvider);
    final fixedSatsStr = ref.watch(fixedSatsProvider);
    final fiatCode = ref.watch(selectedFiatCodeProvider);
    final premium = ref.watch(premiumValueProvider);
    final node = ref.watch(mostroNodeProvider).valueOrNull;
    final satsRangeError = (!isMarket && !_isRange && fixedSatsStr.isNotEmpty)
        ? satsOutOfNodeRange(
            fixedSatsStr, node?.minOrderAmount, node?.maxOrderAmount)
        : null;
    // Watched rather than read on submit, so the fetch is already in flight by
    // the time an amount is typed. Null while it is — and for good when the
    // node publishes no rate — which fails the check open (#337).
    final rate = isMarket
        ? ref.watch(exchangeRateProvider(fiatCode)).valueOrNull
        : null;
    final fiatRangeError = isMarket ? _fiatRangeError(node, rate) : null;
    final isValid =
        _checkValid(selectedMethods, customMethod, isMarket, fixedSatsStr) &&
            satsRangeError == null &&
            fiatRangeError == null;
    final l10n = AppLocalizations.of(context);
    final rangeWarning = _rangeWarning(
      l10n: l10n,
      satsRangeError: satsRangeError,
      fiatRangeError: fiatRangeError,
      fiatCode: fiatCode,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.creatingNewOrderTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Preset cards: Express / Conservative / Custom
          OrderPresetSelector(onSelect: _applyPreset),
          const SizedBox(height: AppSpacing.lg),

          // Card 1: Order type + amount + currency
          _Card(
            color: cardBg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isBuy ? l10n.youWantToBuyBitcoin : l10n.youWantToSellBitcoin,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.md),

                // Range toggle
                Row(
                  children: [
                    Text(
                      l10n.rangeOrderLabel,
                      style: TextStyle(
                        color: colors?.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Switch(
                      value: _isRange,
                      activeThumbColor: green,
                      onChanged: _onRangeChanged,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // Amount input(s)
                if (_isRange) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: l10n.minHint,
                            filled: true,
                            fillColor: inputBg,
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.input),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _maxController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: l10n.maxHint,
                            filled: true,
                            fillColor: inputBg,
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.input),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ] else
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: l10n.fiatAmountHint,
                      filled: true,
                      fillColor: inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ).withAutomationId(AutomationIds.orderCreateFiatAmount),
                const SizedBox(height: AppSpacing.md),

                // Currency selector
                const CurrencySection(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Card 2: Payment methods
          _Card(
            color: cardBg,
            child: const PaymentMethodSection(),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Card 3 + 4: Price type + premium
          _Card(
            color: cardBg,
            child: const PriceSection(),
          ),
          // Out-of-range warning, for fixed-sats (#282) and market-price
          // (#337) orders alike: show the node's accepted range so the user can
          // correct it before submitting, instead of the daemon rejecting the
          // order after the fact.
          if (rangeWarning != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                rangeWarning,
                style: TextStyle(
                  color: colors?.destructiveRed ?? const Color(0xFFD84D4D),
                  fontSize: 13,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),

      // Bottom bar: live preview + Cancel + Submit
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _previewFooter(
                colors: colors,
                cardBg: cardBg,
                isMarket: isMarket,
                fixedSatsStr: fixedSatsStr,
                fiatCode: fiatCode,
                premium: premium,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors?.textSecondary,
                    side: BorderSide(
                      color: colors?.textSecondary ?? Colors.grey,
                    ),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: Text(l10n.cancel),
                ).withAutomationId(AutomationIds.orderCreateCancel),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: isValid ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: green.withValues(alpha: 0.3),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.submitButton),
                ).withAutomationId(AutomationIds.orderCreateSubmit),
              ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Live preview footer — "You receive ≈ X sats for Y ARS · live for 24 h".
  ///
  /// A sats figure is only shown in Fixed price mode (where the user entered
  /// it); there is no exchange-rate source in the app for market-price
  /// estimates, so market mode shows the fiat side + premium only.
  Widget _previewFooter({
    required AppColors? colors,
    required Color cardBg,
    required bool isMarket,
    required String fixedSatsStr,
    required String fiatCode,
    required double premium,
  }) {
    final secondary = colors?.textSecondary ?? Colors.grey;
    final subtle = colors?.textSubtle ?? Colors.grey;
    final l10n = AppLocalizations.of(context);

    // Fiat side, mirroring _checkValid's rules.
    String? amountStr;
    if (_isRange) {
      final min = enteredAmount(_minController.text);
      final max = enteredAmount(_maxController.text);
      if (min != null && max != null && min < max) {
        amountStr = '${_formatNum(min)}–${_formatNum(max)} $fiatCode';
      }
    } else {
      final amount = enteredAmount(_amountController.text);
      if (amount != null) {
        amountStr = '${_formatNum(amount)} $fiatCode';
      }
    }

    // Exact sats are only known in Fixed price mode (user-entered).
    BigInt? sats;
    if (!isMarket) {
      final parsed = BigInt.tryParse(fixedSatsStr);
      if (parsed != null && parsed > BigInt.zero) sats = parsed;
    }

    Widget body;
    if (amountStr == null) {
      body = Text(
        l10n.enterAmountForPreview,
        style: TextStyle(fontSize: 13, color: subtle),
      );
    } else {
      final String sentence;
      if (sats != null) {
        final satsStr = _groupDigits(sats.toString());
        sentence = _isBuy
            ? l10n.previewReceiveFixed(satsStr, amountStr)
            : l10n.previewSellFixed(satsStr, amountStr);
      } else {
        final priceLabel = premium == 0
            ? l10n.marketPriceLabel
            : l10n.marketPricePremium(
                '${premium > 0 ? '+' : ''}${_formatNum(premium)}');
        sentence = _isBuy
            ? l10n.previewBuyMarket(amountStr, priceLabel)
            : l10n.previewSellMarket(amountStr, priceLabel);
      }
      // Emphasized fragments (amounts, price, duration) are wrapped in '*' in
      // the ARB; split on it and bold the odd-indexed segments.
      final base = TextStyle(fontSize: 13, height: 1.5, color: secondary);
      final bold = base.copyWith(
        fontWeight: FontWeight.w700,
        color: colors?.textPrimary ?? Colors.white,
      );
      final segments = sentence.split('*');
      body = Text.rich(
        TextSpan(
          style: base,
          children: [
            for (var i = 0; i < segments.length; i++)
              TextSpan(text: segments[i], style: i.isOdd ? bold : null),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: subtle.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.previewLabel,
            style: TextStyle(fontSize: 11, letterSpacing: 1, color: subtle),
          ),
          const SizedBox(height: AppSpacing.xs),
          body,
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: child,
    );
  }
}
