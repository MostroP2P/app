import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/invoice_palette.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/features/order/widgets/hero_amount_card.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/shared/utils/countdown.dart';
import 'package:mostro/shared/widgets/countdown_urgency_announcer.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderKind, TradeInfo;

/// Building blocks shared by the two invoice screens
/// (`design_handoff_factura_lightning`, 13a and 13b). Both screens import
/// this file, never each other.

// ── Trade helpers ─────────────────────────────────────────────────────────────

/// `312 ARS`, or null when the trade carries no fiat amount.
String? formatInvoiceFiat(AppLocalizations l10n, TradeInfo trade) {
  final amount = trade.order.fiatAmount;
  if (amount == null || amount <= 0) return null;
  final formatted = NumberFormat.decimalPatternDigits(
    locale: l10n.localeName,
    decimalDigits: amount == amount.truncateToDouble() ? 0 : 2,
  ).format(amount);
  return '$formatted ${trade.order.fiatCode}';
}

/// The counterpart's pseudonym as a data row (DS-CMP-24), with their
/// reputation trailing it once the daemon's snapshot has arrived.
Widget invoiceCounterpartRow(
  WidgetRef ref,
  AppLocalizations l10n,
  TradeInfo trade,
  String label,
) {
  final pubkey = trade.counterpartyPubkey;
  final handle =
      pubkey.isEmpty
          ? null
          : ref.watch(peerNymProvider(pubkey)).valueOrNull?.pseudonym;
  final hasSnapshot = trade.peerRating != null;
  return OrderDataRow(
    icon: Icons.person_outline_rounded,
    label: label,
    value: OrderDataValue(
      handle ?? l10n.unknownPeerHandle,
      trailing:
          hasSnapshot
              ? counterpartStars(trade.peerRating, trade.peerReviews) ??
                  l10n.invoiceNoTrades
              : null,
    ),
  );
}

/// The fiat side of the trade as a data row: `312 ARS · Mercado Pago`.
Widget invoiceFiatRow(String label, String fiat, String paymentMethod) {
  final method = paymentMethod.trim();
  return OrderDataRow(
    icon: Icons.payments_outlined,
    label: label,
    value: OrderDataValue(
      method.isEmpty ? fiat : '$fiat · $method',
      figures: true,
    ),
  );
}

/// Side margin and bottom padding of both screens.
const kInvoiceGutter = 18.0;

/// Minimum hit target of the small icon actions.
const _kHitTarget = 44.0;

/// Stands in for a placeholder while a localized sentence is split around
/// it. A private-use character: no translation can contain it.
const _kSplitMarker = '\u{E000}';

/// [sentence] built around a marker, cut into the text before and after it.
(String, String) _splitAround(String Function(String) sentence) {
  final parts = sentence(_kSplitMarker).split(_kSplitMarker);
  return (parts.first, parts.length > 1 ? parts.sublist(1).join() : '');
}

// ── App bar ───────────────────────────────────────────────────────────────────

/// Back arrow and the action as title. The order id is not here: it is an ID
/// row of the screen's card (DS-CMP-22).
class InvoiceAppBar extends StatelessWidget implements PreferredSizeWidget {
  const InvoiceAppBar({super.key, required this.title, this.onBack});

  final String title;

  /// Null hides the arrow (nothing to go back to).
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return AppBar(
      backgroundColor: book.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading:
          onBack == null
              ? null
              : IconButton(
                icon: Icon(Icons.arrow_back, size: 22, color: book.textBody),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: onBack,
              ).withAutomationId(AutomationIds.appBarBack),
      titleSpacing: onBack == null ? kInvoiceGutter : 0,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: book.textPrimary,
        ),
      ),
    );
  }
}

// ── Hero amount ───────────────────────────────────────────────────────────────

/// The sats amount as the headline of the screen: the shared
/// [HeroAmountCard] (DS-CMP-23) with `sats` as its unit, a context line, and
/// (13b) the QR below.
class InvoiceHeroCard extends StatelessWidget {
  const InvoiceHeroCard({
    super.key,
    required this.label,
    required this.sats,
    required this.semanticsLabel,
    this.contextLine,
    this.automationId,
    this.automationLabel,
    this.child,
  });

  final String label;
  final int sats;

  /// Announced as one label (`252 satoshis to pay`).
  final String semanticsLabel;

