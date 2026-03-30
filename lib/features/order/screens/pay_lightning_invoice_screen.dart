import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';

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
  // Mock invoice — will come from Mostro daemon response.
  final _mockInvoice =
      'lnbc1500n1pj9nr7mpp5xz80dm6k5tqasn3nyh3e6fqzmtqpy0xf5h9m7y0yr5'
      'n4dqwk4esdqqcqzzsxqyz5vqsp5usyc4lg3dxp3skyhw5e8vy5w6v7kw6mxhf'
      'jyzpnpryz4jns7qs9qyyssqjrvz0waerp2g3kx6k2neqfmfp2sxlm0n3m';

  bool _waiting = false;

  void _simulatePaymentDetected() {
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
                            data: _mockInvoice,
                            size: 200,
                            backgroundColor: Colors.white,
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
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _mockInvoice),
                              );
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
                            onPressed: () {
                              // TODO: Wire system share sheet.
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Share coming soon'),
                                ),
                              );
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

            // Hidden dev button to simulate payment (TODO: remove when wired)
            if (!_waiting)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: TextButton(
                  onPressed: _simulatePaymentDetected,
                  child: Text(
                    'Simulate payment (dev)',
                    style: TextStyle(
                      color: colors?.textSubtle,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
