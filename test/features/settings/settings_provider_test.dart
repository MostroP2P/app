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
    binding.platformDispatcher.localeTestValue = const Locale('en');
  });
  tearDown(() {
    binding.platformDispatcher.clearLocaleTestValue();
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
      binding.platformDispatcher.localeTestValue = const Locale('de');
      expect((await stateWith('pt')).language, 'de'); // unsupported -> device
      expect((await stateWith(null)).language, 'de'); // first run -> device
      expect((await stateWith('es')).language, 'es'); // explicit supported wins
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
}
