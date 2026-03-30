import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';

/// Whether Market or Fixed price mode is selected.
final isMarketPriceProvider = StateProvider<bool>((_) => true);

/// Premium slider value (-10% to +10%).
final premiumValueProvider = StateProvider<double>((_) => 0.0);

/// Fixed sats amount (only used in Fixed price mode).
final fixedSatsProvider = StateProvider<String>((_) => '');

/// Price type toggle + premium/fixed sats input.
class PriceSection extends ConsumerStatefulWidget {
  const PriceSection({super.key});

  @override
  ConsumerState<PriceSection> createState() => _PriceSectionState();
}

class _PriceSectionState extends ConsumerState<PriceSection> {
  late final TextEditingController _premiumController;
  bool _editingPremium = false;

  @override
  void initState() {
    super.initState();
    _premiumController = TextEditingController(
      text: ref.read(premiumValueProvider).toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _premiumController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final purple = colors?.purpleButton ?? const Color(0xFF8359C2);
    final inputBg = colors?.backgroundInput ?? const Color(0xFF252A3A);
    final isMarket = ref.watch(isMarketPriceProvider);
    final premium = ref.watch(premiumValueProvider);

    // Sync controller when slider changes (but not while user is editing).
    if (!_editingPremium) {
      final newText = premium.toStringAsFixed(1);
      if (_premiumController.text != newText) {
        _premiumController.text = newText;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with toggle
        Row(
          children: [
            Text('Price Type', style: theme.textTheme.labelLarge),
            const Spacer(),
            Text(
              isMarket ? 'Market' : 'Fixed',
              style: TextStyle(
                color: colors?.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Switch(
              value: isMarket,
              activeThumbColor: green,
              onChanged: (v) =>
                  ref.read(isMarketPriceProvider.notifier).state = v,
            ),
            IconButton(
              onPressed: () => _showPriceInfo(context),
              icon: const Icon(Icons.info_outline, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Price type info',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        if (isMarket) ...[
          // Premium slider with editable field
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: purple.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Premium',
                      style: TextStyle(
                        color: purple,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 60,
                          child: TextField(
                            controller: _premiumController,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: purple,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs,
                              ),
                              filled: true,
                              fillColor: purple.withValues(alpha: 0.1),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.chip),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onTap: () => _editingPremium = true,
                            onSubmitted: (v) {
                              _editingPremium = false;
                              final parsed = double.tryParse(v);
                              if (parsed != null) {
                                ref.read(premiumValueProvider.notifier).state =
                                    parsed.clamp(-10.0, 10.0);
                              }
                            },
                            onTapOutside: (_) {
                              _editingPremium = false;
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '%',
                          style: TextStyle(
                            color: purple,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Icon(Icons.edit, size: 14, color: purple),
                      ],
                    ),
                  ],
                ),
                Slider(
                  value: premium,
                  min: -10,
                  max: 10,
                  divisions: 40,
                  activeColor: purple,
                  label: '${premium >= 0 ? '+' : ''}${premium.toStringAsFixed(1)}%',
                  onChanged: (v) =>
                      ref.read(premiumValueProvider.notifier).state = v,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '-10%',
                      style: TextStyle(
                        color: colors?.textSubtle,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '+10%',
                      style: TextStyle(
                        color: colors?.textSubtle,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ] else ...[
          // Fixed sats input
          TextField(
            decoration: InputDecoration(
              hintText: 'Amount in sats',
              filled: true,
              fillColor: inputBg,
              suffixText: 'sats',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: BorderSide.none,
              ),
            ),
            keyboardType: TextInputType.number,
            style: theme.textTheme.bodyLarge,
            onChanged: (v) =>
                ref.read(fixedSatsProvider.notifier).state = v,
          ),
        ],
      ],
    );
  }

  void _showPriceInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Price Types'),
        content: const Text(
          'Market Price: Your order price follows the market rate with '
          'a premium/discount percentage applied.\n\n'
          'Fixed Price: You set an exact price in satoshis.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
