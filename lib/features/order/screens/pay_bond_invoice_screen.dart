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
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;
import 'package:mostro/shared/widgets/nwc_payment_widget.dart';

/// Pay anti-abuse bond screen — Route `/pay_bond_invoice/:orderId`.
///
/// Shown when a taker takes an order on a bond-requiring node: the order sits
/// at [OrderStatus.waitingTakerBond] with the bond bolt11 in the trade's
/// `bondInvoice` slot. Once the daemon confirms the bond payment, this screen
/// forwards the taker to the next step (add-invoice for a buyer, pay-invoice
/// for a seller, else trade detail), mirroring [PayLightningInvoiceScreen].
class PayBondInvoiceScreen extends ConsumerStatefulWidget {
  const PayBondInvoiceScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<PayBondInvoiceScreen> createState() =>
      _PayBondInvoiceScreenState();
}

/// How far the bond payment has got, which decides whether cancelling and
/// leaving are safe.
enum _PaymentPhase {
  /// Nothing dispatched yet — the bond is certainly unpaid.
  idle,

  /// A payment was launched (external wallet, invoice copied or shared, NWC in
  /// flight) and the Lightning outcome is unknown, so cancelling could race a
  /// bond that is settling or already settled.
  launched,

  /// The wallet reported success; waiting for the daemon to advance the order.
  confirming,
}

/// What the taker chose when backing out of the bond screen.
enum _LeaveChoice { keepPaying, leave, release }

class _PayBondInvoiceScreenState extends ConsumerState<PayBondInvoiceScreen> {
  _PaymentPhase _phase = _PaymentPhase.idle;

  /// `true` when NWC is connected but payment failed → show QR fallback.
  bool _manualMode = false;

  /// One-shot guard so we don't navigate twice as further statuses stream in.
  bool _navigated = false;

  bool get _outcomeUnknown => _phase != _PaymentPhase.idle;

  /// Marks the payment as dispatched. Called at initiation — not on success —
  /// so a bond that is settling can never be cancelled from under the daemon.
  void _onPaymentLaunched() {
    if (!mounted || _phase != _PaymentPhase.idle) return;
    setState(() => _phase = _PaymentPhase.launched);
  }

  /// NWC success callback: just show the spinner — the actual navigation is
  /// driven by the [tradeStatusProvider] listener below, which waits for the
  /// daemon to confirm the bond HTLC and advance the order.
  void _onPaymentDetected() {
    if (!mounted) return;
    setState(() => _phase = _PaymentPhase.confirming);
  }

  /// Recovery path when the launched payment never happened (wallet dismissed,
  /// invoice copied but not paid), returning the screen to a cancellable state.
  void _onNotPaidYet() {
    if (!mounted) return;
    setState(() => _phase = _PaymentPhase.idle);
  }

