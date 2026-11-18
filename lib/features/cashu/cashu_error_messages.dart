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
  final unit = _unsupportedUnit.firstMatch(raw)?.group(1);
  if (unit != null) {
    final name = _unitName(unit, l10n);
    if (name != null) return l10n.cashuErrorUnsupportedUnitNamed(name);
  }
  for (final entry in _messages.entries) {
    if (raw.contains(entry.key)) return entry.value(l10n);
  }
  return l10n.cashuErrorGeneric;
}

/// `CashuUnsupportedUnit: <code>` — the one marker whose tail is shown, and
/// only as a name this app chose: Rust sends `msat`, `usd`, `eur`, a
/// three-letter custom code or `other` (`unsupported_unit_code`).
final _unsupportedUnit = RegExp(r'CashuUnsupportedUnit: ([a-z]+)\b');

/// What to call a refused token's unit, or null for the generic message.
String? _unitName(String code, AppLocalizations l10n) => switch (code) {
  'msat' => l10n.cashuUnitMsat,
  'usd' => l10n.cashuUnitUsd,
  'eur' => l10n.cashuUnitEur,
  // A currency code the app has no name for: shown as the code itself.
  _ when RegExp(r'^[a-z]{3}$').hasMatch(code) => code.toUpperCase(),
  _ => null,
};

/// Marker → message. Insertion-ordered, most specific first: a marker that is a
/// prefix of another must come first, or the broader one would shadow it.
final Map<String, String Function(AppLocalizations)> _messages = {
  // Paying a Lightning invoice (phase C3b-1). First, so a cdk detail in the
  // tail of a melt failure can never be read as one of the markers below.
  'CashuInvalidInvoice': (l) => l.cashuErrorInvalidInvoice,
  'CashuInvoiceNoAmount': (l) => l.cashuErrorInvoiceNoAmount,
  'CashuInvoiceExpired': (l) => l.cashuErrorInvoiceExpired,
  'CashuMeltUnsupported': (l) => l.cashuErrorMeltUnsupported,
  'CashuMeltAmountOutOfRange': (l) => l.cashuErrorMeltAmountOutOfRange,
  'CashuMeltQuoteExpired': (l) => l.cashuErrorMeltQuoteExpired,
  'CashuMeltQuoteFailed': (l) => l.cashuErrorMeltQuoteFailed,
  // Refused before paying: nothing left the wallet, which is what to say.
  'CashuMeltFeeChanged': (l) => l.cashuErrorMeltFeeChanged,
  // Refused before starting: another payment is still waiting for the mint.
  'CashuMeltInFlight': (l) => l.cashuErrorMeltInFlight,
  // Not `CashuInsufficientFunds` (escrow) — neither contains the other.
  'CashuMeltInsufficientFunds': (l) => l.cashuErrorMeltInsufficientFunds,
  'CashuMeltFailed': (l) => l.cashuErrorMeltFailed,
  // Receiving over Lightning (phase C3b-2). Up here for the same reason: a
  // cdk detail in their tail must not read as a later marker.
  'CashuMintUnsupported': (l) => l.cashuErrorMintUnsupported,
  'CashuMintAmountOutOfRange': (l) => l.cashuErrorMintAmountOutOfRange,
  'CashuMintQuoteUnknown': (l) => l.cashuErrorMintQuoteUnknown,
  'CashuMintQuoteFailed': (l) => l.cashuErrorMintQuoteFailed,
  'CashuInsufficientFunds': (l) => l.lockEscrowInsufficientFunds,
  'CashuMintNotSupported': (l) => l.lockEscrowMintNotSupported,
  // The wallet's mint is the user's and can differ from the node's: the fix
  // is switching it in the wallet, not retrying.
  'CashuWalletOnOtherMint': (l) => l.cashuErrorWalletOnOtherMint,
  // The daemon's answers to a submission (phase C5). Each reason says what
  // happened to the recorded escrow, which is what the seller must know.
  'CashuEscrowRejected: InvalidCashuToken': (l) => l.lockEscrowRejectedToken,
  'CashuEscrowRejected: InvalidMintUrl': (l) => l.lockEscrowRejectedMint,
  'CashuEscrowRejected: CashuMintUnavailable': (l) =>
      l.lockEscrowMintUnavailableAtNode,
  'CashuEscrowRejected': (l) => l.lockEscrowRejectedGeneric,
  'CashuEscrowOrderMovedOn': (l) => l.lockEscrowOrderMovedOn,
  'CashuEscrowNotPersisted': (l) => l.lockEscrowNotRecorded,
  'NoDaemonResponse': (l) => l.lockEscrowNoAnswer,
  'CashuEscrowRequestMissing': (l) => l.lockEscrowRequestMissing,
  'CashuWrongTradeKey': (l) => l.lockEscrowWrongTradeKey,
  'CashuLocktimeNotReached': (l) => l.lockEscrowLocktimeNotReached,
  'DeviceClockInvalid': (l) => l.lockEscrowClockInvalid,
  'InvalidEscrowParties': (l) => l.lockEscrowInvalidToken,
  'InvalidEscrowToken': (l) => l.lockEscrowInvalidToken,
  'NotTheSeller': (l) => l.lockEscrowNotTheSeller,
  // The trade is on another node than the selected one: nothing was swapped
  // or sent (#810).
  'TradeOnOtherNode': (l) => l.tradeOnOtherNode,
  'CashuLockFailed': (l) => l.lockEscrowFailed,
  'CashuNotEnabled': (l) => l.cashuErrorNotEnabled,
  'CashuNotConnected': (l) => l.cashuErrorNotConnected,
  // No mint was ever set: the wallet asks for one, or takes a token's.
  'CashuNoMint': (l) => l.cashuErrorNoMint,
  'InvalidMintUrl': (l) => l.cashuErrorInvalidMintUrl,
  'CashuMintUnreachable': (l) => l.cashuErrorMintUnreachable,
  'CashuMintUnusable': (l) => l.cashuErrorMintUnusable,
  'CashuUnsupportedOnWeb': (l) => l.cashuErrorUnsupportedOnWeb,
  'CashuAmountZero': (l) => l.cashuErrorAmountZero,
  // The wallet holds sats only. Refused from the token alone, before any
  // mint was asked, so the token is untouched — which is what to say, rather
  // than leave the user to think it was lost. A unit the app can name is
  // handled above; this is the rest (`other`).
  'CashuUnsupportedUnit': (l) => l.cashuErrorUnsupportedUnit,
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
