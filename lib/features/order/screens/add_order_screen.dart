import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/order/widgets/order_preset_selector.dart';
import 'package:mostro/features/order/widgets/payment_method_section.dart';
import 'package:mostro/features/order/widgets/price_section.dart';
import 'package:mostro/core/services/identity_service.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show refreshTrades;
import 'package:mostro/src/rust/api/identity.dart' as identity_api;
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
      final min = double.tryParse(_minController.text);
      final max = double.tryParse(_maxController.text);
      return min != null && max != null && min > 0 && min < max;
    } else {
      final amount = double.tryParse(_amountController.text);
      return amount != null && amount > 0;
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
        ref.read(premiumValueProvider.notifier).state =
            source.premium.clamp(-10.0, 10.0);
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
    if (_submitting || !_checkValid(selectedMethods, customMethod, isMarket, fixedSatsStr)) return;
    setState(() => _submitting = true);

    try {
      final fiatCode = ref.read(selectedFiatCodeProvider);
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

      // Persist the updated trade key index so it survives app restarts.
      // Failures here are non-fatal — the order was already created.
      try {
        final identity = await identity_api.getIdentity();
        if (identity != null) {
          await IdentityService.saveTradeKeyIndex(identity.tradeKeyIndex);
        }
      } catch (e) {
        debugPrint('[orders] save tradeKeyIndex failed: $e');
      }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
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
    final isValid = _checkValid(selectedMethods, customMethod, isMarket, fixedSatsStr);

    return Scaffold(
      appBar: AppBar(title: const Text('CREATING NEW ORDER')),
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
                  'You want to ${_isBuy ? 'buy' : 'sell'} Bitcoin',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.md),

                // Range toggle
                Row(
                  children: [
                    Text(
                      'Range order',
                      style: TextStyle(
                        color: colors?.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Switch(
                      value: _isRange,
                      activeThumbColor: green,
                      onChanged: (v) => setState(() => _isRange = v),
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
                            hintText: 'Min',
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
                            hintText: 'Max',
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
                      hintText: 'Fiat amount',
                      filled: true,
                      fillColor: inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
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
                  child: const Text('Cancel'),
                ),
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
                      : const Text('Submit'),
                ),
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
    final textPrimary = colors?.textPrimary ?? Colors.white;
    final secondary = colors?.textSecondary ?? Colors.grey;
    final subtle = colors?.textSubtle ?? Colors.grey;

    // Fiat side, mirroring _checkValid's rules.
    String? amountStr;
    if (_isRange) {
      final min = double.tryParse(_minController.text);
      final max = double.tryParse(_maxController.text);
      if (min != null && max != null && min > 0 && min < max) {
        amountStr = '${_formatNum(min)}–${_formatNum(max)} $fiatCode';
      }
    } else {
      final amount = double.tryParse(_amountController.text);
      if (amount != null && amount > 0) {
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
        'Enter an amount to see a live preview.',
        style: TextStyle(fontSize: 13, color: subtle),
      );
    } else {
      final bold = TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      );
      final spans = <TextSpan>[];
      if (sats != null) {
        spans
          ..add(TextSpan(text: _isBuy ? 'You receive ' : 'You sell '))
          ..add(TextSpan(
            text: '${_groupDigits(sats.toString())} sats',
            style: bold,
          ))
          ..add(const TextSpan(text: ' for '))
          ..add(TextSpan(text: amountStr, style: bold));
      } else {
        final priceLabel = premium == 0
            ? 'market price'
            : 'market ${premium > 0 ? '+' : ''}${_formatNum(premium)}%';
        spans
          ..add(TextSpan(text: _isBuy ? 'You buy BTC for ' : 'You sell BTC for '))
          ..add(TextSpan(text: amountStr, style: bold))
          ..add(const TextSpan(text: ' at '))
          ..add(TextSpan(text: priceLabel, style: bold));
      }
      spans
        ..add(const TextSpan(text: ' · live for '))
        ..add(TextSpan(text: '24 h', style: bold));

      body = Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 13, height: 1.5, color: secondary),
          children: spans,
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
            'PREVIEW',
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
