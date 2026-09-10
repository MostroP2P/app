@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards every first-party surface that states the project's licence.
///
/// The relicensing to GPLv3 (PR #401) changed `LICENSE`, the README and the
/// package manifests, and left the app-store metadata and the in-app About
/// dialog still saying MIT — a mismatch nothing in the build could catch,
/// because each surface is plain data that compiles and ships either way.
/// Users read the About screen and the store listing, not `LICENSE`, so a
/// stale one grants terms the project no longer offers.
///
/// Deliberately excluded: `web/coi-serviceworker.min.js` and its
/// `web/coi-serviceworker.LICENSE` are vendored third-party MIT code and keep
/// their own licence, as do the dependencies inside the npm lockfile.
void main() {
  const spdx = 'GPL-3.0-only';

  group('repository licence', () {
    test('LICENSE holds the GPLv3 text, not MIT', () {
      // Arrange
      final license = File('LICENSE').readAsStringSync();

      // Act / Assert
      expect(license, contains('GNU GENERAL PUBLIC LICENSE'));
      expect(license, contains('Version 3'));
      expect(license, isNot(contains('Permission is hereby granted')));
    });
  });

  group('machine-readable metadata', () {
    test('the Rust crate declares the SPDX identifier', () {
      // Arrange
      final cargo = File('rust/Cargo.toml').readAsStringSync();

      // Act / Assert
      expect(cargo, contains('license = "$spdx"'));
    });

    test('the smoke-test manifest and its lockfile agree', () {
      // Arrange
      final manifest =
          jsonDecode(File('test/web/smoke/package.json').readAsStringSync())
              as Map<String, dynamic>;
      final lock =
          jsonDecode(File('test/web/smoke/package-lock.json').readAsStringSync())
              as Map<String, dynamic>;
      final rootEntry =
          (lock['packages'] as Map<String, dynamic>)[''] as Map<String, dynamic>;

      // Act / Assert — a lockfile left behind makes inventory tooling report
      // the old licence even though package.json is current.
      expect(manifest['license'], spdx);
      expect(rootEntry['license'], spdx);
    });

    test('the Zapstore listing declares GPLv3 in both places', () {
      // Arrange
      final zapstore = File('zapstore.yaml').readAsStringSync();

      // Act / Assert — the machine-readable field and the human-readable
      // feature bullet are indexed separately and drifted apart once already.
      expect(zapstore, contains('license: $spdx'));
      expect(zapstore, isNot(contains('license: MIT')));
      expect(zapstore, isNot(contains('MIT licensed')));
    });
  });

  group('surfaces a user actually reads', () {
    test('the README license section names GPLv3', () {
      // Arrange
      final readme = File('README.md').readAsStringSync();
      final section = readme.substring(readme.indexOf('## License'));

      // Act / Assert
      expect(section, contains('GNU General Public License v3'));
      expect(section, isNot(contains('MIT License')));
    });

    test('the About dialog shows the GPL notice, not the MIT grant', () {
      // Arrange — read the displayed constant itself, so prose in the
      // surrounding comments cannot satisfy or break these assertions.
      final source =
          File('lib/features/about/screens/about_screen.dart').readAsStringSync();
      const opening = "const _gplLicenseNotice = '''";
      final start = source.indexOf(opening);
      expect(start, isNonNegative, reason: 'the displayed notice was renamed');
      final notice = source.substring(
        start + opening.length,
        source.indexOf("''';", start),
      );

      // Act / Assert — `GPL-3.0-only` means the notice must not offer the
      // upgrade path to later versions of the licence.
      expect(notice, contains('GNU General Public License'));
      expect(notice, isNot(contains('Permission is hereby granted')));
      expect(notice, isNot(contains('any later version')));
    });

    test('every locale labels the licence GPLv3', () {
      // Arrange
      final locales = ['en', 'es', 'fr', 'de', 'it'];

      for (final locale in locales) {
        final arb =
            jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
                as Map<String, dynamic>;

        // Act / Assert — a locale left on MIT shows the wrong licence to
        // exactly the users who cannot read the English README.
        expect(arb['aboutLicenseName'], 'GPLv3', reason: 'locale $locale');
        expect(
          arb['aboutLicenseDialogTitle'] as String,
          isNot(contains('MIT')),
          reason: 'locale $locale',
        );
      }
    });
  });
}
