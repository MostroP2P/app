import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_detail_palette.dart';
import 'package:mostro/features/order/models/order_detail_rules.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';

/// Building blocks shared by the maker's own-order screen (handoff 6a) and
/// the take-order screen (handoff 7a): the surface card, the currency chip,
/// the data card with its `label → value` rows, the copyable id row, the
/// action bar and the amount figure that shrinks before it wraps.

const _cardRadius = BorderRadius.all(Radius.circular(18));

/// Vertical gap between the blocks of both screens.
const double orderDetailBlockGap = 12;

/// Side padding of both screens — the redesign's, shared with the settings
/// screens so the two cannot drift.
const double orderDetailSidePadding = redesignSidePadding;

// ── Surface ───────────────────────────────────────────────────────────────────

/// A block on the page: surface fill, hairline border, radius 18.
class OrderDetailCard extends StatelessWidget {
  const OrderDetailCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: _cardRadius,
        border: Border.all(color: book.border),
      ),
      child: child,
    );
  }
}

// ── Currency chip ─────────────────────────────────────────────────────────────

/// Flag + code, identical to the order-book card's chip.
class OrderCurrencyChip extends StatelessWidget {
  const OrderCurrencyChip({super.key, required this.flag, required this.code});

  final String flag;
  final String code;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
      decoration: BoxDecoration(
        color: book.currencyChipFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (flag.isNotEmpty) ...[
            Text(flag, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
          ],
          Text(
            code,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: book.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Amount figure ─────────────────────────────────────────────────────────────

/// The fiat amount in Manrope 34. A range that does not fit at 34 drops to
/// 28 before the line is allowed to break; it is never truncated.
class OrderAmountFigure extends StatelessWidget {
  const OrderAmountFigure({super.key, required this.text});

  final String text;

  static const double _full = 34;
  static const double _compact = 28;

  TextStyle _style(double size, Color color) => TextStyle(
    fontFamily: AppFonts.figures,
    fontSize: size,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.02 * size,
    height: 1,
    color: color,
  );

  @override
  Widget build(BuildContext context) {
    final color = OrderBookPalette.of(context).textPrimary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: _style(_full, color)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final fits = painter.width <= constraints.maxWidth;
        painter.dispose();
        return Text(text, style: _style(fits ? _full : _compact, color));
      },
    );
  }
}

// ── Data card ─────────────────────────────────────────────────────────────────

/// Stacked `label → value` rows separated by hairlines (handoff 6a §3).
class OrderDataCard extends StatelessWidget {
  const OrderDataCard({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final pal = OrderDetailPalette.of(context);
    return OrderDetailCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Divider(height: 1, thickness: 1, color: pal.rowDivider),
          ],
        ],
      ),
    );
  }
}

/// One row of the data card: icon, label, and the value flush right.
class OrderDataRow extends StatelessWidget {
  const OrderDataRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Widget value;

  /// When set, the whole row is the tap target.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 16, color: book.textTertiary),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: book.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: value,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    // A custom tappable is announced as a button (DS-A11Y-1); its label is
    // still the row's own text, and the automation ids inside it stay.
    return Semantics(
      button: true,
      enabled: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: row,
      ),
    );
  }
}

/// Plain value text of a data row (DS-CMP-24): in the figures face when
/// [figures] (an amount or a count), with [trailing] — something said about
/// the value, like the counterpart's reputation — after it.
class OrderDataValue extends StatelessWidget {
  const OrderDataValue(
    this.text, {
    super.key,
    this.figures = false,
    this.trailing,
  });

  final String text;
  final bool figures;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final value = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: TextStyle(
        fontFamily: figures ? AppFonts.figures : null,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: book.textStrong,
      ),
    );
    final aside = trailing;
    if (aside == null) return value;
    // Value and note share the room and each ellipsizes past its half, so
    // a long note (or a large text scale) never pushes the row out of its
    // card, and the reputation stays in view beside a long name.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: value),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            aside,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.figures,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: book.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Payment methods row ───────────────────────────────────────────────────────

/// `Mercado Pago, Transferencia`, or `Mercado Pago +2` when the order
/// accepts more than two — tapping the row then lists them in a sheet.
class OrderPaymentMethodsRow extends StatelessWidget {
  const OrderPaymentMethodsRow({
    super.key,
    required this.label,
    required this.paymentMethod,
  });

  final String label;
  final String paymentMethod;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = paymentMethodsSummary(paymentMethod);
    final text =
        summary.hidden > 0
            ? l10n.paymentMethodsMore(summary.shown.first, summary.hidden)
            : summary.shown.join(', ');
    return OrderDataRow(
      icon: Icons.credit_card_outlined,
      label: label,
      value: OrderDataValue(text),
      onTap:
          summary.hidden > 0
              ? () => _showMethodsSheet(context, summary.all)
              : null,
    );
  }

  Future<void> _showMethodsSheet(BuildContext context, List<String> methods) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return showMostroSheet<void>(
      context: context,
      builder:
          (_) => MostroSheet(
            title: l10n.paymentMethodsSheetTitle,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final method in methods)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      method,
                      style: TextStyle(fontSize: 14, color: book.textBody),
                    ),
                  ),
              ],
            ),
          ),
    );
  }
}

