import 'dart:ui' show Offset;

import 'package:mostro/l10n/app_localizations.dart';

/// Where the walkthrough's SVG illustrations live.
const walkthroughArtDir = 'assets/images/walkthrough';

/// One of the privacy modes the second slide presents as a card.
typedef WalkthroughMode = ({String name, String description});

/// A dashed line whose dashes run from [from] to [to], over the slide's art
/// and under [front]: the traffic between the two peers of the first slide.
/// Points are in the art's 240 x 240 view box.
class WalkthroughFlow {
  const WalkthroughFlow({
    required this.from,
    required this.to,
    required this.front,
  });

  final Offset from;
  final Offset to;

  /// Asset drawn over the line, where it runs into the hub.
  final String front;
}

/// One slide of the first-run walkthrough: an illustration, a title and its
/// paragraphs, optionally mode cards with a closing paragraph after them.
class WalkthroughSlide {
  const WalkthroughSlide({
    required this.art,
    required this.title,
    required this.paragraphs,
    this.modes = const [],
    this.footer,
    this.flow,
    this.bolt,
  });

  /// Asset path of the slide's illustration.
  final String art;
  final String title;
  final List<String> paragraphs;
  final List<WalkthroughMode> modes;

  /// The paragraph after [modes].
  final String? footer;

  /// The animated line drawn into the art, if the slide has one.
  final WalkthroughFlow? flow;

  /// Asset of a bolt drawn on top of the art, flickering with the glint.
  final String? bolt;
}

/// The six slides, in order.
List<WalkthroughSlide> walkthroughSlides(AppLocalizations l10n) => [
  WalkthroughSlide(
    art: '$walkthroughArtDir/welcome.svg',
    title: l10n.walkthroughWelcomeTitle,
    paragraphs: [l10n.walkthroughWelcomeBody1, l10n.walkthroughWelcomeBody2],
    // The handoff's M94 120H146, inside the drawing's 1.3x scale about the
    // centre.
    flow: const WalkthroughFlow(
      from: Offset(86.2, 120),
      to: Offset(153.8, 120),
      front: '$walkthroughArtDir/welcome_hub.svg',
    ),
    bolt: '$walkthroughArtDir/welcome_bolt.svg',
  ),
  WalkthroughSlide(
    art: '$walkthroughArtDir/privacy.svg',
    title: l10n.walkthroughPrivacyTitle,
    paragraphs: [l10n.walkthroughPrivacyBody1, l10n.walkthroughPrivacyBody2],
    modes: [
      (
        name: l10n.walkthroughReputationModeName,
        description: l10n.walkthroughReputationModeBody,
      ),
      (
        name: l10n.walkthroughFullPrivacyModeName,
        description: l10n.walkthroughFullPrivacyModeBody,
      ),
    ],
    footer: l10n.walkthroughPrivacyFooter,
  ),
  WalkthroughSlide(
    art: '$walkthroughArtDir/held.svg',
    title: l10n.walkthroughHeldTitle,
    paragraphs: [l10n.walkthroughHeldBody1, l10n.walkthroughHeldBody2],
    bolt: '$walkthroughArtDir/held_bolt.svg',
  ),
  WalkthroughSlide(
    art: '$walkthroughArtDir/chat.svg',
    title: l10n.walkthroughChatTitle,
    paragraphs: [l10n.walkthroughChatBody1, l10n.walkthroughChatBody2],
  ),
  WalkthroughSlide(
    art: '$walkthroughArtDir/take.svg',
    title: l10n.walkthroughTakeTitle,
    paragraphs: [l10n.walkthroughTakeBody1, l10n.walkthroughTakeBody2],
  ),
  WalkthroughSlide(
    art: '$walkthroughArtDir/make.svg',
    title: l10n.walkthroughMakeTitle,
    paragraphs: [l10n.walkthroughMakeBody1, l10n.walkthroughMakeBody2],
  ),
];
