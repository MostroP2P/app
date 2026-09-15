import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/providers/push_settings_provider.dart';
import 'package:mostro/src/rust/api/types.dart' show PushStatus;

import '../../../support/provider_harness.dart';

PushStatus _status({bool enabled = true, int registered = 0}) => PushStatus(
  enabled: enabled,
  hasToken: true,
  registered: registered,
  wanted: registered,
);

/// Records every call, in order, across the bridge and the device.
class _Calls {
  final log = <String>[];
}

class _FakeBridge extends PushBridge {
  _FakeBridge(this.calls, {this.failSet = false, PushStatus? initial})
    : _current = initial ?? _status();

  final _Calls calls;
  final bool failSet;
  PushStatus _current;
  final updates = StreamController<PushStatus>();
  int watches = 0;

  @override
  Future<PushStatus> status() async => _current;

  @override
  Future<void> setEnabled(bool enabled) async {
    calls.log.add('setEnabled($enabled)');
    if (failSet) throw Exception('StorageUnavailable');
    _current = _status(enabled: enabled);
    updates.add(_current);
  }

  @override
  Future<Future<PushStatus> Function()> watch() async {
    watches++;
    final queue = StreamIterator(updates.stream);
    return () async {
      await queue.moveNext();
      return queue.current;
    };
  }
}

class _FakeDevice implements PushDevice {
  _FakeDevice(this.calls, {this.failRelease = false, this.releaseGate});

  final _Calls calls;
  final bool failRelease;
  final Completer<void>? releaseGate;
  bool hasToken = true;

  @override
  Future<void> release() async {
    calls.log.add('release');
    if (failRelease) throw Exception('deleteToken failed');
    await releaseGate?.future;
    hasToken = false;
  }

  @override
  Future<void> reacquire() async {
    calls.log.add('reacquire');
    hasToken = true;
  }
}

void main() {
  group('PushToggle', () {
    test('off unregisters in Rust first, then lets the token go', () async {
      final calls = _Calls();
      final toggle = PushToggle(
        bridge: _FakeBridge(calls),
        device: _FakeDevice(calls),
      );

      final ok = await toggle.set(false);

      expect(ok, isTrue);
      // Persist opt-out and attempt server cleanup before device cleanup.
      expect(calls.log, ['setEnabled(false)', 'release']);
    });

    test('on enables in Rust first, then hands a fresh token over', () async {
      final calls = _Calls();
      final toggle = PushToggle(
        bridge: _FakeBridge(calls),
        device: _FakeDevice(calls),
      );

      final ok = await toggle.set(true);

      expect(ok, isTrue);
      expect(calls.log, ['setEnabled(true)', 'reacquire']);
    });

    test(
      'a bridge failure reports false and leaves the device alone',
      () async {
        final calls = _Calls();
        final toggle = PushToggle(
          bridge: _FakeBridge(calls, failSet: true),
          device: _FakeDevice(calls),
        );

        final ok = await toggle.set(false);

        expect(ok, isFalse);
        expect(calls.log, ['setEnabled(false)']);
      },
    );

    test('a device failure does not undo what Rust already did', () async {
      // Rust holds the preference; status still reports any pending cleanup.
      final calls = _Calls();
      final toggle = PushToggle(
        bridge: _FakeBridge(calls),
        device: _FakeDevice(calls, failRelease: true),
      );

      final ok = await toggle.set(false);

      expect(ok, isTrue);
    });

    test('shares the pending target and clears it after a failure', () async {
      final pending = <bool?>[];
      final calls = _Calls();
      final toggle = PushToggle(
        bridge: _FakeBridge(calls, failSet: true),
        device: _FakeDevice(calls),
        onPendingChanged: pending.add,
      );

      await toggle.set(false);

      expect(pending, [false, null]);
    });

    test('queues activation behind an opt-out from an earlier visit', () async {
      final calls = _Calls();
      final gate = Completer<void>();
      final device = _FakeDevice(calls, releaseGate: gate);
      final container = createContainer(
        overrides: [
          pushBridgeProvider.overrideWithValue(_FakeBridge(calls)),
          pushDeviceProvider.overrideWithValue(device),
        ],
      );
      final firstVisit = container.listen(
        pushTogglePendingProvider,
        (_, __) {},
      );
      final off = container.read(pushToggleProvider).set(false);
      await Future<void>.delayed(Duration.zero);
      firstVisit.close();

      // A reopened screen sees the same active transaction.
      expect(container.read(pushTogglePendingProvider), false);
      final on = container.read(pushToggleProvider).set(true);
      await Future<void>.delayed(Duration.zero);
      expect(calls.log, ['setEnabled(false)', 'release']);
      gate.complete();
      expect(await Future.wait([off, on]), [true, true]);
      expect(calls.log, [
        'setEnabled(false)',
        'release',
        'setEnabled(true)',
        'reacquire',
      ]);
      expect(device.hasToken, isTrue);
      expect(container.read(pushTogglePendingProvider), isNull);
    });

    test(
      'a failed device operation does not block a later activation',
      () async {
        final calls = _Calls();
        final toggle = PushToggle(
          bridge: _FakeBridge(calls),
          device: _FakeDevice(calls, failRelease: true),
        );
        expect(await Future.wait([toggle.set(false), toggle.set(true)]), [
          true,
          true,
        ]);
        expect(calls.log.last, 'reacquire');
      },
    );
  });

  group('pushStatusProvider', () {
    test('reuses one reader across visits and toggle transactions', () async {
      final calls = _Calls();
      final bridge = _FakeBridge(calls);
      final container = createContainer(
        overrides: [
          pushBridgeProvider.overrideWithValue(bridge),
          pushDeviceProvider.overrideWithValue(_FakeDevice(calls)),
        ],
      );
      for (var i = 0; i < 3; i++) {
        final visit = container.listen(pushStatusProvider, (_, __) {});
        await Future<void>.delayed(Duration.zero);
        visit.close();
        await Future<void>.delayed(Duration.zero);
      }
      await container.read(pushToggleProvider).set(false);
      await Future<void>.delayed(Duration.zero);
      final reopened = container.listen(pushStatusProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(bridge.watches, 1);
      expect(container.read(pushStatusProvider).requireValue.enabled, isFalse);
      reopened.close();
    });

    test('starts from the persisted status, then follows the stream', () async {
      final calls = _Calls();
      final bridge = _FakeBridge(calls, initial: _status(registered: 1));
      final container = createContainer(
        overrides: [pushBridgeProvider.overrideWithValue(bridge)],
      );
      final seen = <int>[];
      container.listen(pushStatusProvider, (_, next) {
        final status = next.valueOrNull;
        if (status != null) seen.add(status.registered);
      }, fireImmediately: true);

      await Future<void>.delayed(Duration.zero);
      bridge.updates.add(_status(registered: 3));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(seen, [1, 3]);
    });
  });
}
