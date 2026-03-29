# Contract: NWC (Nostr Wallet Connect) API

**Module**: `rust/src/api/nwc.rs`

Nostr Wallet Connect integration for automatic Lightning invoice payment.

## Functions

### connect_wallet(nwc_uri: String) → NwcWalletInfo
Parse NWC URI and establish connection to wallet service.

**URI format**: `nostr+walletconnect://<pubkey>?relay=<url>&secret=<hex>`

**Validation**: URI MUST be valid NWC format with pubkey, at least one
relay URL, and hex secret.

**Side effects**: Stores encrypted credentials in secure storage.
Connects to wallet relay(s). Queries wallet info.

**Errors**: `InvalidNwcUri`, `ConnectionFailed`, `StorageError`.

---

### disconnect_wallet() → ()
Disconnect and remove wallet credentials.

**Side effects**: Clears credentials from secure storage. Disconnects
from wallet relays.

**Errors**: `NoWalletConnected`.

---

### get_wallet() → NwcWalletInfo?
Get current wallet connection info. Returns null if no wallet connected.

---

### get_balance() → u64?
Query wallet balance in sats. Returns null if wallet doesn't support
balance queries.

**Errors**: `NoWalletConnected`, `WalletError`.

---

### pay_invoice(bolt11: String) → PaymentResult
Pay a Lightning invoice via the connected NWC wallet.

**Returns**:
```
PaymentResult {
  success: bool
  preimage: String?    # Payment preimage if successful
  error: String?       # Error message if failed
}
```

**Errors**: `NoWalletConnected`, `InvoiceInvalid`, `InsufficientBalance`,
`PaymentFailed`, `WalletTimeout`.

## Streams

### on_wallet_status_changed() → Stream<NwcWalletInfo?>
Emits when wallet connection status changes (connected, disconnected,
error).

## Types

### NwcWalletInfo
```
wallet_pubkey: String
wallet_name: String?
status: WalletStatus
balance_sats: u64?
relay_urls: Vec<String>
last_connected_at: i64?
```

### WalletStatus
```
Connected | Disconnected | Connecting | Error
```
