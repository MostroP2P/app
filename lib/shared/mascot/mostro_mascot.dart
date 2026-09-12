import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/mascot/mascot_season_badge.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';

/// The Mostro mascot, with a pulse.
///
/// Same artwork everywhere; only the motion changes. Reactions to a tap play
/// once and are over ([MostroMood.happy], [MostroMood.dizzy]); ambient moods
/// loop until they are replaced ([MostroMood.asleep],
/// [MostroMood.impatient]).
///
/// The loops are gated behind the viewer's reduce-motion setting. That is an
/// accessibility call first — decorative motion nobody asked for is exactly
/// what the setting is about — and it is also what keeps a looping mascot
/// from making widget tests that settle hang forever.
class MostroMascot extends StatefulWidget {
  const MostroMascot({
    super.key,
    required this.height,
    this.mood = MostroMood.neutral,
    this.interactive = false,
    this.opacity = 1,
    this.season,
  });

  final double height;

  /// The ambient mood. A tap reaction overrides it while it plays.
  final MostroMood mood;

  /// Whether tapping earns a reaction. Only the one in the order book's app
  /// bar does, which is where v1 put its easter egg.
  final bool interactive;

  final double opacity;

  /// Overrides the date. Null reads the clock, so the anniversaries arrive on
  /// their own.
  final MostroSeason? season;

  static const String asset = 'assets/images/mostro_mascot.webp';

  /// The artwork is 199 × 288.
  static const double aspect = 199 / 288;

  @override
  State<MostroMascot> createState() => _MostroMascotState();
}

