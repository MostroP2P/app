import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show refreshTrades, tradeInfoProvider;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart' show OrderStatus, TradeUpdate;
import 'package:mostro/shared/widgets/nwc_payment_widget.dart';
import 'package:mostro/shared/widgets/peer_reputation_card.dart';

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
  /// `true` while a protocol cancel is in flight — blocks re-entry.
  bool _canceling = false;
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

  /// Cancel button = cancel the trade itself (confirmed via dialog), not
  /// just leave the screen — going back is what lands on trade detail (#268).
  Future<void> _cancelOrder() async {
    // Serialize state-changing requests: one cancel at a time (review round 1).
    if (_canceling) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cancelTradeDialogTitle),
        content: Text(l10n.cancelTradeDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.noButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.yesCancelButtonLabel),
          ).withAutomationId(AutomationIds.tradeCancelConfirm),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _canceling = true);
    try {
      await orders_api.cancelOrder(orderId: widget.orderId);
      if (!mounted) return;
      _navigated = true;
      refreshTrades(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cancelRequestSent)),
      );
      context.go(AppRoute.home);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localizedDaemonError(l10n, e, fallback: l10n.cancelRequestFailed),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _canceling = false);
    }
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

    // Counterpart (taker) reputation: the maker is the seller here (paying the
    // hold invoice), so the taker is the buyer (#305). Read via a separate
    // tradeInfoProvider rather than `tradeAsync`, because the polling stream
    // stops once the hold invoice arrives — which may be before the follow-up
    // Peer DM persists — and tradeInfoProvider refreshes on its TradeUpdate.
    final peerTrade = ref.watch(tradeInfoProvider(widget.orderId)).valueOrNull;

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
          // waitingBuyerInvoice: on this screen it can only mean the hold
          // invoice payment was registered and mostrod is now waiting for
          // the buyer's invoice — move the seller to the trade screen.
          case OrderStatus.waitingBuyerInvoice:
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
              SnackBar(content: Text(l10n.orderNoLongerActive)),
            );
            context.go(AppRoute.home);
            break;
          default:
            break;
        }
      },
    );

    // Push-based cancellation signal. The polling listener above cannot see
    // a daemon cancel anymore: the wiped trade has no DB row left, and after
    // a timeout republish the book reads `pending` — a status the switch
    // above deliberately ignores.
    ref.listen<AsyncValue<TradeUpdate>>(tradeUpdatesProvider, (prev, next) {
      final update = next.valueOrNull;
      if (update == null || _navigated || !mounted) return;
      if (update.orderId != widget.orderId) return;
      switch (update.status) {
        case OrderStatus.canceled:
        case OrderStatus.cooperativelyCanceled:
        case OrderStatus.canceledByAdmin:
        case OrderStatus.expired:
          _navigated = true;
          refreshTrades(ref);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.orderNoLongerActive)),
          );
          context.go(AppRoute.home);
        default:
          break;
      }
    });

    return tradeAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.payLightningInvoiceTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) {
        debugPrint('[PayLightningInvoiceScreen] load error: $e\n$st');
        return Scaffold(
          appBar: AppBar(title: Text(l10n.payLightningInvoiceTitle)),
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
            appBar: AppBar(title: Text(l10n.payLightningInvoiceTitle)),
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
            appBar: AppBar(title: Text(l10n.payLightningInvoiceTitle)),
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  // The seller must see who took their order even when NWC
                  // auto-pays the hold invoice — the app can settle without a
                  // manual step, so this is where the decision matters (#305).
                  if (peerTrade?.peerRating != null) ...[
                    PeerReputationCard(
                      rating: peerTrade!.peerRating!,
                      reviews: peerTrade.peerReviews ?? 0,
                      days: peerTrade.peerDays ?? 0,
                      counterpartIsBuyer: true,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  Expanded(
                    child: Center(
                      child: NwcPaymentWidget(
                        bolt11: invoice,
                        amountSats: amountSats,
                        onPaymentSuccess: _onPaymentDetected,
                        onFallbackToManual: () =>
                            setState(() => _manualMode = true),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text(l10n.payLightningInvoiceTitle)),
          body: Padding(
            // #267: bottom system-bar inset so the Cancel button clears the
            // gesture / 3-button navigation bar.
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg + MediaQuery.of(context).viewPadding.bottom,
            ),
            child: Column(
              children: [
                // Counterpart (taker) reputation — see `peerTrade` above.
                if (peerTrade?.peerRating != null) ...[
                  PeerReputationCard(
                    rating: peerTrade!.peerRating!,
                    reviews: peerTrade.peerReviews ?? 0,
                    days: peerTrade.peerDays ?? 0,
                    counterpartIsBuyer: true,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
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
                        // Sats amount of the hold invoice (from the daemon's
                        // pay-invoice reply, stored in the trade record).
                        const SizedBox(height: AppSpacing.md),
                        // The invoice itself is only rendered as a QR, so the
                        // readout is what an automated driver can correlate
                        // the settlement against.
                        Text(
                          l10n.payInvoiceAmount(amountSats.toString()),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: green,
                            fontWeight: FontWeight.bold,
                          ),
                        ).withAutomationId(
                          AutomationIds.payInvoiceText,
                          label: invoice,
                        ),
                        const SizedBox(height: AppSpacing.lg),

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
                                semanticsLabel: l10n.lightningInvoiceQrLabel,
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
                                  } catch (e, st) {
                                    debugPrint(
                                      '[PayLightningInvoiceScreen] share failed: $e\n$st',
                                    );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(l10n.shareFailed),
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
                      onPressed: _canceling ? null : _cancelOrder,
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
                      child: Text(l10n.cancel),
                    ).withAutomationId(AutomationIds.payCancel),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
