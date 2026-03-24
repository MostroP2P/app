# Notification Settings Screen (v1 Reference)

> Detailed behavior of `/notification_settings`, where users manage push delivery, sound, and vibration preferences.

## Overview

- **Route:** `/notification_settings`
- **Widget:** `NotificationSettingsScreen` (stateless, Riverpod-powered)
- **State Source:** `settingsProvider` (see [SETTINGS_SCREEN.md](./SETTINGS_SCREEN.md))
- **Platform Awareness:** Push toggles enabled only on Android/iOS (disabled on Web, desktop platforms).

## Architecture

| Component | Responsibility |
|-----------|----------------|
| `Settings.pushNotificationsEnabled` | Master toggle. Disabling triggers token unregister + FCM deletion. |
| `Settings.notificationSoundEnabled` | Per-device preference for audible alerts. |
| `Settings.notificationVibrationEnabled` | Per-device preference for haptic alerts. |
| `SettingsNotifier.updatePushNotificationsEnabled()` | Saves preference, logs change, and calls `_unregisterPushTokens()` when turning off. |
| `_unregisterPushTokens()` | Uses injected `PushNotificationService` + `FCMService` to delete remote subscriptions. |
| `MostroSwitch` | Custom switch widget consistent with AppTheme. |

## Layout & Cards

### 1. Push Notifications Card
- Icon: `LucideIcons.bell`.
- Title: localized `S.pushNotifications`.
- Summary: `S.pushNotificationsDescription`.
- Switch: bound to `settings.pushNotificationsEnabled`.
  - Disabled on unsupported platforms (`kIsWeb`, desktop) and shows an orange warning banner.
- When toggled off:
  - `SettingsNotifier` writes to storage.
  - `_pushService.unregisterAllTokens()` ensures Mostro backend stops sending silent pushes.
  - `_fcmService.deleteToken()` removes local token.

### 2. Preferences Card
- Icon: `LucideIcons.settings`.
- Two toggles rendered via `_buildPreferenceToggle()`:
  1. **Sound** (`LucideIcons.volume2`)
  2. **Vibration** (`LucideIcons.vibrate`)
- Each toggle is disabled (opacity 0.5) when push notifications are off or unsupported.
- `MostroSwitch` writes to `Settings.notificationSoundEnabled` / `notificationVibrationEnabled`.
- Tooltips communicate that changes affect future push payloads (sound/vibration flags included when building notifications).

### 3. Privacy Information Card
- Icon: `LucideIcons.shield`.
- Static bullets describing:
  - Silent data pushes until decrypted locally.
  - Token encryption at rest.
  - Client-side decryption ensures Mostro servers never see notification contents.

## Behavior Summary

| Action | Outcome |
|--------|---------|
| Enable push | Registers device tokens (handled by app bootstrap elsewhere) and sets `pushNotificationsEnabled = true`. |
| Disable push | Immediately unregisters tokens + deletes FCM token, sets sound/vibration toggles but leaves their values cached. |
| Change sound/vibration | Updates preferences even if temporarily disabled; values preserved for next enablement. |
| Unsupported platform | Master switch disabled, warning banner shown, preferences non-interactive. |

## Cross-References

- [SETTINGS_SCREEN.md](./SETTINGS_SCREEN.md) — entry point card linking here; describes overall settings architecture.
- [LOGGING_SYSTEM.md](./LOGGING_SYSTEM.md) — push logging can be toggled for debugging.
- [FCM_IMPLEMENTATION.md](./FCM_IMPLEMENTATION.md) — explains how push tokens are registered and notifications are constructed.
