import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/walkthrough/walkthrough_slides.dart';

/// A walkthrough illustration: a dark disc with a gold ring, on a lime halo.
///
/// Every layer is a static SVG (flutter_svg runs no CSS animation and draws
/// no filters), and the motion of the handoff is played here: the ring draws
/// itself, the slide's drawing pops in, a blurred glint keeps running around
/// the ring, and a slide's [flow] line streams. With animations disabled the
/// art shows complete and nothing loops (DS-MOT-3).
///
/// The widget takes [size] in layout; the halo spreads beyond it, as the
/// handoff's `::before` does, without taking space.
///
/// Give each slide its own key, so a new slide replays the entrance.
class WalkthroughArt extends StatefulWidget {
  const WalkthroughArt({
    super.key,
    required this.asset,
    required this.size,
    this.flow,
    this.bolt,
  });

  /// The slide's drawing, laid over the disc.
  final String asset;

  /// Diameter of the disc's box.
  final double size;

  /// A dashed line streaming over [asset], under its front layer.
  final WalkthroughFlow? flow;

  /// A bolt drawn on top, flickering as the glint ends its run.
  final String? bolt;

  static const _glow = '$walkthroughArtDir/glow.svg';
  static const _disc = '$walkthroughArtDir/disc.svg';
  static const _ring = '$walkthroughArtDir/ring.svg';
  static const _glintHalo = '$walkthroughArtDir/glint_halo.svg';
  static const _glint = '$walkthroughArtDir/glint.svg';

  /// The layers every slide shares.
  static const frameAssets = [_glow, _disc, _ring, _glintHalo, _glint];

  /// The halo's diameter relative to the disc's box (224 to 184 in the
  /// handoff).
  static const glowScale = 224 / 184;

  @override
  State<WalkthroughArt> createState() => _WalkthroughArtState();
}

/// Side of the SVG view box every layer is drawn in.
const _viewBox = 240.0;

// The handoff's timing: the ring draws in 900 ms, the drawing pops in over
// 500 ms from 250 ms, and the glint circles once every 4.2 s, visible for the
// first 42% of each cycle.
const _entranceDuration = Duration(milliseconds: 1150);
const _glintPeriod = Duration(milliseconds: 4200);
const _ringEnd = 900 / 1150;
const _popStart = 250 / 1150;
const _popEnd = 750 / 1150;
const _glintTravel = 0.42;
const _glintFadeIn = 0.04;
const _glintFadeOut = 0.38;
const _popFromScale = 0.92;

/// The handoff blurs the glint's halo with `stdDeviation="3"`, in view-box
/// units.
const _glintBlur = 3.0;

// The flow line: `stroke-dasharray="4 6"`, width 2.5, its dashes advancing
// 20 units every 1.2 s, all inside the welcome drawing's 1.3x scale.
const _flowScale = 1.3;
const _flowDash = 4 * _flowScale;
const _flowGap = 6 * _flowScale;
const _flowWidth = 2.5 * _flowScale;
const _flowAdvance = 20 * _flowScale;
const _flowPeriod = Duration(milliseconds: 1200);

// The bolt's flicker (the handoff's `.zap`), on the glint's 4.2 s cycle: two
// dips in opacity, and a drop shadow that flares lime, then light lime, then
// dies away. Each track is (time, value); CSS eases between keyframes.
const _zapOpacity = [
  (0.0, 1.0),
  (0.34, 1.0),
  (0.36, 0.35),
  (0.38, 1.0),
  (0.40, 0.55),
  (0.43, 1.0),
  (1.0, 1.0),
];
const _zapGlow = [
  (0.0, 0.0),
  (0.34, 0.0),
  (0.38, 5.0),
  (0.43, 9.0),
  (0.55, 2.0),
  (1.0, 0.0),
];
const _zapShadowAlpha = [
  (0.0, 0.0),
  (0.34, 0.0),
  (0.38, 1.0),
  (0.55, 1.0),
  (1.0, 0.0),
];
const _zapLight = [
  (0.0, 0.0),
  (0.38, 0.0),
  (0.43, 1.0),
  (0.55, 0.0),
  (1.0, 0.0),
];

/// The bolt at [t] of the glint's cycle: its [opacity], the drop shadow's
/// blur radius ([glow], in view-box units) and alpha ([shadow]), and how far
/// the shadow has turned from lime to light lime ([light]).
@visibleForTesting
({double opacity, double glow, double shadow, double light}) zapAt(double t) =>
    (
      opacity: _track(_zapOpacity, t),
      glow: _track(_zapGlow, t),
      shadow: _track(_zapShadowAlpha, t),
      light: _track(_zapLight, t),
    );

double _track(List<(double, double)> keys, double t) {
  for (var i = 1; i < keys.length; i++) {
    final (t1, v1) = keys[i];
    if (t <= t1) {
      final (t0, v0) = keys[i - 1];
      final f = Curves.ease.transform((t - t0) / (t1 - t0));
      return v0 + (v1 - v0) * f;
    }
  }
  return keys.last.$2;
}

