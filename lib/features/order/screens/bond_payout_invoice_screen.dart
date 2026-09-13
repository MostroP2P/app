import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/core/invoice_palette.dart';
import 'package:mostro/features/order/models/bond_rules.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/features/order/widgets/invoice_widgets.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/shared/widgets/nwc_invoice_widget.dart';
import 'package:mostro/shared/widgets/platform_aware_qr_scanner.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/types.dart' show BondClaim, BondClaimPhase;

/// Claim the counterparty's share of a slashed bond
/// (docs/ANTI_ABUSE_BOND.md §6.4): the daemon asked for a bolt11 for
/// exactly the share; the user pastes one, scans one, or lets the connected
/// wallet create it. The claim's phase drives the screen: the form while
/// `Pending`, a wait while `Submitted`, a read-only state once acknowledged,
/// paid or expired.
class BondPayoutInvoiceScreen extends ConsumerStatefulWidget {
  const BondPayoutInvoiceScreen({
    super.key,
    required this.orderId,
    this.generateInvoice,
  });

  final String orderId;

  /// Test seam forwarded to [NwcInvoiceWidget]; production leaves it null.
  final Future<String> Function(int amountSats)? generateInvoice;

  @override
  ConsumerState<BondPayoutInvoiceScreen> createState() =>
      _BondPayoutInvoiceScreenState();
}