// ── Order id row ──────────────────────────────────────────────────────────────

/// `09150348…99b5` with a copy icon; the whole row copies the full id. The
/// reference of DS-CMP-22, and the ID row of every data card (DS-CMP-24).
/// At least 48 high, the minimum target (DS-CMP-6).
class OrderIdRow extends StatelessWidget {
  const OrderIdRow({
    super.key,
    required this.orderId,
    this.automationId = AutomationIds.orderId,
  });

  final String orderId;

  /// The readout carrying the full id, which each screen names its own.
  final String automationId;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      hint: l10n.copyOrderIdTooltip,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: OrderDataRow(
          icon: Icons.link_rounded,
          label: l10n.orderDetailIdLabel,
          onTap: () => copyOrderId(context, orderId),
          value: OrderIdValue(
            orderId: orderId,
            color: book.textMuted,
            automationId: automationId,
          ),
        ),
      ),
    );
  }
}

/// The value side of an id row (DS-CMP-22): the short id in figures and the
/// copy icon. The readout under [automationId] carries the full id.
class OrderIdValue extends StatelessWidget {
  const OrderIdValue({
    super.key,
    required this.orderId,
    required this.color,
    this.automationId = AutomationIds.orderId,
  });

  final String orderId;
  final Color color;
  final String automationId;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            shortOrderId(orderId),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.figures,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ).withAutomationId(automationId, label: orderId),
        ),
        const SizedBox(width: 8),
        Icon(Icons.copy_rounded, size: 16, color: book.limeIcon),
      ],
    );
  }
}

/// Copies the full [orderId] and confirms it (DS-CMP-22, DS-CMP-15).
void copyOrderId(BuildContext context, String orderId) {
  Clipboard.setData(ClipboardData(text: orderId));
  HapticFeedback.selectionClick();
  showOrderDetailSnackBar(context, AppLocalizations.of(context).orderIdCopied);
}

/// The screens' snackbar: surface fill, radius 12, two seconds.
void showOrderDetailSnackBar(BuildContext context, String text) {
  final book = OrderBookPalette.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text, style: TextStyle(color: book.textStrong)),
        backgroundColor: book.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
}

// ── Action bar ────────────────────────────────────────────────────────────────

/// The bar pinned under the page: nav surface, hairline on top, padding
/// 12 / 18 / 18, safe area below.
class OrderDetailActionBar extends StatelessWidget {
  const OrderDetailActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: book.surfaceNav,
        border: Border(top: BorderSide(color: book.navBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: child,
        ),
      ),
    );
  }
}

/// The filled lime button both screens end on (`Close` / `Take order`).
class OrderPrimaryButton extends StatelessWidget {
  const OrderPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.verticalPadding = 14,
  });

  final String label;
  final VoidCallback? onPressed;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = OrderDetailPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: onPressed != null ? pal.ctaShadow : const [],
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: book.lime,
          foregroundColor: book.onLime,
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontFamily: AppFonts.ui,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        // One line, shrunk to fit at large text sizes, rather than
        // breaking the word.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1),
        ),
      ),
    );
  }
}

/// App bar of both screens: the redesign's shared bar, with an optional
/// trailing widget flush right.
PreferredSizeWidget orderDetailAppBar(
  BuildContext context, {
  required String title,
  required VoidCallback onBack,
  Widget? trailing,
}) => redesignAppBar(
  context,
  title: title,
  onBack: onBack,
  actions:
      trailing == null
          ? const []
          : [
            Padding(
              padding: const EdgeInsets.only(right: orderDetailSidePadding),
              child: trailing,
            ),
          ],
);

// ── Text helpers ──────────────────────────────────────────────────────────────

/// Spans for a localized [sentence] with one [figure] set in its own style.
///
/// One sentence with a placeholder rather than a prefix glued to the figure,
/// so a locale can put the figure wherever its word order needs; the styled
/// run is found by splitting around it. A translation that drops the
/// placeholder still reads, just unstyled.
List<InlineSpan> figureSpans(
  String sentence,
  String figure,
  TextStyle figureStyle,
) {
  final at = sentence.indexOf(figure);
  if (at < 0) return [TextSpan(text: sentence)];
  return [
    TextSpan(text: sentence.substring(0, at)),
    TextSpan(text: figure, style: figureStyle),
    TextSpan(text: sentence.substring(at + figure.length)),
  ];
}

/// `3m ago` — the order book's relative time, from the injectable clock.
String orderRelativeTime(AppLocalizations l10n, DateTime dt) {
  final diff = clock.now().difference(dt);
  if (diff.isNegative || diff.inMinutes < 1) return l10n.justNow;
  if (diff.inMinutes < 60) return l10n.minutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.hoursAgo(diff.inHours);
  return l10n.daysAgo(diff.inDays);
}
