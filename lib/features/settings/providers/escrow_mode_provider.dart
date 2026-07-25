import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/escrow.dart' as escrow_api;
import 'package:mostro/src/rust/api/types.dart';

/// The settlement backend the active Mostro node runs, as resolved by Rust.
///
/// Emits the current value immediately, then every time it changes: a node
/// capability fetch, a node switch, or a developer override flip.
///
/// This is the **client-side resolution**, developer overrides included — it is
/// what gates behaviour. It is deliberately *not* what the About screen shows:
/// About reports what the node itself advertises (see `MostroInstance`), so a
/// forced override can never make About claim a node said something it did not.
final escrowModeProvider = StreamProvider<EscrowModeInfo>((ref) async* {
  // Subscribe before reading the snapshot so no change is missed in between.
  final stream = await escrow_api.onEscrowModeChanged();
  yield await escrow_api.getEscrowMode();

  while (true) {
    yield await stream.next();
  }
});

/// Whether a Cashu path may run against the active node.
///
/// The single question the rest of the app asks. Mirrors Rust's
/// `is_cashu_mode()`: the mode must be Cashu **and** there must be a usable
/// mint. False while loading and on error, so every Cashu path stays shut
/// unless the node was positively identified.
final isCashuAvailableProvider = Provider<bool>((ref) {
  return ref.watch(escrowModeProvider).valueOrNull?.isCashuAvailable ?? false;
});

// ── Developer override ────────────────────────────────────────────────────────

/// Writes the developer escrow overrides (§4.3 of `docs/cashu/README.md`).
///
/// Exists so a tester can work against a daemon branch that implements Cashu
/// before it publishes the Kind 38385 tags. Every caller must be behind
/// [kDebugMode] — release builds must not be able to force a backend the node
/// does not run. The assertions below make a misuse fail loudly in a debug
/// build rather than silently ship a switch to users.
class EscrowOverrideController {
  const EscrowOverrideController();

  /// Force (or stop forcing) Cashu mode regardless of the node's tags.
  Future<void> setForceCashu(bool forceCashu) {
    assert(kDebugMode, 'the escrow override is a debug-only affordance');
    return escrow_api.setEscrowModeOverride(forceCashu: forceCashu);
  }

  /// Point Cashu at a specific mint. `null` or blank clears the override.
  ///
  /// Throws when the URL is not an `http(s)` URL with a host — the Rust side
  /// validates and returns an `InvalidMintUrl` marker.
  Future<void> setMintUrl(String? mintUrl) {
    assert(kDebugMode, 'the escrow override is a debug-only affordance');
    return escrow_api.setCashuMintUrlOverride(mintUrl: mintUrl);
  }
}

final escrowOverrideControllerProvider = Provider<EscrowOverrideController>(
  (ref) => const EscrowOverrideController(),
);
