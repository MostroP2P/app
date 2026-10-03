import 'package:flutter/foundation.dart' show kIsWeb;

/// Whether this build can connect an NWC wallet at all. The web build's Rust
/// core stubs the NWC client out (`rust/src/nwc/client.rs`), so every attempt
/// there fails before the URI is even read.
const bool nwcSupported = !kIsWeb;

/// Why `connectWallet` failed, as far as the user can act on it.
enum NwcConnectFailure {
  /// The URI does not parse: the user has something to fix.
  invalidUri,

  /// This build cannot do NWC: no URI will help.
  unsupported,

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
    'Unsupported' => NwcConnectFailure.unsupported,
    'WalletRejected' => NwcConnectFailure.rejected,
    _ => NwcConnectFailure.unreachable,
  };
}
