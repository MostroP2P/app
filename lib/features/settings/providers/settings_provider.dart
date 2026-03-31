import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

// Sentinel to distinguish "not provided" from explicit null in copyWith.
const _unset = Object();

// ── Notifier ──────────────────────────────────────────────────────────────────

class SettingsNotifier extends StateNotifier<AppSettingsState> {
  SettingsNotifier() : super(const AppSettingsState());

  void setLanguage(String code) => state = state.copyWith(language: code);

  void setDefaultFiatCode(String? code) =>
      state = state.copyWith(defaultFiatCode: code);

  void setDefaultLightningAddress(String? address) =>
      state = state.copyWith(defaultLightningAddress: address);

  void setLoggingEnabled(bool enabled) =>
      state = state.copyWith(loggingEnabled: enabled);

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Main settings provider. Holds all user preferences in memory.
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettingsState>(
  (ref) => SettingsNotifier(),
);

/// Current display locale, derived automatically from [settingsProvider].
///
/// Rebuilds whenever [AppSettingsState.language] changes so that
/// [MaterialApp.router] locale stays in sync without manual updates.
final localeProvider = Provider<Locale>((ref) {
  final language = ref.watch(settingsProvider.select((s) => s.language));
  return Locale(language);
});
