# Nostr-Based Exchange Rates (v2 Feature)

> Censorship-resistant exchange rate fetching via NIP-33 addressable events, with Yadio HTTP API fallback.

## Overview

Mostro v2 will fetch Bitcoin/fiat exchange rates from Nostr relays instead of (or in addition to) the Yadio HTTP API. This solves:

- **Censorship vulnerability** — API blocked in Venezuela and potentially other countries
- **Scaling costs** — HTTP APIs require infrastructure that scales with user count
- **Decentralization** — Aligns with Nostr/Bitcoin philosophy

**Primary source:** Nostr (NIP-33 addressable event)  
**Fallback:** Yadio HTTP API (`https://api.yadio.io`)

---

## Protocol Specification

### Event Structure (NIP-33)

**Kind:** `30078` (Application-specific data)  
**d tag:** `"rates"`  
**Publisher:** Mostro daemon pubkey (same pubkey that signs order events)

#### Example Event

```json
{
  "kind": 30078,
  "pubkey": "82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390",
  "created_at": 1732546800,
  "tags": [
    ["d", "rates"],
    ["updated_at", "1732546800"],
    ["source", "yadio"]
  ],
  "content": "{\"USD\": {\"BTC\": 0.000024}, \"EUR\": {\"BTC\": 0.000022}, \"VES\": {\"BTC\": 0.0000000012}, \"ARS\": {\"BTC\": 0.0000000095}, ...}",
  "sig": "..."
}
```

### Content Format

The `content` field is a JSON-encoded string with currency rates:

```json
{
  "USD": { "BTC": 0.000024 },
  "EUR": { "BTC": 0.000022 },
  "VES": { "BTC": 0.0000000012 },
  "ARS": { "BTC": 0.0000000095 },
  ...
}
```

**Rate semantics:** Each value represents how much BTC equals 1 unit of fiat currency.

**Example:** `"USD": {"BTC": 0.000024}` means 1 USD = 0.000024 BTC (or ~41,666 USD/BTC).

---

## Security Requirement: Pubkey Verification

**Critical:** Clients MUST verify the event `pubkey` matches the connected Mostro instance's pubkey.

### Why?

Anyone can publish a kind `30078` event with `#d: rates`. Accepting rates from untrusted sources opens attack vectors:

- **Price manipulation** — Malicious actor publishes fake rates to influence order creation
- **Market exploitation** — Attacker tricks users into accepting unfavorable trades
- **DoS via bad data** — Invalid JSON crashes the app

### Verification Flow

```rust
// Pseudo-code (Rust core logic)
fn verify_exchange_rate_event(event: &Event, mostro_pubkey: &PublicKey) -> Result<()> {
    if event.kind != 30078 {
        return Err("Invalid event kind");
    }
    
    if !event.tags.iter().any(|t| t[0] == "d" && t[1] == "rates") {
        return Err("Missing d:rates tag");
    }
    
    // CRITICAL: Verify signer is the connected Mostro instance
    if event.pubkey != *mostro_pubkey {
        return Err("Exchange rate event not signed by connected Mostro instance");
    }
    
    // Verify signature
    event.verify_signature()?;
    
    Ok(())
}
```

**Flutter integration:**
```dart
// After fetching event from Nostr
final mostroPubkey = ref.read(mostroInstanceProvider)!.pubkey;

if (event.pubkey != mostroPubkey) {
  logger.e('Exchange rate event rejected: pubkey mismatch');
  return; // Fall back to HTTP API
}

// Proceed to parse rates
final rates = jsonDecode(event.content);
```

---

## Client Implementation (v2)

### Architecture

```
ExchangeRateService (Rust core)
    ├─ NostrExchangeRateProvider (primary)
    │   ├─ Subscribe to kind 30078 with #d:rates from Mostro pubkey
    │   ├─ Verify signature + pubkey
    │   └─ Parse JSON content
    └─ YadioHttpProvider (fallback)
        └─ Fetch from https://api.yadio.io/exrates/{currency}
```

### Subscription Filter

