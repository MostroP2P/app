import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/shared/widgets/nwc_payment_widget.dart';

/// Pay Lightning Invoice screen — Route `/pay_invoice/:orderId`.
///
/// Shows a QR code for the hold invoice that the seller must pay.
/// Seller pays externally → Mostro detects payment → trade goes active.
class PayLightningInvoiceScreen extends ConsumerStatefulWidget {
  const PayLightningInvoiceScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<PayLightningInvoiceScreen> createState() =>
      _PayLightningInvoiceScreenState();
}

class _PayLightningInvoiceScreenState
    extends ConsumerState<PayLightningInvoiceScreen> {
  bool _waiting = false;
  /// `true` when NWC is connected but payment failed → show QR fallback.
  bool _manualMode = false;

  void _onPaymentDetected() {
    setState(() => _waiting = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      context.go(AppRoute.tradeDetailPath(widget.orderId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);

    final isWalletConnected = ref.watch(isWalletConnectedProvider);
    final tradeAsync = ref.watch(tradeInfoProvider(widget.orderId));

    return tradeAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Pay Lightning Invoice')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Pay Lightning Invoice')),
        body: Center(child: Text('Error loading trade: $e')),
      ),
      data: (trade) {
        final invoice = trade?.holdInvoice ?? '';
        final amountSats = trade?.order.amountSats?.toInt() ?? 0;

        if (invoice.isEmpty) {
          // Hold invoice not yet available — waiting for Mostro daemon.
          return Scaffold(
            appBar: AppBar(title: const Text('Pay Lightning Invoice')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: green),
                  const SizedBox(height: 16),
                  Text(
                    'Waiting for hold invoice...',
                    style: TextStyle(color: colors?.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        // If NWC wallet is connected and payment hasn't failed yet, show auto-pay.
        if (isWalletConnected && !_manualMode) {
          return Scaffold(
            appBar: AppBar(title: const Text('Pay Lightning Invoice')),
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: NwcPaymentWidget(
                  bolt11: invoice,
                  amountSats: amountSats,
                  onPaymentSuccess: _onPaymentDetected,
                  onFallbackToManual: () => setState(() => _manualMode = true),
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Pay Lightning Invoice')),
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                // Info card with QR
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.bolt, color: green, size: 24),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Pay this hold invoice to start the trade',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // QR Code
                        Expanded(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.card),
                              ),
                              child: QrImageView(
                                data: invoice,
                                size: 200,
                                backgroundColor: Colors.white,
                                semanticsLabel: 'Lightning invoice QR code',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Copy + Share buttons
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: invoice),
                                  );
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
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.button),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () async {
                                  try {
                                    await SharePlus.instance
                                        .share(ShareParams(text: invoice));
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Share failed: $e'),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.share, size: 16),
                                label: const Text('Share'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: green,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.button),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Waiting indicator or Cancel button
                if (_waiting)
                  Column(
                    children: [
                      CircularProgressIndicator(color: green),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Waiting for payment confirmation...',
                        style: TextStyle(color: colors?.textSecondary),
                      ),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => context.pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            colors?.destructiveRed ?? const Color(0xFFD84D4D),
                        side: BorderSide(
                          color:
                              colors?.destructiveRed ?? const Color(0xFFD84D4D),
                        ),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.button),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
