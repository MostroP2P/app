import 'package:flutter/material.dart';

/// Rail of the premium slider: a 4px track filled **from the zero mark** to
/// the thumb, with a 1×10 tick at 0%. Colours come from the [SliderThemeData]
/// — `activeTrackColor` is the fill, `inactiveTrackColor` the rail.
class PremiumTrackShape extends SliderTrackShape {
  const PremiumTrackShape({
    required this.zeroFraction,
    required this.zeroMarkColor,
    required this.showFill,
  });

  /// Where 0% sits on the rail, 0…1 from the left.
  final double zeroFraction;
  final Color zeroMarkColor;

  /// False at exactly 0%, where the handoff wants no coloured fill at all.
  final bool showFill;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4;
    final thumbWidth =
        sliderTheme.thumbShape?.getPreferredSize(isEnabled, isDiscrete).width ??
            0;
    final trackLeft = offset.dx + thumbWidth / 2;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width - thumbWidth;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final canvas = context.canvas;
    final radius = Radius.circular(rect.height / 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = sliderTheme.inactiveTrackColor ?? Colors.white24,
    );

    final zeroX = rect.left + rect.width * zeroFraction;
    if (showFill) {
      final from = zeroX < thumbCenter.dx ? zeroX : thumbCenter.dx;
      final to = zeroX < thumbCenter.dx ? thumbCenter.dx : zeroX;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(from, rect.top, to, rect.bottom),
          radius,
        ),
        Paint()..color = sliderTheme.activeTrackColor ?? Colors.white,
      );
    }

    canvas.drawRect(
      Rect.fromCenter(center: Offset(zeroX, rect.center.dy), width: 1, height: 10),
      Paint()..color = zeroMarkColor,
    );
  }
}

/// 16dp knob with a 4dp halo at 18% of its colour; grows to 18dp while
/// dragged. No Material overlay.
class PremiumThumbShape extends SliderComponentShape {
  const PremiumThumbShape();

  static const _restRadius = 8.0;
  static const _dragRadius = 9.0;
  static const _halo = 4.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square((_dragRadius + _halo) * 2);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final color = sliderTheme.thumbColor ?? Colors.white;
    final radius = _restRadius +
        (_dragRadius - _restRadius) * activationAnimation.value;
    canvas.drawCircle(
      center,
      radius + _halo,
      Paint()..color = color.withValues(alpha: 0.18),
    );
    canvas.drawCircle(center, radius, Paint()..color = color);
  }
}
