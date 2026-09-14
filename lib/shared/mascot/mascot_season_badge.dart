import 'package:flutter/material.dart';

import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';

/// The badge Mostro wears on one of the three dates Bitcoin remembers.
///
/// Must be a child of a [Stack] sized to the mascot: it returns a
/// [Positioned] placed against that box. The offsets are tuned to the
/// artwork, whose head sits in the upper-left of the bolt, so the hat lands
/// on the head and the other badges sit clear of the silhouette.
class MascotSeasonBadge extends StatelessWidget {
  const MascotSeasonBadge({
    super.key,
    required this.season,
    required this.mascotHeight,
  });

  final MostroSeason season;

  /// Height of the mascot this badge rides on; everything scales off it.
  final double mascotHeight;

  /// The artwork is 199 × 288, and the badge is placed against that box.
  static const double mascotAspect = 199 / 288;

  @override
  Widget build(BuildContext context) {
    final emoji = seasonEmoji(season);
    if (emoji == null) return const Positioned.fill(child: SizedBox.shrink());

    final height = mascotHeight;
    final width = height * mascotAspect;
    final size = height * 0.38;

    // The pumpkin is a hat, so it sits on the skull: in this artwork the head
    // fills the upper half and its crown is just right of centre. The rest
    // hang off the right, clear of the bolt's tip.
    final isHat = season == MostroSeason.whitepaper;

    return Positioned(
      top: isHat ? -size * 0.50 : height * 0.30,
      left: isHat ? width * 0.16 : null,
      right: isHat ? null : -width * 0.30,
      child: ExcludeSemantics(
        child: Text(emoji, style: TextStyle(fontSize: size, height: 1)),
      ),
    );
  }
}

/// What Mostro has to say when tapped on [season], or null on an ordinary
/// day.
///
/// The genesis line is a quotation from The Times, and reads the same in
/// every locale by design.
String? seasonMessage(AppLocalizations l10n, MostroSeason season) =>
    switch (season) {
      MostroSeason.whitepaper => l10n.easterEggWhitepaper,
      MostroSeason.genesis => l10n.easterEggGenesis,
      MostroSeason.pizzaDay => l10n.easterEggPizzaDay,
      MostroSeason.none => null,
    };
