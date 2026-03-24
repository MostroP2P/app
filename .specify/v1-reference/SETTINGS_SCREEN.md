# Settings Screen (v1 Reference)

> App preferences: language, currency, wallet, relays, Mostro node.

**Route:** `/settings`

## Screen Layout

```text
┌─────────────────────────────────────────────────────┐
│  ←  Settings                                        │  AppBar
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  🌐  Language                             ℹ️  │  │
│  │                                               │  │
│  │  Choose your preferred language               │  │
│  │                                               │  │
│  │  [Language Selector Widget]                   │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  🪙  Currency                             ℹ️  │  │
│  │                                               │  │
│  │  Set default fiat currency                    │  │
│  │                                               │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │  Default Fiat Currency                  │  │  │
│  │  │  🇻🇪 VES - Venezuelan Bolívar       ▼  │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  ⚡  Default Lightning Address            ℹ️  │  │
│  │                                               │  │
│  │  Set default lightning address                │  │
│  │                                               │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │  Lightning Address (Optional)           │  │  │
│  │  │  user@wallet.com                        │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  💳  Wallet                                   │  │
│  │  [Wallet Status Card - separate widget]       │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  📻  Relays                               ℹ️  │  │
│  │                                               │  │
│  │  [Relay Selector Widget]                      │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  🔔  Notification Settings                    │  │
│  │                                               │  │
│  │  Configure notification preferences           │  │
│  │                                               │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │  ⚙️  Push Notifications              ›  │  │  │
│  │  │      Enable or disable push...           │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  🐛  Dev Tools                                │  │
│  │                                               │  │
│  │  Warning: For debugging only                  │  │
│  │                                               │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │  📄  Logs Report                     ›  │  │  │
│  │  │      View and export logs                │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  ⚡  Mostro                               ℹ️  │  │
│  │                                               │  │
│  │  Select your Mostro daemon                    │  │
│  │                                               │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │  [Avatar] Mostro P2P     ✓ Trusted   ▼  │  │  │
│  │  │           npub1m0str0...               │  │  │
│  │  │           Tap to select node            │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Cards Detail

### 1. Language Card

**Icon:** `LucideIcons.globe`, mostroGreen, 20px

**Language Selector Widget:**
- Dropdown or modal with supported languages
- Shows current language with flag emoji
- Persisted to local storage

**Supported Languages (v1):**
- English (en)
- Spanish (es)
- Portuguese (pt)
- French (fr)
- German (de)
- Italian (it)
- Russian (ru)
- Chinese (zh)
- Japanese (ja)
- Korean (ko)

### 2. Currency Card

**Icon:** `LucideIcons.coins`, mostroGreen, 20px

**Currency Selector:**
- Tap opens full-screen currency selection dialog
- Shows emoji flag + code + full name
- Searchable list of all fiat currencies
- Selected currency used as default for new orders

### 3. Lightning Address Card

**Icon:** `LucideIcons.zap`, mostroGreen, 20px

**Input Field:**
- Optional field
- Placeholder: "Enter Lightning Address"
- Format validation: `name@domain` — accepts any valid hostname or subdomain with any TLD (e.g., name@example, name@example.org, name@sub.example.co)
- Auto-saves on change
- Used as default when selling (auto-fills invoice destination)

### 4. Wallet Status Card

**Separate widget** (`WalletStatusCard`):
- Shows NWC connection status
- Connected: wallet name + balance
- Disconnected: "Connect Wallet" button
- Tap → navigates to `/wallet_settings`

> See [NWC_ARCHITECTURE.md](./NWC_ARCHITECTURE.md) for full wallet connection details.

### 5. Relays Card

**Icon:** `LucideIcons.radio`, mostroGreen, 20px

**Relay Selector Widget:**
- List of connected relays with status indicators
- Green dot = connected
- Red dot = disconnected
- Add relay button (+)
- Remove relay (swipe or tap)
- Shows relay health metrics

### 6. Notification Settings Card

**Icon:** `LucideIcons.bell`, mostroGreen, 24px

**Navigable Row:**
- Tap → `/notification_settings`
- Chevron icon on right
- Sub-description of current state

### 7. Dev Tools Card

**Icon:** `LucideIcons.bug`, mostroGreen, 24px

**Warning text** about debugging only.

**Navigable Row:**
- Icon: `LucideIcons.fileText`
- Tap → `/logs`
- View and export diagnostic logs

### 8. Mostro Card

**Icon:** `LucideIcons.zap`, mostroGreen, 20px

**Node Selector:**
- Shows currently selected Mostro daemon
- Avatar + name + pubkey (truncated)
- "Trusted" badge for verified nodes
- Tap opens node selection modal

**Node Selection Modal:**
- List of known Mostro nodes
- Custom node input option
- Shows node info (fee, limits, version)

## Card Component Pattern

All cards follow this structure:

```dart
Container(
  decoration: BoxDecoration(
    color: AppTheme.backgroundCard,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Colors.white.withOpacity(0.1)),
  ),
  child: Padding(
    padding: EdgeInsets.all(20),
    child: Column(
      children: [
        // Header row: icon + title + info button
        Row(children: [icon, title, Spacer(), infoButton]),
        SizedBox(height: 20),
        // Description
        Text(description),
        SizedBox(height: 16),
        // Content (selector, input, etc.)
        content,
      ],
    ),
  ),
)
```

## Info Dialogs

| Card | Dialog Content |
|------|----------------|
| Language | Explanation of language settings |
| Currency | Explanation of default fiat currency |
| Lightning Address | Explanation of LNURL/Lightning Address |
| Relays | Explanation of Nostr relays |
| Mostro | Explanation of Mostro daemon selection |
