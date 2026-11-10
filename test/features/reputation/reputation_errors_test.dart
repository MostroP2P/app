import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/features/reputation/reputation_errors.dart';
import 'package:mostro/l10n/app_localizations_en.dart';

void main() {
  final en = AppLocalizationsEn();

  test('a known marker wins over the fallback', () {
    // Arrange
    final error = Exception('ReputationAlreadyImported: refused by the node');

    // Act
    final text = localizedReputationError(en, error, fallback: 'export failed');

    // Assert
    expect(text, en.reputationAlreadyImported);
  });

  test('a failure without a marker of its own reads as the fallback', () {
    // Arrange
    final error = Exception('InvalidPayload: answered without an attestation');

    // Act
    final text = localizedReputationError(en, error, fallback: 'export failed');

    // Assert
    expect(text, 'export failed');
  });

  test('without a fallback, a failure reads as an invalid attestation', () {
    // Arrange: the import screen's default, where a paste is involved.
    final error = Exception('InvalidPayload: no attestation');

    // Act
    final text = localizedReputationError(en, error);

    // Assert
    expect(text, en.reputationInvalidAttestation);
  });

  // #882
  test('an answer signed by another key than announced has its own text', () {
    // Arrange
    final error = Exception('ReputationIssuerKeyMismatch: another key');

    // Act
    final text = localizedReputationError(en, error, fallback: 'export failed');

    // Assert
    expect(text, isNot('export failed'));
    expect(text, contains('other than the one it announced'));
  });
}
