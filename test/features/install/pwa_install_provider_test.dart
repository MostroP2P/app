import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/web/pwa_install_bridge.dart';
import 'package:mostro/features/install/providers/pwa_install_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_pwa_install_bridge.dart';
import '../../support/provider_harness.dart';

/// A container on [platform] whose page is [bridge], with the install offer
/// read once its stored answer has loaded.
Future<ProviderContainer> _offerOn(
  FakePwaInstallBridge bridge, {
  TargetPlatform platform = TargetPlatform.android,
}) async {
  final container = createContainer(
    overrides: [
      pwaInstallBridgeProvider.overrideWithValue(bridge),
      pwaInstallPlatformProvider.overrideWithValue(platform),
    ],
  );
  container.listen(pwaInstallProvider, (_, __) {});
  await container.read(pwaInstallProvider.notifier).loaded;
  return container;
}

PwaInstallState _state(ProviderContainer c) => c.read(pwaInstallProvider);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('which way the app can install itself (#778)', () {
    test('Android: the browser dialog, once the browser says it can', () async {
      // Arrange
      final bridge = FakePwaInstallBridge(canPromptNatively: true);

      // Act
      final c = await _offerOn(bridge);

      // Assert
      expect(_state(c).route, PwaInstallRoute.native);
      expect(_state(c).offersCard, isTrue);
    });

    test(
      'Android: nothing while the browser has not fired its event',
      () async {
        // Arrange — Firefox never fires it; Chrome doesn't once installed.
        final bridge = FakePwaInstallBridge();

        // Act
        final c = await _offerOn(bridge);

        // Assert
        expect(_state(c).route, PwaInstallRoute.none);
        expect(_state(c).offersCard, isFalse);
      },
    );

    test('iOS: instructions, since Safari has no install API', () async {
      // Arrange
      final bridge = FakePwaInstallBridge();

      // Act
      final c = await _offerOn(bridge, platform: TargetPlatform.iOS);

      // Assert
      expect(_state(c).route, PwaInstallRoute.instructions);
      expect(_state(c).offersCard, isTrue);
    });

    test('nothing when the page already runs as the installed app', () async {
      // Arrange
      final bridge = FakePwaInstallBridge(
        isStandalone: true,
        canPromptNatively: true,
      );

      // Act
      final android = await _offerOn(bridge);
      final ios = await _offerOn(bridge, platform: TargetPlatform.iOS);

      // Assert
      expect(_state(android).route, PwaInstallRoute.none);
      expect(_state(ios).route, PwaInstallRoute.none);
    });

    test('nothing off web: a native build is already installed', () async {
      // Arrange
      final bridge = FakePwaInstallBridge(isWeb: false);

      // Act
      final c = await _offerOn(bridge, platform: TargetPlatform.iOS);

      // Assert
      expect(_state(c).route, PwaInstallRoute.none);
      expect(_state(c).offersCard, isFalse);
    });

    test('desktop: installable from Settings, but no card', () async {
      // Arrange
      final bridge = FakePwaInstallBridge(canPromptNatively: true);

      // Act
      final c = await _offerOn(bridge, platform: TargetPlatform.linux);

      // Assert
      expect(_state(c).canInstall, isTrue);
      expect(_state(c).offersCard, isFalse);
    });
  });

  group('the card asks once', () {
    test('an answer is kept across launches', () async {
      // Arrange
      final bridge = FakePwaInstallBridge(canPromptNatively: true);
      final first = await _offerOn(bridge);

      // Act
      await first.read(pwaInstallProvider.notifier).markAnswered();
      final relaunch = await _offerOn(bridge);

      // Assert — Settings still offers the install.
      expect(_state(first).offersCard, isFalse);
      expect(_state(relaunch).offersCard, isFalse);
      expect(_state(relaunch).canInstall, isTrue);
    });

    test('an ignored card shows again on the next launch', () async {
      // Arrange
      final bridge = FakePwaInstallBridge(canPromptNatively: true);
      await _offerOn(bridge);

      // Act
      final relaunch = await _offerOn(bridge);

      // Assert
      expect(_state(relaunch).offersCard, isTrue);
    });

    test('no card until the stored answer has been read', () {
      // Arrange
      SharedPreferences.setMockInitialValues({kPwaInstallAnsweredKey: true});
      final c = createContainer(
        overrides: [
          pwaInstallBridgeProvider.overrideWithValue(
            FakePwaInstallBridge(canPromptNatively: true),
          ),
          pwaInstallPlatformProvider.overrideWithValue(TargetPlatform.android),
        ],
      );

      // Act — read synchronously, before the load resolves.
      final state = c.read(pwaInstallProvider);

      // Assert — a card that flashes and vanishes would be worse than none.
      expect(state.offersCard, isFalse);
    });
  });

  group('the page changes underneath', () {
    test('the browser firing its event late brings the card', () async {
      // Arrange
      final bridge = FakePwaInstallBridge();
      final c = await _offerOn(bridge);

      // Act
      bridge.fireInstallable();
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(_state(c).route, PwaInstallRoute.native);
    });

    test('installing removes the offer everywhere', () async {
      // Arrange
      final bridge = FakePwaInstallBridge(canPromptNatively: true);
      final c = await _offerOn(bridge);

      // Act
      bridge.fireInstalled();
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(_state(c).canInstall, isFalse);
    });

    test(
      'the browser dialog is spent once shown, whatever the answer',
      () async {
        // Arrange
        final bridge = FakePwaInstallBridge(
          canPromptNatively: true,
          outcome: PwaPromptOutcome.dismissed,
        );
        final c = await _offerOn(bridge);

        // Act
        final outcome =
            await c.read(pwaInstallProvider.notifier).promptNatively();

        // Assert
        expect(outcome, PwaPromptOutcome.dismissed);
        expect(bridge.prompts, 1);
        expect(_state(c).route, PwaInstallRoute.none);
      },
    );
  });

  group('Install', () {
    test('asks the browser within the tap, before the answer is stored', () {
      // Arrange — a disk that never answers. Chrome only shows its dialog
      // while the tap's user activation lasts, so nothing may be awaited
      // before it is asked for.
      final bridge = FakePwaInstallBridge(canPromptNatively: true);
      final stalled = Completer<SharedPreferences>();
      final notifier = PwaInstallNotifier(
        bridge: bridge,
        platform: TargetPlatform.android,
        prefs: () => stalled.future,
      );
      addTearDown(notifier.dispose);

      // Act
      unawaited(notifier.install());

      // Assert
      expect(bridge.prompts, 1);
      expect(notifier.state.answered, isTrue);
    });

    test('counts as the answer on iOS, where nothing is prompted', () async {
      // Arrange
      final bridge = FakePwaInstallBridge();
      final c = await _offerOn(bridge, platform: TargetPlatform.iOS);

      // Act
      final outcome = await c.read(pwaInstallProvider.notifier).install();

      // Assert
      expect(outcome, PwaPromptOutcome.unavailable);
      expect(bridge.prompts, 0);
      expect(_state(c).offersCard, isFalse);
    });

    test('an answer given while the disk is still read is kept', () async {
      // Arrange
      final bridge = FakePwaInstallBridge(canPromptNatively: true);
      final c = createContainer(
        overrides: [
          pwaInstallBridgeProvider.overrideWithValue(bridge),
          pwaInstallPlatformProvider.overrideWithValue(TargetPlatform.android),
        ],
      );
      final notifier = c.read(pwaInstallProvider.notifier);

      // Act — answered before the load resolved.
      await notifier.markAnswered();
      await notifier.loaded;

      // Assert
      expect(_state(c).answered, isTrue);
      expect(_state(c).offersCard, isFalse);
    });
  });
}
