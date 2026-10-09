import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/features/account/providers/my_reputation_provider.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/src/rust/api/my_reputation.dart';

MyReputation _rep(String node, {int reviews = 3, double rating = 4.5}) =>
    MyReputation(
      nodePubkey: node,
      rating: rating,
      reviews: reviews,
      operatingDays: 10,
      fetchedAt: 1,
    );

/// A core double: a cache per node, a scripted answer, and a change feed.
class _FakeCore {
  _FakeCore({Map<String, MyReputation>? cache}) : cache = cache ?? {};

  final Map<String, MyReputation> cache;
  String activeNode = 'node-a';
  int refreshes = 0;
  Completer<MyReputation?>? pending;
  final _feeds = <StreamController<MyReputation>>[];

  /// A new single-subscription feed per call, like the bridge's.
  Stream<MyReputation> openChanges() {
    final feed = StreamController<MyReputation>();
    _feeds.add(feed);
    return feed.stream;
  }

  /// Rust stored [answer]: every open feed hears it.
  void stored(MyReputation answer) {
    for (final feed in _feeds) {
      feed.add(answer);
    }
  }

  /// Holds cache reads back while set, like a slow store.
  Completer<void>? readGate;

  Future<MyReputation?> readCache() async {
    final node = activeNode;
    await readGate?.future;
    return cache[node];
  }

  Future<MyReputation?> refresh() async {
    refreshes++;
    final answer = await (pending = Completer<MyReputation?>()).future;
    if (answer != null) cache[answer.nodePubkey] = answer;
    return answer;
  }

  MyReputationNotifier notifier() => MyReputationNotifier(
    readCache: readCache,
    refresh: refresh,
    changes: openChanges,
  );
}

void main() {
  test('starts from the cached answer of the active node', () async {
    // Arrange
    final core = _FakeCore(cache: {'node-a': _rep('node-a')});

    // Act
    final notifier = core.notifier();
    await pumpEventQueue();

    // Assert
    expect(notifier.state.reputation, _rep('node-a'));
    expect(notifier.state.loading, isFalse);
  });

  test('a refresh is loading until the node answers, then shows it', () async {
    final core = _FakeCore();
    final notifier = core.notifier();
    await pumpEventQueue();

    final done = notifier.refresh();
    expect(notifier.state.loading, isTrue);
    core.pending!.complete(_rep('node-a', reviews: 7));
    await done;

    expect(notifier.state.loading, isFalse);
    expect(notifier.state.reputation?.reviews, 7);
  });

  test('a refresh with no answer keeps the cached one', () async {
    final core = _FakeCore(cache: {'node-a': _rep('node-a')});
    final notifier = core.notifier();
    await pumpEventQueue();

    final done = notifier.refresh();
    core.pending!.complete(null);
    await done;

    expect(notifier.state.reputation, _rep('node-a'));
    expect(notifier.state.loading, isFalse);
  });

  test('a failed refresh stops loading and keeps the cached one', () async {
    final notifier = MyReputationNotifier(
      readCache: () async => _rep('node-a'),
      refresh: () async => throw StateError('relay down'),
      changes: Stream.empty,
    );
    await pumpEventQueue();

    await notifier.refresh();

    expect(notifier.state.reputation, _rep('node-a'));
    expect(notifier.state.loading, isFalse);
  });

  test('an answer stored in the background is picked up', () async {
    final core = _FakeCore();
    final notifier = core.notifier();
    await pumpEventQueue();

    core.cache['node-a'] = _rep('node-a', reviews: 9);
    core.stored(core.cache['node-a']!);
    await pumpEventQueue();

    expect(notifier.state.reputation?.reviews, 9);
  });

  test('an answer from a node the user left is not shown', () async {
    final core = _FakeCore(cache: {'node-a': _rep('node-a')});
    final notifier = core.notifier();
    await pumpEventQueue();

    core.cache['node-b'] = _rep('node-b', reviews: 9);
    core.stored(core.cache['node-b']!);
    await pumpEventQueue();

    expect(notifier.state.reputation, _rep('node-a'));
  });

  group('provider wiring', () {
    late _FakeCore core;
    late ProviderContainer container;

    setUp(() {
      core = _FakeCore(
        cache: {'node-a': _rep('node-a'), 'node-b': _rep('node-b')},
      );
      container = ProviderContainer(
        overrides: [
          mostroPubkeyProvider.overrideWith((ref) => 'node-a'),
          privacyModeProvider.overrideWith(
            (ref) => PrivacyModeNotifier(
              initialValue: true,
              setCore: (_) async {},
              persist: (_) async {},
            ),
          ),
          myReputationCoreProvider.overrideWithValue(
            MyReputationCore(
              readCache: core.readCache,
              refresh: core.refresh,
              changes: core.openChanges,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
    });

    test('switching node shows the new node\'s cached answer', () async {
      container.read(myReputationProvider);
      await pumpEventQueue();

      core.activeNode = 'node-b';
      container.read(mostroPubkeyProvider.notifier).state = 'node-b';
      await pumpEventQueue();

      expect(container.read(myReputationProvider).reputation, _rep('node-b'));
    });

    test('a node switch never shows the previous node\'s answer', () async {
      // Arrange
      container.read(myReputationProvider);
      await pumpEventQueue();
      final gate = core.readGate = Completer<void>();

      // Act
      core.activeNode = 'node-b';
      container.read(mostroPubkeyProvider.notifier).state = 'node-b';
      await pumpEventQueue();

      // Assert
      expect(container.read(myReputationProvider).reputation, isNull);
      gate.complete();
      await pumpEventQueue();
      expect(container.read(myReputationProvider).reputation, _rep('node-b'));
    });

    test('a late answer from the node the user left is not shown', () async {
      final notifier = container.read(myReputationProvider.notifier);
      await pumpEventQueue();
      final asked = notifier.refresh();

      core.activeNode = 'node-b';
      container.read(mostroPubkeyProvider.notifier).state = 'node-b';
      await pumpEventQueue();
      core.pending!.complete(_rep('node-a', reviews: 9));
      await asked;

      expect(
        container.read(myReputationProvider).reputation,
        _rep('node-b'),
      );
    });

    test('an identity swap rebuilds it without breaking it', () async {
      // Arrange: an identity swap invalidates the provider (#755).
      container.read(myReputationProvider);
      await pumpEventQueue();

      // Act
      container.invalidate(myReputationProvider);

      // Assert
      expect(() => container.read(myReputationProvider), returnsNormally);
      await pumpEventQueue();
      expect(container.read(myReputationProvider).reputation, _rep('node-a'));
    });

    test('leaving full privacy asks the node', () async {
      container.read(myReputationProvider);
      await pumpEventQueue();
      expect(core.refreshes, 0);

      await container.read(privacyModeProvider.notifier).setPrivacyMode(false);
      await pumpEventQueue();

      expect(core.refreshes, 1);
    });
  });
}
