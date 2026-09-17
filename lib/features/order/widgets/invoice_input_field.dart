import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/invoice_palette.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Minimum hit target of the actions under the field.
const _kHitTarget = 44.0;

/// Fixed height of the text area: three lines of a BOLT11, never more.
const _kTextareaHeight = 78.0;

/// One cycle of the pulse of the empty field (rest → peak → rest).
const _kPulseCycle = Duration(milliseconds: 2400);

/// One on + off cycle of the lime cursor drawn while the field is idle.
const _kCursorBlink = Duration(milliseconds: 1100);

const _kTextStyle = TextStyle(
  fontFamily: AppFonts.figures,
  fontSize: 12.5,
  height: 1.45,
);

/// The field where the buyer gives the invoice or Lightning address
/// (`design_handoff_campo_factura`, 17a empty and 17b filled).
///
/// Empty, it asks to be filled: lime fill, a border that pulses and a
/// blinking cursor. The pulse is a first-time pointer, not decoration — it
/// stops for good once the field gets focus or content, and never runs
/// under reduced motion. Filled and idle, the invoice shows cut to three
/// lines; a long press opens it whole. The controller always keeps the full
/// string.
class InvoiceInputField extends StatefulWidget {
  const InvoiceInputField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onPaste,
    required this.onScan,
    this.validSats,
    this.isValid = false,
    this.isAddress = false,
    this.hasError = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;

  /// Null when the clipboard holds nothing to paste: the button is not drawn
  /// and `Scan` takes the whole row.
  final VoidCallback? onPaste;
  final VoidCallback onScan;

  /// The amount of a valid BOLT11, shown beside the label.
  final int? validSats;

  /// Draws the check beside the label.
  final bool isValid;

  /// The input is a Lightning address, not an invoice: labelled and
  /// announced as such.
  final bool isAddress;

  /// Draws the field's border in the error ink.
  final bool hasError;

  @override
  State<InvoiceInputField> createState() => _InvoiceInputFieldState();
}

