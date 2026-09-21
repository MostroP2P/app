/// The one dialog and the one bottom sheet the app asks a question with.
///
/// Before these existed every modal styled itself: six corner radii, five CTA
/// colours, four button heights and three scrims across 29 modals (#534). The
/// geometry lives here rather than in a global button theme so it applies to
/// modal actions only — an in-page button keeps its own size.
///
/// Both surfaces take the same [ModalAction] pair, so a question asked in a
/// dialog and the same question asked in a sheet answer with the same buttons.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

// Re-exports OrderBookPalette, the redesign's surfaces and accent.
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';

/// How much weight an action carries, which is all a caller gets to choose.
enum ModalTone {
  /// The ordinary confirm: accent fill, dark ink.
  normal,

  /// Confirms something that cannot be undone (cancel a trade, open a
  /// dispute, delete a node): red fill, dark ink.
  destructive,
}

/// One button in a modal's footer.
@immutable
class ModalAction {
  const ModalAction({
    required this.label,
    required this.onPressed,
    this.tone = ModalTone.normal,
    this.busy = false,
    this.automationId,
  });

  final String label;

  /// `null` disables the button — a form's confirm before it is valid.
  final VoidCallback? onPressed;

  final ModalTone tone;

  /// Replaces the label with a spinner and blocks the press, for an action
  /// that reaches the daemon before the modal closes.
  final bool busy;

  /// Automation identifier, applied to the button itself so the driver reads
  /// its label and enabled state (see `docs/automation-contract.md`).
  final String? automationId;
}

/// A low-emphasis action that reads as a link, not a button: "view policy",
/// "clear". Rendered above the footer row, never as the answer to the modal's
/// question.
@immutable
class ModalLink {
  const ModalLink({
    required this.label,
    required this.onPressed,
    this.automationId,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? automationId;
}

/// Opens [MostroDialog] and resolves to what the action passed to
/// `Navigator.pop`.
Future<T?> showMostroDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: builder,
  );
}

/// Opens [MostroSheet] and resolves to what the action passed to
/// `Navigator.pop`.
///
/// Every bottom sheet in the app opens through here, so the scrim, the safe
/// area and the surface are decided once (#534).
///
/// [bare] is for the two sheets that are screens rather than questions — the
/// node selector and the backup invitation. They paint their own backdrop,
/// so the route gives them a transparent one; they still take this scrim and
/// this safe area.
Future<T?> showMostroSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool bare = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    backgroundColor: bare ? Colors.transparent : null,
    elevation: bare ? 0 : null,
    builder: builder,
  );
}

/// The app's dialog: centred card, optional icon, title, body, footer.
///
/// Surface, radius and scrim come from `dialogTheme`, so this widget only
/// owns what a theme cannot express — the layout and the footer.
class MostroDialog extends StatelessWidget {
  const MostroDialog({
    super.key,
    required this.title,
    this.body,
    this.content,
    this.icon,
    this.iconTone = ModalTone.normal,
    this.primary,
    this.secondary,
    this.links = const [],
  }) : assert(
         body == null || content == null,
         'Pass body for prose or content for a custom child, not both.',
       );

  final String title;

  /// The question's prose. Centred under the title when there is an [icon].
  final String? body;

  /// An arbitrary child in place of [body] — a text field, a list of values.
  final Widget? content;

  final IconData? icon;
  final ModalTone iconTone;

  /// The answer. Right-hand button, or the only one.
  final ModalAction? primary;

  /// The way out. Left-hand button; omit it when the barrier is the way out.
  final ModalAction? secondary;

  final List<ModalLink> links;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final centred = icon != null;
    final footer = ModalFooter(
      primary: primary,
      secondary: secondary,
      links: links,
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              centred ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
          children: [
            // The content scrolls and the footer does not: long localized
            // prose, a large text scale or an open keyboard must never push
            // the answer off the screen (#534).
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      centred
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.stretch,
                  children: [
                    if (icon case final glyph?) ...[
                      Icon(glyph, size: 44, color: _fillOf(book, iconTone)),
                      const SizedBox(height: 14),
                    ],
                    Text(
                      title,
                      textAlign: centred ? TextAlign.center : TextAlign.start,
                      style: TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: book.textPrimary,
                      ),
                    ),
                    if (body case final prose?) ...[
                      const SizedBox(height: 10),
                      Text(
                        prose,
                        textAlign:
                            centred ? TextAlign.center : TextAlign.start,
                        style: TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 14,
                          height: 1.5,
                          color: book.textSecondary,
                        ),
                      ),
                    ],
                    if (content case final child?) ...[
                      const SizedBox(height: 14),
                      child,
                    ],
                  ],
                ),
              ),
            ),
            if (!footer._isEmpty) ...[const SizedBox(height: 20), footer],
          ],
        ),
      ),
    );
  }
}

/// The app's bottom sheet: grabber, title, body, footer — the dialog's
/// content on a surface that rises from the bottom edge.
class MostroSheet extends StatelessWidget {
  const MostroSheet({
    super.key,
    required this.title,
    this.body,
    this.content,
    this.primary,
    this.secondary,
    this.links = const [],
  }) : assert(
         body == null || content == null,
         'Pass body for prose or content for a custom child, not both.',
       );

  final String title;
  final String? body;
  final Widget? content;
  final ModalAction? primary;
  final ModalAction? secondary;
  final List<ModalLink> links;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final footer = ModalFooter(
      primary: primary,
      secondary: secondary,
      links: links,
    );

