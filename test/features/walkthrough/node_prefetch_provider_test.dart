import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/providers/node_stats_provider.dart';
import 'package:mostro/features/walkthrough/providers/node_prefetch_provider.dart';
import 'package:mostro/src/rust/api/types.dart' show MostroNodeEntry;

import '../../support/provider_harness.dart';

/// An empty registry, so neither stats provider reaches the Rust bridge;
/// counts how often the registry is read and its metadata refreshed.
class _CountingNodesNotifier extends MostroNodesNotifier {
  int builds = 0;
  int refreshes = 0;

  @override
  Future<List<MostroNodeEntry>> build() async {
    builds++;
    return const [];
  }

  @override
  Future<void> refreshMetadata() async => refreshes++;
}

void main() {
  late Completer<void> warmUp;
  late _CountingNodesNotifier nodes;

  setUp(() {
    warmUp = Completer<void>();
    nodes = _CountingNodesNotifier();
  });

  ProviderContainer makeContainer() => createContainer(
    overrides: [
      nodeInfoWarmUpProvider.overrideWith((ref) => warmUp.future),
      mostroNodesProvider.overrideWith(() => nodes),
    ],
  );

  test('the order counts wait for the kind 38385 warm-up', () async {
    // Arrange
    final container = makeContainer();
    final sub = container.listen(nodeStatsProvider, (_, __) {});
    addTearDown(sub.close);

    // Act
    await pumpEventQueue();

    // Assert: nothing asked for the registry, let alone the relays.
    expect(nodes.builds, 0);
    expect(container.read(nodeStatsProvider).isLoading, isTrue);

    warmUp.complete();
    expect(await container.read(nodeStatsProvider.future), isEmpty);
    expect(nodes.builds, 1);
  });

  test(
    'the prefetch refreshes the node names once the warm-up lands',
    () async {
      // Arrange
      final container = makeContainer();
      final sub = container.listen(firstRunNodePrefetchProvider, (_, __) {});
      addTearDown(sub.close);
      await pumpEventQueue();
      expect(nodes.refreshes, 0);

      // Act
      warmUp.complete();
      await pumpEventQueue();

      // Assert
      expect(nodes.refreshes, 1);
    },
  );

  test('the prefetch keeps both passes alive while it is watched', () async {
    // Arrange
    warmUp.complete();
    final container = makeContainer();

    // Act
    final sub = container.listen(firstRunNodePrefetchProvider, (_, __) {});
    addTearDown(sub.close);
    await pumpEventQueue();

    // Assert
    expect(container.exists(cachedNodeStatsProvider), isTrue);
    expect(container.exists(nodeStatsProvider), isTrue);
    expect(container.read(nodeStatsProvider).valueOrNull, isEmpty);
  });
}
