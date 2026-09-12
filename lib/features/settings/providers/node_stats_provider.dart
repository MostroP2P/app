import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/src/rust/api/node_stats.dart' as node_stats_api;

/// Decision data for every node in the registry, keyed by pubkey: accepted
/// currencies, open orders per fiat, fee, sats range, escrow backend, bond.
///
/// Fetched from the relays each time the selector opens (`autoDispose`), in
/// two batched queries over all candidate pubkeys — see
/// `rust/src/api/node_stats.rs`. Re-runs when the registry changes (a custom
/// node was added), so the new card gets its figures too.
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