```dart
final mostroPubkey = mostroInstance.pubkey;

final filter = Filter(
  kinds: [30078],
  authors: [mostroPubkey],  // ONLY accept events from Mostro
  tags: {
    '#d': ['rates'],
  },
);

final subscription = nostrPool.subscribe([filter]);
```

**Relay list:** Use the same relays configured for Mostro orders (ensures consistency).

**Recommended additional relays for rates:**
- `wss://relay.mostro.network` (primary)
- `wss://nos.lol` (fast, public fallback)
- `wss://relay.nostr.band` (archival)

### Update Handling

**Event reception flow:**

1. Nostr relay pushes new kind `30078` event
2. Verify `event.pubkey == mostroPubkey`
3. Verify signature (`event.verify()`)
4. Parse `event.content` as JSON
5. Update local cache (in-memory + persistent storage)
6. Notify UI (Riverpod state update)

**Cache strategy:**

- **In-memory cache:** 5-10 minute TTL
- **Persistent cache (SQLite):** Store last successful fetch as fallback if both Nostr and HTTP fail
- **Cache key:** `"exchange_rates"`

### Fallback Logic

```rust
async fn fetch_exchange_rates(&self) -> Result<Map<String, f64>> {
    // Try Nostr first
    match self.fetch_from_nostr().await {
        Ok(rates) => return Ok(rates),
        Err(e) => {
            log::warn!("Nostr exchange rates failed: {}", e);
        }
    }
    
    // Fallback to HTTP API
    match self.fetch_from_yadio_http().await {
        Ok(rates) => return Ok(rates),
        Err(e) => {
            log::error!("HTTP exchange rates failed: {}", e);
        }
    }
    
    // Last resort: load from persistent cache
    self.load_from_cache()
}
```

**Timeout policy:**
- Nostr: 10 seconds (if no event received, fall back)
- HTTP: 30 seconds (Yadio API standard timeout)

---

## Mostro Daemon Integration (Phase 1)

**File:** `src/exchange_rates.rs` (new module)

### Responsibilities

1. Fetch rates from Yadio HTTP API every 5 minutes
2. Publish NIP-33 event to configured relays
3. Sign event with Mostro's private key

### Configuration

```toml
# mostro.toml
[exchange_rates]
enabled = true
source = "yadio"
publish_interval_seconds = 300  # 5 minutes
relays = [
    "wss://relay.mostro.network",
    "wss://nos.lol",
    "wss://relay.nostr.band",
]
```

### Publishing Logic

```rust
// Pseudo-code
async fn publish_exchange_rates(&self) -> Result<()> {
    // Fetch from Yadio
    let rates = self.fetch_from_yadio().await?;
    
    // Build NIP-33 event
    let event = Event {
        kind: 30078,
        pubkey: self.keypair.public_key(),
        created_at: unix_timestamp(),
        tags: vec![
            vec!["d".to_string(), "rates".to_string()],
            vec!["updated_at".to_string(), unix_timestamp().to_string()],
            vec!["source".to_string(), "yadio".to_string()],
        ],
        content: serde_json::to_string(&rates)?,
    };
    
    // Sign with Mostro's private key
    let signed_event = event.sign(&self.keypair)?;
    
    // Publish to all relays
    for relay_url in &self.config.relays {
        self.nostr_client.publish_to(relay_url, &signed_event).await?;
    }
    
    Ok(())
}
```

**Error handling:**
- If Yadio fetch fails → log warning, skip publishing (keeps last event valid)
- If relay publish fails → log error, retry next interval
- Never crash the daemon on exchange rate errors

---

## UI/UX Considerations

### Currency Selection Dialog

**Current behavior (v1):**
- Fetches currency codes from `https://api.yadio.io/currencies` on first load
- Displays picker with currency name + emoji flag

**v2 behavior:**
- Fetch currency codes from Nostr event `content` keys
- Fallback to HTTP API if Nostr unavailable
- Cache currency list locally (rarely changes)

### Rate Staleness Warning

