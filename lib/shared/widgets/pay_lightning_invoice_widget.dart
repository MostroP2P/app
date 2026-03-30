import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:mostro/core/app_theme.dart';

/// Manual pay invoice widget — QR code + copy + share.
///
/// Used on the pay_lightning_invoice_screen when NWC is not connected.
class PayLightningInvoiceWidget extends StatelessWidget {
  const PayLightningInvoiceWidget({
    super.key,
    required this.bolt11,
    required this.amountSats,
  });

  final String bolt11;
  final int amountSats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // QR Code
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: QrImageView(
            data: bolt11,
            size: 200,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        Text(
          '$amountSats sats',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.lg),

        // Copy + Share row
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: bolt11));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invoice copied'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  // TODO: Wire system share sheet via Share.share().
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share coming soon')),
                  );
                },
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Share'),
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
