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
import 'package:mostro/core/invoice_palette.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/models/bond_rules.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/widgets/bond_widgets.dart';
import 'package:mostro/features/order/widgets/invoice_clock.dart';
import 'package:mostro/features/order/widgets/invoice_widgets.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show refreshTrades, tradeInfoProvider;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/shared/widgets/nwc_payment_widget.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart'
    show BondInfo, OrderStatus, TradeInfo, TradeRole, TradeUpdate;

/// User docs the explainer links to; the same page About opens.
const _docsUrl = 'https://mostro.network/docs-english/';

/// 14 · Anti-abuse deposit — Route `/pay_bond/:orderId`.
///
/// The taker pays the bond hold invoice the daemon asks for before the trade
/// starts (`docs/ANTI_ABUSE_BOND.md` §6.1). 14a puts the amount first, the
/// three things that can happen to it, and the wallet as the primary action;
/// 14b is the same scroll with the long explanation open. Mostro detects the
/// payment and the trade moves on: the screen leaves on its own.
class PayBondInvoiceScreen extends ConsumerStatefulWidget {
  const PayBondInvoiceScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<PayBondInvoiceScreen> createState() =>
      _PayBondInvoiceScreenState();
}

class _PayBondInvoiceScreenState extends ConsumerState<PayBondInvoiceScreen>
    with InvoiceClock {
  static const _copiedFeedback = Duration(milliseconds: 1200);

  bool _waiting = false;
  bool _canceling = false;
  bool _requesting = false;
  bool _manualMode = false;
  bool _navigated = false;
  bool _noWalletApp = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  void _onPaymentDetected() {
    if (!mounted) return;
    setState(() => _waiting = true);
  }

  /// "Don't take the order": nothing is committed yet, so no confirmation —
  /// the daemon releases this taker's bond and the order stays in the book.
  Future<void> _cancel() async {
    if (_canceling) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _canceling = true);
    try {
      await orders_api.cancelOrder(orderId: widget.orderId);
      if (!mounted) return;
      _navigated = true;
      refreshTrades(ref);
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

  /// A row restored without its bolt11 (fresh device): the same-take
  /// re-request, which the daemon answers with the same invoice.
  Future<void> _requestAgain() async {
    if (_requesting) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _requesting = true);
    try {
      await ref.read(requestBondInvoiceAgainProvider)(widget.orderId);
      if (!mounted) return;
      refreshTrades(ref);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            localizedDaemonError(l10n, e, fallback: l10n.bondRequestFailed),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _requesting = false);
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
      debugPrint('[PayBondInvoiceScreen] share failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).shareFailed)),
      );
    }
  }

  Future<void> _openDocs() async {
    try {
      await launchUrl(
        Uri.parse(_docsUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('[PayBondInvoiceScreen] docs link failed: $e');
    }
  }

  /// What a `canceled` / `expired` during the bond window means, by the cause
  /// the core attached — never "taken by another user" when it cannot know.
  String? _cancelMessage(AppLocalizations l10n, TradeUpdate update) {
    if (update.status == OrderStatus.expired) return l10n.bondExpiredNotice;
    return switch (bondCancelCopy(update.reason)) {
      BondCancelCopy.lostRace => l10n.bondLostRace,
      BondCancelCopy.makerCanceled => l10n.bondMakerCanceled,
      BondCancelCopy.own => null,
      BondCancelCopy.neutral => l10n.orderNoLongerActive,
    };
  }

  void _listen(AppLocalizations l10n, TradeRole? role) {
    ref.listen<AsyncValue<TradeUpdate>>(tradeUpdatesProvider, (prev, next) {
      final update = next.valueOrNull;
      if (update == null || _navigated || !mounted) return;
      if (update.orderId != widget.orderId) return;
      switch (update.status) {
        case OrderStatus.waitingTakerBond:
        case OrderStatus.waitingMakerBond:
        case OrderStatus.pending:
        case OrderStatus.inProgress:
          break;
        case OrderStatus.canceled:
        case OrderStatus.cooperativelyCanceled:
        case OrderStatus.canceledByAdmin:
        case OrderStatus.expired:
          _navigated = true;
          refreshTrades(ref);
          final message = _cancelMessage(l10n, update);
          if (message != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          }
          context.go(AppRoute.home);
        // The bond locked and the trade flow started: hand over to the
        // step the daemon opened. A seller-as-taker locks the trade amount
        // next (two HTLCs, each approved by the user); a buyer adds their
        // invoice; anything further along is the trade screen.
        case OrderStatus.waitingPayment:
          _navigated = true;
          refreshTrades(ref);
          context.go(AppRoute.tradeDetailPath(widget.orderId));
          if (role == TradeRole.seller) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.bondLockedNowEscrow)));
            context.push(AppRoute.payInvoicePath(widget.orderId));
          }
        case OrderStatus.waitingBuyerInvoice:
          _navigated = true;
          refreshTrades(ref);
          context.go(AppRoute.tradeDetailPath(widget.orderId));
          if (role == TradeRole.buyer) {
            context.push(AppRoute.addInvoicePath(widget.orderId));
          }
        default:
          _navigated = true;
          refreshTrades(ref);
          context.go(AppRoute.tradeDetailPath(widget.orderId));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final tradeAsync = ref.watch(tradeInfoProvider(widget.orderId));
    final trade = tradeAsync.valueOrNull;
    final bond = trade?.bond;
    final expiresAt = bond?.expiresAt;
    trackInvoiceDeadline(
      expiresAt == null ? null : platformInt64ToInt(expiresAt),
    );
    _listen(l10n, trade?.role);

    final canPop = Navigator.of(context).canPop();
    final appBar = InvoiceAppBar(
      title: l10n.bondTitle,
      orderId: widget.orderId,
      orderIdAutomationId: AutomationIds.bondOrderId,
      copiedMessage: l10n.invoiceOrderIdCopied,
      onBack: canPop ? () => Navigator.of(context).maybePop() : null,
    );

    if (tradeAsync.isLoading && trade == null) {
      return Scaffold(
        backgroundColor: book.bg,
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (trade == null || bond == null) {
      return Scaffold(
        backgroundColor: book.bg,
        appBar: appBar,
        body: Center(child: Text(l10n.tradeLoadError)),
      );
    }

    final invoice = bond.invoice ?? '';
    final amountSats = bond.amountSats.toInt();
    if (invoice.isEmpty) return _missingInvoice(l10n, appBar);

    final isWalletConnected = ref.watch(isWalletConnectedProvider);
    if (isWalletConnected && !_manualMode) {
      return Scaffold(
        backgroundColor: book.bg,
        appBar: appBar,
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
                      trade: trade,
                      bond: bond,
                      invoice: invoice,
                      amountSats: amountSats,
                      remaining: remaining,
                    ),
      ),
    );
  }

  Widget _payable(
    AppLocalizations l10n, {
    required TradeInfo trade,
    required BondInfo bond,
    required String invoice,
    required int amountSats,
    required Duration? remaining,
  }) {
    final open = ref.watch(bondExplainerOpenProvider);
    final node = ref.watch(mostroNodeProvider).valueOrNull;
    final rate =
        ref.watch(exchangeRateProvider(trade.order.fiatCode)).valueOrNull;
    final fiat = bondFiatEquivalent(sats: amountSats, rate: rate);
    final fiatLine =
        fiat == null
            ? l10n.bondComesBack
            : l10n.bondFiatComesBack(
              formatBondFiat(l10n.localeName, fiat, trade.order.fiatCode),
            );
    // The timeout consequence is the node's policy; the dispute one always
    // applies (docs/ANTI_ABUSE_BOND.md §8.2).
    final slashOnTimeout = node?.bondSlashOnWaitingTimeout ?? false;

    return LayoutBuilder(
      builder:
          (context, constraints) => SingleChildScrollView(
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
                    if (open)
                      BondAmountRow(
                        label: l10n.bondRefundableLabel,
                        sats: amountSats,
                        remaining: remaining,
                        hours: l10n.invoiceCountdownHours,
                      )
                    else ...[
                      InvoiceHeroCard(
                        label: l10n.bondRefundableLabel,
                        sats: amountSats,
                        semanticsLabel: l10n.bondPaySemantics(
                          amountSats.toString(),
                        ),
                        contextLine: fiatLine,
                        automationId: AutomationIds.bondInvoiceText,
                        automationLabel: invoice,
                        child: _qr(l10n, invoice),
                      ),
                      if (remaining != null) ...[
                        const SizedBox(height: 11),
                        InvoiceTimeBand(
                          remaining: remaining,
                          sentence: l10n.bondReleasesIn,
                          hours: l10n.invoiceCountdownHours,
                        ),
                      ],
                      const SizedBox(height: 11),
                      BondConsequenceCard(
                        rows: _consequences(l10n, slashOnTimeout),
                      ),
                    ],
                    const SizedBox(height: 11),
                    BondExplainerToggle(
                      label: l10n.bondWhyTitle,
                      open: open,
                      onPressed:
                          () =>
                              ref
                                  .read(bondExplainerOpenProvider.notifier)
                                  .toggle(),
                    ).withAutomationId(AutomationIds.bondExplainer),
                    if (open) ...[
                      const SizedBox(height: 11),
                      BondExplainerBody(
                        paragraphs: _explainer(l10n, slashOnTimeout),
                        linkLabel: l10n.bondReadDocs,
                        onLink: _openDocs,
                      ),
                      const SizedBox(height: 11),
                      InvoiceCounterpartCard(
                        rows: _context(l10n, trade, node?.bondAmountPct),
                      ),
                    ],
                    const Spacer(),
                    const SizedBox(height: 16),
                    ..._footer(l10n, invoice, open: open),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  List<BondConsequence> _consequences(
    AppLocalizations l10n,
    bool slashOnTimeout,
  ) {
    final book = OrderBookPalette.of(context);
    final palette = InvoicePalette.of(context);
    return [
      BondConsequence(
        icon: Icons.lock_outline,
        color: palette.icon,
        sentence: l10n.bondRowHeld,
        boldPart: l10n.bondRowHeldBold,
      ),
      BondConsequence(
        icon: Icons.lock_open_outlined,
        color: book.lime,
        sentence: l10n.bondRowReleased,
        boldPart: l10n.bondRowReleasedBold,
      ),
      BondConsequence(
        icon: Icons.warning_amber_outlined,
        color: palette.cancelDanger,
        sentence: slashOnTimeout ? l10n.bondRowLostTimeout : l10n.bondRowLost,
        boldPart: l10n.bondRowLostBold,
      ),
    ];
  }

  List<InlineSpan> _explainer(AppLocalizations l10n, bool slashOnTimeout) {
    final bold = TextStyle(
      fontWeight: FontWeight.w600,
      color: OrderBookPalette.of(context).textPrimary,
    );
    final hold = l10n.bondWhyHold(' ').split(' ');
    return [
      TextSpan(text: l10n.bondWhyCustody),
      TextSpan(
        children: [
          TextSpan(text: hold.first),
          TextSpan(text: 'hold', style: bold),
          if (hold.length > 1) TextSpan(text: hold.last),
        ],
      ),
      TextSpan(
        text: slashOnTimeout ? l10n.bondWhyDisputeTimeout : l10n.bondWhyDispute,
      ),
    ];
  }

  List<InvoiceCardRow> _context(
    AppLocalizations l10n,
    TradeInfo trade,
    double? bondAmountPct,
  ) {
    final fiat = formatInvoiceFiat(l10n, trade);
    final buying = takerIsBuying(trade.order.kind);
    final share = bondSharePercent(bondAmountPct);
    return [
      if (fiat != null)
        (
          label: l10n.bondContextOrder,
          value:
              buying ? l10n.bondContextBuy(fiat) : l10n.bondContextSell(fiat),
          trailing: null,
        ),
      if (share != null)
        (
          label: l10n.bondContextEquals,
          value: l10n.bondContextPercent(share),
          trailing: null,
        ),
    ];
  }

  Widget _qr(AppLocalizations l10n, String invoice) => Center(
    child: SizedBox.square(
      dimension: 150 + 2 * 11,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: QrImageView(
          data: invoice,
          size: 150,
          padding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          semanticsLabel: l10n.invoiceQrSemantics(invoice),
        ),
      ),
    ),
  );

  List<Widget> _footer(
    AppLocalizations l10n,
    String invoice, {
    required bool open,
  }) {
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
    final secondaries = Row(
      children: [
        Expanded(
          child: InvoiceSecondaryButton(
            icon: _noWalletApp ? Icons.bolt : copyIcon,
            iconColor: !_noWalletApp && copied ? book.lime : null,
            label: _noWalletApp ? l10n.invoiceOpenWallet : l10n.copyButtonLabel,
            onPressed:
                _noWalletApp
                    ? () => _openWallet(invoice)
                    : () => _copy(invoice),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: InvoiceSecondaryButton(
            icon: Icons.share,
            label: l10n.shareButtonLabel,
            onPressed: () => _share(invoice),
          ),
        ),
      ],
    );
    return [
      // Without an app for `lightning:` links, `Copy` is the primary action
      // and the wallet link drops to a secondary one.
      if (_noWalletApp)
        InvoicePrimaryButton(
          icon: copyIcon,
          label: l10n.copyButtonLabel,
          onPressed: () => _copy(invoice),
        )
      else
        InvoicePrimaryButton(
          icon: Icons.bolt,
          label: l10n.invoiceOpenWallet,
          onPressed: () => _openWallet(invoice),
        ),
      // 14b hides copy / share: whoever is reading is not scanning.
      if (!open) ...[const SizedBox(height: 9), secondaries],
      const SizedBox(height: 4),
      InvoiceCancelLink(
        label: l10n.bondDontTake,
        // Nothing is committed yet: not a destructive action.
        danger: false,
        onPressed: _canceling ? null : _cancel,
      ).withAutomationId(AutomationIds.bondCancel),
    ];
  }

  /// A row without its bolt11: restored on a fresh device. The daemon
  /// answers a retake from the same key with the same invoice.
  Widget _missingInvoice(AppLocalizations l10n, PreferredSizeWidget appBar) {
    final book = OrderBookPalette.of(context);
    return Scaffold(
      backgroundColor: book.bg,
      appBar: appBar,
      body: Padding(
        padding: const EdgeInsets.all(kInvoiceGutter),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.bondInvoiceMissing,
              textAlign: TextAlign.center,
              style: TextStyle(color: book.textSecondary),
            ),
            const SizedBox(height: 16),
            InvoicePrimaryButton(
              icon: Icons.refresh,
              label: l10n.bondRequestAgain,
              busy: _requesting,
              onPressed: _requesting ? null : _requestAgain,
            ),
            const SizedBox(height: 4),
            InvoiceCancelLink(
              label: l10n.bondDontTake,
              danger: false,
              onPressed: _canceling ? null : _cancel,
            ),
          ],
        ),
      ),
    );
  }

  /// The bolt11 ran out unpaid: the order went back to the book (the core
  /// wipes the row); a way back, never a dead QR.
  Widget _expired(AppLocalizations l10n) => InvoiceTimeUpView(
    title: l10n.bondExpiredTitle,
    body: l10n.bondExpiredBody,
    actionLabel: l10n.invoiceBackToBook,
    onAction: () {
      _navigated = true;
      refreshTrades(ref);
      context.go(AppRoute.home);
    },
  );
}
