# Account Screen (v1 Reference)

> Identity management: mnemonic backup, privacy mode, user generation.

**Route:** `/key_management`

## Screen Layout

```text
┌─────────────────────────────────────────────────────┐
│  ←  Account                                         │  AppBar
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  🔑  Secret Words                         ℹ️  │  │
│  │                                               │  │
│  │  To restore your account                      │  │
│  │                                               │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │ apple orange ••• ••• ••• ••• ••• •••    │  │  │
│  │  │ ••• ••• banana grape                    │  │  │
│  │  │                                         │  │  │
│  │  │                        👁️ Show          │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  🛡️  Privacy                              ℹ️  │  │
│  │                                               │  │
│  │  Control your privacy settings                │  │
│  │                                               │  │
│  │  ◉ Reputation Mode                            │  │
│  │    Standard privacy with reputation           │  │
│  │                                               │  │
│  │  ○ Full Privacy Mode                          │  │
│  │    Maximum anonymity                          │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  👤+  Generate New User                       │  │  Primary button
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌─────────────────────────────┐  ┌─────────────┐  │
│  │  ⬇️  Import Mostro User     │  │     🔄      │  │  Outlined buttons
│  └─────────────────────────────┘  └─────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Components

### 1. Secret Words Card

Displays the 12-word mnemonic phrase with partial masking for security.

**Masking Logic:**
- Show first 2 words clearly
- Show last 2 words clearly
- Mask middle 8 words as `••• ••• ••• •••`

```dart
String _maskSeedPhrase(String seedPhrase) {
  final words = seedPhrase.split(' ');
  if (words.length < 4) return seedPhrase;

  final first = words.take(2).join(' ');
  final last = words.skip(words.length - 2).join(' ');
  final masked = '••• ••• ••• •••';

  return '$first $masked $last';
}
```

**Show/Hide Toggle:**
- Default: masked (only first 2 and last 2 visible)
- Tap "Show" → reveals all 12 words
- Tap "Hide" → masks again
- When user reveals words → dismiss backup reminder notification

**Specs:**
| Element | Style |
|---------|-------|
| Card background | `backgroundCard` |
| Icon | `LucideIcons.key`, `mostroGreen`, 20px |
| Title | 18sp, semibold, `textPrimary` |
| Description | 14sp, regular, `textSecondary` |
| Mnemonic container | `backgroundInput`, 8px radius |
| Mnemonic text | 14sp, monospace, `textPrimary` |
| Show/Hide button | `mostroGreen` text + icon |

### 2. Privacy Card

Toggle between reputation mode and full privacy mode.

**Options:**

| Mode | Description | Effect |
|------|-------------|--------|
| Reputation Mode | Standard privacy with reputation | Identity key signs seal, enables cross-trade reputation |
| Full Privacy Mode | Maximum anonymity | Trade key signs seal, no cross-trade linking |

**Radio Button Specs:**
- Circle: 20px diameter, 2px border
- Selected: `mostroGreen` border + inner 10px filled circle
- Unselected: white @ 30% opacity border

### 3. Generate New User Button

**Primary button** (filled, mostroGreen background):
- Icon: `LucideIcons.userPlus`
- Text: "Generate New User"
- Action: Shows confirmation dialog, then generates new mnemonic

**Confirmation Dialog:**
- Title: "Generate New User?"
- Content: Warning about losing current identity
- Actions: Cancel (ghost) | Continue (primary)

**On Confirm:**
1. Reset session
2. Delete all stored data (orders, events, notifications)
3. Generate new master key
4. Show backup reminder
5. Reload screen

### 4. Import User Button

**Outlined button** (mostroGreen border, no fill):
- Icon: `LucideIcons.download`
- Text: "Import Mostro User"
- Action: Opens import dialog

**Import Dialog:**
- Title: "Import Mnemonic"
- Input: Text field for 12/24 word phrase
- Validation: Check valid BIP-39 mnemonic format
- Actions: Cancel | Import

**On Import:**
1. Validate mnemonic
2. Import and store
3. Trigger restore process (sync past trades from relays)
4. Show success snackbar

### 5. Refresh User Button

**Outlined button** (mostroGreen border, icon only):
- Icon: `LucideIcons.refreshCw`
- Action: Re-sync user data from relays

**Confirmation Dialog:**
- Title: "Refresh User?"
- Content: Explanation of what refresh does
- Actions: Cancel | Refresh

## Debug-Only Section

Only visible when `kDebugMode == true`:

### Current Trade Index Card

Shows the current trade key derivation index:
- Icon: `LucideIcons.refreshCcw`
- Title: "Current Trade Index"
- Value: Large number (32sp bold)
- Description: "Increments with each trade"

## Info Dialogs

Each card has an ℹ️ icon that shows explanatory dialog:

| Card | Dialog Content |
|------|----------------|
| Secret Words | Explanation of mnemonic backup importance |
| Privacy | Explanation of privacy modes |
| Trade Index | Explanation of HD key derivation |
