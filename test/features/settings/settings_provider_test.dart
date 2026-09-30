import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for the saved-language normalization: the effective locale, the
/// persisted [AppSettingsState.language] and the Settings picker must always
/// agree, including for unsupported (`pt`) and region-qualified (`es-MX`)
/// stored values.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // Force a deterministic, supported device locale so the device-default
  // fallback is predictable across machines and CI.
  setUp(() {
    binding.platformDispatcher.localesTestValue = const [Locale('en')];
  });
  tearDown(() {
    binding.platformDispatcher.clearLocalesTestValue();
  });

  Future<AppSettingsState> stateWith(String? language) async {
    SharedPreferences.setMockInitialValues(
      language == null ? {} : {'settings.language': language},
    );
    final prefs = await SharedPreferences.getInstance();
    return AppSettingsState.fromPrefs(prefs);
  }

  group('AppSettingsState.fromPrefs language normalization', () {
    test('supported code is kept as-is', () async {
      expect((await stateWith('es')).language, 'es');
      expect((await stateWith('fr')).language, 'fr');
      expect((await stateWith('de')).language, 'de');
    });

    test('region-qualified supported code is stripped to its base', () async {
      expect((await stateWith('es-MX')).language, 'es');
      expect((await stateWith('es_MX')).language, 'es');
      expect((await stateWith('fr-CA')).language, 'fr');
    });

    test('unsupported code falls back to the device default', () async {
      expect((await stateWith('pt')).language, 'en');
      expect((await stateWith('pt-BR')).language, 'en');
      expect((await stateWith('zz')).language, 'en');
    });

    test('missing or empty value falls back to the device default', () async {
      expect((await stateWith(null)).language, 'en');
      expect((await stateWith('')).language, 'en');
    });

    test('device default follows a supported device locale', () async {
      binding.platformDispatcher.localesTestValue = const [Locale('de')];
      expect((await stateWith('pt')).language, 'de'); // unsupported -> device
      expect((await stateWith(null)).language, 'de'); // first run -> device
      expect((await stateWith('es')).language, 'es'); // explicit supported wins
    });

    test('device default picks the first supported preferred locale', () async {
      // Unsupported primary (pt-BR) but a supported secondary (es).
      binding.platformDispatcher.localesTestValue = const [
        Locale('pt', 'BR'),
        Locale('es'),
      ];
      expect(
        (await stateWith('pt')).language,
        'es',
      ); // unsupported stored -> secondary
      expect((await stateWith(null)).language, 'es'); // first run -> secondary
    });
  });

  group('SettingsNotifier.setLanguage normalizes before persisting', () {
    test('region-qualified and unsupported values are normalized', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(prefs: prefs);

      notifier.setLanguage('es-MX');
      expect(notifier.state.language, 'es');
      expect(prefs.getString('settings.language'), 'es');

      notifier.setLanguage('pt'); // unsupported -> device default (en)
      expect(notifier.state.language, 'en');
      expect(prefs.getString('settings.language'), 'en');

      notifier.setLanguage('it');
      expect(notifier.state.language, 'it');
      expect(prefs.getString('settings.language'), 'it');
    });
  });

  group('localeProvider agrees with the persisted state', () {
    Future<void> expectAgreement(String? stored, String expected) async {
      SharedPreferences.setMockInitialValues(
        stored == null ? {} : {'settings.language': stored},
      );
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => SettingsNotifier(
              prefs: prefs,
              initial: AppSettingsState.fromPrefs(prefs),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final language = container.read(settingsProvider).language;
      final locale = container.read(localeProvider);
      expect(language, expected);
      expect(locale.languageCode, expected);
      // The effective locale and the persisted UI state must agree.
      expect(locale.languageCode, language);
    }

    test('supported es kept for both state and locale', () async {
      await expectAgreement('es', 'es');
    });
    test('region-qualified es-MX -> es for both', () async {
      await expectAgreement('es-MX', 'es');
    });
    test('unsupported pt -> device default for both', () async {
      await expectAgreement('pt', 'en');
    });
  });

  group('the Lightning address reaches the Rust core', () {
    // The take flow reads the address from the Rust settings store, which
    // lives in memory: without these writes Mostro never pays it directly.
    test('setting and clearing it hands each value to the core', () async {
      // Arrange
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final synced = <String?>[];
      final notifier = SettingsNotifier(
        prefs: prefs,
        syncLightningAddress: (address) async => synced.add(address),
      );

      // Act
      notifier.setDefaultLightningAddress('alice@example.com');
      notifier.setDefaultLightningAddress(null);
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(synced, ['alice@example.com', null]);
      expect(prefs.getString('settings.lightningAddress'), isNull);
    });

    test('a core that refuses the address keeps the saved setting', () async {
      // Arrange
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = SettingsNotifier(
        prefs: prefs,
        syncLightningAddress:
            (_) async => throw Exception('InvalidLightningAddress'),
      );

      // Act
      notifier.setDefaultLightningAddress('alice@example.com');
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(notifier.state.defaultLightningAddress, 'alice@example.com');
      expect(prefs.getString('settings.lightningAddress'), 'alice@example.com');
    });

    test('the saved address is handed to the core at startup', () async {
      // Arrange
      final synced = <String?>[];

      // Act
      await syncLightningAddressToCore(
        'alice@example.com',
        sink: (address) async => synced.add(address),
      );

      // Assert
      expect(synced, ['alice@example.com']);
    });

    test('a refused replacement clears the core copy', () async {
      // Arrange: the core would otherwise keep the previous address and
      // have Mostro pay it on the next take.
      final synced = <String?>[];

      // Act
      await syncLightningAddressToCore(
        'a@b',
        sink: (address) async {
          if (address != null) throw Exception('InvalidLightningAddress');
          synced.add(address);
        },
      );

      // Assert
      expect(synced, [null]);
    });

    test('a failed startup sync does not throw', () async {
      // Act + Assert
      await expectLater(
        syncLightningAddressToCore(
          'alice@example.com',
          sink: (_) async => throw Exception('bridge down'),
        ),
        completes,
      );
    });
  });
}
