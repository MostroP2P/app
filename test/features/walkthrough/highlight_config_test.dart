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

    // One highlight per slide is not enough: German slide 2 used to highlight
    // only "Reputationsmodus" because its second pattern named a phrase the
    // German text did not contain, and the test above stayed green.
    test('every walkthrough pattern matches in ${locale.languageCode}',
        () async {
      final bodies = slideBodies(await AppLocalizations.delegate.load(locale));

      HighlightConfig.patterns.forEach((slide, patterns) {
        for (final pattern in patterns) {
          expect(
            RegExp(pattern, caseSensitive: false).hasMatch(bodies[slide]),
            isTrue,
            reason: 'slide ${slide + 1} in ${locale.languageCode} does not '
                'contain /$pattern/',
          );
        }
      });
    });
  }

  // A top-level alternative that matches in no language is dead weight that
  // misleads the next translator into thinking the phrase is live.
  test('every alternative in a walkthrough pattern matches some locale',
      () async {
    final bodiesPerLocale = [
      for (final locale in AppLocalizations.supportedLocales)
        slideBodies(await AppLocalizations.delegate.load(locale)),
    ];

    HighlightConfig.patterns.forEach((slide, patterns) {
      for (final pattern in patterns) {
        for (final alternative in _topLevelAlternatives(pattern)) {
          final regex = RegExp(alternative, caseSensitive: false);
          expect(
            bodiesPerLocale.any((bodies) => regex.hasMatch(bodies[slide])),
            isTrue,
            reason: 'slide ${slide + 1}: "$alternative" matches no locale',
          );
        }
      }
    });
  });
}

/// Splits [pattern] on the `|` characters that are not inside a group, so
/// `cré(?:er|ez) votre propre offre` stays one alternative.
List<String> _topLevelAlternatives(String pattern) {
  final alternatives = <String>[];
  var depth = 0;
  var current = StringBuffer();
  for (final char in pattern.split('')) {
    if (char == '(') depth++;
    if (char == ')') depth--;
    if (char == '|' && depth == 0) {
      alternatives.add(current.toString());
      current = StringBuffer();
    } else {
      current.write(char);
    }
  }
  return alternatives..add(current.toString());
}
