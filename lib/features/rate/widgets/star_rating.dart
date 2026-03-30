import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';

/// Interactive 5-star rating selector.
///
/// Renders 5 tappable [Icon] widgets.  Filled stars use [AppColors.mostroGreen]
/// (`#8CC63F`); empty stars use a dark-gray outline.  Tapping a star sets the
/// rating to that star's index + 1 (1-based).
///
/// The [onChanged] callback is invoked with the new score whenever the user
/// taps a star.  The widget is read-only when [onChanged] is null.
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.rating,
    this.onChanged,
    this.starSize = 40.0,
  }) : assert(rating >= 0 && rating <= 5);

  /// Current rating value (0 = none selected, 1–5 = star count).
  final int rating;

  /// Called with the new score when the user taps a star.
  /// Pass `null` to make the widget read-only.
  final ValueChanged<int>? onChanged;

  /// Diameter of each star icon in logical pixels.
  final double starSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final filledColor = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    const emptyColor = Color(0xFF4A4A4A);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final isFilled = index < rating;
        final starNumber = index + 1;
        return IconButton(
          onPressed: onChanged == null ? null : () => onChanged!(starNumber),
          tooltip: 'Select $starNumber star${starNumber == 1 ? '' : 's'}',
          padding: const EdgeInsets.symmetric(horizontal: 4),
          constraints: BoxConstraints(minWidth: starSize + 8, minHeight: starSize + 8),
          icon: Icon(
            isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
            color: isFilled ? filledColor : emptyColor,
            size: starSize,
          ),
        );
      }),
    );
  }
}
