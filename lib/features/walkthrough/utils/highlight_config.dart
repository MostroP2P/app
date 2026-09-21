import 'package:flutter/material.dart';

/// Per-slide list of terms to highlight in green (semibold).
///
/// Each entry is a regex pattern with one alternative per wording the
/// supported languages use. Where a language keeps the English term (every
/// locale says "Hold Invoices" on slide 3), the English alternative covers it.
/// Case-insensitive matching is enabled. `highlight_config_test.dart` checks
/// that every pattern matches in every locale, so a stale alternative fails.
class HighlightConfig {
  /// Slide index → list of term patterns.
  static final Map<int, List<String>> patterns = {
    // Page 1: Welcome
    0: [
      r'Nostr',
      r'no KYC|sin KYC|senza KYC|sans KYC|ohne KYC|zonder KYC',
      r'censorship.resistant|resistente a la censura|resistente alla censura|résistant à la censure|zensurresistent|bestand tegen censuur',
    ],
    // Page 2: Privacy by Default
    1: [
      r'Reputation mode|Modo reputación|Modalità reputazione|Mode réputation|Reputationsmodus|Reputatiemodus',
      r'Full privacy mode|Modo privacidad total|Modalità privacy totale|Mode confidentialité totale|Vollständiger Privatsphäre-Modus|Volledig privé',
    ],
    // Page 3: Security at Every Step
    2: [
      r'Hold Invoices?|Factures retenues',
    ],
    // Page 4: Encrypted Chat
    3: [
      r'end.to.end encrypted|cifrado de extremo a extremo|cifrat[oa] end.to.end|chiffré de bout en bout|Ende.zu.Ende.verschlüsselt|end.to.end versleuteld',
    ],
    // Page 5: Take an Offer
    4: [
      r"order book|libro de órdenes|book degli ordini|carnet d'ordres|Orderbuch|orderboek",
    ],
    // Page 6: Create Your Own Offer
    5: [
      r'create your own offer|crear? tu propia oferta|crea(?:re)? la tua offerta|cré(?:er|ez) votre propre offre|dein eigenes Angebot erstellen|je eigen aanbod plaatsen',
    ],
  };

  /// The combined pattern per slide, built once rather than on every build.
  static final Map<int, RegExp?> _compiled = {};

  static RegExp? _regexFor(int slideIndex) =>
      _compiled.putIfAbsent(slideIndex, () {
        final termPatterns = patterns[slideIndex];
        if (termPatterns == null || termPatterns.isEmpty) return null;
        return RegExp(termPatterns.join('|'), caseSensitive: false);
      });

  /// Build a [TextSpan] tree from [text], highlighting any match from
  /// [patterns[slideIndex]] in [highlightColor] with [FontWeight.w600].
  static TextSpan buildHighlighted(
    String text,
    int slideIndex,
    Color highlightColor,
    TextStyle baseStyle,
  ) {
    final regex = _regexFor(slideIndex);
    if (regex == null) {
      return TextSpan(text: text, style: baseStyle);
    }

    final spans = <TextSpan>[];
    int cursor = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: text.substring(cursor, match.start),
            style: baseStyle,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: baseStyle.copyWith(
            color: highlightColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(cursor),
          style: baseStyle,
        ),
      );
    }

    return TextSpan(children: spans);
  }
}
