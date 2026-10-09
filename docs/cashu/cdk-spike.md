# cdk spike — what was verified before C2

Findings from a throwaway crate built against **cdk 0.17.3** before writing the
wallet phase. The spike itself is not in the repo; this is what it established,
and it is the justification for the version pin in `rust/Cargo.toml`.

§1–§3 are the spike as it ran on 0.17.3. The pin has moved since; what each
upgrade re-checked is in §5.

Everything below was *run*, not read off documentation.

## 1. NUT-11 with custom tags — yes, fully

This was the question that could have doubled the size of C4. It does not.

`cashu` (re-exported through `cdk::nuts`) exposes the whole NUT-11 surface:

```rust
Conditions::new(
    Some(locktime),                    // unix seconds
    Some(vec![buyer_pk, seller_pk]),   // additional pubkeys
    Some(vec![seller_pk]),             // refund keys
    Some(2),                           // n_sigs
    Some(SigFlag::SigInputs),          // sigflag
    Some(1),                           // n_sigs_refund
)?;

SpendingConditions::P2PKConditions { data: mostro_pk, conditions: Some(conditions) }
```

Verified in the spike:

- the built conditions serialise into a NUT-10 secret containing `P2PK`,
  `n_sigs`, `SIG_INPUTS`, `locktime`, `refund` and `n_sigs_refund`;
- `SpendingConditions::try_from(&Secret)` round-trips back to an equal value, so
  the client can *read* an escrow secret it did not build — which is what the
  buyer must do to verify the seller locked correctly;
- `Proof::sign_p2pk(secret_key)` attaches a per-proof witness signature;
- `SendOptions` carries `conditions`, `p2pk_signing_keys` and
  `p2pk_locked_proof_send_mode`, so locking on send **and** spending a locked
  input are both first-class.

**Consequence for C4:** no hand-built secrets, no hand-rolled witness encoding.
C4 builds `Conditions`, hands them to the wallet, and signs.

## 2. `WalletDatabase` over IndexedDB — possible, but its own phase

`cdk_common::database::wallet::Database` is declared

```rust
#[cfg_attr(target_arch = "wasm32", async_trait(?Send))]
#[cfg_attr(not(target_arch = "wasm32"), async_trait)]
```

so the trait is *designed* for a non-`Send` wasm implementation. There is no
ready-made backend, though: `cdk-rexie` and `cdk-indexeddb` do not exist at
0.17.3, and `cdk-sqlite` is `rusqlite` — native only, no wasm feature.

The trait has **50 async methods** (mints, keysets, quotes, proofs,
transactions, keys). That is a phase, not a detail.

**Consequence:** C9 stays a real phase. C2 ships native-only with a typed stub
on web, the same split `crate::nwc::client` already uses. Note this compounds
with #233 — the app's *own* IndexedDB backend is a stub too, so "web
persistence" is one problem, not two.

## 3. wasm32 compilation — confirmed

```
cargo add cdk@0.17.3 --no-default-features --features wallet
cargo check --target wasm32-unknown-unknown     # clean
```

`cdk`'s manifest carries explicit `cfg(target_arch = "wasm32")` dependency
blocks (getrandom with `wasm32_unknown_unknown_js`, gloo-timers, a sync-only
tokio). So the web gap really is storage alone — the protocol half would build
today.

## 4. The pin: `=0.18.1`, wallet feature only

```toml
cdk        = { version = "=0.18.1", default-features = false, features = ["wallet"] }
cdk-sqlite = { version = "=0.18.1", default-features = false, features = ["wallet"] }
```

Exact-pinned, not caret. cdk is pre-1.0: minor releases move the wallet API
(`prepare_send`/`confirm` replaced a direct `send` in this line's history), and
a silent bump would break the escrow construction with no test to catch it
until a trade failed.

Default features are off deliberately. The default set pulls `mint`,
`cdk-signatory`, `nostr` and `bip353` and, transitively, an HTTP/TLS/tor stack
the app does not use — `wallet` alone is what a client needs.

### Upgrade procedure

When moving off the current pin:

1. Re-run the checks above — especially §1, since the escrow secret is the part
   with no compile-time guarantee of *semantic* stability.
2. `cargo check --target wasm32-unknown-unknown` (the stub must still build even
   though it does not use cdk).
3. Run the `#[ignore]`d Cashu integration tests against a local nutshell:
   `MOSTRO_TEST_MINT_URL=http://localhost:3338 cargo test --lib cashu:: -- --ignored`,
   or against the public test mint:
   `MOSTRO_TEST_MINT_URL=https://testnut.cashu.space cargo test --lib cashu:: -- --ignored`.
   Keep the `cashu::` filter: an unfiltered `--ignored` also starts the NWC and
   regtest tests, which fail without their own setup. These are the only thing
   that exercises real blind signatures and DLEQ; a unit test cannot substitute
   for them.
4. Check `SendOptions` and `ReceiveOptions` field by field — they are built with
   `..Default::default()`, so a new field lands silently.
5. Re-read the cdk internals that comments in `rust/src/cashu/` cite by file and
   version, and update the version they name only once each still holds.
6. Add an entry to §5.

## 5. Upgrade log

### 0.17.3 → 0.18.1 (#757)

- **API:** `Wallet::load_mint_keysets()` is gone. `keysets(KeysetLoadPolicy)`
  replaces it, but returns `KeySet` (with keys) for **every** keyset of the
  wallet's unit, rotated ones included, where the old call returned the active
  `KeySetInfo`s. So the connect-time `sat` keyset check now asks for an
  *active* one explicitly (policy `Refresh`), and `proofs_of` maps back to
  `KeySetInfo` for `Token::proofs` — keeping rotated keysets, as cdk's own
  crate-private `token_proofs` does.
- **Unchanged:** `receive_proofs`' signature, and the fields of `SendOptions`
  and `ReceiveOptions`. The receive path still verifies DLEQ only when a proof
  carries one, and `check_all_pending_proofs` still skips proofs an operation
  owns — the two cdk facts `wallet.rs` documents.
- **Wallet database:** opening it runs the 0.18 migrations (transaction
  status, derivation indices and counters, saga transactions re-keyed). They
  run in one transaction (`cdk-sql-common`, `wallet/mod.rs`), so a kill
  mid-migration leaves the 0.17 schema intact; once committed, a 0.17.3 build
  may not open the file. **No release goes back to 0.17.x after one ships
  0.18** — fix forward.
- **Verified:** `cargo test`, `cargo clippy`, `cargo check --target
  wasm32-unknown-unknown`, and all twelve `#[ignore]`d Cashu tests against
  `testnut.cashu.space` (a `cdk-mintd` 0.17 mint) — before the bump and after.
  The escrow tests among them cover §1 end to end: conditions built, read back
  by the buyer's verification, signed, settled two of three.
- **Upgrade, by hand (Linux):** a wallet store created by 0.17.3 (34 cdk
  migrations, balance on testnut) opened by 0.18.1: the six new migrations
  applied once, the balance intact, a token sent and redeemed by another
  wallet, the balance unchanged after a restart. Receive and an in-app escrow
  trade were not run by hand; the integration tests cover them.
- **Behaviour change:** a mint whose `sat` keysets are all inactive used to
  fail connect as `CashuMintUnreachable` (the active list came back empty) and
  now fails as `CashuMintUnusable: sat_keyset`, which is the accurate marker.
