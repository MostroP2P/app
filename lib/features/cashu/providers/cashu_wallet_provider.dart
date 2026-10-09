import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/cashu.dart' as cashu_api;
import 'package:mostro/src/rust/api/types.dart';

/// Live state of the embedded Cashu wallet — phase C3 of `docs/cashu/README.md`.
///
/// Emits the current status immediately, then on every change: connect,
/// receive, send, reclaim, disconnect.
///
/// Safe to watch on any node: until the wallet is bound to a mint Rust answers
/// "not connected" and nothing else happens — no mint is contacted and no
/// proof store opens.
///
/// Not `autoDispose`, unlike `mostroNodeProvider`, on purpose: the stream and
/// its Rust handle live for the process, so reopening the wallet shows the
/// last known balance at once instead of re-subscribing on every visit. It
/// holds one receiver on Rust's status broadcast (`on_cashu_wallet_changed`).
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

  /// Bind the wallet to [mintUrl], the mint the user chose, or — when `null` —
  /// to the mint set before (on a fresh install, the default of a Cashu node
  /// that pins one). Works on any node: the wallet's mint is the user's.
  ///
  /// Throws `CashuNoMint` when there is no mint to bind to, `InvalidMintUrl`,
  /// `NoIdentity` before an identity is loaded, or a `CashuMint*` marker when
  /// the mint is unreachable or unusable.
  Future<CashuWalletStatus> connect({String? mintUrl}) =>
      cashu_api.cashuConnect(mintUrl: mintUrl);

  /// Redeem a token into the wallet, returning the amount received in sats.
  Future<BigInt> receiveToken(String encoded) =>
      cashu_api.cashuReceiveToken(encoded: encoded);

  /// Export `amountSats` as an encoded token.
  Future<String> createToken(BigInt amountSats) =>
      cashu_api.cashuCreateToken(amountSats: amountSats);

  /// Drop the proofs the mint reports as spent and refresh the balance.
  ///
  /// Housekeeping, not recovery: cdk's state check skips the proofs a send of
  /// ours reserved, so an unredeemed token is *not* reclaimed here — that is
  /// phase C10. The Rust side returns nothing for exactly that reason, and the
  /// UI must not claim a "reclaimed N sat" it cannot know.
  Future<void> sweepSpentProofs() => cashu_api.cashuSweepSpentProofs();
}

final cashuWalletControllerProvider = Provider<CashuWalletController>(
  (ref) => const CashuWalletController(),
);

/// Seller-side escrow commands — phase C5.
///
/// Split from the wallet controller because the audiences differ: the wallet is
/// something a user opens, an escrow lock is something a trade demands. Both
/// are one Rust call each.
class CashuEscrowController {
  const CashuEscrowController();

  /// What locking this order would cost: escrow, fee, total, and the balance to
  /// compare them against. Changes nothing.
  Future<CashuEscrowQuote> quote(String orderId) =>
      cashu_api.cashuEscrowQuote(orderId: orderId);

  /// Fund the escrow and submit it to the daemon — or re-send the one already
  /// recorded, which swaps nothing. Throws a stable marker on failure
  /// (`cashu_error_messages.dart`).
  Future<void> lock(String orderId) => cashu_api.lockEscrow(orderId: orderId);
}

final cashuEscrowControllerProvider = Provider<CashuEscrowController>(
  (ref) => const CashuEscrowController(),
);
