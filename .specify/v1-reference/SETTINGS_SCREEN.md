# Settings System (v1 Reference)

> Central configuration hub that fans out to wallet, notifications, relays, language, fiat defaults, logging, and Mostro node selection.

**Routes:**
- `/settings` → `SettingsScreen`
- `/notification_settings` → `NotificationSettingsScreen`
- `/about` → `AboutScreen` (documented separately)
- `/relays` → Relay management screen (see [RELAY_SYNC_IMPLEMENTATION.md](./RELAY_SYNC_IMPLEMENTATION.md))

---

## Architecture Overview

### Settings State & Storage

| File | Purpose |
|------|---------|
| `lib/features/settings/settings.dart` | Immutable `Settings` model (relays, privacy mode, locale, fiat, lightning address, push toggles, logging flags). |
| `lib/features/settings/settings_notifier.dart` | `StateNotifier<Settings>` that loads/saves the model to `SharedPreferences` (`SharedPreferencesAsync`). |
| `lib/features/settings/settings_provider.dart` | Global Riverpod provider consumed across the app. |

**Storage:**
- Persisted under `SharedPreferencesKeys.appSettings` as JSON.
- Bootstrapped with defaults from `Config` (relays, privacy mode, Mostro pubkey).
- `init()` is async; UI surfaces default values until load completes.

**Fields and Their Consumers:**
- `selectedLanguage` → `MaterialApp.locale`, background services.
- `defaultFiatCode` → `AddOrderScreen`, exchange rate providers.
- `defaultLightningAddress` → `AddOrderScreen`, `AbstractMostroNotifier` (auto `add-invoice`).
- `relays`, `blacklistedRelays`, `userRelays` → `RelaySelector`, relay sync subsystem.
- `mostroPublicKey` → `MostroNodesNotifier`, `NostrService` handshake headers.
- `pushNotificationsEnabled`, `notificationSoundEnabled`, `notificationVibrationEnabled` → `PushNotificationService`, `FCMService`, notification UI.
- `isLoggingEnabled` → `MemoryLogOutput` toggles in-app logging buffer.
- `fullPrivacyMode` → `RestoreManager`, `NostrService` (decides whether to keep master key in memory).

### Side Effects
- Changing Mostro node resets relay blacklist/user-relay lists to avoid cross-instance bleed.
- Disabling push notifications unregisters tokens and deletes the FCM token immediately.
- Lightning address updates propagate in real time; clearing the field sends `null` so dependent flows fall back to manual invoices.

---

## SettingsScreen (`/settings`)

### Data Flow
1. `SettingsScreen` watches `settingsProvider` and rebuilds individual cards via Riverpod.
2. Supporting widgets (`LanguageSelector`, `CurrencySelectionDialog`, `RelaySelector`, `WalletStatusCard`) talk to their respective providers.
3. Navigation actions route to more detailed screens (wallet, notifications, logs, about, relays).

### Layout (Cards)

**Screenshot:** https://i.nostr.build/1rDSSUd1xeQ1TgRH.png

