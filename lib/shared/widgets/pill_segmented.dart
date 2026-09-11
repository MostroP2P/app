import 'package:flutter/material.dart';

import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/order_book_palette.dart';

/// How long the active tint takes to move to the tapped segment.
const kPillSegmentedSwitchDuration = Duration(milliseconds: 180);

/// One option of a [PillSegmented].
class PillSegment<T> {
  const PillSegment({
    required this.value,
    required this.label,
    this.automationId,
    this.enabled = true,
  });

  final T value;
  final String label;

  /// Stable identifier for black-box drivers; see `AutomationIds`.
  final String? automationId;

  /// A disabled segment is shown faded and ignores taps — the way "Fixed"
  /// is locked while a range order is being written.
  final bool enabled;
}

/// Colours of the selected segment.
class PillActiveStyle {
  const PillActiveStyle({
    required this.fill,
    required this.border,
    required this.ink,
  });

  final Color fill;
  final Color border;
  final Color ink;
}

/// Two sizes from the handoff: the full-width `Buy BTC | Sell BTC` control
/// and the compact `Single | Range` / `Market | Fixed` one inside cards.
enum PillSegmentedSize { large, small }

/// Pill-shaped segmented control with every option always visible, so the
/// user never has to work out whether the word shown is the current state or
/// the one a tap would activate (the flaw of the switches it replaces).
///
/// The active tint moves to the tapped segment in
/// [kPillSegmentedSwitchDuration]. Both states carry the 1px border
/// (transparent when inactive) so switching does not shift the height.
class PillSegmented<T> extends StatelessWidget {
  const PillSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
    this.size = PillSegmentedSize.large,
    this.activeStyleOf,
  });

  final List<PillSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelected;
  final PillSegmentedSize size;

  /// Active colours per value. Defaults to the lime tint; the Sell tab of
  /// the create-order screen passes its coral one.
  final PillActiveStyle Function(T value)? activeStyleOf;

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final isLarge = size == PillSegmentedSize.large;
    final gap = isLarge ? 4.0 : 3.0;
    final defaultStyle = PillActiveStyle(
      fill: palette.tabActiveFill,
      border: palette.tabActiveBorder,
      ink: palette.limeInk,
    );

    final children = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (i > 0) children.add(SizedBox(width: gap));
      Widget tab = _PillTab(
        label: segment.label,
        isSelected: segment.value == selected,
        enabled: segment.enabled,
        size: size,
        activeStyle: activeStyleOf?.call(segment.value) ?? defaultStyle,
        inactiveInk: palette.textSecondary,
        onTap: () => onSelected(segment.value),
      );
      if (segment.automationId != null) {
        tab = tab.withAutomationId(segment.automationId!);
      }
      children.add(isLarge ? Expanded(child: tab) : tab);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.tabTrack,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: EdgeInsets.all(gap),
        child: Row(
          mainAxisSize: isLarge ? MainAxisSize.max : MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  const _PillTab({
    required this.label,
    required this.isSelected,
    required this.enabled,
    required this.size,
    required this.activeStyle,
    required this.inactiveInk,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool enabled;
  final PillSegmentedSize size;
  final PillActiveStyle activeStyle;
  final Color inactiveInk;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(999));
    final isLarge = size == PillSegmentedSize.large;
    final padding = isLarge
        ? const EdgeInsets.symmetric(vertical: 9, horizontal: 8)
        : const EdgeInsets.symmetric(vertical: 5, horizontal: 11);

    return Semantics(
      selected: isSelected,
      enabled: enabled,
      inMutuallyExclusiveGroup: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        // The fill sits under the Material and the InkWell on it, so the
        // ripple paints over the active tint instead of beneath it.
        child: AnimatedContainer(
          duration: kPillSegmentedSwitchDuration,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isSelected ? activeStyle.fill : Colors.transparent,
            borderRadius: radius,
            border: Border.all(
              color: isSelected ? activeStyle.border : Colors.transparent,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: radius,
              child: Padding(
                padding: padding,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: isLarge ? 13 : 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? activeStyle.ink : inactiveInk,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
