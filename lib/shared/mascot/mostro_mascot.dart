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
/// At rest it is the plain artwork; a mood moves it and dresses it in that
/// mood's sticker ([moodSticker]), in the same box. Reactions to a tap play
/// once and are over ([MostroMood.happy], [MostroMood.dizzy], and every trade
/// step); ambient moods loop until they are replaced ([isLoopingMood]).
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

  /// Whether tapping earns a reaction. Only the one in the tabs' app bar
  /// ([HeaderMascot]) does: v1 put its easter egg in the order book's logo,
  /// and since #770 every tab shows that same header.
  final bool interactive;

  final double opacity;

  /// Overrides the date. Null reads the clock, so the anniversaries arrive on
  /// their own.
  final MostroSeason? season;

  static const String asset = 'assets/images/mostro_mascot.webp';

  /// The asset of the sticker named [name] (see [moodSticker]).
  static String stickerAsset(String name) =>
      'assets/images/mascot/mostro-$name.webp';

  /// How much taller than the box a sticker is drawn. Its arms, props and
  /// confetti surround the same body, so at the box's height the body would
  /// shrink; at this scale it stays the plain mascot's size, and the extra
  /// spills over the box without moving anything around it.
  static const double stickerScale = 1.2;

  /// The artwork is 199 × 288.
  static const double aspect = 199 / 288;

  /// Smallest side of the area a tap lands on (DS-CMP-6). The header's
  /// artwork is 18 × 26, so its target is padded out around it.
  static const double minTapTarget = 48;

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
    MostroMood.escrowLocked => const Duration(milliseconds: 600),
    MostroMood.fiatSent => const Duration(milliseconds: 600),
    MostroMood.disputed => const Duration(milliseconds: 900),
    MostroMood.canceled => const Duration(milliseconds: 1000),
    MostroMood.offline => const Duration(milliseconds: 1400),
    MostroMood.published => const Duration(milliseconds: 900),
    MostroMood.loved ||
    MostroMood.thankful => const Duration(milliseconds: 480),
    MostroMood.refused => const Duration(milliseconds: 900),
    MostroMood.greeting ||
    MostroMood.backedUp ||
    MostroMood.agreed => const Duration(milliseconds: 480),
    MostroMood.orderTaken ||
    MostroMood.invoiceAccepted => const Duration(milliseconds: 600),
    MostroMood.cancelAsked => const Duration(milliseconds: 600),
    MostroMood.laughing => const Duration(milliseconds: 1100),
    MostroMood.cool => const Duration(milliseconds: 700),
    MostroMood.onFire => const Duration(milliseconds: 900),
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
    if (!_stickersCached) {
      _stickersCached = true;
      // Decoded ahead, or the first switch to a mood draws one empty frame.
      final stickers =
          [
            for (final mood in MostroMood.values) moodSticker(mood),
            seasonSticker(_season),
          ].nonNulls;
      for (final sticker in stickers) {
        precacheImage(AssetImage(MostroMascot.stickerAsset(sticker)), context);
      }
    }
  }

  bool _stickersCached = false;

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

  /// Drives whatever [widget.mood] asks for.
  ///
  /// Ambient moods arrive from the parent rather than from a tap, so nothing
  /// else would ever start them: a looping one has to be told to repeat, and
  /// a one-shot one — celebrating — has to be played here or it renders at
  /// rest and is never seen.
  ///
  /// All of it is unsolicited motion, so all of it answers to reduce-motion.
  /// A tap reaction does not: the viewer asked for that one themselves.
  void _syncAmbient() {
    final ambient = widget.mood;
    if (_loop.isAnimating) {
      _loop
        ..stop()
        ..value = 0;
    }
    if (ambient == MostroMood.neutral || _reduceMotion) return;

    if (isLoopingMood(ambient)) {
      _loop.duration = _durationOf(ambient);
      _loop.repeat();
      return;
    }
    _reactionPlayer
      ..duration = _durationOf(ambient)
      ..forward(from: 0);
  }

  /// Progress of whatever is playing: the looping controller for a looping
  /// mood, the one-shot player for everything else that moves.
  double get _t {
    final mood = _mood;
    if (mood == MostroMood.neutral) return 0;
    return isLoopingMood(mood) ? _loop.value : _reactionPlayer.value;
  }

  MostroSeason get _season => widget.season ?? currentSeason(clock.now());

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

    if (mood == MostroMood.happy) {
      HapticFeedback.selectionClick();
    } else {
      HapticFeedback.mediumImpact();
    }

    // Once per streak, so insisting does not turn into a wall of snackbars.
    if (count == 1) _sayTheDate();
  }

  /// Held: shades on. Its own reaction, outside the tap streak.
  void _onLongPress() {
    setState(() => _reaction = MostroMood.cool);
    _reactionPlayer
      ..duration = _durationOf(MostroMood.cool)
      ..forward(from: 0);
    HapticFeedback.selectionClick();
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
              // A season with its own sticker wears it instead of a badge.
              if (seasonSticker(_season) == null)
                MascotSeasonBadge(season: _season, mascotHeight: height),
            ],
          ),
        );
      },
      child: _artwork(height),
    );

    final opaque =
        widget.opacity == 1
            ? body
            : Opacity(opacity: widget.opacity, child: body);

    // Decorative from top to bottom, so none of it reaches assistive tech:
    // the artwork carries no information, the glyphs that orbit it are
    // noise, and a tap target with no label would be worse than no target
    // at all. Announcing it would also give the egg away.
    if (!widget.interactive) return ExcludeSemantics(child: opaque);
    return ExcludeSemantics(
      child: GestureDetector(
        onTap: _onTap,
        onLongPress: _onLongPress,
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        child: SizedBox(
          width: math.max(width, MostroMascot.minTapTarget),
          height: math.max(height, MostroMascot.minTapTarget),
          child: Center(child: opaque),
        ),
      ),
    );
  }

  /// The plain mascot at rest (or its season's sticker, [seasonSticker]), or
  /// the sticker of the mood on show, drawn [MostroMascot.stickerScale]
  /// taller and centred over the same box.
  Widget _artwork(double height) {
    final sticker = moodSticker(_mood) ?? seasonSticker(_season);
    if (sticker == null) {
      return Image.asset(
        MostroMascot.asset,
        height: height,
        excludeFromSemantics: true,
      );
    }
    final drawn = height * MostroMascot.stickerScale;
    return OverflowBox(
      maxWidth: double.infinity,
      maxHeight: drawn,
      child: Image.asset(
        MostroMascot.stickerAsset(sticker),
        height: drawn,
        excludeFromSemantics: true,
      ),
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
      MostroMood.happy ||
      MostroMood.loved ||
      MostroMood.thankful ||
      MostroMood.greeting ||
      MostroMood.backedUp ||
      MostroMood.agreed => Transform.rotate(
        angle: 0.12 * wave,
        child: Transform.scale(scale: 1 + 0.18 * arc, child: image),
      ),

      // Three wobbles that die down.
      MostroMood.dizzy => Transform.rotate(
        angle: 0.30 * math.sin(6 * math.pi * t) * (1 - t),
        child: Transform.scale(scale: 1 + 0.06 * arc, child: image),
      ),

      // A jump, with the squash that sells it.
      MostroMood.celebrating || MostroMood.onFire => Transform.translate(
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

      // Settles in, like a lid closing.
      MostroMood.escrowLocked => Transform.scale(
        scaleX: 1 + 0.05 * arc,
        scaleY: 1 - 0.08 * arc,
        child: image,
      ),

      // A small hop.
      MostroMood.fiatSent ||
      MostroMood.orderTaken ||
      MostroMood.invoiceAccepted => Transform.translate(
        offset: Offset(0, -height * 0.14 * arc),
        child: image,
      ),

      // A stern side-to-side that dies down.
      MostroMood.disputed => Transform.translate(
        offset: Offset(width * 0.10 * math.sin(6 * math.pi * t) * (1 - t), 0),
        child: image,
      ),

      // Sinks a little, and comes back up.
      MostroMood.canceled => Transform.translate(
        offset: Offset(0, height * 0.08 * arc),
        child: Transform.scale(scale: 1 - 0.04 * arc, child: image),
      ),

      // A shiver.
      MostroMood.offline => Transform.translate(
        offset: Offset(width * 0.025 * math.sin(8 * math.pi * t), 0),
        child: image,
      ),

      // Lifts off, and lands again.
      MostroMood.published => Transform.translate(
        offset: Offset(0, -height * 0.32 * arc),
        child: Transform.scale(scaleY: 1 + 0.08 * arc, child: image),
      ),

      // Shakes its head, twice.
      MostroMood.refused => Transform.rotate(
        angle: 0.12 * math.sin(4 * math.pi * t) * (1 - t),
        child: image,
      ),

      // Jumps back, wide-eyed.
      MostroMood.cancelAsked => Transform.translate(
        offset: Offset(0, -height * 0.08 * arc),
        child: Transform.scale(scale: 1 + 0.14 * arc, child: image),
      ),

      // Shakes with laughter, bouncing.
      MostroMood.laughing => Transform.translate(
        offset: Offset(0, -height * 0.06 * arc),
        child: Transform.rotate(
          angle: 0.10 * math.sin(6 * math.pi * t) * (1 - t),
          child: image,
        ),
      ),

      // Leans back.
      MostroMood.cool => Transform.rotate(angle: -0.10 * arc, child: image),
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