class _MostroMascotState extends State<MostroMascot>
    with TickerProviderStateMixin {
  late final AnimationController _reactionPlayer = AnimationController(
    vsync: this,
  )..addStatusListener((status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _reaction = null);
    }
  });

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  /// The tap-driven mood, while it plays.
  MostroMood? _reaction;

  int _tapCount = 0;
  DateTime? _lastTap;

  MostroMood get _mood => _reaction ?? widget.mood;

  static Duration _durationOf(MostroMood mood) => switch (mood) {
    MostroMood.happy => const Duration(milliseconds: 480),
    MostroMood.dizzy => const Duration(milliseconds: 1100),
    MostroMood.celebrating => const Duration(milliseconds: 900),
    MostroMood.asleep => const Duration(milliseconds: 2800),
    MostroMood.impatient => const Duration(milliseconds: 760),
    MostroMood.neutral => Duration.zero,
  };

  @override
  void didUpdateWidget(MostroMascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _syncAmbient();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAmbient();
  }

  @override
  void dispose() {
    _reactionPlayer.dispose();
    _loop.dispose();
    super.dispose();
  }

  /// Whether the viewer asked for less motion. Read from [MediaQuery] so the
  /// OS setting reaches it, and so a test can turn the loops off.
  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _syncAmbient() {
    final ambient = widget.mood;
    if (isLoopingMood(ambient) && !_reduceMotion) {
      _loop.duration = _durationOf(ambient);
      if (!_loop.isAnimating) _loop.repeat();
    } else if (_loop.isAnimating) {
      _loop
        ..stop()
        ..value = 0;
    }
  }

  /// A one-shot mood that is playing has its own progress; a loop reads the
  /// looping controller; anything else is at rest.
  double get _t {
    if (_reaction != null) return _reactionPlayer.value;
    return isLoopingMood(widget.mood) ? _loop.value : 0;
  }

  MostroSeason get _season => widget.season ?? seasonOn(clock.now());

  void _onTap() {
    final now = clock.now();
    final count = nextTapCount(count: _tapCount, lastTap: _lastTap, now: now);
    _tapCount = count;
    _lastTap = now;

    final mood = moodForTaps(count);
    setState(() => _reaction = mood);
    _reactionPlayer
      ..duration = _durationOf(mood)
      ..forward(from: 0);

    if (mood == MostroMood.dizzy) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }

    // Once per streak, so insisting does not turn into a wall of snackbars.
    if (count == 1) _sayTheDate();
  }

  void _sayTheDate() {
    final message = seasonMessage(AppLocalizations.of(context), _season);
    if (message == null) return;
    final palette = OrderBookPalette.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: palette.textStrong)),
          backgroundColor: palette.surface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.height;
    final width = height * MostroMascot.aspect;

    final body = AnimatedBuilder(
      animation: Listenable.merge([_reactionPlayer, _loop]),
      builder: (context, child) {
        final mood = _mood;
        final t = _t;
        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              _posed(child!, mood, t, height, width),
              ..._flourishes(mood, t, height, width),
              MascotSeasonBadge(season: _season, mascotHeight: height),
            ],
          ),
        );
      },
      child: Image.asset(
        MostroMascot.asset,
        height: height,
        excludeFromSemantics: true,
      ),
    );

    final opaque =
        widget.opacity == 1
            ? body
            : Opacity(opacity: widget.opacity, child: body);

    if (!widget.interactive) return opaque;
    return GestureDetector(
      // Decorative on purpose: announcing it would give the egg away.
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: opaque,
    );
  }

  /// How the artwork itself sits, for [mood] at progress [t].
  Widget _posed(
    Widget image,
    MostroMood mood,
    double t,
    double height,
    double width,
  ) {
    final arc = math.sin(math.pi * t);
    final wave = math.sin(2 * math.pi * t);

    return switch (mood) {
      MostroMood.neutral => image,

      // A springy nod: up, over, and back.
      MostroMood.happy => Transform.rotate(
        angle: 0.12 * wave,
        child: Transform.scale(scale: 1 + 0.18 * arc, child: image),
      ),

      // Three wobbles that die down.
      MostroMood.dizzy => Transform.rotate(
        angle: 0.30 * math.sin(6 * math.pi * t) * (1 - t),
        child: Transform.scale(scale: 1 + 0.06 * arc, child: image),
      ),

      // A jump, with the squash that sells it.
      MostroMood.celebrating => Transform.translate(
        offset: Offset(0, -height * 0.28 * arc),
        child: Transform.scale(
          scaleX: 1 - 0.06 * arc,
          scaleY: 1 + 0.10 * arc,
          child: image,
        ),
      ),

      // Breathing.
      MostroMood.asleep => Transform.scale(
        scale: 1 + 0.035 * wave,
        child: image,
      ),

      // Foot to foot.
      MostroMood.impatient => Transform.translate(
        offset: Offset(width * 0.05 * wave, 0),
        child: Transform.rotate(angle: 0.05 * wave, child: image),
      ),
    };
  }

  /// What orbits, rises or bursts around the artwork.
  List<Widget> _flourishes(
    MostroMood mood,
    double t,
    double height,
    double width,
  ) {
    final fade = math.sin(math.pi * t).clamp(0.0, 1.0);
    return switch (mood) {
      MostroMood.dizzy => [
        _orbit(
          glyph: '✨',
          height: height,
          width: width,
          angle: 2 * math.pi * t,
          opacity: fade,
        ),
      ],
      MostroMood.celebrating => [
        _orbit(
          glyph: '✨',
          height: height,
          width: width,
          angle: 2 * math.pi * t,
          opacity: fade,
          spread: 0.45 + 0.55 * t,
        ),
      ],
      MostroMood.asleep => [_sleepZ(height, width, t)],
      _ => const [],
    };
  }

  /// Three glyphs going round the head, which sits up and to the left.
  Widget _orbit({
    required String glyph,
    required double height,
    required double width,
    required double angle,
    required double opacity,
    double spread = 1,
  }) {
    final size = height * 0.26;
    final rx = height * 0.34 * spread;
    final ry = height * 0.16 * spread;
    return Positioned(
      left: width * 0.36 - size / 2,
      top: -height * 0.10 - size / 2,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < 3; i++)
              Transform.translate(
                offset: Offset(
                  rx * math.cos(angle + i * 2 * math.pi / 3),
                  ry * math.sin(angle + i * 2 * math.pi / 3),
                ),
                child: Opacity(
                  opacity: opacity,
                  child: Text(
                    glyph,
                    style: TextStyle(fontSize: size, height: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A Z that drifts up and off.
  Widget _sleepZ(double height, double width, double t) {
    final size = height * 0.26;
    return Positioned(
      left: width * 0.58,
      top: -height * 0.04 - height * 0.34 * t,
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: Text(
          'Z',
          style: TextStyle(
            fontSize: size,
            height: 1,
            fontWeight: FontWeight.w700,
            color: OrderBookPalette.of(context).textSecondary,
          ),
        ),
      ),
    );
  }
}
