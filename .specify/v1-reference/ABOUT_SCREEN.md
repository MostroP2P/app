# About Screen (v1 Reference)

> App information, documentation links, and Mostro node details.

**Route:** `/about`

## Screen Layout

```text
┌─────────────────────────────────────────────────────┐
│  ←  About                                           │  AppBar
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  📱  App Information                          │  │
│  │                                               │  │
│  │  Version              0.2.5                   │  │
│  │                                               │  │
│  │  GitHub Repository    mostro-mobile  ↗️       │  │
│  │                                               │  │
│  │  Commit Hash          abc1234                 │  │
│  │                                               │  │
│  │  License              MIT                     │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  📖  Documentation                            │  │
│  │                                               │  │
│  │  Users (English)      Read  ↗️                │  │
│  │                                               │  │
│  │  Users (Spanish)      Read  ↗️                │  │
│  │                                               │  │
│  │  Technical            Read  ↗️                │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  🖥️  Mostro Node                              │  │
│  │                                               │  │
│  │  ══ General Info ══                           │  │
│  │                                               │  │
│  │  Mostro Public Key    npub1m0str0...  ℹ️ 📋   │  │
│  │  Max Order Amount     10,000,000 Satoshis ℹ️  │  │
│  │  Min Order Amount     100 Satoshis       ℹ️  │  │
│  │  Order Lifespan       24 hours           ℹ️  │  │
│  │  Service Fee          0.6%               ℹ️  │  │
│  │  Fiat Currencies      All                ℹ️  │  │
│  │                                               │  │
│  │  ══ Anti-abuse Bond ══                        │  │
│  │                                               │  │
│  │  Bond status          Enabled            ℹ️  │  │
│  │  Applies to           Makers and takers  ℹ️  │  │
│  │  Bond amount          5%                 ℹ️  │  │
│  │  Minimum bond         1,000 Satoshis     ℹ️  │  │
│  │  Node share on slash  50%                ℹ️  │  │
│  │  Slash on timeout     Enabled            ℹ️  │  │
│  │  Payout claim window  3 days             ℹ️  │  │
│  │                                               │  │
│  │  ══ Technical Details ══                      │  │
│  │                                               │  │
│  │  Mostro Version       0.12.5             ℹ️  │  │
│  │  Mostro Commit        def5678             ℹ️  │  │
│  │  Order Expiration     900 sec             ℹ️  │  │
│  │  Hold Invoice Exp.    86400 sec           ℹ️  │  │
│  │  Hold Invoice CLTV    144 blocks          ℹ️  │  │
│  │  Invoice Exp. Window  3600 seconds        ℹ️  │  │
│  │  Proof of Work        0                   ℹ️  │  │
│  │  Max Orders/Response  50                  ℹ️  │  │
│  │                                               │  │
│  │  ══ Lightning Network ══                      │  │
│  │                                               │  │
│  │  LND Version          0.18.0-beta        ℹ️  │  │
│  │  LND Node Public Key  02abc...      ℹ️ 📋   │  │
│  │  LND Commit           ghi9012             ℹ️  │  │
│  │  LND Node Alias       MostroNode          ℹ️  │  │
│  │  Supported Chains     bitcoin             ℹ️  │  │
│  │  Supported Networks   mainnet             ℹ️  │  │
│  │  LND Node URI         02abc@host:9735 ℹ️ 📋  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Cards Detail

### 1. App Information Card

**Icon:** `LucideIcons.smartphone`, mostroGreen, 20px

| Field | Value Source | Clickable |
|-------|--------------|-----------|
| Version | `APP_VERSION` env var | No |
| GitHub Repository | Static URL | Yes → opens GitHub |
| Commit Hash | `GIT_COMMIT` env var | No |
| License | "MIT" | Yes → shows license dialog |

**License Dialog:**
- Full MIT license text in scrollable container
- Monospace font
- Close button

### 2. Documentation Card

**Icon:** `LucideIcons.book`, mostroGreen, 20px

| Link | URL |
|------|-----|
| Users (English) | https://mostro.network/docs-english/ |
| Users (Spanish) | https://mostro.network/docs-spanish/ |
| Technical | https://mostro.network/protocol/ |

**Clickable rows** with external link icon (↗️).

### 3. Mostro Node Card

**Icon:** `LucideIcons.server`, mostroGreen, 20px

**Loading State:** Shows spinner while fetching node info.

**Data Source:** Nostr kind `38385` event (NIP-33 addressable/replaceable) published periodically by the Mostro daemon. The `d` tag contains the Mostro instance pubkey. All node metadata is encoded as individual tags in the event (not in `content`).

**Protocol Reference:** [Mostro Instance Status](https://mostro.network/protocol/other_events.html#mostro-instance-status)

**How the app fetches it:**
1. App subscribes to kind `38385` events filtered by `authors: [settings.mostroPublicKey]`
2. Relays return the latest replaceable event for that `d` tag
3. App parses each tag (e.g. `["mostro_version", "0.12.8"]`, `["fee", "0.006"]`) into the `MostroInstance` model
4. The About screen renders each tag as a labeled info row

**Event structure (kind 38385):**
```json
{
  "kind": 38385,
  "pubkey": "<Mostro's pubkey>",
  "tags": [
    ["d", "<Mostro's pubkey>"],
    ["mostro_version", "0.12.8"],
    ["mostro_commit_hash", "1aac442..."],
    ["max_order_amount", "1000000"],
    ["min_order_amount", "100"],
    ["expiration_hours", "1"],
    ["expiration_seconds", "900"],
    ["fiat_currencies_accepted", "USD,EUR,ARS,CUP,VES"],
    ["fee", "0.006"],
    ["pow", "0"],
    ["hold_invoice_expiration_window", "120"],
    ["hold_invoice_cltv_delta", "144"],
    ["invoice_expiration_window", "120"],
    ["lnd_version", "0.18.4-beta"],
    ["lnd_node_pubkey", "0220e455..."],
    ["lnd_commit_hash", "ddeb8351..."],
    ["lnd_node_alias", "alice"],
    ["lnd_chains", "bitcoin"],
    ["lnd_networks", "mainnet"],
    ["lnd_uris", "0220e455...@host:9735"],
    ["bond_enabled", "true"],
    ["bond_apply_to", "both"],
    ["bond_slash_on_waiting_timeout", "true"],
    ["bond_amount_pct", "0.05"],
    ["bond_base_amount_sats", "1000"],
    ["bond_slash_node_share_pct", "0.5"],
    ["bond_payout_claim_window_days", "3"],
    ["y", "mostro", "[instance name]"],
    ["z", "info"]
  ],
  "content": ""
}
```

**Important:** The `content` field is empty. All data is in tags. The event is a NIP-33 addressable event (kind 30000-39999 range), meaning relays store only the latest version per `d` tag value.

#### General Info Section

| Field | Key | Format |
|-------|-----|--------|
| Mostro Public Key | `pubKey` | Truncated, copyable |
| Max Order Amount | `maxOrderAmount` | Formatted number + "Satoshis" |
| Min Order Amount | `minOrderAmount` | Formatted number + "Satoshis" |
| Order Lifespan | `expirationHours` | Number + "hours" |
| Service Fee | `fee` | Percentage (fee * 100 + "%") |
| Fiat Currencies | `fiatCurrenciesAccepted` | Comma-separated or "All" |

#### Anti-abuse Bond Section

Advertises the node's anti-abuse bond policy — a Lightning hold invoice locked for the duration of a trade and released when it completes normally. Rendered between General Info and Technical Details.

**Three-state visibility** (`bondPolicy`, from the `bond_enabled` tag):

- `unsupported` — tag absent or malformed (legacy daemon). Only the status row renders, showing "Not supported".
- `disabled` — `bond_enabled="false"`. Only the status row renders, showing "Disabled".
- `enabled` — `bond_enabled="true"`. The status row plus every parameter the daemon populated renders.

Each parameter row renders only when its tag parsed to a non-null value, so a partially-configured node never shows empty fields.

| Field | Key | Format |
|-------|-----|--------|
| Bond status | `bondPolicy` | Enabled / Disabled / Not supported |
| Applies to | `bondApplyTo` | Takers / Makers / Makers and takers |
| Bond amount | `bondAmountPct` | Percentage (`pct * 100 + "%"`); the larger of this and the minimum bond is charged |
| Minimum bond | `bondBaseAmountSats` | Formatted number + "Satoshis" |
| Node share on slash | `bondSlashNodeSharePct` | Percentage (`pct * 100 + "%"`) |
| Slash on waiting timeout | `bondSlashOnWaitingTimeout` | Enabled / Disabled |
| Payout claim window | `bondPayoutClaimWindowDays` | Number + "days" |

The bond parameters are meaningful only when `bondPolicy` is `enabled`; a disabled or unsupported node exposes them as null. The client never computes a bond charge — the daemon sends the exact bolt11; these fields exist for up-front UI disclosure only.

#### Technical Details Section

| Field | Key |
|-------|-----|
| Mostro Version | `mostroVersion` |
| Mostro Commit | `commitHash` |
| Order Expiration | `expirationSeconds` + "sec" |
| Hold Invoice Expiration | `holdInvoiceExpirationWindow` + "sec" |
| Hold Invoice CLTV Delta | `holdInvoiceCltvDelta` + "blocks" |
| Invoice Expiration Window | `invoiceExpirationWindow` + "seconds" |
| Proof of Work | `pow` |
| Max Orders Per Response | `maxOrdersPerResponse` |

#### Lightning Network Section

| Field | Key |
|-------|-----|
| LND Version | `lndVersion` |
| LND Node Public Key | `lndNodePublicKey` (copyable) |
| LND Commit | `lndCommitHash` |
| LND Node Alias | `lndNodeAlias` |
| Supported Chains | `supportedChains` |
| Supported Networks | `supportedNetworks` |
| LND Node URI | `lndNodeUri` (copyable) |

## Info Row Patterns

### Standard Info Row

```text
Label              Value
```

- Label: `textSecondary`, 14sp
- Value: `textPrimary`, 14sp, medium weight

### Info Row with Dialog

```text
Label  ℹ️
Value
```

- Tap ℹ️ → shows explanation dialog
- Info icon: 16px, `textSecondary`

### Info Row with Dialog and Copy

```text
Label  ℹ️  📋
Value (truncated)
```

- Tap ℹ️ → explanation dialog
- Tap 📋 → copies value to clipboard
- Shows "Copied to clipboard" snackbar

## Section Headers

```dart
Text(
  "General Info",
  style: TextStyle(
    color: AppTheme.activeColor,  // mostroGreen
    fontSize: 16,
    fontWeight: FontWeight.w600,
  ),
)
```

## Info Dialogs

Each ℹ️ button shows a dialog with explanation:

| Field | Explanation Key |
|-------|----------------|
| Mostro Public Key | `mostroPublicKeyExplanation` |
| Max Order Amount | `maxOrderAmountExplanation` |
| Min Order Amount | `minOrderAmountExplanation` |
| Order Lifespan | `orderExpirationExplanation` |
| Service Fee | `serviceFeeExplanation` |
| ... | (all fields have explanations) |

Explanations are i18n strings that describe what each field means and why it matters.