class _BondPayoutInvoiceScreenState
    extends ConsumerState<BondPayoutInvoiceScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _submitting = false;
  bool _manualMode = false;
  String? _lastError;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit(String invoice) async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _submitting = true;
      _lastError = null;
    });
    try {
      await ref.read(submitBondPayoutInvoiceProvider)(widget.orderId, invoice);
      if (!mounted) return;
      ref.invalidate(bondClaimProvider(widget.orderId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.bondClaimSent)));
    } catch (e) {
      if (!mounted) return;
      ref.invalidate(bondClaimProvider(widget.orderId));
      setState(() {
        _lastError = localizedDaemonError(
          l10n,
          e,
          fallback: l10n.bondClaimErrorRejected,
        );
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = normalizeInvoiceInput(data?.text ?? '');
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).clipboardEmptyError),
        ),
      );
      return;
    }
    _setInput(text);
  }

  Future<void> _scan() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (routeContext) {
          final l10n = AppLocalizations.of(routeContext);
          return Scaffold(
            backgroundColor: OrderBookPalette.of(routeContext).bg,
            appBar: redesignAppBar(
              routeContext,
              title: l10n.scanQrCodeTitle,
              onBack: () => Navigator.of(routeContext).pop(),
            ),
            body: PlatformAwareQrScanner(
              hint: l10n.bondClaimFieldHint,
              onDetected: (value) => Navigator.of(routeContext).pop(value),
            ),
          );
        },
      ),
    );
    if (!mounted || scanned == null) return;
    _setInput(normalizeInvoiceInput(scanned));
  }

  void _setInput(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _lastError = null);
  }

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final claimAsync = ref.watch(bondClaimProvider(widget.orderId));
    final claim = claimAsync.valueOrNull;
    final canPop = Navigator.of(context).canPop();
    final appBar = InvoiceAppBar(
      title: l10n.bondClaimTitle,
      orderId: widget.orderId,
      orderIdAutomationId: AutomationIds.bondClaimOrderId,
      copiedMessage: l10n.invoiceOrderIdCopied,
      onBack: canPop ? () => Navigator.of(context).maybePop() : null,
    );
    if (claimAsync.isLoading && claim == null) {
      return Scaffold(
        backgroundColor: book.bg,
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (claim == null) {
      return Scaffold(
        backgroundColor: book.bg,
        appBar: appBar,
        body: Center(child: Text(l10n.bondClaimMissing)),
      );
    }
    final now = clock.now().millisecondsSinceEpoch ~/ 1000;
    final deadlineAt = platformInt64ToInt(claim.deadlineAt);
    final phase = bondClaimEffectivePhase(
      phase: claim.phase,
      deadlineAt: deadlineAt,
      now: now,
    );
    final body = switch (phase) {
      BondClaimPhase.pending => _pending(l10n, claim, deadlineAt),
      BondClaimPhase.submitted => _state(
        l10n,
        claim,
        deadlineAt,
        icon: Icons.hourglass_top,
        title: l10n.bondClaimSubmittedTitle,
        body: l10n.bondClaimSubmittedBody,
        busy: true,
      ),
      BondClaimPhase.acknowledged => _state(
        l10n,
        claim,
        deadlineAt,
        icon: Icons.bolt,
        title: l10n.bondClaimAcknowledgedTitle,
        body: l10n.bondClaimAcknowledgedBody,
      ),
      BondClaimPhase.completed => _state(
        l10n,
        claim,
        deadlineAt,
        icon: Icons.check_circle_outline,
        title: l10n.bondClaimCompletedTitle,
        body: l10n.bondClaimCompletedBody(
          formatInvoiceSats(claim.amountSats.toInt()),
        ),
      ),
      BondClaimPhase.expired => InvoiceTimeUpView(
        title: l10n.bondClaimExpiredTitle,
        body: l10n.bondClaimExpiredBody(_date(deadlineAt)),
        actionLabel: l10n.invoiceBackToBook,
        onAction: () => context.go(AppRoute.home),
      ),
    };
    return Scaffold(
      backgroundColor: book.bg,
      resizeToAvoidBottomInset: true,
      appBar: appBar,
      body: body.withAutomationId(
        AutomationIds.bondClaimStatus,
        label: phase.name,
      ),
    );
  }

  String _date(int unixSecs) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMd(
      locale,
    ).add_Hm().format(DateTime.fromMillisecondsSinceEpoch(unixSecs * 1000));
  }

  Widget _hero(AppLocalizations l10n, BondClaim claim, int deadlineAt) {
    final sats = claim.amountSats.toInt();
    final fiat = claim.fiatAmount;
    final context_ = [
      if (fiat != null) formatBondFiat(l10n.localeName, fiat, claim.fiatCode),
      claim.paymentMethod,
    ].where((s) => s.isNotEmpty).join(' · ');
    return InvoiceHeroCard(
      label: l10n.bondClaimShareLabel,
      sats: sats,
      semanticsLabel: l10n.bondClaimShareSemantics(sats.toString()),
      contextLine: context_.isEmpty ? null : l10n.bondClaimContext(context_),
      automationId: AutomationIds.bondClaimAmount,
      automationLabel: sats.toString(),
    );
  }

  Widget _deadline(AppLocalizations l10n, int deadlineAt) {
    final book = OrderBookPalette.of(context);
    return Row(
      children: [
        Icon(Icons.schedule, size: 14, color: book.textTertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.bondClaimDeadline(_date(deadlineAt)),
            style: TextStyle(fontSize: 12, color: book.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _pending(AppLocalizations l10n, BondClaim claim, int deadlineAt) {
    final sats = claim.amountSats.toInt();
    final nwc = ref.watch(isWalletConnectedProvider) && !_manualMode;
    final error = _lastError;
    return _scroll(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hero(l10n, claim, deadlineAt),
          const SizedBox(height: 12),
          _deadline(l10n, deadlineAt),
          const SizedBox(height: 12),
          Text(
            l10n.bondClaimExplainer,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: OrderBookPalette.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          if (nwc) ...[
            Center(
              child: NwcInvoiceWidget(
                amountSats: sats,
                generateInvoice: widget.generateInvoice,
                onInvoiceConfirmed: _submit,
                onFallbackToManual: () => setState(() => _manualMode = true),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              InvoiceValidationRow(text: error, isValid: false),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _manualMode = true),
                child: Text(l10n.enterInvoiceManually),
              ).withAutomationId(AutomationIds.bondClaimManual),
            ],
          ] else ...[
            _field(l10n),
            if (error != null) ...[
              const SizedBox(height: 8),
              InvoiceValidationRow(text: error, isValid: false),
            ],
            const Spacer(),
            const SizedBox(height: 16),
            InvoicePrimaryButton(
              icon: Icons.bolt,
              label: l10n.bondClaimSubmit,
              busy: _submitting,
              onPressed:
                  _submitting || _controller.text.trim().isEmpty
                      ? null
                      : () => _submit(_controller.text),
            ).withAutomationId(AutomationIds.bondClaimSubmit),
          ],
        ],
      ),
    );
  }

  Widget _state(
    AppLocalizations l10n,
    BondClaim claim,
    int deadlineAt, {
    required IconData icon,
    required String title,
    required String body,
    bool busy = false,
  }) {
    final book = OrderBookPalette.of(context);
    final pal = InvoicePalette.of(context);
    return _scroll(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hero(l10n, claim, deadlineAt),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: book.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: pal.cardBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (busy)
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: book.lime,
                    ),
                  )
                else
                  Icon(icon, size: 20, color: book.lime),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: book.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: book.textSecondary,
                        ),
                      ),
                      if (claim.submittedInvoice case final invoice?) ...[
                        const SizedBox(height: 8),
                        Text(
                          invoice,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppFonts.figures,
                            fontSize: 11,
                            color: book.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(height: 16),
          InvoicePrimaryButton(
            icon: Icons.arrow_back,
            label: l10n.closeButtonLabel,
            onPressed:
                () =>
                    Navigator.of(context).canPop()
                        ? Navigator.of(context).pop()
                        : context.go(AppRoute.home),
          ),
        ],
      ),
    );
  }

  Widget _scroll(Widget child) => LayoutBuilder(
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
            child: IntrinsicHeight(child: child),
          ),
        ),
  );

  Widget _field(AppLocalizations l10n) {
    final book = OrderBookPalette.of(context);
    final pal = InvoicePalette.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 14),
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _focus.hasFocus ? pal.fieldFocusBorder : pal.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.bondClaimFieldLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.66,
                    color: book.textSecondary,
                  ),
                ),
              ),
              InvoiceIconAction(
                icon: Icons.content_paste,
                tooltip: l10n.pasteButtonLabel,
                onPressed: _paste,
              ),
              InvoiceIconAction(
                icon: Icons.qr_code_scanner,
                tooltip: l10n.scanQrButtonLabel,
                onPressed: _scan,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              minLines: 1,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              cursorColor: book.lime,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: l10n.bondClaimFieldHint,
                hintStyle: TextStyle(
                  fontFamily: AppFonts.figures,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: book.textTertiary,
                ),
              ),
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: book.textPrimary,
              ),
              onChanged: (_) => setState(() => _lastError = null),
            ).withAutomationId(AutomationIds.bondClaimText),
          ),
        ],
      ),
    );
  }
}
