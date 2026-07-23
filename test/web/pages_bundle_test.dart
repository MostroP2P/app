@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the web deployment against the failure modes that produce a blank page
/// on GitHub Pages instead of an error (issue #212).
///
/// Every assertion here stands for a mistake that compiles, deploys, and only
/// shows up as a white screen in a browser: dropping the cross-origin isolation
/// shim, loading it too late, letting Flutter's service worker take the shim's
/// scope, or forgetting the project sub-path.
void main() {
  final indexHtml = File('web/index.html');
  final shim = File('web/coi-serviceworker.min.js');
  final workflow = File('.github/workflows/deploy-pages.yml');

  group('web/index.html', () {
    test('loads the cross-origin isolation shim', () {
      // Arrange
      final html = indexHtml.readAsStringSync();

      // Act
      final loadsShim = html.contains('coi-serviceworker.min.js');

      // Assert — without it, SharedArrayBuffer is unavailable on a static host
      // and the Rust core cannot start its worker pool.
      expect(loadsShim, isTrue);
    });

    test('loads the shim before flutter_bootstrap.js', () {
      // Arrange
      final html = indexHtml.readAsStringSync();

      // Act
      final shimAt = html.indexOf('<script src="coi-serviceworker.min.js">');
      final bootstrapAt = html.indexOf('flutter_bootstrap.js');

      // Assert — the shim must register (and reload the page) before Flutter
      // starts loading the engine, or the first paint runs un-isolated.
      expect(shimAt, greaterThanOrEqualTo(0));
      expect(bootstrapAt, greaterThanOrEqualTo(0));
      expect(shimAt, lessThan(bootstrapAt));
    });
  });

  group('vendored coi-serviceworker', () {
    test('is committed and non-empty', () {
      // Arrange / Act
      final exists = shim.existsSync();

      // Assert — vendored on purpose: fetching it at build time would make the
      // deployment depend on a third-party host at the worst possible moment.
      expect(exists, isTrue);
      expect(shim.lengthSync(), greaterThan(0));
    });

    test('ships its MIT license alongside it', () {
      // Arrange / Act
      final license = File('web/coi-serviceworker.LICENSE');

      // Assert
      expect(license.existsSync(), isTrue);
      expect(license.readAsStringSync(), contains('MIT License'));
    });
  });

  group('deploy-pages workflow', () {
    test('builds with the project sub-path and without Flutter service worker',
        () {
      // Arrange
      final yaml = workflow.readAsStringSync();

      // Act / Assert — a missing --base-href 404s every asset; Flutter's own
      // service worker would evict the isolation shim from the same scope.
      expect(yaml, contains('--base-href'));
      expect(yaml, contains('--pwa-strategy=none'));
    });

    test('compiles the Rust core through scripts/build-web.sh', () {
      // Arrange
      final yaml = workflow.readAsStringSync();

      // Act / Assert — the shared-memory linker flags live in that script only;
      // `flutter build web` alone never compiles the Rust core.
      expect(yaml, contains('./scripts/build-web.sh --release'));
    });
  });
}
