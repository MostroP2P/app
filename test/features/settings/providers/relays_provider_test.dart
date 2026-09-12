import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/models/settings_rows.dart';
import 'package:mostro/features/settings/providers/relay_auto_sync_provider.dart';
import 'package:mostro/features/settings/providers/relays_provider.dart';
import 'package:mostro/src/rust/api/types.dart'
    show RelayInfo, RelaySource, RelayStatus;

import '../../../support/provider_harness.dart';

RelayInfo _relay(
  String url, {
  bool isActive = true,
  bool isDefault = true,
  RelayStatus status = RelayStatus.connected,
}) => RelayInfo(
  url: url,
  isActive: isActive,
  isDefault: isDefault,
  source: isDefault ? RelaySource.default_ : RelaySource.userAdded,
  isBlacklisted: false,
  status: status,
);

/// Records what the mutator was asked to do, and can be told to fail.
class _FakeMutator extends RelayMutator {
  _FakeMutator({this.fail = false});

  final bool fail;
  final added = <String>[];
  final removed = <String>[];

  @override
  Future<void> add(String url) async {
    added.add(url);
    if (fail) throw StateError('bridge refused');
  }

  @override
  Future<void> remove(String url) async {
    removed.add(url);
    if (fail) throw StateError('bridge refused');
  }
}

/// Stands in for the Rust broadcast receiver: `push` makes the next `read`
/// complete, and a read with nothing queued waits, as the real one does.
class _FakeStatusStream {
  final _pending = <RelayInfo>[];
  Completer<RelayInfo>? _waiting;

  void push(RelayInfo info) {
    final waiting = _waiting;
    if (waiting != null) {
      _waiting = null;
      waiting.complete(info);
    } else {
      _pending.add(info);
    }
  }

  Future<RelayInfo?> read() {
    if (_pending.isNotEmpty) {
      return Future.value(_pending.removeAt(0));
    }
    return (_waiting = Completer<RelayInfo>()).future;
  }
}

/// Builds a container whose relay list comes from [loaded] and whose status
/// stream emits whatever is pushed onto the returned fake.
({ProviderContainer container, _FakeStatusStream status}) _harness({
  required List<RelayInfo> loaded,
  RelayMutator? mutator,
}) {
  final status = _FakeStatusStream();
  final container = createContainer(
    overrides: [
      relayListLoaderProvider.overrideWithValue(() async => loaded),
      relayStatusStreamProvider.overrideWithValue(() async => status.read),
      if (mutator != null) relayMutatorProvider.overrideWithValue(mutator),
      // The real provider needs the bridge; the list is driven directly here.
      relayAutoSyncProvider.overrideWith((ref) => const Stream.empty()),
    ],
  );
  return (container: container, status: status);
}

void main() {
  group('canonicalRelayUrl', () {
    test('collapses trailing slashes and surrounding space', () {
      expect(canonicalRelayUrl('  wss://a.example/// '), 'wss://a.example');
    });
  });

  group('RelaysNotifier', () {
    test('seeds with the defaults before the first load returns', () {
      final h = _harness(loaded: [_relay('wss://loaded')]);
      // Read synchronously: the seed is what the screen draws first.
      expect(h.container.read(relaysProvider), isNotEmpty);
    });

    test('replaces the seed with what the bridge reports', () async {
      final h = _harness(loaded: [_relay('wss://a'), _relay('wss://b')]);
      h.container.read(relaysProvider);
      await pumpEventQueue();

      expect(
        h.container.read(relaysProvider).map((r) => r.url),
        ['wss://a', 'wss://b'],
      );
    });

    test('folds a status change in without reordering the list', () async {
      final h = _harness(loaded: [_relay('wss://a'), _relay('wss://b')]);
      h.container.read(relaysProvider);
      await pumpEventQueue();

      h.status.push(_relay('wss://a', status: RelayStatus.error));
      await pumpEventQueue();

      final relays = h.container.read(relaysProvider);
      // Same order — a row that moved under the finger makes the user toggle
      // the wrong relay.
      expect(relays.map((r) => r.url), ['wss://a', 'wss://b']);
      expect(relayHealth(relays.first), RelayHealth.offline);
      expect(relayHealth(relays.last), RelayHealth.connected);
    });

    test('appends a relay the stream reports but the list has not seen',
        () async {
      final h = _harness(loaded: [_relay('wss://a')]);
      h.container.read(relaysProvider);
      await pumpEventQueue();

      h.status.push(_relay('wss://new'));
      await pumpEventQueue();

      expect(
        h.container.read(relaysProvider).map((r) => r.url),
        ['wss://a', 'wss://new'],
      );
    });

    test('setActive applies optimistically and calls the bridge', () async {
      final mutator = _FakeMutator();
      final h = _harness(loaded: [_relay('wss://a')], mutator: mutator);
      h.container.read(relaysProvider);
      await pumpEventQueue();

      final ok = await h.container
          .read(relaysProvider.notifier)
          .setActive('wss://a', false);

      expect(ok, isTrue);
      expect(mutator.removed, ['wss://a']);
      expect(h.container.read(relaysProvider).single.isActive, isFalse);
    });

    test('setActive rolls the row back when the bridge refuses', () async {
      final mutator = _FakeMutator(fail: true);
      final h = _harness(loaded: [_relay('wss://a')], mutator: mutator);
      h.container.read(relaysProvider);
      await pumpEventQueue();

      final ok = await h.container
          .read(relaysProvider.notifier)
          .setActive('wss://a', false);

      expect(ok, isFalse);
      expect(h.container.read(relaysProvider).single.isActive, isTrue);
    });

    test('add canonicalizes the URL it stores and sends', () async {
      final mutator = _FakeMutator();
      final h = _harness(loaded: [_relay('wss://a')], mutator: mutator);
      h.container.read(relaysProvider);
      await pumpEventQueue();

      await h.container.read(relaysProvider.notifier).add('  wss://b/ ');

      expect(mutator.added, ['wss://b']);
      expect(h.container.read(relaysProvider).last.url, 'wss://b');
    });

    test('add drops the optimistic row when the bridge refuses', () async {
      final mutator = _FakeMutator(fail: true);
      final h = _harness(loaded: [_relay('wss://a')], mutator: mutator);
      h.container.read(relaysProvider);
      await pumpEventQueue();

      final ok = await h.container.read(relaysProvider.notifier).add('wss://b');

      expect(ok, isFalse);
      expect(h.container.read(relaysProvider).map((r) => r.url), ['wss://a']);
    });

    test('remove restores the row when the bridge refuses', () async {
      final mutator = _FakeMutator(fail: true);
      final h = _harness(
        loaded: [_relay('wss://a'), _relay('wss://b', isDefault: false)],
        mutator: mutator,
      );
      h.container.read(relaysProvider);
      await pumpEventQueue();

      final ok =
          await h.container.read(relaysProvider.notifier).remove('wss://b');

      expect(ok, isFalse);
      expect(
        h.container.read(relaysProvider).map((r) => r.url),
        ['wss://a', 'wss://b'],
      );
    });
  });
}