    return SafeArea(
      child: Padding(
        // The sheet is scroll-controlled, so nothing lifts it off the
        // keyboard but this inset.
        padding: EdgeInsets.fromLTRB(
          18,
          10,
          18,
          14 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: book.divider,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            // As in the dialog: the content scrolls, the answer stays put.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: book.textPrimary,
                      ),
                    ),
                    if (body case final prose?) ...[
                      const SizedBox(height: 10),
                      Text(
                        prose,
                        style: TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 14,
                          height: 1.5,
                          color: book.textSecondary,
                        ),
                      ),
                    ],
                    if (content case final child?) ...[
                      const SizedBox(height: 14),
                      child,
                    ],
                  ],
                ),
              ),
            ),
            if (!footer._isEmpty) ...[const SizedBox(height: 20), footer],
          ],
        ),
      ),
    );
  }
}

/// The footer both surfaces share: the links, then the button row.
///
/// Two actions split the row evenly, with the answer on the right — the side
/// the thumb reaches and the side Material puts it on. One action fills the
/// row. A label too long for half the row stacks the pair instead of
/// shrinking the text, so a German or French confirm stays readable.
class ModalFooter extends StatelessWidget {
  const ModalFooter({
    super.key,
    this.primary,
    this.secondary,
    this.links = const [],
  });

  final ModalAction? primary;
  final ModalAction? secondary;
  final List<ModalLink> links;

  /// Horizontal room a button spends before its label starts — twice
  /// [_actionPadding], the value both buttons below are built with. It has to
  /// be the real number: guessing it low makes the footer keep a pair on one
  /// row whose labels then wrap inside the buttons.
  static const double _labelInset = _actionPadding * 2;

  /// Nothing to render: a picker answers by tapping one of its rows, so it
  /// passes no action at all and the gap above the footer is not spent.
  bool get _isEmpty => primary == null && secondary == null && links.isEmpty;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);

    final linkRow =
        links.isEmpty
            ? null
            : Wrap(
              spacing: 4,
              children: [
                for (final link in links)
                  _withId(
                    TextButton(
                      onPressed: link.onPressed,
                      style: TextButton.styleFrom(
                        foregroundColor: book.limeText,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      child: Text(link.label),
                    ),
                    link.automationId,
                  ),
              ],
            );

    final buttons = <Widget>[
      if (secondary case final action?) _SecondaryButton(action: action),
      if (primary case final action?) _PrimaryButton(action: action),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (linkRow != null) ...[linkRow, const SizedBox(height: 6)],
        if (buttons.length < 2)
          ...buttons
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final half = (constraints.maxWidth - 10) / 2;
              final scaler = MediaQuery.textScalerOf(context);
              final widest = math.max(
                _labelWidth(secondary!.label, _secondaryTextStyle, scaler),
                _labelWidth(primary!.label, _primaryTextStyle, scaler),
              );
              if (widest + _labelInset <= half) {
                return Row(
                  children: [
                    Expanded(child: buttons[0]),
                    const SizedBox(width: 10),
                    Expanded(child: buttons[1]),
                  ],
                );
              }
              // Neither label fits beside the other: stack, the answer on
              // top where the eye lands first. Better a taller footer than a
              // truncated verb — German and French confirms are long, and a
              // reader who scaled their text up needs this too.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buttons[1],
                  const SizedBox(height: 8),
                  buttons[0],
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Height of every modal action — one number, so a dialog's footer and a
/// sheet's footer are the same shape.
const double _actionHeight = 48;

/// Horizontal padding inside an action. Material's default for these buttons
/// is 24, which costs 48 of a 131 px half-row on a 360 px phone and wraps
/// ordinary labels like "Yes, cancel"; the footer already guarantees the
/// height, so the padding only has to keep the label off the edge.
const double _actionPadding = 12;

const _primaryTextStyle = TextStyle(
  fontFamily: AppFonts.ui,
  fontSize: 15,
  fontWeight: FontWeight.w600,
);

const _secondaryTextStyle = TextStyle(
  fontFamily: AppFonts.ui,
  fontSize: 15,
  fontWeight: FontWeight.w500,
);

/// Width [text] needs on one line, at the reader's text scale.
double _labelWidth(String text, TextStyle style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  return painter.width;
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.action});

  final ModalAction action;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final fill = _fillOf(book, action.tone);
    final ink = _inkOf(book, action.tone);

    return _withId(
      FilledButton(
        onPressed: action.busy ? null : action.onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: ink,
          disabledBackgroundColor: fill.withValues(alpha: 0.35),
          disabledForegroundColor: ink.withValues(alpha: 0.6),
          minimumSize: const Size.fromHeight(_actionHeight),
          padding: const EdgeInsets.symmetric(horizontal: _actionPadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.cta),
          ),
          textStyle: _primaryTextStyle,
        ),
        child:
            action.busy
                ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: ink),
                )
                : Text(action.label),
      ),
      action.automationId,
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.action});

  final ModalAction action;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);

    return _withId(
      OutlinedButton(
        onPressed: action.busy ? null : action.onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: book.textBody,
          side: BorderSide(color: book.border),
          minimumSize: const Size.fromHeight(_actionHeight),
          padding: const EdgeInsets.symmetric(horizontal: _actionPadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.cta),
          ),
          textStyle: _secondaryTextStyle,
        ),
        child: Text(action.label),
      ),
      action.automationId,
    );
  }
}

Color _fillOf(OrderBookPalette book, ModalTone tone) => switch (tone) {
  ModalTone.normal => book.lime,
  ModalTone.destructive => book.sell,
};

Color _inkOf(OrderBookPalette book, ModalTone tone) => switch (tone) {
  ModalTone.normal => book.onLime,
  ModalTone.destructive => book.onSell,
};

Widget _withId(Widget child, String? id) =>
    id == null ? child : child.withAutomationId(id);
