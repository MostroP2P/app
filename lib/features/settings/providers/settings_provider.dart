import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/settings.dart' as settings_api;

// ── Preference keys ────────────────────────────────────────────────────────────

const _kLanguage = 'settings.language';
const _kFiatCode = 'settings.fiatCode';
const _kLightningAddress = 'settings.lightningAddress';
const _kLoggingEnabled = 'settings.loggingEnabled';
const _kThemeMode = 'settings.themeMode';

// ── State ─────────────────────────────────────────────────────────────────────

class AppSettingsState {
  const AppSettingsState({
    this.language = 'en',
    this.defaultFiatCode,
    this.defaultLightningAddress,
    this.loggingEnabled = false,
    this.themeMode = ThemeMode.dark,
  });

  final String language;
  final String? defaultFiatCode;
  final String? defaultLightningAddress;
  final bool loggingEnabled;

  /// Current Flutter [ThemeMode]; kept in sync with the Rust settings store.
  final ThemeMode themeMode;

  AppSettingsState copyWith({
    String? language,
    Object? defaultFiatCode = _unset,
    Object? defaultLightningAddress = _unset,
    bool? loggingEnabled,
    ThemeMode? themeMode,
  }) {
    return AppSettingsState(
      language: language ?? this.language,
      defaultFiatCode: identical(defaultFiatCode, _unset)
          ? this.defaultFiatCode
          : defaultFiatCode as String?,
      defaultLightningAddress: identical(defaultLightningAddress, _unset)
          ? this.defaultLightningAddress
          : defaultLightningAddress as String?,
      loggingEnabled: loggingEnabled ?? this.loggingEnabled,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  /// Load initial values from [SharedPreferences].
  factory AppSettingsState.fromPrefs(SharedPreferences prefs) {
    final themeModeStr = prefs.getString(_kThemeMode) ?? 'dark';
    return AppSettingsState(
      language: _normalizeLanguage(prefs.getString(_kLanguage)),
      defaultFiatCode: prefs.getString(_kFiatCode),
      defaultLightningAddress: prefs.getString(_kLightningAddress),
      loggingEnabled: prefs.getBool(_kLoggingEnabled) ?? false,
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == themeModeStr,
        orElse: () => ThemeMode.dark,
      ),
    );
  }
}

// Sentinel to distinguish "not provided" from explicit null in copyWith.
const _unset = Object();

/// Hands the default Lightning address (null clears it) to the Rust core.
typedef LightningAddressSink = Future<void> Function(String? address);

Future<void> _pushLightningAddress(String? address) =>
    settings_api.setDefaultLightningAddress(address: address);

/// Mirrors the saved Lightning address into the Rust settings store, which
/// lives in memory and is what the take flow reads to have Mostro pay the
/// address directly. Called at startup and on every change. Never throws:
/// the setting stays saved on the Dart side, and the add-invoice screen
/// still pre-fills it.
///
/// An address the core refuses clears the core copy instead: it would
/// otherwise keep the previous address and have Mostro pay one the user
/// replaced. With none there, a take asks for an invoice.
Future<void> syncLightningAddressToCore(
  String? address, {
  LightningAddressSink? sink,
}) async {
  final push = sink ?? _pushLightningAddress;
  try {
    await push(address);
  } catch (e) {
    debugPrint('[settings] Lightning address not synced to the core: $e');
    if (address == null) return;
    try {
      await push(null);
    } catch (e) {
      debugPrint('[settings] stale Lightning address not cleared: $e');
    }
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class SettingsNotifier extends StateNotifier<AppSettingsState> {
  SettingsNotifier({
    SharedPreferences? prefs,
    AppSettingsState? initial,
    LightningAddressSink? syncLightningAddress,
  })  : _prefs = prefs,
        _syncLightningAddress = syncLightningAddress,
        super(initial ?? const AppSettingsState());

  final SharedPreferences? _prefs;
  final LightningAddressSink? _syncLightningAddress;

  void setLanguage(String code) {
    final normalized = _normalizeLanguage(code);
    state = state.copyWith(language: normalized);
    _prefs?.setString(_kLanguage, normalized);
  }

  void setDefaultFiatCode(String? code) {
    state = state.copyWith(defaultFiatCode: code);
    if (code == null) {
      _prefs?.remove(_kFiatCode);
    } else {
      _prefs?.setString(_kFiatCode, code);
    }
  }

  void setDefaultLightningAddress(String? address) {
    state = state.copyWith(defaultLightningAddress: address);
    if (address == null) {
      _prefs?.remove(_kLightningAddress);
    } else {
      _prefs?.setString(_kLightningAddress, address);
    }
    syncLightningAddressToCore(address, sink: _syncLightningAddress);
  }

  /// Turns verbose (`Debug`) logging on or off. The Rust core owns the global
  /// log filter, so the flag has to reach it or the toggle does nothing.
  void setLoggingEnabled(bool enabled) {
    state = state.copyWith(loggingEnabled: enabled);
    _prefs?.setBool(_kLoggingEnabled, enabled);
    settings_api.setLoggingEnabled(enabled: enabled);
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _prefs?.setString(_kThemeMode, mode.name);
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Main settings provider. Holds all user preferences, persisted to
/// SharedPreferences. Override in [main] via [ProviderScope] overrides so that
/// the [SharedPreferences] instance and saved initial values are injected
/// synchronously before the first frame.
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettingsState>(
  (ref) => SettingsNotifier(), // no-persistence fallback; replaced in main()
);

/// Language codes the app ships translations for, derived from the generated
/// [AppLocalizations]. Used to validate stored and device languages.
final Set<String> _supportedLanguageCodes =
    AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();

/// The first supported language among the device's preferred locales, or
/// English when none is supported.
///
/// Iterates the ordered [PlatformDispatcher.locales] rather than just the
/// primary locale, so a device preferring e.g. `pt-BR` then `es` starts in
/// Spanish instead of falling back to English. Used as the first-run default.
String _deviceDefaultLanguage() {
  for (final locale in WidgetsBinding.instance.platformDispatcher.locales) {
    if (_supportedLanguageCodes.contains(locale.languageCode)) {
      return locale.languageCode;
    }
  }
  return 'en';
}

/// Normalizes a stored or selected language to a supported code.
///
/// Strips any region qualifier (e.g. `es-MX` -> `es`) and falls back to the
/// device default when the value is empty or unsupported (e.g. `pt`). Keeping
/// [AppSettingsState.language] normalized ensures the effective locale, the
/// Settings display and the language picker all agree.
String _normalizeLanguage(String? stored) {
  final code = (stored ?? '').split(RegExp(r'[-_]')).first;
  return _supportedLanguageCodes.contains(code)
      ? code
      : _deviceDefaultLanguage();
}

/// Current display locale, derived automatically from [settingsProvider].
///
/// Rebuilds whenever [AppSettingsState.language] changes so that
/// [MaterialApp.router] locale stays in sync without manual updates.
///
/// [AppSettingsState.language] is normalized to a supported code at the state
/// boundary (see [_normalizeLanguage]), so the effective locale, the Settings
/// display and the language picker always agree.
final localeProvider = Provider<Locale>((ref) {
  final language = ref.watch(settingsProvider.select((s) => s.language));
  return Locale(language);
});