  /// `≈ 312 ARS · Bitcoin Bolivia` / the fee line.
  final String? contextLine;
  final String? automationId;
  final String? automationLabel;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final line = contextLine;
    return HeroAmountCard(
      label: label,
      figure: formatInvoiceSats(sats, l10n.localeName),
      unit: l10n.satsUnitLabel,
      semanticsLabel: semanticsLabel,
      automationId: automationId,
      automationLabel: automationLabel,
      footer: line == null ? null : HeroContextLine(line),
      child: child,
    );
  }
}

// ── Time band ─────────────────────────────────────────────────────────────────

/// What the countdown says at 00:00 on a waiting step: what mostrod is about
/// to do with the order ([stepExpiry]), or, while the order's [kind] is not
/// known yet, only that the step is about to close.
String stepElapsedNotice(
  AppLocalizations l10n, {
  required bool buyerStep,
  required OrderKind? kind,
}) => switch (kind == null
    ? null
    : stepExpiry(buyerStep: buyerStep, kind: kind)) {
  StepExpiry.backToBook => l10n.stepElapsedBackToBook,
  StepExpiry.cancelled => l10n.stepElapsedCancelled,
  null => l10n.invoiceStepElapsed,
};

/// Amber band with the time left; red, with a pulsing figure, once
/// `countdownTone` turns urgent — under a minute in an invoice window of
/// 15 minutes or less, under five in a longer one (DS-CMP-21).
///
/// [sentence] receives the figure and returns the localized sentence around
/// it, so the figure can be styled on its own wherever the locale puts it.
class InvoiceTimeBand extends StatefulWidget {
  const InvoiceTimeBand({
    super.key,
    required this.remaining,
    required this.window,
    required this.sentence,
    required this.hours,
    this.elapsed,
  });

  final Duration remaining;

  /// The whole window the band counts down, or null when unknown.
  final Duration? window;
  final String Function(String time) sentence;

  /// Shown instead of [sentence] once [remaining] reaches zero. The local
  /// clock running out is not the daemon acting: the step stays open until
  /// its message arrives.
  final String? elapsed;

  /// The localized countdown above an hour (`1 h 05`).
  final String Function(String hours, String minutes) hours;

  @override
  State<InvoiceTimeBand> createState() => _InvoiceTimeBandState();
}

class _InvoiceTimeBandState extends State<InvoiceTimeBand>
    with SingleTickerProviderStateMixin {
  /// Same pulse as the order status of 6a.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(InvoiceTimeBand old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool get _urgent =>
      countdownTone(widget.remaining, window: widget.window) ==
      CountdownTone.urgent;

  bool get _pulsing => widget.remaining > Duration.zero && _urgent;

  void _syncPulse() {
    if (_pulsing) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating || _pulse.value != 0) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = InvoicePalette.of(context);
    final urgent = _urgent;
    final ink = urgent ? pal.errorInk : pal.timeInk;
    final figureColor = urgent ? pal.errorInk : pal.timeFigure;
    final time = formatCountdown(widget.remaining, hours: widget.hours);
    final (before, after) = _splitAround(widget.sentence);
    final elapsed = widget.remaining == Duration.zero ? widget.elapsed : null;

    return CountdownUrgencyAnnouncer(
      urgent: urgent,
      message: widget.sentence(time),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: urgent ? pal.errorFill : pal.timeFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: urgent ? pal.errorBorder : pal.timeBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule, size: 14, color: figureColor),
            const SizedBox(width: 8),
            Expanded(
              child:
                  elapsed != null
                      // Appears while the user watches the countdown: announced
                      // (DS-A11Y-2). The ticking figure below is not.
                      ? Semantics(
                        liveRegion: true,
                        child: Text(
                          elapsed,
                          style: TextStyle(fontSize: 12, color: ink),
                        ),
                      )
                      : Semantics(
                        label: widget.sentence(time),
                        excludeSemantics: true,
                        child: AnimatedBuilder(
                          animation: _pulse,
                          builder:
                              (context, _) => Text.rich(
                                TextSpan(
                                  style: TextStyle(fontSize: 12, color: ink),
                                  children: [
                                    TextSpan(text: before),
                                    TextSpan(
                                      text: time,
                                      style: TextStyle(
                                        fontFamily: AppFonts.figures,
                                        fontWeight: FontWeight.w700,
                                        color: figureColor.withValues(
                                          alpha: 1 - 0.65 * _pulse.value,
                                        ),
                                      ),
                                    ),
                                    TextSpan(text: after),
                                  ],
                                ),
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

// ── Actions ───────────────────────────────────────────────────────────────────

/// Full-width lime action. [onPressed] null draws it disabled; [busy] swaps
/// the icon for a spinner.
class InvoicePrimaryButton extends StatelessWidget {
  const InvoicePrimaryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = InvoicePalette.of(context);
    final enabled = onPressed != null;
    final ink = enabled ? book.onLime : pal.disabledInk;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: enabled ? book.lime : pal.disabledFill,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: busy ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ink,
                    ),
                  )
                else
                  Icon(icon, size: 16, color: ink),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Grey action that shares a row (`Copy`, `Share`).
class InvoiceSecondaryButton extends StatelessWidget {
  const InvoiceSecondaryButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Overrides the ink of the icon (the copy check).
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final pal = InvoicePalette.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: pal.secondaryBorder),
    );
    return Material(
      color: pal.secondaryFill,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _kHitTarget),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: iconColor ?? pal.secondaryInk),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: pal.secondaryInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `Cancel trade` as bare text: grey in 13a, red in 13b.
class InvoiceCancelLink extends StatelessWidget {
  const InvoiceCancelLink({
    super.key,
    required this.label,
    required this.danger,
    required this.onPressed,
  });

  final String label;
  final bool danger;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = InvoicePalette.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: danger ? pal.cancelDanger : book.textSecondary,
        minimumSize: const Size.fromHeight(_kHitTarget),
        // A button's textStyle replaces the theme's instead of merging with
        // it: without a family the label falls back to the platform font.
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Text(label),
    );
  }
}

