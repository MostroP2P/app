import 'package:flutter/material.dart';

/// Drag [child] downwards and it stretches like taffy, then springs back.
///
/// The drawer's Mostro is the biggest one in the app and the one people
/// linger on, so it answers a pull. The pull is read from a vertical drag
/// rather than from the scroll view's overscroll: the drawer only scrolls
/// when its content outgrows the panel, so on most screens there would be
/// no overscroll to listen to.
class MascotStretch extends StatefulWidget {
  const MascotStretch({
    super.key,
    required this.child,
    required this.height,
  });

  final Widget child;

  /// Height of the artwork, which sets how far a pull has to travel.
  final double height;

  /// How far it can be stretched, as a share of its own height.
  static const double maxStretch = 0.45;

  @override
  State<MascotStretch> createState() => _MascotStretchState();
}

class _MascotStretchState extends State<MascotStretch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _springBack = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..addListener(() => setState(() {}));

  /// 0 at rest, 1 fully stretched.
  double _pull = 0;

  /// The pull the release started from, so the spring runs from there.
  double _releasedFrom = 0;

  @override
  void dispose() {
    _springBack.dispose();
    super.dispose();
  }

  double get _stretch =>
      _springBack.isAnimating
          ? _releasedFrom * (1 - Curves.elasticOut.transform(_springBack.value))
          : _pull;

  void _onDragUpdate(DragUpdateDetails details) {
    // Only downward pulls stretch; the travel needed grows with the artwork.
    final travel = widget.height * 1.6;
    setState(() {
      _springBack.stop();
      _pull = (_pull + details.delta.dy / travel).clamp(0.0, 1.0);
    });
  }

  void _onDragEnd() {
    if (_pull == 0) return;
    _releasedFrom = _pull;
    _pull = 0;
    _springBack.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final pull = _stretch;
    final scaleY = 1 + MascotStretch.maxStretch * pull;
    // Taffy keeps its volume: what it gains in length it loses in width.
    final scaleX = 1 - MascotStretch.maxStretch * 0.42 * pull;

    return GestureDetector(
      // The artwork is a bolt with a lot of transparent margin, and deferring
      // the hit test to it would leave most of the box unpullable.
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: (_) => _onDragEnd(),
      onVerticalDragCancel: _onDragEnd,
      child: Transform(
        // Pinned at the top, so it hangs down the way a pulled thing does.
        alignment: Alignment.topCenter,
        transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
        child: widget.child,
      ),
    );
  }
}
