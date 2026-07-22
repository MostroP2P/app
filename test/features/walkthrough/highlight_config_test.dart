import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/walkthrough/utils/highlight_config.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Guards against the silent regression where a translated onboarding slide
/// body no longer contains a phrase that [HighlightConfig] highlights, dropping
/// the intended green emphasis. Every slide must produce at least one
/// highlighted span in every supported locale.
void main() {
  List<String> slideBodies(AppLocalizations l) => [
        l.walkthroughSlideOneBody,
        l.walkthroughSlideTwoBody,
        l.walkthroughSlideThreeBody,
        l.walkthroughSlideFourBody,
        l.walkthroughSlideFiveBody,
        l.walkthroughSlideSixBody,
      ];

  for (final locale in AppLocalizations.supportedLocales) {
    test('walkthrough slides highlight a phrase in ${locale.languageCode}',
        () async {
      final l10n = await AppLocalizations.delegate.load(locale);
      final bodies = slideBodies(l10n);

      for (var i = 0; i < bodies.length; i++) {
        final span = HighlightConfig.buildHighlighted(
          bodies[i],
          i,
          const Color(0xFF8CC63F),
          const TextStyle(),
        );
        // The highlighted fragment is the only span with a bold weight.
        final hasHighlight = (span.children ?? const <InlineSpan>[]).any(
          (c) => c is TextSpan && c.style?.fontWeight == FontWeight.w600,
        );
        expect(
          hasHighlight,
          isTrue,
          reason: 'slide ${i + 1} in ${locale.languageCode} has no highlight',
        );
      }
    });
  }
}
