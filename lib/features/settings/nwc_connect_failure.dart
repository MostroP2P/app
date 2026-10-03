/// Whether a page at [page] can open none of the relays in [nwcUri]: an
/// https page may not open a `ws://` socket (mixed content), except to the
/// machine itself. Such a URI can never connect from the web app, however
/// online the wallet is, so the screen says so instead of trying.
bool relaysBlockedByPage(String nwcUri, Uri page) {
  if (page.scheme != 'https') return false;
  final relays = Uri.tryParse(nwcUri)?.queryParametersAll['relay'] ?? const [];
  if (relays.isEmpty) return false;
  return relays.every((relay) {
    final url = Uri.tryParse(relay);
    if (url == null || url.scheme.toLowerCase() != 'ws') return false;
    return !const {'localhost', '127.0.0.1', '[::1]', '::1'}.contains(url.host);
  });
}

/// Why `connectWallet` failed, as far as the user can act on it.
enum NwcConnectFailure {
  /// The URI does not parse: the user has something to fix.
  invalidUri,

  /// The wallet refused this connection (revoked, or not allowed): retrying
  /// will not help, a new connection URI from the wallet will.
  rejected,

  /// Nothing usable came back — no answer, or a wallet error a retry can
  /// clear.
  unreachable,
}

/// The label the Rust core puts in front of the error text, read only there:
/// the rest can carry the wallet's own message, which must not steer this.
final _leadingLabel = RegExp(r'^(?:AnyhowException\()?(\w+):');

/// Reads the label the Rust core puts in front of a `connect_wallet` error
/// (`rust/src/api/nwc.rs`). Anything unlabelled is treated as a wallet that
/// did not answer, never as a bad URI: blaming the URI is only right when the
/// core said so.
NwcConnectFailure classifyNwcConnectError(Object error) {
  return switch (_leadingLabel.firstMatch(error.toString())?.group(1)) {
    'InvalidNwcUri' => NwcConnectFailure.invalidUri,
    'WalletRejected' => NwcConnectFailure.rejected,
    _ => NwcConnectFailure.unreachable,
  };
}