class _WalkthroughArtState extends State<WalkthroughArt>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: _entranceDuration,
  )..addStatusListener(_startGlint);
  late final AnimationController _glint = AnimationController(
    vsync: this,
    duration: _glintPeriod,
  );
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: _flowPeriod,
  );
  late final Animation<double> _ring = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0, _ringEnd, curve: Cubic(0.6, 0.1, 0.2, 1)),
  );
  late final Animation<double> _pop = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(_popStart, _popEnd, curve: Curves.easeOut),
  );
  late final Animation<double> _popScale = Tween<double>(
    begin: _popFromScale,
    end: 1,
  ).animate(_pop);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      _glint.stop();
      _flow.stop();
      _entrance.value = 1;
    } else {
      if (!_started) {
        _entrance.forward();
      } else if (_entrance.isCompleted && !_glint.isAnimating) {
        // Animations turned back on after the entrance: resume the loop.
        _glint.repeat();
      }
      if (widget.flow != null && !_flow.isAnimating) _flow.repeat();
    }
    _started = true;
  }

  void _startGlint(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    _glint.repeat();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _glint.dispose();
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final glowSize = size * WalkthroughArt.glowScale;
    final flow = widget.flow;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Positioned(
              left: (size - glowSize) / 2,
              top: (size - glowSize) / 2,
              width: glowSize,
              height: glowSize,
              child: SvgPicture.asset(WalkthroughArt._glow),
            ),
            SvgPicture.asset(WalkthroughArt._disc),
            AnimatedBuilder(
              animation: _ring,
              builder:
                  (_, ring) => ClipPath(
                    clipper: _SweepClipper(_ring.value),
                    child: ring,
                  ),
              child: SvgPicture.asset(WalkthroughArt._ring),
            ),
            // The glint repaints every frame of its loop: keep that to its
            // own layer.
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _glint,
                builder: _buildGlint,
                child: _GlintLayers(blur: _glintBlur * size / _viewBox),
              ),
            ),
            FadeTransition(
              opacity: _pop,
              child: ScaleTransition(
                scale: _popScale,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SvgPicture.asset(widget.asset),
                    if (flow != null) ...[
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: _FlowPainter(
                            flow: flow,
                            progress: _flow,
                            color: OrderBookPalette.of(context).lime,
                          ),
                        ),
                      ),
                      SvgPicture.asset(flow.front),
                    ],
                    if (widget.bolt case final bolt?)
                      RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _glint,
                          builder:
                              (_, __) => _Bolt(
                                asset: bolt,
                                // Steady unless the loop runs.
                                zap: zapAt(
                                  _glint.isAnimating ? _glint.value : 0,
                                ),
                                scale: size / _viewBox,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlint(BuildContext context, Widget? glint) {
    final t = _glint.value;
    if (!_glint.isAnimating || t >= _glintTravel) return const SizedBox();
    final opacity =
        t < _glintFadeIn
            ? t / _glintFadeIn
            : t > _glintFadeOut
            ? (_glintTravel - t) / (_glintTravel - _glintFadeOut)
            : 1.0;
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.rotate(
        angle: 2 * math.pi * t / _glintTravel,
        child: glint,
      ),
    );
  }
}

/// A bolt under its zap: faded by its opacity, over a blurred, tinted copy of
/// itself standing in for the handoff's `drop-shadow`.
class _Bolt extends StatelessWidget {
  const _Bolt({required this.asset, required this.zap, required this.scale});

  final String asset;
  final ({double opacity, double glow, double shadow, double light}) zap;

  /// Logical pixels per view-box unit.
  final double scale;

  @override
  Widget build(BuildContext context) {
    // The disc is dark in both themes, so its glow takes the dark inks.
    const palette = OrderBookPalette.dark;
    final color = Color.lerp(
      palette.lime,
      palette.limeIcon,
      zap.light,
    )!.withValues(alpha: zap.shadow);
    // A CSS blur radius is twice the Gaussian's sigma.
    final sigma = zap.glow / 2 * scale;
    return Opacity(
      opacity: zap.opacity.clamp(0.0, 1.0),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (sigma > 0 && zap.shadow > 0)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                child: SvgPicture.asset(asset),
              ),
            ),
          SvgPicture.asset(asset),
        ],
      ),
    );
  }
}

/// The glint: its soft halo, blurred as the handoff's `feGaussianBlur`, under
/// its bright core.
class _GlintLayers extends StatelessWidget {
  const _GlintLayers({required this.blur});

  /// Blur sigma in logical pixels.
  final double blur;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: SvgPicture.asset(WalkthroughArt._glintHalo),
      ),
      SvgPicture.asset(WalkthroughArt._glint),
    ],
  );
}

/// Draws [flow]'s dashes, shifted along the line by [progress] of one advance.
class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.flow,
    required this.progress,
    required this.color,
  }) : super(repaint: progress);

  final WalkthroughFlow flow;
  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _viewBox;
    canvas.scale(scale);
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = _flowWidth
          ..strokeCap = StrokeCap.round;
    final line = flow.to - flow.from;
    final length = line.distance;
    final direction = line / length;
    const period = _flowDash + _flowGap;
    final shift = (progress.value * _flowAdvance) % period;
    // Start one period early so a dash entering at [from] is drawn in part.
    for (var start = shift - period; start < length; start += period) {
      final a = math.max(start, 0.0);
      final b = math.min(start + _flowDash, length);
      if (b <= a) continue;
      canvas.drawLine(
        flow.from + direction * a,
        flow.from + direction * b,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.flow != flow || old.color != color || old.progress != progress;
}

/// Clips to a sector that opens clockwise from 12 o'clock, [progress] of a
/// full turn: drawn over the ring, it makes the ring draw itself.
class _SweepClipper extends CustomClipper<Path> {
  const _SweepClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    final box = Offset.zero & size;
    if (progress >= 1) return Path()..addRect(box);
    final center = box.center;
    // A circle around the box, so the sector covers its corners too.
    final radius = size.longestSide;
    return Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
      )
      ..close();
  }

  @override
  bool shouldReclip(_SweepClipper old) => old.progress != progress;
}
