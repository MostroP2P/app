import 'dart:async';

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
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart'
    show formatInvoiceFiat, invoiceCounterpartRow;
import 'package:mostro/features/order/widgets/invoice_clock.dart';
import 'package:mostro/features/order/widgets/invoice_widgets.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show refreshTrades, tradeInfoProvider;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart'
    show OrderStatus, TradeInfo, TradeUpdate;
import 'package:mostro/shared/widgets/nwc_payment_widget.dart';
import 'package:mostro/shared/widgets/peer_reputation_card.dart';

/// 13b · Lock your sats — Route `/pay_invoice/:orderId`.
///
/// The seller pays the hold invoice that locks the sats in escrow. One screen
/// whether the seller took the order or someone took theirs. Mostro detects
/// the payment → the trade moves on and this screen leaves on its own.
class PayLightningInvoiceScreen extends ConsumerStatefulWidget {
  const PayLightningInvoiceScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<PayLightningInvoiceScreen> createState() =>
      _PayLightningInvoiceScreenState();
}

class _PayLightningInvoiceScreenState
    extends ConsumerState<PayLightningInvoiceScreen>
    with InvoiceClock {
  /// How long the copy icon stays a check.
  static const _copiedFeedback = Duration(milliseconds: 1200);

  bool _waiting = false;

  /// `true` while a protocol cancel is in flight — blocks re-entry.
  bool _canceling = false;

  /// `true` when NWC is connected but payment failed → show QR fallback.
  bool _manualMode = false;

  /// One-shot guard so we don't navigate twice as further statuses stream in.
  bool _navigated = false;

  /// No app answered the `lightning:` link: `Copy` becomes the primary
  /// action and the wallet link drops to a secondary one.
  bool _noWalletApp = false;

  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<int?>>(
      invoiceDeadlineProvider(widget.orderId),
      (_, next) => trackInvoiceDeadline(next.valueOrNull),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  /// NWC success callback: just show the spinner — the actual navigation is
  /// driven by the [tradeStatusProvider] listener below, which waits for
  /// mostrod to confirm the HTLC and flip the order status to Active.
  void _onPaymentDetected() {
    if (!mounted) return;
    setState(() => _waiting = true);
  }

  /// Cancel = cancel the trade itself (confirmed via dialog), not just leave
  /// the screen — going back is what lands on trade detail (#268).
  Future<void> _cancelOrder() async {
    // Serialize state-changing requests: one cancel at a time (review round 1).
    if (_canceling) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l10n.cancelTradeDialogTitle),
            // This screen only exists before the trade goes active, where
            // mostrod cancels at once — no cooperative request.
            content: Text(l10n.cancelTradeDialogContentNotStarted),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.cancelRequestSent)));
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

  Future<void> _openWallet(String invoice) async {
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse('lightning:$invoice'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    // No error: a device without a wallet app just gets `Copy` promoted.
    if (!launched && mounted) setState(() => _noWalletApp = true);
  }

  Future<void> _copy(String invoice) async {
    await Clipboard.setData(ClipboardData(text: invoice));
    if (!mounted) return;
    _copiedTimer?.cancel();
    setState(() {
      _copiedTimer = Timer(_copiedFeedback, () {
        if (mounted) setState(() => _copiedTimer = null);
      });
    });
  }

  Future<void> _share(String invoice) async {
    try {
      await SharePlus.instance.share(ShareParams(text: invoice));
    } catch (e, st) {
      debugPrint('[PayLightningInvoiceScreen] share failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).shareFailed)),
      );
    }
  }

  void _leaveHome(AppLocalizations l10n) {
    _navigated = true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.orderNoLongerActive)));
    context.go(AppRoute.home);
  }

  void _listenForProgress(AppLocalizations l10n) {
    // Listen to live status updates from mostrod. Once the hold invoice is
    // settled, mostrod broadcasts a BuyerTookOrder/HoldInvoicePaymentAccepted
    // message that the Rust handler writes as OrderStatus.active. We react
    // here because `tradeInfoStreamProvider` terminates as soon as the hold
    // invoice is delivered and does not observe later transitions.
    ref.listen<AsyncValue<OrderStatus>>(tradeStatusProvider(widget.orderId), (
      prev,
      next,
    ) {
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
          _leaveHome(l10n);
          break;
        default:
          break;
      }
    });

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
          refreshTrades(ref);
          _leaveHome(l10n);
        default:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);

    final isWalletConnected = ref.watch(isWalletConnectedProvider);
    final canPop = Navigator.of(context).canPop();
    final appBar = InvoiceAppBar(
      title: l10n.invoiceLockTitle,
      orderId: widget.orderId,
      orderIdAutomationId: AutomationIds.payOrderId,
      copiedMessage: l10n.invoiceOrderIdCopied,
      onBack: canPop ? () => Navigator.of(context).maybePop() : null,
    );
    final tradeAsync = ref.watch(tradeInfoStreamProvider(widget.orderId));

    // Counterpart (taker) reputation: the maker is the seller here (paying the
    // hold invoice), so the taker is the buyer (#305). Read via a separate
    // tradeInfoProvider rather than `tradeAsync`, because the polling stream
    // stops once the hold invoice arrives — which may be before the follow-up
    // Peer DM persists — and tradeInfoProvider refreshes on its TradeUpdate.
    final peerTrade = ref.watch(tradeInfoProvider(widget.orderId)).valueOrNull;

    _listenForProgress(l10n);

    return tradeAsync.when(
      loading:
          () => Scaffold(
            backgroundColor: book.bg,
            appBar: appBar,
            body: const Center(child: CircularProgressIndicator()),
          ),
      error: (e, st) {
        debugPrint('[PayLightningInvoiceScreen] load error: $e\n$st');
        return Scaffold(
          backgroundColor: book.bg,
          appBar: appBar,
          body: Center(child: Text(l10n.tradeLoadError)),
        );
      },
      data: (trade) {
        final invoice = trade?.holdInvoice ?? '';
        final amountSats = trade?.order.amountSats?.toInt() ?? 0;

        if (trade == null || invoice.isEmpty || amountSats <= 0) {
          // Hold invoice not yet available — waiting for Mostro daemon.
          return Scaffold(
            backgroundColor: book.bg,
            appBar: appBar,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: book.lime),
                  const SizedBox(height: 16),
                  Text(
                    l10n.tradeWaitingForHoldInvoice,
                    style: TextStyle(color: book.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        // If NWC wallet is connected and payment hasn't failed yet, show auto-pay.
        if (isWalletConnected && !_manualMode) {
          return Scaffold(
            backgroundColor: book.bg,
            appBar: appBar,
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
                        onFallbackToManual:
                            () => setState(() => _manualMode = true),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: book.bg,
          appBar: appBar,
          body: ValueListenableBuilder<Duration?>(
            valueListenable: invoiceRemaining,
            builder:
                (context, remaining, _) =>
                    remaining == Duration.zero && !_waiting
                        ? _expired(l10n)
                        : _payable(
                          l10n,
                          invoice: invoice,
                          amountSats: amountSats,
                          remaining: remaining,
                          peer: peerTrade ?? trade,
                        ),
          ),
        );
      },
    );
  }

  Widget _payable(
    AppLocalizations l10n, {
    required String invoice,
    required int amountSats,
    required Duration? remaining,
    required TradeInfo peer,
  }) {
    final fee = holdInvoiceFee(
      holdSats: amountSats,
      nodeFee: ref.watch(mostroNodeProvider).valueOrNull?.fee,
    );
    final fiat = formatInvoiceFiat(l10n, peer);
    final method = peer.order.paymentMethod.trim();

    return LayoutBuilder(
      builder:
          (context, constraints) => SingleChildScrollView(
            // #267: bottom system-bar inset so the footer clears the
            // gesture / 3-button navigation bar.
            padding: EdgeInsets.fromLTRB(
              kInvoiceGutter,
              4,
              kInvoiceGutter,
              kInvoiceGutter + MediaQuery.of(context).viewPadding.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 4 - kInvoiceGutter,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The amount and the QR share a card on purpose: a QR
                    // without its amount beside it invites paying unread.
                    InvoiceHeroCard(
                      label: l10n.invoiceToPayLabel,
                      sats: amountSats,
                      semanticsLabel: l10n.invoicePaySemantics(
                        amountSats.toString(),
                      ),
                      contextLine:
                          fee != null && fee > 0
                              ? l10n.invoiceFeeIncluded(formatInvoiceSats(fee))
                              : null,
                      // The invoice itself is only rendered as a QR, so the
                      // readout is what an automated driver can correlate
                      // the settlement against.
                      automationId: AutomationIds.payInvoiceText,
                      automationLabel: invoice,
                      child: _qr(l10n, invoice),
                    ),
                    if (remaining != null) ...[
                      const SizedBox(height: 11),
                      InvoiceTimeBand(
                        remaining: remaining,
                        sentence: l10n.invoiceExpiresIn,
                      ),
                    ],
                    const SizedBox(height: 11),
                    InvoiceHoldNote(
                      sentence: l10n.invoiceHoldNote,
                      boldWord: 'hold',
                    ),
                    const SizedBox(height: 11),
                    InvoiceCounterpartCard(
                      rows: [
                        invoiceCounterpartRow(
                          ref,
                          l10n,
                          peer,
                          l10n.invoiceBuyerLabel,
                        ),
                        if (fiat != null)
                          (
                            label: l10n.invoiceYouGetLabel,
                            value: method.isEmpty ? fiat : '$fiat · $method',
                            trailing: null,
                          ),
                      ],
                    ),
                    const Spacer(),
                    const SizedBox(height: 16),
                    ..._footer(l10n, invoice),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  /// 168 dp of code inside a 12 dp white quiet zone. The tight box also
  /// answers the page's intrinsic-height pass, which `QrImageView` (built on
  /// a `LayoutBuilder`) cannot.
  Widget _qr(AppLocalizations l10n, String invoice) => Center(
    child: SizedBox.square(
      dimension: 168 + 2 * 12,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: QrImageView(
          data: invoice,
          size: 168,
          padding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          semanticsLabel: l10n.invoiceQrSemantics(invoice),
        ),
      ),
    ),
  );

  List<Widget> _footer(AppLocalizations l10n, String invoice) {
    final book = OrderBookPalette.of(context);
    if (_waiting) {
      return [
        Center(child: CircularProgressIndicator(color: book.lime)),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.waitingForPaymentConfirmation,
          textAlign: TextAlign.center,
          style: TextStyle(color: book.textSecondary),
        ),
      ];
    }

    final copied = _copiedTimer != null;
    final copyIcon = copied ? Icons.check : Icons.copy;
    final share = InvoiceSecondaryButton(
      icon: Icons.share,
      label: l10n.shareButtonLabel,
      onPressed: () => _share(invoice),
    );

    return [
      if (_noWalletApp) ...[
        InvoicePrimaryButton(
          icon: copyIcon,
          label: l10n.copyButtonLabel,
          onPressed: () => _copy(invoice),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InvoiceSecondaryButton(
                icon: Icons.bolt,
                label: l10n.invoiceOpenWallet,
                onPressed: () => _openWallet(invoice),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: share),
          ],
        ),
      ] else ...[
        InvoicePrimaryButton(
          icon: Icons.bolt,
          label: l10n.invoiceOpenWallet,
          onPressed: () => _openWallet(invoice),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InvoiceSecondaryButton(
                icon: copyIcon,
                iconColor: copied ? book.lime : null,
                label: l10n.copyButtonLabel,
                onPressed: () => _copy(invoice),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: share),
          ],
        ),
      ],
      const SizedBox(height: 4),
      InvoiceCancelLink(
        label: l10n.invoiceCancelTrade,
        // Cancelling once the hold invoice exists has a consequence.
        danger: true,
        onPressed: _canceling ? null : _cancelOrder,
      ).withAutomationId(AutomationIds.payCancel),
    ];
  }

  /// Terminal state once the hold invoice ran out: the reason and a way
  /// back, never a dead QR left on screen.
  Widget _expired(AppLocalizations l10n) {
    final book = OrderBookPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        kInvoiceGutter,
        0,
        kInvoiceGutter,
        kInvoiceGutter + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Icon(Icons.timer_off_outlined, size: 40, color: book.textSecondary),
          const SizedBox(height: 16),
          Text(
            l10n.invoiceExpiredTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: book.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.invoiceExpiredBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: book.textSecondary,
            ),
          ),
          const Spacer(),
          InvoicePrimaryButton(
            icon: Icons.arrow_back,
            label: l10n.invoiceBackToBook,
            onPressed: () {
              _navigated = true;
              refreshTrades(ref);
              context.go(AppRoute.home);
            },
          ),
        ],
      ),
    );
  }
}