class _InvoiceInputFieldState extends State<InvoiceInputField>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: _kPulseCycle ~/ 2,
  );
  late final AnimationController _cursor = AnimationController(
    vsync: this,
    duration: _kCursorBlink,
  );

  /// True until the field first gets focus or content; never true again.
  bool _prompting = true;

  bool get _hasText => widget.controller.text.isNotEmpty;

  /// What the filled field holds: an address or an invoice.
  String _filledLabel(AppLocalizations l10n) =>
      widget.isAddress
          ? l10n.invoiceFieldAddressLabel
          : l10n.invoiceFieldFilledLabel;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onFieldChanged);
    widget.focusNode.addListener(_onFieldChanged);
    _prompting = !_hasText && !widget.focusNode.hasFocus;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimations();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onFieldChanged);
    widget.focusNode.removeListener(_onFieldChanged);
    _pulse.dispose();
    _cursor.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (!mounted) return;
    setState(() {
      if (_hasText || widget.focusNode.hasFocus) _prompting = false;
    });
    _syncAnimations();
  }

  void _syncAnimations() {
    final animate = _prompting && !MediaQuery.disableAnimationsOf(context);
    if (animate) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
      if (!_cursor.isAnimating) _cursor.repeat();
    } else {
      _pulse.stop();
      _cursor.stop();
    }
  }

  void _showWhole(AppLocalizations l10n) {
    final book = OrderBookPalette.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: book.surface,
      isScrollControlled: true,
      builder:
          (sheetContext) => ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _filledLabel(l10n).toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.66,
                        color: book.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          widget.controller.text,
                          style: _kTextStyle.copyWith(color: book.textStrong),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    final pal = InvoicePalette.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        // Under reduced motion the border holds the value of the peak.
        final t =
            _prompting
                ? (reduceMotion
                    ? 1.0
                    : Curves.easeInOut.transform(_pulse.value))
                : 0.0;
        final border =
            _prompting
                ? Color.lerp(pal.promptBorder, pal.promptBorderPeak, t)!
                : widget.hasError
                ? pal.errorBorder
                : _hasText
                ? pal.filledBorder
                : pal.cardBorder;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _prompting ? pal.promptFill : book.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border, width: 1.5),
            boxShadow: [
              if (_prompting && !reduceMotion && t > 0)
                BoxShadow(
                  color: pal.promptHalo.withValues(alpha: pal.promptHalo.a * t),
                  spreadRadius: 5 * t,
                ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(l10n, book, pal),
          const SizedBox(height: 9),
          _textarea(l10n, book, pal),
          const SizedBox(height: 9),
          _actions(l10n, pal),
        ],
      ),
    );
  }

  Widget _header(
    AppLocalizations l10n,
    OrderBookPalette book,
    InvoicePalette pal,
  ) {
    final sats = widget.validSats;
    final showCheck = _hasText && widget.isValid;
    return Row(
      children: [
        Expanded(
          child: Text(
            (_hasText ? _filledLabel(l10n) : l10n.invoiceFieldPromptLabel)
                .toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.66,
              color: _hasText ? book.textSecondary : pal.validInk,
            ),
          ),
        ),
        if (showCheck) ...[
          Icon(Icons.check, size: 13, color: pal.validIcon),
          if (sats != null) ...[
            const SizedBox(width: 4),
            Text(
              '${formatInvoiceSats(sats)} sats',
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: pal.validInk,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _textarea(
    AppLocalizations l10n,
    OrderBookPalette book,
    InvoicePalette pal,
  ) {
    final focused = widget.focusNode.hasFocus;
    final sats = widget.validSats;
    return Container(
      height: _kTextareaHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: pal.textareaFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pal.textareaBorder),
      ),
      child: Stack(
        children: [
          Semantics(
            label: l10n.invoiceFieldSemantics,
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              minLines: 3,
              maxLines: 3,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              keyboardType: TextInputType.visiblePassword,
              // An invoice has no whitespace: a pasted mail's line breaks
              // never reach the field.
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              cursorColor: book.lime,
              cursorWidth: 1.5,
              cursorHeight: 16,
              style: _kTextStyle.copyWith(color: book.textStrong),
              decoration: InputDecoration(
                // The text area draws its own fill and border.
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: l10n.invoiceFieldHint,
                hintStyle: _kTextStyle.copyWith(color: pal.placeholder),
              ),
              onChanged: (_) => widget.onChanged(),
            ).withAutomationId(AutomationIds.invoiceText),
          ),
          if (_prompting)
            Positioned(
              left: 0,
              top: 1,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _cursor,
                  builder:
                      (context, _) => Opacity(
                        // step-end: on for the first half of the cycle.
                        opacity: _cursor.value < 0.5 ? 1 : 0,
                        child: SizedBox(
                          width: 1.5,
                          height: 16,
                          child: ColoredBox(color: book.lime),
                        ),
                      ),
                ),
              ),
            ),
          if (_hasText && !focused)
            Positioned.fill(
              child: Semantics(
                label:
                    sats != null && widget.isValid
                        ? l10n.invoiceFilledSemantics(formatInvoiceSats(sats))
                        : _filledLabel(l10n),
                excludeSemantics: true,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.focusNode.requestFocus,
                  onLongPress: () => _showWhole(l10n),
                  child: ColoredBox(
                    color: pal.textareaFill,
                    // A painted mask over the editable, not a second text
                    // widget: the field keeps one text value, and the
                    // Semantics above says what it holds.
                    child: RichText(
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textScaler: MediaQuery.textScalerOf(context),
                      text: TextSpan(
                        text: widget.controller.text,
                        style: _kTextStyle.copyWith(color: book.textStrong),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actions(AppLocalizations l10n, InvoicePalette pal) {
    final paste = widget.onPaste;
    final scan = _FieldAction(
      icon: Icons.qr_code_scanner,
      label: l10n.invoiceScanButton,
      fill: pal.fieldActionFill,
      border: pal.fieldActionBorder,
      ink: pal.fieldActionInk,
      iconColor: pal.fieldActionIcon,
      onPressed: widget.onScan,
    ).withAutomationId(AutomationIds.invoiceScan);
    if (paste == null) return scan;
    final pasteButton = (_hasText
            ? _FieldAction(
              icon: Icons.content_paste,
              label: l10n.invoiceReplaceButton,
              fill: pal.fieldActionFill,
              border: pal.fieldActionBorder,
              ink: pal.fieldActionInk,
              iconColor: pal.fieldActionIcon,
              onPressed: paste,
            )
            : _FieldAction(
              icon: Icons.content_paste,
              label: l10n.pasteButtonLabel,
              fill: pal.pasteFill,
              border: pal.pasteBorder,
              ink: pal.validInk,
              iconColor: pal.validIcon,
              onPressed: paste,
            ))
        .withAutomationId(AutomationIds.invoicePaste);
    return Row(
      children: [
        Expanded(child: pasteButton),
        const SizedBox(width: 8),
        Expanded(child: scan),
      ],
    );
  }
}

/// A labelled action of the row under the field.
class _FieldAction extends StatelessWidget {
  const _FieldAction({
    required this.icon,
    required this.label,
    required this.fill,
    required this.border,
    required this.ink,
    required this.iconColor,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color fill;
  final Color border;
  final Color ink;
  final Color iconColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: border),
    );
    return Material(
      color: fill,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _kHitTarget),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: iconColor),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