/// A 44 dp target around a 16 dp lime icon (paste, scan).
class InvoiceIconAction extends StatelessWidget {
  const InvoiceIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 16, color: book.limeText),
      constraints: const BoxConstraints.tightFor(
        width: _kHitTarget,
        height: _kHitTarget,
      ),
      padding: EdgeInsets.zero,
    );
  }
}

// ── Cards ─────────────────────────────────────────────────────────────────────

/// A state of an invoice screen with no card of its own (loading, waiting,
/// paying through the wallet, closed): a data card holding only the order's
/// ID row on top, [child] below, so the id reads the same in every state
/// (DS-CMP-22, DS-CMP-24).
class InvoiceOrderIdBody extends StatelessWidget {
  const InvoiceOrderIdBody({
    super.key,
    required this.orderId,
    required this.automationId,
    required this.child,
  });

  final String orderId;
  final String automationId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kInvoiceGutter,
            8,
            kInvoiceGutter,
            0,
          ),
          child: OrderDataCard(
            rows: [OrderIdRow(orderId: orderId, automationId: automationId)],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// Terminal state once an invoice step ran out of time: the reason and one
/// way back, instead of a form or a QR nobody can use any more.
class InvoiceTimeUpView extends StatelessWidget {
  const InvoiceTimeUpView({
    super.key,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
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
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: book.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
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
            label: actionLabel,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}

/// The verdict under the invoice field: lime when usable, red with the
/// concrete reason otherwise.
class InvoiceValidationRow extends StatelessWidget {
  const InvoiceValidationRow({
    super.key,
    required this.text,
    required this.isValid,
  });

  final String text;
  final bool isValid;

  @override
  Widget build(BuildContext context) {
    final pal = InvoicePalette.of(context);
    final ink = isValid ? pal.validInk : pal.errorInk;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isValid ? pal.validFill : pal.errorFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isValid ? pal.validBorder : pal.errorBorder,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                isValid ? Icons.check_circle_outline : Icons.error_outline,
                size: 14,
                color: isValid ? pal.validIcon : pal.errorInk,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 12, color: ink)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A submission the node has not answered yet (#615): the waiting style of
/// the time banner, not the error one — nothing went wrong, and the screen
/// moves on by itself when the answer arrives.
class InvoiceAwaitingRow extends StatelessWidget {
  const InvoiceAwaitingRow({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final pal = InvoicePalette.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: pal.timeFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pal.timeBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.hourglass_top_rounded,
                size: 14,
                color: pal.timeInk,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 12, color: pal.timeInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The validation row under the invoice field, carrying the `invoice.check`
/// readout (`docs/automation-contract.md`).
///
/// The label is derived from [check] here instead of being passed in, so the
/// row cannot be labelled with [sentence]: that copy is translated, and
/// automation reading it would break in every locale but one. Callers choose
/// what to say; they do not get to choose what it is called.
Widget invoiceCheckRow({
  required InvoiceCheck check,
  required String sentence,
}) => InvoiceValidationRow(
  text: sentence,
  isValid: check is! InvoiceCheckError,
).withAutomationId(AutomationIds.invoiceCheck, label: invoiceCheckWord(check));
