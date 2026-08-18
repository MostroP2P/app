import 'package:mostro/l10n/app_localizations.dart';

/// Central mapping from the stable error markers the Rust core emits to
/// localized, actionable messages.
///
/// Every daemon-bound action can now fail with a node-capability marker —
/// the compatibility gate runs on all wraps, not only create/take — and some
/// Rust wrappers prepend their own context (`ProtocolError: ...`,
/// `RateUserDispatchFailed: ...`) while interpolating the inner error, so the
/// marker is matched by substring anywhere in the message.
///
/// Returns [fallback] when the error carries no known marker, so each screen
/// keeps its action-specific generic failure text.
String localizedDaemonError(
  AppLocalizations l10n,
  Object error, {
  required String fallback,
}) {
  final raw = error.toString();
  // The selected node speaks a wire protocol this v2-native client does not:
  // it would never read the request, so picking another node is the fix.
  if (raw.contains('UnsupportedNodeProtocol')) {
    return l10n.nodeProtocolUnsupported;
  }
  // The node's capability fetch has not completed (startup or node switch):
  // the send failed closed and a retry a moment later usually succeeds.
  if (raw.contains('NodeCapabilitiesUnknown')) {
    return l10n.nodeCapabilitiesUnknown;
  }
  // The daemon never answered within the reply window.
  if (raw.contains('NoDaemonResponse')) {
    return l10n.sessionTimeoutMessage;
  }
  // No relay accepted the event — it never left the device. Same remedy as
  // a daemon timeout: check the connection and retry.
  if (raw.contains('NoRelayAccepted')) {
    return l10n.sessionTimeoutMessage;
  }
  // No durable storage: no trade key can be derived (issue #249).
  if (raw.contains('StorageUnavailable')) {
    return l10n.storageUnavailable;
  }
  // The trade has not reached the state where the daemon accepts a dispute.
  if (raw.contains('TradeNotDisputable')) {
    return l10n.tradeNotDisputable;
  }
  // The fiat code failed the create-order preflight (#175): a stale or tampered
  // saved default that is not a valid ISO 4217 code. Re-picking a currency fixes
  // it before the request is ever published.
  if (raw.contains('InvalidFiatCode')) {
    return l10n.invalidFiatCode;
  }
  return fallback;
}
