import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';

/// The Rust flag lives in memory, so the toggle has to be saved too, or every
/// restart silently goes back to reputation mode and the next trade is signed
/// with the identity key.
void main() {
  test('turning privacy mode on sets the core flag and saves it', () async {
    // Arrange
    final core = <bool>[];
    final saved = <bool>[];
    final notifier = PrivacyModeNotifier(
      initialValue: false,
      setCore: (enabled) async => core.add(enabled),
      persist: (enabled) async => saved.add(enabled),
    );

    // Act
    await notifier.setPrivacyMode(true);

    // Assert
    expect(notifier.state, isTrue);
    expect(core, [true]);
    expect(saved, [true]);
  });

  test('a core that refuses the change saves nothing', () async {
    // Arrange
    final saved = <bool>[];
    final notifier = PrivacyModeNotifier(
      initialValue: false,
      setCore: (_) async => throw Exception('bridge down'),
      persist: (enabled) async => saved.add(enabled),
    );

    // Act
    await notifier.setPrivacyMode(true);

    // Assert
    expect(notifier.state, isFalse);
    expect(saved, isEmpty);
  });

  test('a failed save puts the core flag back, so the two agree', () async {
    // Arrange
    final core = <bool>[];
    final notifier = PrivacyModeNotifier(
      initialValue: false,
      setCore: (enabled) async => core.add(enabled),
      persist: (_) async => throw Exception('keystore locked'),
    );

    // Act
    await notifier.setPrivacyMode(true);

    // Assert
    expect(notifier.state, isFalse);
    expect(core, [true, false]);
  });
}
