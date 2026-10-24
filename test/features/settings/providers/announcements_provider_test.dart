import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/providers/announcements_provider.dart';

/// The Announcements toggle (specs/006-announcement-channel §7): the UI
/// answers the tap, Rust is told, and a refused write rolls back.
class _FakeBridge extends AnnouncementsBridge {
  _FakeBridge({
    this.stored = true,
    this.failSet = false,
    this.gate,
    this.holdWrites = false,
  });

  bool stored;
  final bool failSet;

  /// When set, the first [enabled] waits on it: the load is in flight.
  final Completer<void>? gate;

  /// When true, each [setEnabled] waits on its own entry in [writes].
  final bool holdWrites;
  final writes = <Completer<void>>[];
  final asked = <bool>[];
  int reads = 0;

  @override
  Future<bool> enabled() async {
    if (reads++ == 0 && gate != null) await gate!.future;
    return stored;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    asked.add(enabled);
    if (holdWrites) {
      final gate = Completer<void>();
      writes.add(gate);
      await gate.future;
    }
    if (failSet) throw Exception('StorageUnavailable');
    stored = enabled;
  }
}

void main() {
  test('starts on, then loads what Rust persisted', () async {
    // Arrange
    final bridge = _FakeBridge(stored: false);

    // Act
    final notifier = AnnouncementsEnabledNotifier(bridge: bridge);
    expect(notifier.state, isTrue);
    await Future<void>.delayed(Duration.zero);

    // Assert
    expect(notifier.state, isFalse);
  });

  test('a tap is applied first and handed to Rust after', () async {
    // Arrange
    final bridge = _FakeBridge();
    final notifier = AnnouncementsEnabledNotifier(bridge: bridge);
    await Future<void>.delayed(Duration.zero);

    // Act
    final ok = await notifier.set(false);

    // Assert
    expect(ok, isTrue);
    expect(notifier.state, isFalse);
    expect(bridge.asked, [false]);
  });

  test('a write Rust refuses rolls the toggle back', () async {
    // Arrange
    final bridge = _FakeBridge(failSet: true);
    final notifier = AnnouncementsEnabledNotifier(bridge: bridge);
    await Future<void>.delayed(Duration.zero);

    // Act
    final ok = await notifier.set(false);

    // Assert
    expect(ok, isFalse);
    expect(notifier.state, isTrue);
  });

  test('a load that lands after a tap does not undo it', () async {
    // Arrange: the load is still reading when the user taps.
    final gate = Completer<void>();
    final bridge = _FakeBridge(stored: true, gate: gate);
    final notifier = AnnouncementsEnabledNotifier(bridge: bridge);

    // Act
    await notifier.set(false);
    gate.complete();
    await Future<void>.delayed(Duration.zero);

    // Assert: the stale `true` the load read is not applied.
    expect(notifier.state, isFalse);
  });

  test(
    'two quick taps reach Rust one after the other, last one wins',
    () async {
      // Arrange: writes hang until the test lets each one through.
      final bridge = _FakeBridge(holdWrites: true);
      final notifier = AnnouncementsEnabledNotifier(bridge: bridge);
      await Future<void>.delayed(Duration.zero);

      // Act
      final first = notifier.set(false);
      final second = notifier.set(true);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.writes, hasLength(1), reason: 'second waits for first');
      bridge.writes[0].complete();
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(bridge.writes, hasLength(2));
      bridge.writes[1].complete();
      await second;

      // Assert
      expect(bridge.asked, [false, true]);
      expect(bridge.stored, isTrue);
      expect(notifier.state, isTrue);
    },
  );

  test('a write refused while the load is in flight lands on what Rust '
      'holds, not on the pre-tap default', () async {
    // Arrange: persisted off, the load still reading, the write refused.
    final gate = Completer<void>();
    final bridge = _FakeBridge(stored: false, failSet: true, gate: gate);
    final notifier = AnnouncementsEnabledNotifier(bridge: bridge);
    expect(notifier.state, isTrue, reason: 'the default until the load lands');

    // Act
    final ok = await notifier.set(false);
    gate.complete();
    await Future<void>.delayed(Duration.zero);

    // Assert: re-read from Rust, not rolled back to the stale `true`.
    expect(ok, isFalse);
    expect(notifier.state, isFalse);
  });
}
