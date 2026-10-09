import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/src/rust/api/node_stats.dart' as node_stats_api;

/// Resolves once the startup download of every registry node's kind 38385
/// event (`refreshMostroNodeInfoCache`) has settled, landed or failed — the
/// first of the selector's two passes. `app_bootstrap.dart` overrides it with
/// the warm-up it starts; anywhere else (tests) it is already settled.
///
/// That warm-up is also what waits for the relay handshakes, so nothing that
/// asks the relays for node data should start before it: on a fresh install
/// the walkthrough opens while the pool is still connecting.
final nodeInfoWarmUpProvider = FutureProvider<void>((ref) async {});

/// Decision data for every node in the registry, keyed by pubkey: accepted
/// currencies, open orders per fiat, fee, sats range, escrow backend, bond.
///
/// Fetched from the relays each time the selector opens (`autoDispose`), in
/// batched queries over all candidate pubkeys — see
/// `rust/src/api/node_stats.rs`. Re-runs when the registry changes (a custom
/// node was added), so the new card gets its figures too. Until it lands the
/// sheet shows [cachedNodeStatsProvider]; the fetch also rewrites that cache.
///
/// The second pass: it waits for [nodeInfoWarmUpProvider], so a fetch issued
/// during the first run's walkthrough reaches connected relays instead of
/// finding none and calling every node unreachable.
///
/// Errors propagate: the sheet shows `—` in every column and keeps every card
/// selectable — missing data is never a verdict against a node.
final nodeStatsProvider =
    FutureProvider.autoDispose<Map<String, node_stats_api.MostroNodeStats>>((
      ref,
    ) async {
      await ref.watch(nodeInfoWarmUpProvider.future);
      final entries = await ref.watch(mostroNodesProvider.future);
      final pubkeys = entries.map((e) => e.pubkey).toList();
      if (pubkeys.isEmpty) return const {};
      final rows = await node_stats_api.fetchMostroNodeStats(pubkeys: pubkeys);
      // The fetch rewrote the kind 38385 cache: reread the active node's list.
      // Through the container, which only touches a provider already alive:
      // `ref.invalidate` would create it in debug builds just to check it.
      ref.container.invalidate(activeNodeCurrenciesProvider);
      return {for (final r in rows) r.pubkey: r};
    });

/// The nodes' settings as last seen — fee, range, currencies, custody, bond —
/// read from the local kind 38385 cache without asking any relay. Rust warms
/// it at startup and on every [nodeStatsProvider] fetch, so the selector has
/// something to show the moment it opens. Nodes never seen are left out.
/// Read again when the warm-up settles, so a screen opened before it — the
/// first run's node choice — fills in as soon as the first pass lands.
///
/// These rows carry **no order count and no fresh heartbeat**: never read
/// liquidity or availability off them (`NodeCard.statsCached`).
final cachedNodeStatsProvider =
    FutureProvider.autoDispose<Map<String, node_stats_api.MostroNodeStats>>((
      ref,
    ) async {
      ref.watch(nodeInfoWarmUpProvider);
      final entries = await ref.watch(mostroNodesProvider.future);
      final pubkeys = entries.map((e) => e.pubkey).toList();
      if (pubkeys.isEmpty) return const {};
      final rows = await node_stats_api.cachedMostroNodeStats(pubkeys: pubkeys);
      return {
        for (final r in rows)
          if (r.infoSeenAt != null) r.pubkey: r,
      };
    });

/// The active node's `fiat_currencies_accepted`, as Rust parsed it from the
/// node's cached kind 38385 event ([node_stats_api.cachedMostroNodeStats]):
/// a local read, with no relay round trip. Empty for a node never seen, or
/// one that sets no limit. Reread whenever the cache is written: by the
/// startup warm-up (`app_bootstrap.dart`), by [nodeStatsProvider], and by the
/// live fetch behind `mostroNodeProvider` (`acceptedFiatCodesProvider`).
final activeNodeCurrenciesProvider = FutureProvider.autoDispose<List<String>>((
  ref,
) async {
  final pubkey = ref.watch(activeMostroPubkeyProvider);
  final rows = await node_stats_api.cachedMostroNodeStats(pubkeys: [pubkey]);
  return rows.isEmpty ? const [] : rows.first.acceptedCurrencies;
});
