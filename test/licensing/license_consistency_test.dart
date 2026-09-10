@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards every first-party surface that states the project's licence.
///
/// Relicensing touches `LICENSE`, the README and the package manifests, and it
/// is easy to stop there — leaving the app-store listing and the in-app About
/// dialog granting terms the project no longer offers. Nothing in the build
/// catches that: each surface is plain data that compiles and ships whatever it
/// says. Users read the About screen and the store listing, not `LICENSE`.
/// It happened once already on the GPLv3 attempt (#401).
///
/// Deliberately excluded: `web/coi-serviceworker.min.js` and its
/// `web/coi-serviceworker.LICENSE` are vendored third-party MIT code and keep
/// their own licence, as do the dependencies nested in the npm lockfile.
void main() {
  const spdx = 'AGPL-3.0-only';

  group('repository licence', () {
    test('LICENSE holds the AGPLv3 text, not GPLv3 or MIT', () {
      // Arrange
      final license = File('LICENSE').readAsStringSync();

      // Act / Assert — the Affero name is what separates this text from plain
      // GPLv3, whose opening line is otherwise nearly identical.
      expect(license, contains('GNU AFFERO GENERAL PUBLIC LICENSE'));
      expect(license, contains('Version 3, 19 November 2007'));
      expect(license, isNot(contains('Permission is hereby granted')));
    });

    test('LICENSE carries the network-interaction clause', () {
      // Arrange
      final license = File('LICENSE').readAsStringSync();

      // Act / Assert — section 13 is the whole reason for choosing AGPL over
      // GPL, and plain GPLv3 has no such section, so this also catches the
      // wrong licence being pasted in.
      expect(license, contains('13. Remote Network Interaction'));

      // And the file must be whole: a copy truncated below section 13 still
      // satisfies the check above while dropping the terms that follow it.
      expect(license.trimRight(), endsWith('<https://www.gnu.org/licenses/>.'));
      expect(license, contains('How to Apply These Terms'));
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

      // Act / Assert — a lockfile left behind makes licence-inventory tooling
      // report the old licence even though package.json is current.
      expect(manifest['license'], spdx);
      expect(rootEntry['license'], spdx);
    });

    test('the Zapstore listing declares AGPLv3 in both places', () {
      // Arrange
      final zapstore = File('zapstore.yaml').readAsStringSync();

      // Act / Assert — the machine-readable field and the human-readable
      // feature bullet are indexed separately and drift apart independently.
      expect(zapstore, contains('license: $spdx'));
      expect(zapstore, isNot(contains('license: MIT')));
      expect(zapstore, isNot(contains('MIT licensed')));
    });
  });

  group('surfaces a user actually reads', () {
    test('the README license section names AGPLv3', () {
      // Arrange
      final readme = File('README.md').readAsStringSync();
      final section = readme.substring(readme.indexOf('## License'));

      // Act / Assert
      expect(section, contains('GNU Affero General Public License v3'));
      expect(section, isNot(contains('MIT License')));
    });

    test('the About dialog shows the AGPL notice, not the MIT grant', () {
      // Arrange — read the displayed constant itself, so prose in the
      // surrounding comments cannot satisfy or break these assertions.
      final source =
          File('lib/features/about/screens/about_screen.dart').readAsStringSync();
      const opening = "const _agplLicenseNotice = '''";
      final start = source.indexOf(opening);
      expect(start, isNonNegative, reason: 'the displayed notice was renamed');
      final notice = source.substring(
        start + opening.length,
        source.indexOf("''';", start),
      );

      // Act / Assert — `AGPL-3.0-only` means the notice must name the Affero
      // licence and must not offer the upgrade path to later versions.
      expect(notice, contains('GNU Affero General Public License'));
      expect(notice, isNot(contains('Permission is hereby granted')));
      expect(notice, isNot(contains('any later version')));
    });

    test('every locale labels the licence AGPLv3', () {
      // Arrange
      final locales = ['en', 'es', 'fr', 'de', 'it'];

      for (final locale in locales) {
        final arb =
            jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
                as Map<String, dynamic>;

        // Act / Assert — a locale left behind shows the wrong licence to
        // exactly the users who cannot read the English README.
        expect(arb['aboutLicenseName'], 'AGPLv3', reason: 'locale $locale');
        expect(
          arb['aboutLicenseDialogTitle'] as String,
          contains('Affero'),
          reason: 'locale $locale',
        );
      }
    });

    test('the About screen offers this app own source, per section 13', () {
      // Arrange — read the declaration's value, not the whole file, so the
      // comment explaining the old URL cannot fail the assertion below.
      final source =
          File('lib/features/about/screens/about_screen.dart').readAsStringSync();
      final declaration =
          RegExp(r"const _githubUrl =\s*'([^']+)'").firstMatch(source);
      expect(declaration, isNotNull, reason: 'the source link was renamed');
      final url = declaration!.group(1)!;

      // Act / Assert — under AGPL the repository link stops being decorative:
      // section 13 asks a network-interacting program to offer its users the
      // Corresponding Source, and this link is that offer. It used to point at
      // `MostroP2P/mostro-mobile`, which does not exist, so the offer was a
      // 404; `MostroP2P/mobile` is the v1 app, not this one.
      expect(url, 'https://github.com/MostroP2P/app');
    });

    test('the displayed repository name matches the link it opens', () {
      // Arrange
      final locales = ['en', 'es', 'fr', 'de', 'it'];

      for (final locale in locales) {
        final arb =
            jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
                as Map<String, dynamic>;

        // Act / Assert — the row shows this label and opens the URL above.
        // They drifted apart once: the label read `mostro-mobile` while the
        // link had already moved, which reads as a link to some other project.
        expect(arb['aboutGithubRepoName'], 'MostroP2P/app',
            reason: 'locale $locale');
      }
    });
  });
}
