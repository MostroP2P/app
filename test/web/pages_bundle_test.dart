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
  final webBuild = File('.github/workflows/web-build.yml');
  final deploy = File('.github/workflows/deploy-pages.yml');
  final ci = File('.github/workflows/ci.yml');
  final smoke = File('test/web/smoke/smoke.mjs');

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

    test(
      'loads the locale sanitizer between the shim and flutter_bootstrap.js',
      () {
        // Arrange
        final html = indexHtml.readAsStringSync();

        // Act
        final shimAt = html.indexOf('<script src="coi-serviceworker.min.js">');
        final sanitizerAt = html.indexOf('<!-- locale-sanitizer');
        final bootstrapAt = html.indexOf('flutter_bootstrap.js');

        // Assert — the sanitizer must rewrite navigator.language(s) before the
        // engine reads them during CanvasKit bootstrap, or an unparseable
        // browser locale throws out of it and the page stays blank (#227). It
        // still comes after the shim, which reloads the page to gain isolation.
        expect(sanitizerAt, greaterThanOrEqualTo(0));
        expect(shimAt, lessThan(sanitizerAt));
        expect(sanitizerAt, lessThan(bootstrapAt));
      },
    );
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

  group('web-build workflow (shared definition)', () {
    test('is reusable, so CI and the deploy cannot drift apart', () {
      // Arrange
      final yaml = webBuild.readAsStringSync();

      // Act / Assert — one definition, two callers (issue #154). A copy-pasted
      // build job is a build that passes on PRs and breaks on deploy.
      expect(yaml, contains('workflow_call'));
    });

    test(
      'builds with the project sub-path and without Flutter service worker',
      () {
        // Arrange
        final yaml = webBuild.readAsStringSync();

        // Act / Assert — a missing --base-href 404s every asset; Flutter's own
        // service worker would evict the isolation shim from the same scope.
        expect(yaml, contains('--base-href'));
        expect(yaml, contains('--pwa-strategy=none'));
      },
    );

    test('compiles the Rust core through scripts/build-web.sh', () {
      // Arrange
      final yaml = webBuild.readAsStringSync();

      // Act / Assert — the shared-memory linker flags live in that script only;
      // `flutter build web` alone never compiles the Rust core.
      expect(yaml, contains('./scripts/build-web.sh --release'));
    });

    test('smoke-tests the release bundle it just built', () {
      // Arrange
      final yaml = webBuild.readAsStringSync();

      // Act / Assert — the static "Verify bundle" greps pass on a page that
      // dies at runtime with DataCloneError, so the bundle must also be loaded
      // in a real browser before it is deployable.
      expect(yaml, contains('smoke.mjs'));
      expect(yaml, contains(r'BUNDLE_DIR'));
    });
  });

  group('deploy-pages workflow', () {
    test('delegates the build to the shared workflow', () {
      // Arrange
      final yaml = deploy.readAsStringSync();

      // Act / Assert — it must call web-build.yml rather than carry its own
      // copy of the toolchain setup and build steps.
      expect(yaml, contains('uses: ./.github/workflows/web-build.yml'));
      expect(yaml, isNot(contains('flutter build web')));
      expect(yaml, isNot(contains('build-web.sh')));
    });

    test('only deploys from main, even on a manual dispatch', () {
      // Arrange
      final yaml = deploy.readAsStringSync();

      // Act / Assert — workflow_dispatch lets the operator pick any ref; without
      // this guard a branch build could be published to the production URL.
      expect(yaml, contains("if: github.ref == 'refs/heads/main'"));
    });

    test('grants Pages and OIDC write tokens to the deploy job only', () {
      // Arrange
      final yaml = deploy.readAsStringSync();

      // Act — everything before the deploy job: workflow-wide scope plus build.
      final beforeDeploy = yaml.substring(0, yaml.indexOf('  deploy:'));

      // Assert — the build job runs codegen and third-party build scripts, so it
      // must not hold a token that can publish or mint an OIDC identity.
      expect(beforeDeploy, isNot(contains('pages: write')));
      expect(beforeDeploy, isNot(contains('id-token: write')));
      expect(yaml, contains('pages: write'));
      expect(yaml, contains('id-token: write'));
    });
  });

  group('CI', () {
    test('runs the shared web build on pull requests', () {
      // Arrange
      final yaml = ci.readAsStringSync();

      // Act / Assert — the whole point of issue #154: a PR that breaks the web
      // target must fail before it lands, not after deploy-pages runs on main.
      expect(yaml, contains('pull_request'));
      expect(yaml, contains('uses: ./.github/workflows/web-build.yml'));
    });
  });

  group('headless smoke test', () {
    test('asserts every precondition a blank page would hide', () {
      // Arrange
      final js = smoke.readAsStringSync();

      // Act / Assert — each of these stands for a documented blank-page cause:
      // lost isolation, an engine that never mounted, a dead FRB worker pool,
      // and errors the page swallows instead of surfacing.
      //
      // Presence, not behaviour: searching source cannot prove the run fails
      // when it should — `if (errors.length)` could be mutated to `if (false)`
      // and every line here would still pass. test/web/smoke/selftest.mjs is
      // what actually holds that down, by running smoke.mjs against fixtures
      // and asserting exit codes. This is only a cheap early warning that runs
      // without a browser.
      expect(js, contains('crossOriginIsolated'));
      expect(js, contains('flutter-view'));
      expect(js, contains(bridgeReadyFlag));
      expect(js, contains('errors.length'));
    });

    test('is itself tested, and that self-test runs in CI', () {
      // Arrange
      final selftest = File('test/web/smoke/selftest.mjs');
      final yaml = webBuild.readAsStringSync();

      // Act / Assert — a healthy bundle goes green whether or not the error
      // checks still work, so without this the gate could rot unnoticed. The
      // fixtures are the executable form of issue #154's "fail on any console
      // error" requirement.
      expect(selftest.existsSync(), isTrue);
      for (final fixture in [
        'healthy',
        'console-error',
        'page-error',
        'store-probe',
        'store-probe-empty',
        'push-worker',
      ]) {
        expect(
          File('test/web/smoke/fixtures/$fixture/index.html').existsSync(),
          isTrue,
          reason: 'missing smoke self-test fixture: $fixture',
        );
      }
      expect(yaml, contains('selftest.mjs'));
    });

    test('serves the bundle cross-origin isolated, under the sub-path', () {
      // Arrange
      final js = smoke.readAsStringSync();

      // Act / Assert — the isolation shim only registers when the headers are
      // absent, and it takes effect one load late; serving the headers directly
      // keeps the first load deterministic. Serving from the root instead of the
      // production sub-path would let --base-href breakage pass here.
      expect(js, contains('Cross-Origin-Opener-Policy'));
      expect(js, contains('Cross-Origin-Embedder-Policy'));
      expect(js, contains('BASE_PATH'));
    });
  });

  group('bond store read-back', () {
    test('Dart, the smoke test and CI agree on the probe and the seed', () {
      // Arrange — the check only runs when CI opts in, reads a flag Dart
      // writes, and seeds the database Dart opens. A rename on any one side
      // turns it into a timeout that reads as a broken bundle, or into a
      // check that never runs.
      final dart =
          File('lib/core/web/store_probe_signal_web.dart').readAsStringSync();
      final location =
          File('lib/core/storage/db_location.dart').readAsStringSync();
      final js = smoke.readAsStringSync();
      final seed = File('test/web/smoke/seed/bond_store.json');
      final yaml = webBuild.readAsStringSync();

      // Act / Assert
      expect(dart, contains(storeProbeFlag));
      expect(js, contains(storeProbeFlag));
      // Production publishes nothing unless the page asks, so the request
      // flag must match too, or the check times out on a healthy bundle.
      expect(dart, contains(storeProbeRequestFlag));
      expect(js, contains(storeProbeRequestFlag));
      expect(js, contains('SMOKE_BOND_STORE'));
      expect(yaml, contains('SMOKE_BOND_STORE: "1"'));
      expect(seed.existsSync(), isTrue);
      expect(seed.readAsStringSync(), contains('"database": "mostro"'));
      expect(location, contains("webDatabaseName = 'mostro'"));
    });
  });

  group('messaging service worker (docs/PUSH_NOTIFICATIONS.md T4.5)', () {
    final worker = File('web/firebase-messaging-sw.js');
    final logic = File('web/push_worker_logic.js');

    test('index.html registers it, relative to the base path, after the shim',
        () {
      // Arrange
      final html = indexHtml.readAsStringSync();

      // Act
      final shimAt = html.indexOf('<script src="coi-serviceworker.min.js">');
      final registerAt = html.indexOf("register('$messagingWorkerScript'");
      final bootstrapAt = html.indexOf('flutter_bootstrap.js');

      // Assert — Firebase's default is the origin root, which under /app/ is
      // a 404; a relative URL resolves against <base href>. After the shim,
      // which must stay the first script.
      expect(registerAt, greaterThan(shimAt));
      expect(registerAt, lessThan(bootstrapAt));
      expect(html, contains("scope: '$messagingWorkerScope'"));
      expect(html, isNot(contains("'/$messagingWorkerScript'")));
    });

    test('routes on no payload field and carries no placeholder config', () {
      // Arrange
      final js = worker.readAsStringSync() + logic.readAsStringSync();

      // Act / Assert — the server's push carries nothing to route on (§2.3).
      expect(js, isNot(contains('REPLACE_ME')));
      expect(js, isNot(contains('routeFromPayload')));
      expect(js, isNot(contains('orderId')));
      expect(js, isNot(contains('disputeId')));
    });

    test('uses the web Firebase config firebase_options.dart ships', () {
      // Arrange — the worker cannot import Dart, so the values are copied;
      // this is what keeps the copy honest after a `flutterfire configure`.
      final options = File('lib/firebase_options.dart').readAsStringSync();
      final web = options.substring(
        options.indexOf('FirebaseOptions web = FirebaseOptions('),
        options.indexOf('FirebaseOptions android'),
      );
      final js = worker.readAsStringSync();

      // Act
      final values = RegExp(r"(apiKey|appId|messagingSenderId|projectId): '([^']+)'")
          .allMatches(web)
          .map((m) => (m.group(1)!, m.group(2)!))
          .toList();

      // Assert
      expect(values, hasLength(4));
      for (final (key, value) in values) {
        expect(js, contains("$key: '$value'"), reason: key);
      }
    });

    test('loads the Firebase JS SDK version the page itself loads', () {
      // Arrange — firebase_core_web pins the SDK the page imports; a worker
      // on another version is a second SDK talking to the same push scope.
      final config = File('.dart_tool/package_config.json').readAsStringSync();
      final root = RegExp(
        r'"name": "firebase_core_web",\s*"rootUri": "file://([^"]+)"',
      ).firstMatch(config)!.group(1)!;
      final pinned = RegExp(r"supportedFirebaseJsSdkVersion = '([^']+)'")
          .firstMatch(
            File('$root/lib/src/firebase_sdk_version.dart').readAsStringSync(),
          )!
          .group(1)!;
      final js = worker.readAsStringSync();

      // Act
      final imported = RegExp(r'firebasejs/([0-9.]+)/')
          .allMatches(js)
          .map((m) => m.group(1))
          .toSet();

      // Assert
      expect(imported, {pinned});
    });

    test('shows the chat-wake notice in the app’s own words', () {
      // Arrange — the Dart background handler uses the arb strings; the
      // worker cannot, so it carries a copy for every locale. The locales
      // come from the translation files, so a new one cannot be missed here.
      final js = logic.readAsStringSync();
      final locales = Directory('lib/l10n')
          .listSync()
          .map((f) => RegExp(r'app_([a-z]{2})\.arb$').firstMatch(f.path)?.group(1))
          .whereType<String>()
          .toList()
        ..sort();
      expect(locales, isNotEmpty);

      // Act / Assert
      for (final locale in locales) {
        final arb = File('lib/l10n/app_$locale.arb').readAsStringSync();
        final body = RegExp(r'"pushNewMessageBody": "([^"]+)"')
            .firstMatch(arb)!
            .group(1)!;
        expect(js, contains("$locale: '$body'"), reason: locale);
      }
    });

    test('Dart, index.html, the smoke test and CI agree on the worker', () {
      // Arrange — Dart registers the same script and scope index.html does;
      // a mismatch is a second registration the token is never bound to.
      final dart = File(
        'lib/features/notifications/services/web_push_web.dart',
      ).readAsStringSync();
      final js = smoke.readAsStringSync();
      final yaml = webBuild.readAsStringSync();

      // Act / Assert
      expect(dart, contains("'$messagingWorkerScript'"));
      expect(dart, contains("'$messagingWorkerScope'"));
      expect(js, contains(messagingWorkerScope));
      expect(js, contains('SMOKE_PUSH_WORKER'));
      expect(yaml, contains('SMOKE_PUSH_WORKER: "1"'));
    });

    test('CI builds with the VAPID define and keeps web push off', () {
      // Arrange
      final yaml = webBuild.readAsStringSync();

      // Act / Assert — the key is public and set per repository (forks use
      // their own); the flag flips only when the push server accepts web.
      expect(yaml, contains('--dart-define=FCM_VAPID_KEY='));
      expect(yaml, isNot(contains('PUSH_WEB_ENABLED')));
      expect(yaml, contains('node --test test/web/push_worker/'));
    });
  });

  group('bridge readiness probe', () {
    test('Dart and the smoke test agree on the flag name', () {
      // Arrange — the probe is the only positive signal that the Rust bridge
      // survived; a rename on one side would silently never be awaited.
      final dart =
          File('lib/core/web/bridge_probe_web.dart').readAsStringSync();
      final js = smoke.readAsStringSync();

      // Act / Assert
      expect(dart, contains(bridgeReadyFlag));
      expect(js, contains(bridgeReadyFlag));
    });
  });
}

/// The `window` property `main()` sets once a real Rust bridge call has
/// returned on web, and that the headless smoke test waits for.
const bridgeReadyFlag = 'mostroBridgeReady';

/// The `window` property the web build sets to what it read back from the
/// persistent store, and that the smoke test compares with its seed.
const storeProbeFlag = 'mostroStoreProbe';

/// The `window` property the smoke test sets before the page loads to ask the
/// web build for the store read-back.
const storeProbeRequestFlag = 'mostroStoreProbeRequested';

/// The FCM service worker, relative to the base path.
const messagingWorkerScript = 'firebase-messaging-sw.js';

/// Its scope — Firebase's own default name, relative to the base path.
const messagingWorkerScope = 'firebase-cloud-messaging-push-scope';
