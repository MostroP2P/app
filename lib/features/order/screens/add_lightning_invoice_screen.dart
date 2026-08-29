import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show refreshTrades, tradeInfoProvider;
import 'package:mostro/shared/widgets/nwc_invoice_widget.dart';
import 'package:mostro/shared/widgets/peer_reputation_card.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart' show OrderStatus, TradeUpdate;

/// Add Lightning Invoice screen — Route `/add_invoice/:orderId`.
///
/// Buyer enters a Lightning invoice (or it's pre-filled from settings).
/// Shown when NWC is NOT configured.
class AddLightningInvoiceScreen extends ConsumerStatefulWidget {
  const AddLightningInvoiceScreen({
    super.key,
    required this.orderId,
    this.amountSats,
    this.generateInvoice,
  });

  final String orderId;
  /// Sats amount for the invoice. `null` until the trade provider resolves it.
  final int? amountSats;

  /// Test seam forwarded to [NwcInvoiceWidget]; production leaves it null so
  /// the widget generates the invoice over NWC. See [NwcInvoiceWidget].
  @visibleForTesting
  final Future<String> Function(int amountSats)? generateInvoice;

  @override
  ConsumerState<AddLightningInvoiceScreen> createState() =>
      _AddLightningInvoiceScreenState();
}

