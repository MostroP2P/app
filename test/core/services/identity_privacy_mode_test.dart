import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/services/identity_service.dart';

/// The Rust privacy flag starts off at every launch; loading a stored
/// identity must hand it the saved value.
void main() {
  const words = [
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'abandon',
    'about',
  ];

  for (final enabled in [true, false]) {
    test('a stored privacy mode $enabled reaches the core at load', () async {
      // Arrange
      final applied = <bool>[];
      final stored = StoredIdentity(
        words: words,
        tradeKeyIndex: 3,
        privacyMode: enabled,
        createdAtMillis: 0,
      );

      // Act
      await IdentityService.loadExisting(
        stored,
        load: (_) async {},
        applyPrivacyMode: (value) async => applied.add(value),
      );

      // Assert
      expect(applied, [enabled]);
    });
  }
}
