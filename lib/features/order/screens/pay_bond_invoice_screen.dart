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
  bool _sweptExpired = false;
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

  /// Walk away: nothing is committed yet, so no confirmation. A taker
  /// cancels — the daemon releases the bond and the order stays in the book.
  /// A maker abandons — the daemon refuses a cancel during its bond window
  /// (docs/ANTI_ABUSE_BOND.md §6.2), so the row is wiped locally: the order
  /// was never published and nothing was charged.
  Future<void> _cancel({required bool maker}) async {
    if (_canceling) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _canceling = true);
    try {
      if (maker) {
        await ref.read(abandonBondedOrderProvider)(widget.orderId);
      } else {
        await orders_api.cancelOrder(orderId: widget.orderId);
      }
      if (!mounted) return;
      _navigated = true;
      refreshTrades(ref);
      if (maker) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.bondAbandoned)));
      }
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
  String? _cancelMessage(
    AppLocalizations l10n,
    TradeUpdate update, {
    required bool maker,
  }) {
    if (update.status == OrderStatus.expired) {
      return maker ? l10n.bondExpiredNoticeMaker : l10n.bondExpiredNotice;
    }
    return switch (bondCancelCopy(update.reason)) {
      BondCancelCopy.lostRace => l10n.bondLostRace,
      BondCancelCopy.makerCanceled => l10n.bondMakerCanceled,
      BondCancelCopy.own => null,
      BondCancelCopy.neutral => l10n.orderNoLongerActive,
    };
  }

  void _listen(AppLocalizations l10n, TradeRole? role, {required bool maker}) {
    ref.listen<AsyncValue<TradeUpdate>>(tradeUpdatesProvider, (prev, next) {
      final update = next.valueOrNull;
      if (update == null || _navigated || !mounted) return;
      if (update.orderId != widget.orderId) return;
      switch (update.status) {
        case OrderStatus.waitingTakerBond:
        case OrderStatus.waitingMakerBond:
        case OrderStatus.inProgress:
          break;
        // A maker's bond locked: the daemon published the order, which now
        // waits for a taker on My Order (docs/ANTI_ABUSE_BOND.md §6.2). For
        // a taker `pending` is the book's word for the order and says
        // nothing about the bond.
        case OrderStatus.pending:
          if (!maker) break;
          _navigated = true;
          refreshTrades(ref);
          context.go(AppRoute.myOrderPath(widget.orderId));
        case OrderStatus.canceled:
        case OrderStatus.cooperativelyCanceled:
        case OrderStatus.canceledByAdmin:
        case OrderStatus.expired:
          _navigated = true;
          refreshTrades(ref);
          final message = _cancelMessage(l10n, update, maker: maker);
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
    final maker = bondIsMakers(bond, isMine: trade?.order.isMine ?? false);
    final orderExpiresAt = trade?.order.expiresAt;
    trackInvoiceDeadline(
      bondCountdownEnd(
        invoiceExpiresAt:
            bond?.expiresAt == null
                ? null
                : platformInt64ToInt(bond!.expiresAt!),
        orderExpiresAt:
            orderExpiresAt == null ? null : platformInt64ToInt(orderExpiresAt),
        maker: maker,
      ),
    );
    _listen(l10n, trade?.role, maker: maker);

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
    if (trade == null) {
      return Scaffold(
        backgroundColor: book.bg,
        appBar: appBar,
        body: Center(child: Text(l10n.tradeLoadError)),
      );
    }

    // A row restored on a fresh device carries no bond at all, not just no
    // bolt11 (docs/ANTI_ABUSE_BOND.md §6.5): the same missing-invoice state.
    final invoice = bond?.invoice ?? '';
    if (bond == null || invoice.isEmpty) {
      return _missingInvoice(l10n, appBar, maker: maker);
    }
    final amountSats = bond.amountSats.toInt();

    return Scaffold(
      backgroundColor: book.bg,
      appBar: appBar,
      body: ValueListenableBuilder<Duration?>(
        valueListenable: invoiceRemaining,
        builder:
            (context, remaining, _) =>
                remaining == Duration.zero && !_waiting
                    ? _expired(l10n, maker: maker)
                    : _payable(
                      l10n,
                      trade: trade,
                      bond: bond,
                      invoice: invoice,
                      amountSats: amountSats,
                      remaining: remaining,
                      maker: maker,
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
    required bool maker,
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
    // applies (docs/ANTI_ABUSE_BOND.md §8.2). Unknown policy warns.
    final slashOnTimeout = bondWarnsTimeout(node?.bondSlashOnWaitingTimeout);
    // A connected wallet pays the bolt11 itself; the disclosures around it
    // (refundable, consequences, countdown, cancel) stay where they are.
    final nwc = ref.watch(isWalletConnectedProvider) && !_manualMode;

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
                        unit: l10n.satsUnitLabel,
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
                          sentence:
                              maker
                                  ? l10n.bondPublishesIn
                                  : l10n.bondReleasesIn,
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
                        rows: _context(
                          l10n,
                          trade,
                          node?.bondAmountPct,
                          maker: maker,
                        ),
                      ),
                    ],
                    const Spacer(),
                    const SizedBox(height: 16),
                    if (nwc)
                      ..._nwcFooter(
                        l10n,
                        invoice,
                        amountSats: amountSats,
                        open: open,
                        maker: maker,
                      )
                    else
                      ..._footer(l10n, invoice, open: open, maker: maker),
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
    final (before, after) = bondSentenceParts(l10n.bondWhyHold);
    return [
      TextSpan(text: l10n.bondWhyCustody),
      TextSpan(
        children: [
          TextSpan(text: before),
          TextSpan(text: 'hold', style: bold),
          if (after.isNotEmpty) TextSpan(text: after),
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
    double? bondAmountPct, {
    required bool maker,
  }) {
    final fiat = formatInvoiceFiat(l10n, trade);
    final buying = bondPayerIsBuying(trade.order.kind, maker: maker);
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

  /// The way out of the window: a taker's cancel, a maker's abandon.
  Widget _leaveLink(AppLocalizations l10n, {required bool maker}) =>
      InvoiceCancelLink(
        label: maker ? l10n.bondDontPublish : l10n.bondDontTake,
        // Nothing is committed yet: not a destructive action.
        danger: false,
        onPressed: _canceling ? null : () => _cancel(maker: maker),
      ).withAutomationId(AutomationIds.bondCancel);

  List<Widget> _footer(
    AppLocalizations l10n,
    String invoice, {
    required bool open,
    required bool maker,
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
      _leaveLink(l10n, maker: maker),
    ];
  }

  /// The wallet pays: one button, the fallback to manual payment lives in
  /// the widget, the cancel link stays. When the QR card is hidden (14b)
  /// the widget's readout carries the bolt11 for automation instead.
  List<Widget> _nwcFooter(
    AppLocalizations l10n,
    String invoice, {
    required int amountSats,
    required bool open,
    required bool maker,
  }) {
    if (_waiting) return _footer(l10n, invoice, open: open, maker: maker);
    return [
      NwcPaymentWidget(
        bolt11: invoice,
        amountSats: amountSats,
        invoiceAutomationId: open ? AutomationIds.bondInvoiceText : null,
        onPaymentSuccess: _onPaymentDetected,
        onFallbackToManual: () => setState(() => _manualMode = true),
      ),
      const SizedBox(height: 4),
      _leaveLink(l10n, maker: maker),
    ];
  }

  /// A row without its bolt11: restored on a fresh device. The daemon
  /// answers a taker's retake from the same key with the same invoice; a
  /// maker has no such re-request upstream (docs/ANTI_ABUSE_BOND.md §6.5),
  /// so that order can only be abandoned or left to expire.
  Widget _missingInvoice(
    AppLocalizations l10n,
    PreferredSizeWidget appBar, {
    required bool maker,
  }) {
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
              maker ? l10n.bondInvoiceMissingMaker : l10n.bondInvoiceMissing,
              textAlign: TextAlign.center,
              style: TextStyle(color: book.textSecondary),
            ),
            const SizedBox(height: 16),
            if (!maker)
              InvoicePrimaryButton(
                icon: Icons.refresh,
                label: l10n.bondRequestAgain,
                busy: _requesting,
                onPressed: _requesting ? null : _requestAgain,
              ),
            const SizedBox(height: 4),
            _leaveLink(l10n, maker: maker),
          ],
        ),
      ),
    );
  }

  Future<void> _closeExpiredWindow() async {
    try {
      final closed = await ref.read(closeExpiredBondWindowProvider)(
        widget.orderId,
      );
      if (closed && mounted) refreshTrades(ref);
    } catch (e) {
      debugPrint('[PayBondInvoiceScreen] expiry sweep failed: $e');
    }
  }

  /// The window ran out unpaid: a taker's order went back to the book, a
  /// maker's was never published (the core wipes the row either way); a way
  /// back, never a dead QR.
  Widget _expired(AppLocalizations l10n, {required bool maker}) {
    // The core closes the window on its next sweep; asking it now keeps the
    // row from lingering as "pay deposit" in My Trades until then.
    if (!_sweptExpired) {
      _sweptExpired = true;
      unawaited(_closeExpiredWindow());
    }
    return InvoiceTimeUpView(
        title: l10n.bondExpiredTitle,
        body: maker ? l10n.bondExpiredBodyMaker : l10n.bondExpiredBody,
        actionLabel: l10n.invoiceBackToBook,
        onAction: () {
          _navigated = true;
          refreshTrades(ref);
          context.go(AppRoute.home);
        },
      );
  }
}
