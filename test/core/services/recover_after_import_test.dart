import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/services/identity_service.dart';

void main() {
  group('recoverAfterImport', () {
    test('recovers the trades and reports how many came back', () async {
      // Act
      final outcome = await IdentityService.recoverAfterImport(
        isPrivacyMode: () async => false,
        recover: () async => 3,
      );

      // Assert
      expect(outcome, const RecoveryOutcome.recovered(3));
    });

    test(
      'skips the daemon in privacy mode, which has no account to recover',
      () async {
        // Arrange
        var asked = false;

        // Act
        final outcome = await IdentityService.recoverAfterImport(
          isPrivacyMode: () async => true,
          recover: () async {
            asked = true;
            return 0;
          },
        );

        // Assert
        expect(outcome, const RecoveryOutcome.skipped());
        expect(asked, isFalse);
      },
    );

    test(
      'a failed recovery is reported, never thrown: the import stands',
      () async {
        // Act
        final outcome = await IdentityService.recoverAfterImport(
          isPrivacyMode: () async => false,
          recover: () async => throw Exception('NoDaemonResponse'),
        );

        // Assert
        expect(outcome, const RecoveryOutcome.failed());
      },
    );
  });
}
