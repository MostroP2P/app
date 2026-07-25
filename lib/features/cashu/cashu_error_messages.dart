import 'package:mostro/l10n/app_localizations.dart';

/// Maps the stable markers Rust returns onto localized text.
///
/// Rust never returns prose (repo translation rule), so every Cashu failure
/// arrives as a marker like `CashuNotEnabled` with an opaque tail. One mapper
/// rather than one per screen: the list only grows as later phases add flows,
/// and a screen that forgets a marker would silently show the generic message
/// instead of the right one.
///
/// An **unrecognised** marker deliberately falls back rather than being shown —
/// the tail carries mint URLs, amounts and cdk internals, none of which belong
/// in front of a user.
String cashuErrorMessage(Object error, AppLocalizations l10n) {
  final raw = error.toString();
  for (final entry in _messages.entries) {
    if (raw.contains(entry.key)) return entry.value(l10n);
  }
  return l10n.cashuErrorGeneric;
}

/// Marker → message. Insertion-ordered, most specific first: a marker that is a
/// prefix of another must come first, or the broader one would shadow it.
final Map<String, String Function(AppLocalizations)> _messages = {
  'CashuNotEnabled': (l) => l.cashuErrorNotEnabled,
  'CashuNotConnected': (l) => l.cashuErrorNotConnected,
  'CashuMintUnreachable': (l) => l.cashuErrorMintUnreachable,
  'CashuMintUnusable': (l) => l.cashuErrorMintUnusable,
  'CashuUnsupportedOnWeb': (l) => l.cashuErrorUnsupportedOnWeb,
  'CashuAmountZero': (l) => l.cashuErrorAmountZero,
  'CashuReceiveFailed': (l) => l.cashuErrorReceiveFailed,
  'CashuSendFailed': (l) => l.cashuErrorSendFailed,
  'NoIdentity': (l) => l.cashuErrorNoIdentity,
};