If rates are older than 15 minutes:

```dart
if (DateTime.now().difference(lastUpdate) > Duration(minutes: 15)) {
  // Show warning badge in order creation screen
  showStalenessWarning("Exchange rates may be outdated");
}
```

**Staleness indicator:** Yellow warning icon next to fiat amount input.

### Loading State

```dart
final ratesState = ref.watch(exchangeRatesProvider);

ratesState.when(
  loading: () => CircularProgressIndicator(),
  data: (rates) => OrderForm(rates: rates),
  error: (err, stack) => ErrorView(
    message: "Could not fetch exchange rates. Using cached data.",
    onRetry: () => ref.refresh(exchangeRatesProvider),
  ),
);
```

---

## Migration from v1 → v2

### Step 1: Add Nostr as Primary Source

- Implement `NostrExchangeRateProvider`
- Keep `YadioExchangeRateProvider` as-is (for fallback)
- Update `ExchangeService` to try Nostr first, then HTTP

### Step 2: Test in Regtest/Testnet

- Deploy mostro daemon with exchange rate publishing enabled
- Verify mobile app receives and validates events
- Test fallback when Nostr unavailable

### Step 3: Gradual Rollout

- **Beta users:** Nostr-first (with fallback)
- Monitor metrics:
  - % of rate fetches from Nostr vs HTTP
  - Latency (Nostr vs HTTP)
  - Failure rate
- **Stable release:** Once Nostr proves reliable (>95% success rate)

### Step 4: Optional HTTP API Removal

If Yadio adopts Nostr publishing:
- Remove HTTP fallback code
- Pure Nostr-based rates

---

## Performance & Reliability

### Latency Comparison

| Source | Typical Latency | Notes |
|--------|----------------|-------|
| Nostr relay (cached) | <100ms | Event already subscribed |
| Nostr relay (fresh) | 200-500ms | Initial subscription + event fetch |
| Yadio HTTP API | 300-800ms | HTTP request + JSON parsing |

**Expected improvement:** Nostr should be slightly faster in most cases (persistent subscription vs on-demand HTTP).

### Bandwidth Usage

**v1 (HTTP):**
- 1 request every 5-10 minutes per active user
- ~5-10 KB per request (all currencies)

**v2 (Nostr):**
- 1 event pushed to all subscribed clients every 5 minutes
- ~5-10 KB per event (same payload)
- No per-user request overhead

**Conclusion:** Bandwidth roughly equivalent, but Nostr scales better (relays handle distribution).

### Failure Modes

| Scenario | v1 Behavior | v2 Behavior |
|----------|-------------|-------------|
| API blocked (censorship) | ❌ Cannot create orders | ✅ Fetch from Nostr |
| Yadio API down | ❌ Cannot create orders | ✅ Fetch from Nostr |
| All relays unreachable | ❌ Cannot create orders | ⚠️ Fall back to HTTP API |
| Stale cache (>15 min) | ⚠️ Show warning | ⚠️ Show warning |

**Conclusion:** v2 significantly more resilient to censorship and single-point failures.

---

## Testing Strategy

### Unit Tests (Rust Core)

```rust
#[test]
fn test_verify_exchange_rate_event_valid() {
    let mostro_keypair = Keypair::generate();
    let event = create_test_event(&mostro_keypair);
    
    assert!(verify_exchange_rate_event(&event, &mostro_keypair.public_key()).is_ok());
}

#[test]
fn test_verify_exchange_rate_event_wrong_pubkey() {
    let mostro_keypair = Keypair::generate();
    let attacker_keypair = Keypair::generate();
    let event = create_test_event(&attacker_keypair);
    
    assert!(verify_exchange_rate_event(&event, &mostro_keypair.public_key()).is_err());
}

#[test]
fn test_parse_exchange_rates_content() {
    let content = r#"{"USD": {"BTC": 0.000024}, "EUR": {"BTC": 0.000022}}"#;
    let rates = parse_rates(content).unwrap();
    
    assert_eq!(rates.get("USD").unwrap().btc, 0.000024);
    assert_eq!(rates.get("EUR").unwrap().btc, 0.000022);
}
```

