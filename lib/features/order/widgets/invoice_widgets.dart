import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/invoice_palette.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';

/// Building blocks shared by the two invoice screens
/// (`design_handoff_factura_lightning`, 13a and 13b).

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

/// Back arrow, the action as title, and `#` + the first eight characters of
/// the order id on the right; tapping the id copies the whole UUID.
class InvoiceAppBar extends StatelessWidget implements PreferredSizeWidget {
  const InvoiceAppBar({
    super.key,
    required this.title,
    required this.orderId,
    required this.orderIdAutomationId,
    required this.copiedMessage,
    this.onBack,
  });

  final String title;
  final String orderId;
  final String orderIdAutomationId;

  /// Snackbar shown after the id is copied.
  final String copiedMessage;

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
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: kInvoiceGutter - 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: orderId));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(copiedMessage),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: _kHitTarget,
                minHeight: _kHitTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    invoiceOrderTag(orderId),
                    style: TextStyle(
                      fontFamily: AppFonts.figures,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: book.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ).withAutomationId(orderIdAutomationId, label: orderId),
      ],
    );
  }
}

// ── Hero amount ───────────────────────────────────────────────────────────────

/// The amount as the headline of the screen: label, figure with `sats` on its
/// baseline, a context line, and (13b) the QR below.
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
    final book = OrderBookPalette.of(context);
    final pal = InvoicePalette.of(context);
    final line = contextLine;

    Widget figure = Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            formatInvoiceSats(sats),
            style: TextStyle(
              fontFamily: AppFonts.figures,
              fontSize: 38,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.76,
              height: 1.1,
              color: book.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'sats',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: book.textSecondary,
            ),
          ),
        ],
      ),
    );
    final id = automationId;
    if (id != null) {
      figure = figure.withAutomationId(id, label: automationLabel);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pal.cardBorder),
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.66,
              color: book.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          figure,
          if (line != null) ...[
            const SizedBox(height: 4),
            Text(
              line,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: book.textSecondary),
            ),
          ],
          if (child != null) ...[const SizedBox(height: 14), child!],
        ],
      ),
    );
  }
}

// ── Time band ─────────────────────────────────────────────────────────────────

/// Amber band with the time left; red, with a pulsing figure, under a minute.
///
/// [sentence] receives the figure and returns the localized sentence around
/// it, so the figure can be styled on its own wherever the locale puts it.
class InvoiceTimeBand extends StatefulWidget {
  const InvoiceTimeBand({
    super.key,
    required this.remaining,
    required this.sentence,
  });

  final Duration remaining;
  final String Function(String time) sentence;

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

  bool get _pulsing =>
      widget.remaining > Duration.zero &&
      isInvoiceCountdownUrgent(widget.remaining);

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
    final urgent = isInvoiceCountdownUrgent(widget.remaining);
    final ink = urgent ? pal.errorInk : pal.timeInk;
    final figureColor = urgent ? pal.errorInk : pal.timeFigure;
    final time = formatInvoiceCountdown(widget.remaining);
    final (before, after) = _splitAround(widget.sentence);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: urgent ? pal.errorFill : pal.timeFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: urgent ? pal.errorBorder : pal.timeBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 15, color: figureColor),
          const SizedBox(width: 9),
          Expanded(
            child: Semantics(
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
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
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

/// One label → value row of [InvoiceCounterpartCard]; [trailing] is the
/// reputation beside the counterpart's name.
typedef InvoiceCardRow = ({String label, String value, String? trailing});

/// Counterpart and fiat side of the trade, as label → value rows. The first
/// row is a name; the rest are figures and use the figures face.
class InvoiceCounterpartCard extends StatelessWidget {
  const InvoiceCounterpartCard({super.key, required this.rows});

  final List<InvoiceCardRow> rows;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = InvoicePalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: pal.subtleFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: pal.subtleBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  rows[i].label,
                  style: TextStyle(fontSize: 12, color: book.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    rows[i].value,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: i == 0 ? null : AppFonts.figures,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: book.textStrong,
                    ),
                  ),
                ),
                if (rows[i].trailing != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    rows[i].trailing!,
                    style: TextStyle(
                      fontFamily: AppFonts.figures,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: book.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Lock + the sentence explaining what a hold invoice does, with [boldWord]
/// set in bold wherever the locale places it in [sentence].
class InvoiceHoldNote extends StatelessWidget {
  const InvoiceHoldNote({
    super.key,
    required this.sentence,
    required this.boldWord,
  });

  final String Function(String hold) sentence;
  final String boldWord;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = InvoicePalette.of(context);
    final (before, after) = _splitAround(sentence);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: pal.subtleFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.subtleBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.lock_outline, size: 15, color: pal.icon),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: book.textSecondary,
                ),
                children: [
                  TextSpan(text: before),
                  TextSpan(
                    text: boldWord,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: book.textStrong,
                    ),
                  ),
                  TextSpan(text: after),
                ],
              ),
            ),
          ),
        ],
      ),
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
