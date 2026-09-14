import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/src/rust/api/nodes.dart' as nodes_api;
import 'package:mostro/src/rust/api/settings.dart' as settings_api;
import 'package:mostro/src/rust/api/types.dart';

// ── Active node pubkey ────────────────────────────────────────────────────────

/// Active Mostro node pubkey — seeded at bootstrap from the Rust bridge and
/// synced back to it on every selection, so outgoing events are routed to the
/// selected node.
final mostroPubkeyProvider = StateProvider<String>(
  (ref) => defaultMostroPubkey,
);

/// Truncate a pubkey to `first8…last8` for display.
String truncatePubkey(String pubkey) {
  if (pubkey.length <= 16) return pubkey;
  return '${pubkey.substring(0, 8)}…${pubkey.substring(pubkey.length - 8)}';
}

// ── Node registry ─────────────────────────────────────────────────────────────

/// The Mostro node registry: compiled-in trusted communities plus user-added
/// nodes, each merged with cached kind 0 metadata (name, picture, about).
///
/// The list itself lives in Rust (`api/nodes.rs`); this notifier only mirrors
/// it and forwards mutations.
final mostroNodesProvider =
    AsyncNotifierProvider<MostroNodesNotifier, List<MostroNodeEntry>>(
      MostroNodesNotifier.new,
    );

class MostroNodesNotifier extends AsyncNotifier<List<MostroNodeEntry>> {
  bool _refreshing = false;

  @override
  Future<List<MostroNodeEntry>> build() async {
    final list = await nodes_api.listMostroNodes();
    // Serve the cached registry immediately; fresh kind 0 metadata lands via
    // the background refresh below.
    refreshMetadata();
    return list;
  }

  /// Re-fetch kind 0 metadata for all known nodes. Best-effort: on relay
  /// timeout or bridge error the current list simply stays as it is.
  ///
  /// Coalesced: opening the selector triggers a refresh while the one from
  /// [build] (via the Settings screen) may still be in flight — the second
  /// call is dropped instead of issuing a duplicate relay query.
  Future<void> refreshMetadata() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final refreshed = await nodes_api.refreshMostroNodeMetadata();
      state = AsyncData(refreshed);
    } catch (e) {
      debugPrint('[mostroNodes] metadata refresh failed: $e');
    } finally {
      _refreshing = false;
    }
  }

  /// Activate `pubkey` — persists it, re-targets subscriptions (Rust side) and
  /// keeps [mostroPubkeyProvider] in sync. Rethrows on failure after rolling
  /// the pubkey provider back.
  Future<void> selectNode(String pubkey) async {
    final previous = ref.read(mostroPubkeyProvider);
    ref.read(mostroPubkeyProvider.notifier).state = pubkey;
    try {
      await settings_api.setActiveMostroNode(pubkey: pubkey);
    } catch (e) {
      ref.read(mostroPubkeyProvider.notifier).state = previous;
      rethrow;
    }
    state = AsyncData(await nodes_api.listMostroNodes());
  }

  /// Add a custom node by 64-char hex or `npub1…` pubkey. Rethrows the Rust
  /// marker error (`InvalidPubkey`, `PrivateKeyNotAllowed`,
  /// `NodeAlreadyExists`) for the dialog to localize.
  Future<void> addCustomNode({required String input, String? name}) async {
    await nodes_api.addCustomMostroNode(input: input, name: name);
    state = AsyncData(await nodes_api.listMostroNodes());
    refreshMetadata();
  }

  /// Remove a user-added node. Rethrows on failure
  /// (e.g. `CannotRemoveActiveNode`).
  Future<void> removeCustomNode(String pubkey) async {
    await nodes_api.removeCustomMostroNode(pubkey: pubkey);
    state = AsyncData(await nodes_api.listMostroNodes());
  }
}
