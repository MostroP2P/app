import 'package:flutter/material.dart';

/// Per-slide list of terms to highlight in green (semibold).
///
/// Each entry is a regex pattern that matches the term in all 5 supported
/// languages (EN, ES, IT, FR, DE). Case-insensitive matching is enabled.
class HighlightConfig {
  /// Slide index → list of term patterns.
  static final Map<int, List<String>> patterns = {
    // Page 1: Welcome
    0: [
      r'Nostr',
      r'no KYC|sin KYC|senza KYC|sans KYC|ohne KYC',
      r'censorship.resistant|resistente a la censura|resistente alla censura|résistant à la censure|zensurresistent',
    ],
    // Page 2: Privacy by Default
    1: [
      r'Reputation mode|Modo reputación|Modalità reputazione|Mode réputation|Reputationsmodus',
      r'Full privacy mode|Modo privacidad total|Modalità privacy totale|Mode confidentialité totale|Vollständiger Datenschutzmodus',
    ],
    // Page 3: Security at Every Step
    2: [
      r'Hold Invoices?|Facturas de retención|Fatture hold|Factures retenues|Hold-Rechnungen?',
    ],
    // Page 4: Encrypted Chat
    3: [
      r'end.to.end encrypted|cifrado de extremo a extremo|crittografato end.to.end|chiffré de bout en bout|Ende.zu.Ende.verschlüsselt',
    ],
    // Page 5: Take an Offer
    4: [
      "order book|libro de órdenes|libro degli ordini|carnet d'ordres|Orderbuch",
    ],
    // Page 6: Create Your Own Offer
    5: [
      r'create your own offer|crea tu propia oferta|crea la tua offerta|créez votre propre offre|erstelle dein eigenes Angebot',
    ],
  };

  /// Build a [TextSpan] tree from [text], highlighting any match from
  /// [patterns[slideIndex]] in [highlightColor] with [FontWeight.w600].
  static TextSpan buildHighlighted(
    String text,
    int slideIndex,
    Color highlightColor,
    TextStyle baseStyle,
  ) {
    final termPatterns = patterns[slideIndex];
    if (termPatterns == null || termPatterns.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final combined = termPatterns.join('|');
    final regex = RegExp(combined, caseSensitive: false);

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
