import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/providers/node_stats_provider.dart';

/// Downloads what the first run's node choice shows while the walkthrough is
/// still on screen, so the cards are filled when the user gets there.
///
/// Two passes, in order: the startup warm-up of every node's kind 38385
/// event (fee, range, currencies, bond — [nodeInfoWarmUpProvider], read back
/// by [cachedNodeStatsProvider]), then the order counts ([nodeStatsProvider],
/// which waits for the first). The node names (kind 0) are fetched again once
/// the first pass has the relays connected — after the registry's own fetch,
/// which may have run before any was, rather than coalesced into it.
///
/// Watched by the walkthrough and by the node choice: the second subscribes
/// before the first is gone, so the fetch in flight carries over.
final firstRunNodePrefetchProvider = Provider.autoDispose<void>((ref) {
  ref.listen(cachedNodeStatsProvider, (_, __) {});
  ref.listen(nodeStatsProvider, (_, __) {});
  ref.listen<AsyncValue<void>>(nodeInfoWarmUpProvider, (_, warmUp) {
    if (warmUp.hasValue) {
      ref.read(mostroNodesProvider.notifier).refreshMetadataAfterPending();
    }
  }, fireImmediately: true);
});
