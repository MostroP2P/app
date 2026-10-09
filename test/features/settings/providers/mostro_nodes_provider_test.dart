import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/src/rust/api/types.dart' show MostroNodeEntry;

import '../../../support/provider_harness.dart';

/// Each relay round trip waits on a completer the test resolves, and is
/// counted — no Rust bridge.
class _GatedNodesNotifier extends MostroNodesNotifier {
  final List<Completer<List<MostroNodeEntry>>> fetches = [];

  @override
  Future<List<MostroNodeEntry>> build() async => const [];

  @override
  Future<List<MostroNodeEntry>> fetchMetadata() {
    final fetch = Completer<List<MostroNodeEntry>>();
    fetches.add(fetch);
    return fetch.future;
  }
}

void main() {
  late _GatedNodesNotifier notifier;

  Future<void> start() async {
    notifier = _GatedNodesNotifier();
    final container = createContainer(
      overrides: [mostroNodesProvider.overrideWith(() => notifier)],
    );
    await container.read(mostroNodesProvider.future);
  }

  test('a refresh during another one joins it', () async {
    // Arrange
    await start();
    final first = notifier.refreshMetadata();

    // Act
    final second = notifier.refreshMetadata();
    notifier.fetches.single.complete(const []);
    await Future.wait([first, second]);

    // Assert
    expect(notifier.fetches, hasLength(1));
  });

  test(
    'refreshMetadataAfterPending runs again after the one in flight',
    () async {
      // Arrange
      await start();
      final first = notifier.refreshMetadata();

      // Act
      final again = notifier.refreshMetadataAfterPending();
      await pumpEventQueue();
      expect(notifier.fetches, hasLength(1), reason: 'waits for the first');
      notifier.fetches.first.complete(const []);
      await first;
      await pumpEventQueue();

      // Assert
      expect(notifier.fetches, hasLength(2));
      notifier.fetches.last.complete(const []);
      await again;
    },
  );

  test('refreshMetadataAfterPending refreshes at once when idle', () async {
    await start();

    final run = notifier.refreshMetadataAfterPending();
    await pumpEventQueue();

    expect(notifier.fetches, hasLength(1));
    notifier.fetches.single.complete(const []);
    await run;
  });
}
