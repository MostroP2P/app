import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/src/rust/api/node_stats.dart' as node_stats_api;

/// Decision data for every node in the registry, keyed by pubkey: accepted
/// currencies, open orders per fiat, fee, sats range, escrow backend, bond.
///
/// Fetched from the relays each time the selector opens (`autoDispose`), in
/// batched queries over all candidate pubkeys — see
/// `rust/src/api/node_stats.rs`. Re-runs when the registry changes (a custom
/// node was added), so the new card gets its figures too. Until it lands the
/// sheet shows [cachedNodeStatsProvider]; the fetch also rewrites that cache.
///
/// Errors propagate: the sheet shows `—` in every column and keeps every card
/// selectable — missing data is never a verdict against a node.
final nodeStatsProvider =
    FutureProvider.autoDispose<Map<String, node_stats_api.MostroNodeStats>>((
      ref,
    ) async {
      final entries = await ref.watch(mostroNodesProvider.future);
      final pubkeys = entries.map((e) => e.pubkey).toList();
      if (pubkeys.isEmpty) return const {};
      final rows = await node_stats_api.fetchMostroNodeStats(pubkeys: pubkeys);
      return {for (final r in rows) r.pubkey: r};
    });

/// The nodes' settings as last seen — fee, range, currencies, custody, bond —
/// read from the local kind 38385 cache without asking any relay. Rust warms
/// it at startup and on every [nodeStatsProvider] fetch, so the selector has
/// something to show the moment it opens. Nodes never seen are left out.
///
/// These rows carry **no order count and no fresh heartbeat**: never read
/// liquidity or availability off them (`NodeCard.statsCached`).
final cachedNodeStatsProvider =
    FutureProvider.autoDispose<Map<String, node_stats_api.MostroNodeStats>>((
      ref,
    ) async {
      final entries = await ref.watch(mostroNodesProvider.future);
      final pubkeys = entries.map((e) => e.pubkey).toList();
      if (pubkeys.isEmpty) return const {};
      final rows = await node_stats_api.cachedMostroNodeStats(pubkeys: pubkeys);
      return {
        for (final r in rows)
          if (r.infoSeenAt != null) r.pubkey: r,
      };
    });
