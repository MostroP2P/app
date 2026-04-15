import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;
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
  /// One-shot guard so we don't navigate twice as further statuses stream in.
  bool _navigated = false;

  /// NWC success callback: just show the spinner — the actual navigation is
  /// driven by the [tradeStatusProvider] listener below, which waits for
  /// mostrod to confirm the HTLC and flip the order status to Active.
  void _onPaymentDetected() {
    if (!mounted) return;
    setState(() => _waiting = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final l10n = AppLocalizations.of(context);

    final isWalletConnected = ref.watch(isWalletConnectedProvider);
    final tradeAsync = ref.watch(tradeInfoStreamProvider(widget.orderId));

    // Listen to live status updates from mostrod. Once the hold invoice is
    // settled, mostrod broadcasts a BuyerTookOrder/HoldInvoicePaymentAccepted
    // gift wrap that the Rust handler writes as OrderStatus.active. We react
    // here because `tradeInfoStreamProvider` terminates as soon as the hold
    // invoice is delivered and does not observe later transitions.
    ref.listen<AsyncValue<OrderStatus>>(
      tradeStatusProvider(widget.orderId),
      (prev, next) {
        final status = next.valueOrNull;
        if (status == null || _navigated || !mounted) return;
        switch (status) {
          case OrderStatus.active:
          case OrderStatus.fiatSent:
          case OrderStatus.settledHoldInvoice:
          case OrderStatus.success:
          case OrderStatus.dispute:
            _navigated = true;
            if (!_waiting) setState(() => _waiting = true);
            context.go(AppRoute.tradeDetailPath(widget.orderId));
            break;
          case OrderStatus.canceled:
          case OrderStatus.cooperativelyCanceled:
          case OrderStatus.canceledByAdmin:
          case OrderStatus.expired:
            _navigated = true;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.orderCancelledSuccess)),
            );
            context.go(AppRoute.home);
            break;
          default:
            break;
        }
      },
    );

    return tradeAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.payInvoiceScreenTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) {
        debugPrint('[PayLightningInvoiceScreen] load error: $e\n$st');
        return Scaffold(
          appBar: AppBar(title: Text(l10n.payInvoiceScreenTitle)),
          body: Center(
            child: Text(l10n.tradeLoadError),
          ),
        );
      },
      data: (trade) {
        final invoice = trade?.holdInvoice ?? '';
        final amountSats = trade?.order.amountSats?.toInt() ?? 0;

        if (invoice.isEmpty || amountSats <= 0) {
          // Hold invoice not yet available — waiting for Mostro daemon.
          return Scaffold(
            appBar: AppBar(title: Text(l10n.payInvoiceScreenTitle)),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: green),
                  const SizedBox(height: 16),
                  Text(
                    l10n.tradeWaitingForHoldInvoice,
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
            appBar: AppBar(title: Text(l10n.payInvoiceScreenTitle)),
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
          appBar: AppBar(title: Text(l10n.payInvoiceScreenTitle)),
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
                                l10n.payInvoiceInstruction,
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

                        // Pay with external Lightning wallet (lightning: URI)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () async {
                              final uri = Uri.parse('lightning:$invoice');
                              bool launched = false;
                              try {
                                launched = await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (_) {
                                launched = false;
                              }
                              if (!launched && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text(l10n.noLightningWalletFound),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.bolt, size: 18),
                            label: Text(l10n.payWithLightningWallet),
                            style: FilledButton.styleFrom(
                              backgroundColor: green,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.md,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.button),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),

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
                                    SnackBar(
                                      content: Text(l10n.invoiceCopied),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: Text(l10n.copyButtonLabel),
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
                                        content: Text(
                                          'Share failed: $e',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.share, size: 16),
                                label: Text(l10n.shareButtonLabel),
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
                        l10n.waitingForPaymentConfirmation,
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
                      child: Text(l10n.cancelButtonLabel),
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