```text
┌─────────────────────────────────────────────────────┐
│  ←  Settings                                        │  AppBar
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  🌐  Language                                 │  │
│  │      Default                                  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  💱  Currency                                 │  │
│  │      🇦🇷 ARS - Argentine Peso                 │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  ⚡  Lightning Address                        │  │
│  │      [Lightning Address (optional)]           │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  👛  NWC                                      │  │
│  │      Connected. Balance: 11 sats              │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  📡  Relays                                   │  │
│  │  wss://nos.lol             🟢  [ON]           │  │
│  │  wss://relay.mostro.net    🟢  [ON]           │  │
│  │           [+ Add Relay]                       │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  🔔  Push Notifications                    >  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  🛠️  Log Report                            >  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  ⚡  Mostro  [Trusted]       ...7c575...   >  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Visual Settings Summary

| # | Icon | Setting | Current Value | Action |
|---|------|---------|---------------|--------|
| 1 | 🌐 Globe | Language | "Default" (system locale) | Tap → modal language list |
| 2 | 💱 Currency | Default Fiat Currency | "🇦🇷 ARS - Argentine Peso" | Tap → searchable currency dialog |
| 3 | ⚡ Lightning | Lightning Address | (empty, optional) | Text field, auto-saves on change |
| 4 | 👛 Wallet | NWC Wallet | "Connected. Balance: 11 sats" | Tap → `/wallet_settings` |
| 5 | 📡 Relay | Relays | List with green/red status + ON/OFF toggle | Inline management + "Add Relay" button |
| 6 | 🔔 Bell | Push Notifications | (chevron >) | Tap → `/notification_settings` |
| 7 | 🛠️ Gear | Log Report | (chevron >) | Tap → `/logs` |
| 8 | ⚡ Lightning | Mostro Node | Truncated pubkey + "Trusted" badge | Tap → MostroNodeSelector modal |

### Relay Management (inline):
- Each relay shows: URL + connection status dot (🟢 green = connected, 🔴 red = disconnected) + ON/OFF toggle
- "Add Relay" button at bottom to add custom relay URL
- Relays auto-sync from Mostro's kind 10002 event (see [RELAY_SYNC_IMPLEMENTATION.md](./RELAY_SYNC_IMPLEMENTATION.md))
- Users can blacklist relays to prevent auto-sync re-adding them

Each card is a `Container` with consistent styling (rounded corners, subtle border, AppTheme colors). Info dialogs use `_showInfoDialog()` for contextual explanations.

### Card Details & Behavior

#### 1. Language (`LanguageSelector`)
- Displays current locale (flag + code) or "System default".
- Tapping opens modal list from `shared/widgets/language_selector.dart`.
- Selecting a language updates `settings.selectedLanguage`, which immediately reconfigures `MaterialApp.locale` and background services.

#### 2. Currency
- Shows emoji + currency name derived from `currencyCodesProvider`.
- `CurrencySelectionDialog` fetches the full list, caches exchange metadata, and writes `settings.defaultFiatCode`.
- Orders created afterward pre-fill this fiat code.

#### 3. Default Lightning Address
- Text field with live validation (only trimmed, no deep regex).
- Writes to `settings.defaultLightningAddress`; setting it enables:
  - Auto-filling buyer invoices during `/add_invoice` (see [TRADE_EXECUTION.md](./TRADE_EXECUTION.md)).
  - Auto-populating the field in `AddOrderScreen` for sell orders.
- Clearing the field triggers `clearDefaultLightningAddress` so dependent flows revert to manual entry.

#### 4. Wallet Status Card
- Wrapper around `WalletStatusCard` (see [NWC_ARCHITECTURE.md](./NWC_ARCHITECTURE.md)).
- Shows wallet alias, balance, connection health, and a connect/disconnect CTA.
- Tap → `/wallet_settings`.

#### 5. Relays Card
- Renders `RelaySelector`, which lists relays (green/red dot) and allows add/remove operations.
- Uses `settings.relays`, `blacklistedRelays`, and `userRelays` to manage syncing against Mostro's `kind 10002` events (see [RELAY_SYNC_IMPLEMENTATION.md](./RELAY_SYNC_IMPLEMENTATION.md)).
- Info dialog explains relay roles and privacy implications.

#### 6. Notification Settings Shortcut
- Explains push notification scope, links to `/notification_settings`.
- Actual toggles live in `NotificationSettingsScreen` (documented below).

#### 7. Dev Tools
- Warns about debugging features.
- Toggle for in-memory logging (`settings.isLoggingEnabled` → `MemoryLogOutput.isLoggingEnabled`).
- Button → `/logs` to view/export logs.

#### 8. Mostro Node Selector
- Uses `MostroNodeSelector.show()` to pick from trusted/untrusted nodes.
- Renders avatar, display name, truncated pubkey, and "Trusted" badge.
- Changing node calls `SettingsNotifier.updateMostroInstance`, which resets relay blacklists and user-relay metadata.

### Privacy Mode (hidden toggle)
- Not exposed in the v1 UI but stored in `Settings`. Defaults follow `Config.fullPrivacyMode` and gate whether sensitive keys are kept in memory. Mentioned for completeness because the spec references the data model.

---

## NotificationSettingsScreen (`/notification_settings`)

> Detailed spec in [NOTIFICATION_SETTINGS.md](./NOTIFICATION_SETTINGS.md).

Highlights:
- Push enable switch (disabled on Web/desktop).
- Sound/vibration toggles disabled when push is off.
- Privacy card describing how tokens are handled.
- Disabling push triggers `_unregisterPushTokens()` and FCM token deletion.

---

## SettingsNotifier Responsibilities

1. **Initialization** — load JSON from `SharedPreferences`. Corrupted JSON falls back to defaults.
2. **Persistence** — `_saveToPrefs()` after every mutation (relays, fiat, language, LN address, notifications, logging).
3. **Push Service Integration** — `setPushServices()` injects `PushNotificationService` + `FCMService` so toggles can unregister tokens.
4. **Relay Blacklist Management** — add/remove/clear operations keep URLs normalized.
5. **Mostro Node Switching** — resets relay-related lists and logs the change.
6. **Locale Hooks** — `settings.selectedLanguage` influences `MaterialApp` and headless background workers.

---

## Additional Screens under Settings

| Screen | Route | Notes |
|--------|-------|-------|
| Wallet Settings | `/wallet_settings` | Detailed in [NWC_ARCHITECTURE.md](./NWC_ARCHITECTURE.md). |
| Connect Wallet | `/connect_wallet` | QR scanner, URI validation. |
| Notification Settings | `/notification_settings` | See [NOTIFICATION_SETTINGS.md](./NOTIFICATION_SETTINGS.md). |
| About | `/about` | See [ABOUT_SCREEN.md](./ABOUT_SCREEN.md). |
| Relays | `/relays` | UI for managing relay list; ties into [RELAY_SYNC_IMPLEMENTATION.md](./RELAY_SYNC_IMPLEMENTATION.md). |
| Logs | `/logs` | See [LOGGING_SYSTEM.md](./LOGGING_SYSTEM.md). |

---

## Cross-References

- [NAVIGATION_ROUTES.md](./NAVIGATION_ROUTES.md) — routes `/settings`, `/notification_settings`, `/about`, `/wallet_settings`, `/connect_wallet`, `/logs`, `/relays`.
- [TRADE_EXECUTION.md](./TRADE_EXECUTION.md) — Lightning address + notification settings impact trade flows.
- [NWC_ARCHITECTURE.md](./NWC_ARCHITECTURE.md) — Wallet Status Card.
- [RELAY_SYNC_IMPLEMENTATION.md](./RELAY_SYNC_IMPLEMENTATION.md) — Relay selector + blacklist.
- [ABOUT_SCREEN.md](./ABOUT_SCREEN.md) — About screen spec.
- [LOGGING_SYSTEM.md](./LOGGING_SYSTEM.md) — Dev tools + log export.
