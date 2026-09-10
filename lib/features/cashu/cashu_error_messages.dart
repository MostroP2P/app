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
  // The wallet is bound to the previous node's mint: a node switch happened
  // while this screen was open. Reconnecting is the fix, not retrying.
  'CashuMintChanged': (l) => l.cashuErrorMintChanged,
  'CashuMintUnreachable': (l) => l.cashuErrorMintUnreachable,
  'CashuMintUnusable': (l) => l.cashuErrorMintUnusable,
  'CashuUnsupportedOnWeb': (l) => l.cashuErrorUnsupportedOnWeb,
  'CashuAmountZero': (l) => l.cashuErrorAmountZero,
  // Distinct from ReceiveFailed: the token parsed and belongs to this mint,
  // but carries no DLEQ proof, so "wrong mint or spent" would misdiagnose it.
  'CashuTokenUnverified': (l) => l.cashuErrorTokenUnverified,
  'CashuReceiveFailed': (l) => l.cashuErrorReceiveFailed,
  // The send failed *and* the proofs could not be confirmed back. "Try
  // again" — the generic advice — is the wrong move; the user must sync.
  'CashuSendUnresolved': (l) => l.cashuErrorSendUnresolved,
  'CashuSendFailed': (l) => l.cashuErrorSendFailed,
  // Permanent for an nsec-imported identity: there is no seed to derive the
  // wallet from, and "no identity" would send the user to log in again.
  'CashuNoMnemonic': (l) => l.cashuErrorNoMnemonic,
  'NoIdentity': (l) => l.cashuErrorNoIdentity,
};
