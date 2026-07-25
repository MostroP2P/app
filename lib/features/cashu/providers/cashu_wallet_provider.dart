import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/cashu.dart' as cashu_api;
import 'package:mostro/src/rust/api/types.dart';

/// Live state of the embedded Cashu wallet — phase C3 of `docs/cashu/README.md`.
///
/// Emits the current status immediately, then on every change: connect,
/// receive, send, reclaim, disconnect.
///
/// Safe to watch on any node. On a Lightning one Rust answers "not connected"
/// and nothing else happens — no mint is contacted and no proof store opens.
/// Whether the *UI* should exist at all is a separate question, answered by
/// `isCashuAvailableProvider`.
final cashuWalletProvider = StreamProvider<CashuWalletStatus>((ref) async* {
  // Subscribe before the snapshot so no change is missed in between.
  final stream = await cashu_api.onCashuWalletChanged();
  yield await cashu_api.cashuStatus();

  while (true) {
    yield await stream.next();
  }
});

/// Commands against the wallet.
///
/// Thin by design: each is a single Rust call, and all the gating, mint traffic
/// and cryptography lives there (repo golden rule — no crypto in Dart). Errors
/// surface as stable markers the UI localizes.
class CashuWalletController {
  const CashuWalletController();

  /// Bind the wallet to the mint the active node pins, if it is not already.
  ///
  /// Throws `CashuNotEnabled` on a node that does not run Cashu, `NoIdentity`
  /// before an identity is loaded, or a `CashuMint*` marker when the mint is
  /// unreachable or unusable.
  Future<CashuWalletStatus> connect() => cashu_api.cashuConnect();

  /// Redeem a token into the wallet, returning the amount received in sats.
  Future<BigInt> receiveToken(String encoded) =>
      cashu_api.cashuReceiveToken(encoded: encoded);

  /// Export `amountSats` as an encoded token.
  Future<String> createToken(BigInt amountSats) =>
      cashu_api.cashuCreateToken(amountSats: amountSats);

  /// Reconcile proofs left reserved by an interrupted send, returning the
  /// amount reclaimed.
  Future<BigInt> checkProofsState() => cashu_api.cashuCheckProofsState();
}

final cashuWalletControllerProvider = Provider<CashuWalletController>(
  (ref) => const CashuWalletController(),
);
