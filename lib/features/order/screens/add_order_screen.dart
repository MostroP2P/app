import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
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

      await rust_orders.createOrder(params: params);

      // Persist the updated trade key index so it survives app restarts.
      // Failures here are non-fatal — the order was already created.
      try {
        final identity = await identity_api.getIdentity();
        if (identity != null) {
          await IdentityService.saveTradeKeyIndex(identity.tradeKeyIndex);
        }
      } catch (_) {}

      refreshTrades(ref);

      if (!mounted) return;
      context.go(AppRoute.orderBook);
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
    final isValid = _checkValid(selectedMethods, customMethod, isMarket, fixedSatsStr);

    return Scaffold(
      appBar: AppBar(title: const Text('CREATING NEW ORDER')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
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

      // Bottom bar: Cancel + Submit
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
        ),
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
