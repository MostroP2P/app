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

**Errors**: each is a prefix on the error text, which the connect screen
reads to tell the user what to do.
- `InvalidNwcUri`: the URI does not parse, or no request can be built from
  it (a wallet pubkey that is not a valid point). Only this one blames the URI.
- `WalletRejected`: the wallet answered `get_info` with `UNAUTHORIZED` (a
  revoked connection) or `RESTRICTED`. Retrying does not help; a new
  connection URI does.
- `ConnectionFailed`: a relay could not be added, nothing answered, or the
  wallet answered with an error a retry can clear (`RATE_LIMITED`,
  `INTERNAL`, ...).
- `Unsupported`: the web build, which has no NWC client.
- `StorageError`.

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

---

### make_invoice(amount_sats: u64, description: String?, expiry_secs: u64?) → String
Ask the connected NWC wallet (NIP-47 `make_invoice`) for a BOLT-11 invoice
of `amount_sats`, converted to msats for the request. Returns the invoice.

- `description`: memo for the invoice; `null` sends none.
- `expiry_secs`: the invoice lifetime requested from the wallet (NIP-47
  `expiry`); `null` leaves it to the wallet's default. Callers paying out
  through Mostro pass the node's `invoice_expiration_window` plus a margin
  (`nwcInvoiceExpirySecs` in `lib/features/order/models/invoice_rules.dart`):
  a wallet default inside that window gets the invoice refused. They wait
  for the node's metadata before asking, since the request is made once.

**Errors**: `InvalidAmount` (zero, or too large to express in msats),
`NoWalletConnected`, `WalletError`. Not supported on web.

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
