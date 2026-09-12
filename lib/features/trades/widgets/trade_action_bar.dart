import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/trade_palette.dart';
import 'package:mostro/shared/widgets/mostro_reactive_button.dart';

/// The one lime button of the action bar.
class TradePrimarySpec {
  const TradePrimarySpec({
    required this.label,
    required this.automationId,
    this.icon,
    this.onPressed,
  });

  final String label;
  final String automationId;
  final IconData? icon;

  /// Null renders the button disabled (the rating with no star picked).
  final Future<void> Function()? onPressed;
}

/// A lower-hierarchy action: `Cancel` in outlined coral, the rest neutral.
class TradeSecondarySpec {
  const TradeSecondarySpec({
    required this.label,
    required this.automationId,
    required this.onPressed,
    this.isDestructive = false,
  });

  final String label;
  final String automationId;
  final Future<void> Function() onPressed;
  final bool isDestructive;
}

/// Pinned bar under the trade screen. The rule: when the user has something
/// to do there is one lime button; when they only wait there is none. Cancel
/// and dispute are never two red buttons of the same weight.
class TradeActionBar extends StatelessWidget {
  const TradeActionBar({
    super.key,
    this.primary,
    this.secondary = const [],
    this.closeLink,
    this.closeLabel,
    this.closeAutomationId,
  });

  final TradePrimarySpec? primary;
  final List<TradeSecondarySpec> secondary;

  /// `Close` as a text link under the primary action (8e, unrated).
  final VoidCallback? closeLink;
  final String? closeLabel;
  final String? closeAutomationId;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final trade = TradePalette.of(context);
    // A lone secondary (8a's `Cancel trade`) takes the primary's geometry.
    final secondaryAlone = primary == null && secondary.length == 1;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: book.surfaceNav,
        border: Border(top: BorderSide(color: book.navBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (primary != null) _PrimaryButton(spec: primary!),
              if (primary != null && secondary.isNotEmpty)
                const SizedBox(height: 10),
              if (secondary.isNotEmpty)
                Row(
                  children: [
                    for (var i = 0; i < secondary.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _SecondaryButton(
                          spec: secondary[i],
                          alone: secondaryAlone,
                          book: book,
                          trade: trade,
                        ),
                      ),
                    ],
                  ],
                ),
              if (closeLink != null) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: closeLink,
                  style: TextButton.styleFrom(
                    foregroundColor: book.textSecondary,
                    textStyle: const TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: Text(closeLabel ?? ''),
                ).withAutomationId(closeAutomationId ?? 'trade.close.link'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.spec});

  final TradePrimarySpec spec;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final trade = TradePalette.of(context);
    final enabled = spec.onPressed != null;
    final style = FilledButton.styleFrom(
      backgroundColor: book.lime,
      foregroundColor: book.onLime,
      disabledBackgroundColor: book.lime.withValues(alpha: 0.16),
      disabledForegroundColor: book.limeInk.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );

    final Widget button;
    if (enabled) {
      button = MostroReactiveButton(
        label: spec.label,
        icon: spec.icon,
        iconSize: 17,
        style: style,
        progressColor: book.onLime,
        onPressed: spec.onPressed!,
      );
    } else {
      button = FilledButton(
        onPressed: null,
        style: style,
        child: Text(spec.label),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled ? trade.ctaShadow : const [],
      ),
      child: button,
    ).withAutomationId(spec.automationId);
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.spec,
    required this.alone,
    required this.book,
    required this.trade,
  });

  final TradeSecondarySpec spec;
  final bool alone;
  final OrderBookPalette book;
  final TradePalette trade;

  @override
  Widget build(BuildContext context) {
    final ink = spec.isDestructive ? trade.cancelInk : trade.neutralInk;
    final border =
        spec.isDestructive ? trade.cancelBorder : trade.neutralBorder;
    return MostroReactiveButton(
      outlined: true,
      label: spec.label,
      onPressed: spec.onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: border),
        padding: EdgeInsets.symmetric(vertical: alone ? 14 : 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(alone ? 16 : 14),
        ),
        textStyle: TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: alone ? 15 : 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    ).withAutomationId(spec.automationId);
  }
}