class _AddLightningInvoiceScreenState
    extends ConsumerState<AddLightningInvoiceScreen> {
  final _invoiceController = TextEditingController();
  bool _submitting = false;
  /// `true` while a protocol cancel is in flight — blocks re-entry and submit.
  bool _canceling = false;
  /// `true` when NWC is connected but generation failed → show manual form.
  bool _manualMode = false;
  /// One-shot guard so we don't navigate twice as further updates stream in.
  bool _navigated = false;

  @override
  void dispose() {
    _invoiceController.dispose();
    super.dispose();
  }

  BigInt? _resolvedSats(WidgetRef ref) {
    final fromProvider = ref.watch(tradeAmountProvider(widget.orderId)).valueOrNull;
    if (fromProvider != null) return fromProvider;
    final fallback = widget.amountSats;
    return fallback != null ? BigInt.from(fallback) : null;
  }

  bool _isLnAddress(String text) => text.contains('@');

  bool _isValid(WidgetRef ref) {
    final text = _invoiceController.text.trim();
    if (text.isEmpty) return false;
    // Lightning Address requires a known sats amount before submission.
    if (_isLnAddress(text) && _resolvedSats(ref) == null) return false;
    return true;
  }

  /// Cancel button = cancel the trade itself (confirmed via dialog), not
  /// just leave the screen — going back is what lands on trade detail (#268).
  Future<void> _cancelOrder() async {
    // Serialize state-changing requests: no cancel while a submit or another
    // cancel is in flight (review round 1).
    if (_submitting || _canceling) return;
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

  Future<void> _submit(WidgetRef ref) async {
    if (_submitting || _canceling) return;
    final input = _invoiceController.text.trim();
    // For Lightning Addresses, the sats amount must be resolved before sending —
    // the Rust side uses it to resolve the address. Bolt11 invoices encode
    // their own amount so BigInt.one is an acceptable non-zero placeholder.
    final resolvedSats = _resolvedSats(ref);
    if (_isLnAddress(input) && resolvedSats == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).waitingForTradeAmount)),
      );
      return;
    }
    final sats = resolvedSats ?? BigInt.one;
    setState(() => _submitting = true);

    try {
      await orders_api.sendInvoice(
        orderId: widget.orderId,
        invoiceOrAddress: _invoiceController.text.trim(),
        amountSats: sats,
      );

      if (!mounted) return;
      context.go(AppRoute.tradeDetailPath(widget.orderId));
    } catch (e) {
      if (!mounted) return;
      // sendInvoice now waits for the daemon's reply: an error means the
      // invoice was NOT accepted (CantDo, e.g. invalid invoice, or timeout),
      // so stay on this screen. Strip the Rust error prefix for readability.
      final raw = e.toString();
      final anyhowMatch = RegExp(r'^.*?AnyhowException\((.+)\)$').firstMatch(raw);
      final msg = anyhowMatch != null ? anyhowMatch.group(1)! : raw;
      final display =
          localizedDaemonError(AppLocalizations.of(context), msg, fallback: msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(display)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final inputBg = colors?.backgroundInput ?? const Color(0xFF252A3A);
    final l10n = AppLocalizations.of(context);

    final isWalletConnected = ref.watch(isWalletConnectedProvider);

    // Leave the screen when mostrod cancels the order (e.g. the buyer let the
    // waiting-state window expire): the daemon ignores messages for a
    // canceled order, so without this the form just sits here and every
    // submit dies with a 10s NoDaemonResponse.
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
          // The wiped trade must also disappear from the My Trades cache.
          refreshTrades(ref);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.orderNoLongerActive)),
          );
          context.go(AppRoute.home);
        default:
          break;
      }
    });

    // Resolve sats: provider first (live polling), fall back to constructor param.
    final sats = _resolvedSats(ref);

    // Counterpart (taker) reputation: the maker is the buyer here (adding an
    // invoice), so the taker is the seller (#305). Read via tradeInfoProvider,
    // which refreshes on the TradeUpdate emitted after the snapshot persists.
    final trade = ref.watch(tradeInfoProvider(widget.orderId)).valueOrNull;

    // When NWC is connected, we need the sats amount to auto-generate an invoice.
    // Show a loading indicator only in that case. Manual entry is always available.
    if (isWalletConnected && sats == null && !_manualMode) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.addInvoiceTitle)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.fetchingTradeAmount,
                style: TextStyle(color: Theme.of(context).extension<AppColors>()?.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () => setState(() => _manualMode = true),
                child: Text(l10n.enterInvoiceManually),
              ).withAutomationId(AutomationIds.invoiceManual),
            ],
          ),
        ),
      );
    }

    // If NWC wallet is connected, amount is known, and we haven't fallen back
    // to manual, show the auto-invoice widget instead of the manual form.
    if (isWalletConnected && !_manualMode && sats != null && sats > BigInt.zero) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.addInvoiceTitle)),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              // The maker must see who took their order even when NWC
              // auto-generates the invoice and the flow can proceed on its
              // own — that is exactly where the decision matters most (#305).
              if (trade?.peerRating != null) ...[
                PeerReputationCard(
                  rating: trade!.peerRating!,
                  reviews: trade.peerReviews ?? 0,
                  days: trade.peerDays ?? 0,
                  counterpartIsBuyer: false,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              Expanded(
                child: Center(
                  child: NwcInvoiceWidget(
                    amountSats: sats.toInt(),
                    generateInvoice: widget.generateInvoice,
                    onInvoiceConfirmed: (invoice) {
                      _invoiceController.text = invoice;
                      _submit(ref);
                    },
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
      appBar: AppBar(title: Text(l10n.addInvoiceTitle)),
      body: Padding(
        // #267: bottom system-bar inset so the Cancel/Submit row clears the
        // gesture / 3-button navigation bar.
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: Column(
          children: [
            if (trade?.peerRating != null) ...[
              PeerReputationCard(
                rating: trade!.peerRating!,
                reviews: trade.peerReviews ?? 0,
                days: trade.peerDays ?? 0,
                counterpartIsBuyer: false,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            // Info card
            Container(
              width: double.infinity,
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
                      Expanded(
                        child: Text(
                          l10n.enterLightningInvoiceInstruction,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  // Sats amount calculated by the daemon (arrives in the
                  // take/add-invoice reply and lands in the trade record).
                  if (sats != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      AppLocalizations.of(context).addInvoiceAmount(sats.toString()),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),

                  // Invoice text input
                  TextField(
                    controller: _invoiceController,
                    maxLines: 4,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    decoration: InputDecoration(
                      hintText: 'lnbc...',
                      floatingLabelBehavior: FloatingLabelBehavior.auto,
                      labelText: l10n.lightningInvoiceLabel,
                      filled: true,
                      fillColor: inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
                      fontFamily: 'monospace',
                    ),
                    onChanged: (_) => setState(() {}),
                  ).withAutomationId(AutomationIds.invoiceText),
                ],
              ),
            ),
            const Spacer(),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed:
                        (_submitting || _canceling) ? null : _cancelOrder,
                    child: Text(
                      l10n.cancel,
                      style: TextStyle(color: colors?.textSecondary),
                    ),
                  ).withAutomationId(AutomationIds.invoiceCancel),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: (!_canceling && _isValid(ref))
                        ? () => _submit(ref)
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: green.withValues(alpha: 0.3),
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.submitButton),
                  ).withAutomationId(AutomationIds.invoiceSubmit),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