  /// Back out of the take while the bond is unpaid. Sends a real cancel so the
  /// daemon releases the bond (no slash) and returns the order to the book —
  /// unlike a bare pop, which would strand the order at WaitingTakerBond.
  Future<void> _confirmAndCancel() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cancelTradeDialogTitle),
        content: Text(l10n.cancelBondBackoutDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.noButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.yesCancelButtonLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _releaseOrder();
  }

  Future<void> _releaseOrder() async {
    final l10n = AppLocalizations.of(context);
    try {
      await orders_api.cancelOrder(orderId: widget.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.orderCancelledSuccess)),
      );
      context.go(AppRoute.home);
    } catch (e, st) {
      debugPrint('[PayBondInvoiceScreen] cancelOrder error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.cancelRequestFailed)),
      );
    }
  }

  /// Single back handler for every branch. Leaving is always allowed — it sends
  /// nothing and the trade stays in My Trades — but releasing the order is only
  /// offered while the bond is certainly unpaid, so it can never race a bond
  /// that is settling.
  Future<void> _handleBackIntent() async {
    final l10n = AppLocalizations.of(context);
    if (_outcomeUnknown) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.leaveBondPaymentTitle),
          content: Text(l10n.leaveBondPaymentWaitingContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.keepWaitingButton),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.leaveButton),
            ),
          ],
        ),
      );
      if (leave == true && mounted) context.pop();
      return;
    }
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.leaveBondPaymentTitle),
        content: Text(l10n.leaveBondPaymentContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _LeaveChoice.keepPaying),
            child: Text(l10n.keepPayingButton),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _LeaveChoice.leave),
            child: Text(l10n.leaveButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _LeaveChoice.release),
            child: Text(l10n.releaseOrderButton),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case null:
      case _LeaveChoice.keepPaying:
        return;
      case _LeaveChoice.leave:
        context.pop();
      case _LeaveChoice.release:
        await _releaseOrder();
    }
  }

  Widget _waitingIndicator(AppColors? colors, Color green,
          AppLocalizations l10n) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: green),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.waitingForPaymentConfirmation,
            style: TextStyle(color: colors?.textSecondary),
          ),
        ],
      );

  /// Bottom slot shared by the NWC and manual branches: destructive cancel only
  /// while the bond is certainly unpaid, and never a dead end — every waiting
  /// phase offers a way out in case the daemon never confirms.
  Widget _footer(AppColors? colors, Color green, AppLocalizations l10n) =>
      switch (_phase) {
        _PaymentPhase.idle => _cancelButton(colors, l10n),
        _PaymentPhase.launched => _waitingWithEscape(
            colors,
            green,
            l10n,
            label: l10n.bondPaymentNotPaidYet,
            onPressed: _onNotPaidYet,
          ),
        // The wallet reported success, so "not paid yet" no longer applies: the
        // escape is leaving the screen, which sends nothing.
        _PaymentPhase.confirming => _waitingWithEscape(
            colors,
            green,
            l10n,
            label: l10n.leaveButton,
            onPressed: _handleBackIntent,
          ),
      };

  Widget _waitingWithEscape(
    AppColors? colors,
    Color green,
    AppLocalizations l10n, {
    required String label,
    required VoidCallback onPressed,
  }) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _waitingIndicator(colors, green, l10n),
          TextButton(onPressed: onPressed, child: Text(label)),
        ],
      );

  Widget _cancelButton(AppColors? colors, AppLocalizations l10n) {
    final red = colors?.destructiveRed ?? const Color(0xFFD84D4D);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _confirmAndCancel,
        style: OutlinedButton.styleFrom(
          foregroundColor: red,
          side: BorderSide(color: red),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
        child: Text(l10n.cancel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final l10n = AppLocalizations.of(context);

    final isWalletConnected = ref.watch(isWalletConnectedProvider);
    final tradeAsync = ref.watch(tradeBondInfoProvider(widget.orderId));

    // Forward the taker to the matching next step once the bond is paid;
    // stay put while the order is still at waitingTakerBond/pending.
    ref.listen<AsyncValue<OrderStatus>>(
      tradeStatusProvider(widget.orderId),
      (prev, next) {
        final status = next.valueOrNull;
        if (status == null || _navigated || !mounted) return;
        switch (status) {
          case OrderStatus.waitingTakerBond:
          case OrderStatus.pending:
            break;
          case OrderStatus.waitingBuyerInvoice: // buyer taker
            _navigated = true;
            context.pushReplacement(AppRoute.addInvoicePath(widget.orderId));
            break;
          case OrderStatus.waitingPayment: // seller taker
            _navigated = true;
            context.pushReplacement(AppRoute.payInvoicePath(widget.orderId));
            break;
          // Already progressed past the invoice step.
          case OrderStatus.active:
          case OrderStatus.fiatSent:
          case OrderStatus.inProgress:
          case OrderStatus.settledHoldInvoice:
          case OrderStatus.success:
          case OrderStatus.dispute:
            _navigated = true;
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

    // Every branch below renders its own AppBar, so the back handling lives
    // here: no branch can pop without going through the policy.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBackIntent();
      },
      child: tradeAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.payBondInvoiceTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) {
        debugPrint('[PayBondInvoiceScreen] load error: $e\n$st');
        return Scaffold(
          appBar: AppBar(title: Text(l10n.payBondInvoiceTitle)),
          body: Center(child: Text(l10n.tradeLoadError)),
        );
      },
      data: (trade) {
        final invoice = trade?.bondInvoice ?? '';
        final amountSats = trade?.bondAmountSats?.toInt() ?? 0;

        if (invoice.isEmpty) {
          // Bond invoice not yet available — waiting for the Mostro daemon.
          return Scaffold(
            appBar: AppBar(title: Text(l10n.payBondInvoiceTitle)),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: green),
                  const SizedBox(height: 16),
                  Text(
                    l10n.tradeWaitingForBondInvoice,
                    style: TextStyle(color: colors?.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        // NWC wallet connected and payment hasn't failed yet: pay from it.
        if (isWalletConnected && !_manualMode) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.payBondInvoiceTitle)),
            body: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  const Spacer(),
                  if (_phase == _PaymentPhase.idle)
                    NwcPaymentWidget(
                      bolt11: invoice,
                      amountSats: amountSats,
                      onPaymentStarted: _onPaymentLaunched,
                      onPaymentSuccess: _onPaymentDetected,
                      onFallbackToManual: () => setState(() {
                        _manualMode = true;
                        _phase = _PaymentPhase.idle;
                      }),
                    ),
                  const Spacer(),
                  _footer(colors, green, l10n),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: Text(l10n.payBondInvoiceTitle)),
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
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
                            Icon(Icons.shield_outlined, color: green, size: 24),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                l10n.payBondInvoiceInstruction,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                        if (amountSats > 0) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            l10n.payInvoiceAmount(amountSats.toString()),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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
                                semanticsLabel: l10n.bondInvoiceQrLabel,
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
                              if (launched) {
                                _onPaymentLaunched();
                              } else if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l10n.noLightningWalletFound),
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
                                  _onPaymentLaunched();
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
                                    _onPaymentLaunched();
                                  } catch (e, st) {
                                    debugPrint(
                                      '[PayBondInvoiceScreen] share failed: $e\n$st',
                                    );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(l10n.shareFailed)),
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

                _footer(colors, green, l10n),
              ],
            ),
          ),
        );
      },
      ),
    );
  }
}