### Integration Tests (Flutter)

```dart
testWidgets('Exchange rates load from Nostr', (tester) async {
  final mockNostrService = MockNostrService();
  final mockEvent = createMockRateEvent(mostroPubkey);
  
  when(mockNostrService.subscribe(any))
      .thenAnswer((_) => Stream.value(mockEvent));
  
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nostrServiceProvider.overrideWithValue(mockNostrService),
      ],
      child: OrderCreationScreen(),
    ),
  );
  
  await tester.pumpAndSettle();
  
  expect(find.text('1 USD = 0.000024 BTC'), findsOneWidget);
});
```

### Manual Testing Checklist

- [ ] Subscribe to Nostr rates on app launch
- [ ] Verify signature rejection for wrong pubkey
- [ ] Fallback to HTTP API when Nostr unavailable
- [ ] UI updates when new rate event received
- [ ] Staleness warning after 15 minutes
- [ ] Cache persists across app restarts
- [ ] Works in censored regions (VPN test)

---

## Future Enhancements

### Multi-Source Aggregation

Support multiple rate sources (Yadio, CoinGecko, Binance) published by different Mostro instances:

```rust
// Average rates from multiple trusted pubkeys
let trusted_pubkeys = vec![mostro1_pubkey, mostro2_pubkey];
let aggregated_rate = aggregate_rates_from_sources(trusted_pubkeys).await?;
```

**Benefit:** No single point of failure, more accurate rates.

### Rate History

Store historical rates in local DB:

```sql
CREATE TABLE exchange_rate_history (
    timestamp INTEGER PRIMARY KEY,
    currency TEXT NOT NULL,
    btc_rate REAL NOT NULL
);
```

**Use case:** Show 24h price trend in order creation screen.

### Custom Rate Providers

Allow users to configure custom Nostr pubkeys for rates:

```dart
// Settings screen
TextField(
  label: "Custom rate provider pubkey (optional)",
  onChanged: (pubkey) {
    settings.customRateProviderPubkey = pubkey;
  },
);
```

**Use case:** Power users who trust a specific rate aggregator.

---

## Cross-References

- [EXCHANGE_SERVICE.md](./v1-reference/EXCHANGE_SERVICE.md) — v1 HTTP-based implementation
- [NOSTR.md](./v1-reference/NOSTR.md) — Nostr service architecture
- [MOSTRO_SERVICE.md](./v1-reference/MOSTRO_SERVICE.md) — Mostro protocol integration
- [NIP-33](https://github.com/nostr-protocol/nips/blob/master/33.md) — Parameterized Replaceable Events
- [Issue #684](https://github.com/MostroP2P/mostro/issues/684) — Original feature proposal

---

## Implementation Checklist

### Mostro Daemon (Phase 1)

- [ ] Create `src/exchange_rates.rs` module
- [ ] Fetch from Yadio HTTP API every 5 minutes
- [ ] Publish NIP-33 event to configured relays
- [ ] Sign with Mostro's private key
- [ ] Add config options to `mostro.toml`
- [ ] Error handling (log warnings, don't crash)

### Mobile Client (Phase 2)

- [ ] Implement `NostrExchangeRateProvider` (Rust core)
- [ ] Add pubkey verification logic
- [ ] Update `ExchangeService` to try Nostr first
- [ ] Implement HTTP fallback
- [ ] Add persistent cache (SQLite)
- [ ] UI: staleness warning
- [ ] UI: loading/error states
- [ ] Unit tests (Rust + Dart)
- [ ] Integration tests (Flutter)

### Documentation

- [ ] Update README with Nostr rates feature
- [ ] API migration guide (v1 → v2)
- [ ] User guide: "How exchange rates work in Mostro v2"

### Deployment

- [ ] Deploy to testnet
- [ ] Beta testing (100 users)
- [ ] Monitor metrics (Nostr vs HTTP success rate)
- [ ] Stable release
