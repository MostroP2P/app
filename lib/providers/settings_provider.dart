/// Settings provider stub.
///
/// Phase 9 replaces this with a real implementation backed by
/// rust/src/api/settings.rs.
library settings_provider;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App settings.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemePreference.system,
    this.locale = 'en',
    this.biometricEnabled = false,
    this.notificationsEnabled = true,
    this.privacyMode = false,
  });

  final ThemePreference themeMode;
  final String locale;
  final bool biometricEnabled;
  final bool notificationsEnabled;
  final bool privacyMode;
}

enum ThemePreference { system, light, dark }

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    // Phase 9: load persisted settings from Rust.
    return const AppSettings();
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// Convenience provider for current theme preference.
final themePreferenceProvider = Provider<ThemePreference>((ref) {
  return ref.watch(settingsProvider).valueOrNull?.themeMode ??
      ThemePreference.system;
});
