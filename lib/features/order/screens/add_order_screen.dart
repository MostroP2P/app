import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/features/order/widgets/payment_method_section.dart';
import 'package:mostro/features/order/widgets/price_section.dart';

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
  void dispose() {
    _amountController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  bool _checkValid(List<String> selectedMethods, String customMethod) {
    final hasPayment = selectedMethods.isNotEmpty || customMethod.isNotEmpty;
    if (!hasPayment) return false;

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
    if (_submitting || !_checkValid(selectedMethods, customMethod)) return;
    setState(() => _submitting = true);

    try {
      // TODO (Phase 7): Call create_order() via Rust bridge.
      // For now, simulate a short delay and navigate to My Trades.
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;

      // Navigate to My Trades tab (order book / trades screen).
      context.go(AppRoute.orderBook);
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
    final isValid = _checkValid(selectedMethods, customMethod);

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
