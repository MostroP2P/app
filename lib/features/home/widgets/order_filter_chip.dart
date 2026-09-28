import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// The funnel chip of the order-book filter row, which opens the filters.
///
/// It says whether the book is filtered. That did not matter while the
/// filters reset on every launch — the user had set them a minute earlier.
/// Now that they persist (issue #575), someone can open the app to a short
/// book, or an empty one, days after choosing them; a chip that looks the
/// same filtered or not would leave them to guess why.
///
/// Active, the outline turns lime and a badge counts the controls in use.
/// The outline is [OrderBookPalette.limeText], darkened in light mode so it
/// stays visible on white; the badge is the brand pair, [OrderBookPalette.lime]
/// under [OrderBookPalette.onLime], legible in both themes.
class OrderFilterChip extends StatelessWidget {
  const OrderFilterChip({
    super.key,
    required this.palette,
    required this.activeCount,
    required this.onTap,
  });

  final OrderBookPalette palette;

  /// How many of the four filters narrow the book; 0 draws the idle chip.
  final int activeCount;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = activeCount > 0;

    // One node, one label: the badge's bare digit would otherwise be read
    // on its own. Excluding the children drops the InkWell's tap action
    // with them, so the node carries it itself.
    return Semantics(
      button: true,
      label:
          active
              ? '${l10n.filterButtonLabel}, ${l10n.filtersActiveCount(activeCount)}'
              : l10n.filterButtonLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: palette.chipFill,
        shape: StadiumBorder(
          side: BorderSide(
            color: active ? palette.limeText : palette.chipBorder,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 7, active ? 7 : 12, 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.filter_alt_outlined,
                  size: 14,
                  color: palette.limeIcon,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    l10n.filterButtonLabel,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: palette.textStrong,
                    ),
                  ),
                ),
                if (active) ...[
                  const SizedBox(width: 6),
                  _CountBadge(palette: palette, count: activeCount),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.palette, required this.count});

  final OrderBookPalette palette;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.lime,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontFamily: AppFonts.figures,
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w700,
          color: palette.onLime,
        ),
      ),
    );
  }
}
