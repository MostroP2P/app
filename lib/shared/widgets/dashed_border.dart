import 'package:flutter/material.dart';

/// The redesign's dashed outline: `+ Agregar` affordances draw a 4/3 dash on
/// a rounded rect, and `radius: null` rounds it into a pill.
///
/// One painter for every caller — the create-order chip, `Agregar nodo
/// propio` and `Agregar relay` — so the dash rhythm cannot drift between
/// three copies of the same 4/3 loop.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({required this.color, this.radius = 16});

  final Color color;

  /// Corner radius, or null for a pill (half the painted height).
  final double? radius;

  static const _dash = 4.0;
  static const _gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    final path =
        Path()..addRRect(
          RRect.fromRectAndRadius(
            (Offset.zero & size).deflate(0.5),
            Radius.circular(radius ?? size.height / 2),
          ),
        );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
