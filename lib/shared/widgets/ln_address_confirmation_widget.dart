import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';

/// Confirmation widget for Lightning address payment.
///
/// Shows "Confirm: send sats to [address]" with Confirm + Change buttons.
/// Used when user has a default Lightning address and NWC is not configured.
class LnAddressConfirmationWidget extends StatelessWidget {
  const LnAddressConfirmationWidget({
    super.key,
    required this.address,
    required this.amountSats,
    required this.onConfirm,
    required this.onChange,
  });

  final String address;
  final int amountSats;
  final VoidCallback onConfirm;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, color: green, size: 24),
              const SizedBox(width: AppSpacing.sm),
              Text('Lightning Address', style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Send $amountSats sats to:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            address,
            style: (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
              fontFamily: 'monospace',
              color: green,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onChange,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors?.textSecondary,
                    side: BorderSide(
                      color: colors?.textSecondary ?? Colors.grey,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: const Text('Change'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: const Text('Confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
