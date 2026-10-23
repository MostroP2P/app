import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/providers/announcements_provider.dart';

/// The Announcements toggle (specs/006-announcement-channel §7): the UI
/// answers the tap, Rust is told, and a refused write rolls back.
class _FakeBridge extends AnnouncementsBridge {
  _FakeBridge({this.stored = true, this.failSet = false, this.gate});

  bool stored;
  final bool failSet;

  /// When set, [enabled] waits on it: the load is in flight.
  final Completer<void>? gate;
  final asked = <bool>[];

  @override
  Future<bool> enabled() async {
    if (gate != null) await gate!.future;
    return stored;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    asked.add(enabled);
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
}
