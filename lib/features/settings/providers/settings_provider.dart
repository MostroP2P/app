import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      language: prefs.getString(_kLanguage) ?? 'en',
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

// ── Notifier ──────────────────────────────────────────────────────────────────

class SettingsNotifier extends StateNotifier<AppSettingsState> {
  SettingsNotifier({SharedPreferences? prefs, AppSettingsState? initial})
      : _prefs = prefs,
        super(initial ?? const AppSettingsState());

  final SharedPreferences? _prefs;

  void setLanguage(String code) {
    state = state.copyWith(language: code);
    _prefs?.setString(_kLanguage, code);
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
  }

  void setLoggingEnabled(bool enabled) {
    state = state.copyWith(loggingEnabled: enabled);
    _prefs?.setBool(_kLoggingEnabled, enabled);
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

/// Current display locale, derived automatically from [settingsProvider].
///
/// Rebuilds whenever [AppSettingsState.language] changes so that
/// [MaterialApp.router] locale stays in sync without manual updates.
final localeProvider = Provider<Locale>((ref) {
  final language = ref.watch(settingsProvider.select((s) => s.language));
  return Locale(language);
});
