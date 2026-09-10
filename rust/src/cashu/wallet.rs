//! Native Cashu wallet over `cdk` — see [`super`] for scope and the wasm split.

use std::sync::Arc;

use anyhow::{anyhow, bail, Result};
use cdk::amount::SplitTarget;
use cdk::nuts::nut10::SpendingConditions;
use cdk::nuts::{CurrencyUnit, Proof, Token};
use cdk::wallet::{ReceiveOptions, SendMemo, SendOptions, Wallet};
use cdk::Amount;
use cdk_sqlite::WalletSqliteDatabase;
use std::str::FromStr;

/// Everything the escrow flow needs a mint to support.
///
/// Checked once at connect rather than at the first failing operation: a seller
/// who funds a wallet at a mint that cannot do NUT-11 would only find out when
/// the escrow lock fails, with their sats already sitting at that mint.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct MintCapabilities {
    /// NUT-07 — proof state check. Without it the wallet cannot tell a spent
    /// proof from a live one after an interrupted trade.
    pub nut07_state_check: bool,
    /// NUT-11 — P2PK spending conditions. The escrow lock *is* a P2PK secret.
    pub nut11_p2pk: bool,
    /// NUT-12 — DLEQ proofs, so a received token can be verified as genuinely
    /// issued by this mint rather than taken on trust.
    pub nut12_dleq: bool,
    /// A keyset denominated in `sat`. Mostro amounts are satoshis.
    pub has_sat_keyset: bool,
}

impl MintCapabilities {
    /// All four, or the mint is not one we can trade against.
    pub fn is_usable(&self) -> bool {
        self.nut07_state_check && self.nut11_p2pk && self.nut12_dleq && self.has_sat_keyset
    }

    /// Stable markers for what is missing. Rust does not translate; Dart maps
    /// these to localized strings.
    pub fn missing(&self) -> Vec<&'static str> {
        let mut missing = Vec::new();
        if !self.nut07_state_check {
            missing.push("nut07");
        }
        if !self.nut11_p2pk {
            missing.push("nut11");
        }
        if !self.nut12_dleq {
            missing.push("nut12");
        }
        if !self.has_sat_keyset {
            missing.push("sat_keyset");
        }
        missing
    }
}

/// A wallet bound to exactly one mint.
///
/// One mint is not a simplification to revisit later: the Mostro node pins the
/// mint for every escrow (§2 of the Cashu doc), so ecash at any other mint has
/// no counterparty to trade with.
pub struct CashuWallet {
    inner: Wallet,
    mint_url: String,
    capabilities: MintCapabilities,
}

/// Hand-written so a failed `connect` can be unwrapped in tests and logged
/// without pulling `cdk::Wallet` into the output — it holds the seed, and a
/// derived `Debug` would risk printing key material into a log.
impl std::fmt::Debug for CashuWallet {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CashuWallet")
            .field("mint_url", &self.mint_url)
            .field("capabilities", &self.capabilities)
            .finish_non_exhaustive()
    }
}

impl CashuWallet {
    /// Open the local proof store, bind to `mint_url` and verify it is usable.
    ///
    /// `seed` is the identity's BIP-39 seed, so the ecash is recoverable from
    /// the words the user already backed up. `db_path` is the proof store's own
    /// SQLite file — never the app's, whose schema is unrelated and whose
    /// migrations must not run against `cdk`'s tables.
    ///
    /// **Errors** (stable markers): `CashuMintUnreachable` when the mint does
    /// not answer, `CashuMintUnusable` when it answers but lacks a required NUT
    /// or the `sat` keyset.
    pub async fn connect(
        mint_url: &str,
        seed: zeroize::Zeroizing<[u8; 64]>,
        db_path: &str,
    ) -> Result<Self> {
        let localstore = WalletSqliteDatabase::new(db_path)
            .await
            .map_err(|e| anyhow!("CashuStoreUnavailable: {e}"))?;

        let inner = Wallet::new(
            mint_url,
            CurrencyUnit::Sat,
            Arc::new(localstore),
            // cdk takes the seed by value; our copy is wiped on drop.
            *seed,
            // cdk's own default: keep roughly this many proofs per denomination
            // so an ordinary send rarely needs an extra swap round trip.
            None,
        )
        .map_err(|e| anyhow!("CashuWalletInit: {e}"))?;

        let capabilities = Self::probe(&inner).await?;
        if !capabilities.is_usable() {
            bail!("CashuMintUnusable: {}", capabilities.missing().join(","));
        }

        log::info!("[cashu] connected to {mint_url}");
        Ok(Self {
            inner,
            mint_url: mint_url.to_string(),
            capabilities,
        })
    }

    /// Ask the mint what it supports. Reachability is proven by the same call,
    /// so there is no separate ping.
    async fn probe(wallet: &Wallet) -> Result<MintCapabilities> {
        let info = wallet
            .fetch_mint_info()
            .await
            .map_err(|e| anyhow!("CashuMintUnreachable: {e}"))?
            .ok_or_else(|| anyhow!("CashuMintUnreachable: mint published no info"))?;

        let keysets = wallet
            .load_mint_keysets()
            .await
            .map_err(|e| anyhow!("CashuMintUnreachable: {e}"))?;

        Ok(MintCapabilities {
            nut07_state_check: info.nuts.nut07.supported,
            nut11_p2pk: info.nuts.nut11.supported,
            nut12_dleq: info.nuts.nut12.supported,
            has_sat_keyset: keysets.iter().any(|k| k.unit == CurrencyUnit::Sat),
        })
    }

    /// The mint this wallet is bound to.
    pub fn mint_url(&self) -> &str {
        &self.mint_url
    }

    /// The underlying `cdk` wallet, for the escrow primitives in
    /// [`super::escrow`]. Crate-internal: everything outside this module goes
    /// through the methods above, so mint access stays in one place.
    pub(crate) fn inner(&self) -> &Wallet {
        &self.inner
    }

    /// The proofs inside a token.
    ///
    /// Needs the mint's keysets — a v4 token identifies its keyset by id — so
    /// this cannot be a free function on the token alone.
    pub(crate) async fn proofs_of(&self, token: &Token) -> Result<Vec<Proof>> {
        let keysets = self
            .inner
            .load_mint_keysets()
            .await
            .map_err(|e| anyhow!("CashuMintUnreachable: {e}"))?;
        token
            .proofs(&keysets)
            .map_err(|e| anyhow!("InvalidEscrowToken: unreadable proofs ({e})"))
    }

    /// What the mint advertised at connect time.
    pub fn capabilities(&self) -> &MintCapabilities {
        &self.capabilities
    }

    /// Spendable balance in satoshis.
    pub async fn balance(&self) -> Result<u64> {
        let amount = self
            .inner
            .total_balance()
            .await
            .map_err(|e| anyhow!("CashuBalance: {e}"))?;
        Ok(u64::from(amount))
    }

    /// Swap an encoded token into this wallet, returning the amount received.
    ///
    /// `cdk` swaps the incoming proofs for fresh ones at the mint, so a token
    /// that was also copied elsewhere cannot be spent twice against us, and a
    /// token from another mint is rejected rather than ignored.
    ///
    /// DLEQ (NUT-12) is verified **here**, before the swap, rather than left to
    /// `cdk`: its receive path verifies a proof only `if proof.dleq.is_some()`
    /// (`wallet/receive/saga/mod.rs`, cdk 0.17.3), so a token whose proofs carry
    /// none is accepted on trust. That is the softer guarantee NUT-12 is a hard
    /// connect requirement to avoid — [`Wallet::verify_token_dleq`] rejects the
    /// missing proof instead of skipping it.
    ///
    /// **Errors** (stable markers): `CashuTokenUnverified` when the token
    /// carries no usable DLEQ proof, `CashuReceiveFailed` for everything else
    /// (malformed, wrong mint, already spent).
    pub async fn receive_token(&self, encoded: &str) -> Result<u64> {
        let normalized = normalize_token(encoded);
        let token = Token::from_str(&normalized).map_err(|e| anyhow!("CashuReceiveFailed: {e}"))?;

        if let Err(e) = self.inner.verify_token_dleq(&token).await {
            // A token minted elsewhere is a plain user mistake, not a failed
            // proof — same rejection, different thing to tell the user.
            return match e {
                cdk::Error::IncorrectWallet(detail) => {
                    Err(anyhow!("CashuReceiveFailed: {detail}"))
                }
                other => Err(anyhow!("CashuTokenUnverified: {other}")),
            };
        }

        let amount = self
            .inner
            .receive(&normalized, ReceiveOptions::default())
            .await
            .map_err(|e| anyhow!("CashuReceiveFailed: {e}"))?;
        log::info!("[cashu] received {amount} sat");
        Ok(u64::from(amount))
    }

    /// Export `amount_sats` as an encoded token.
    ///
    /// The proofs are reserved before the token is handed out and only settle
    /// once the recipient redeems them. A token that is never redeemed leaves
    /// its proofs reserved: reclaiming *that* is `revoke_send`, which arrives
    /// with the rest of reconciliation in phase C10 —
    /// [`Self::sweep_spent_proofs`] does not do it and does not claim to. The
    /// one case handled here is the send that fails on the way out, in
    /// [`Self::send_with_conditions`].
    ///
    /// **Errors** (stable markers): `CashuAmountZero`, `CashuSendFailed` (the
    /// send failed and the proofs are back), `CashuSendUnresolved` (the send
    /// failed and the proofs could *not* be confirmed back).
    pub async fn create_token(&self, amount_sats: u64) -> Result<String> {
        self.send_with_conditions(amount_sats, None).await
    }

    /// Swap `amount_sats` of wallet proofs into a token, optionally locked to
    /// `conditions` (NUT-11). `None` is a plain send; the escrow primitives in
    /// [`super::escrow`] pass the 2-of-3.
    ///
    /// One implementation for both because the failure path is the subtle
    /// part and must not drift: a `confirm` that fails after `prepare_send`
    /// leaves the whole amount reserved and invisible unless it is revoked
    /// here, and for an escrow that amount is the whole trade.
    ///
    /// **Errors** (stable markers): `CashuAmountZero`, `CashuSendFailed`,
    /// `CashuSendUnresolved` — see [`Self::create_token`].
    pub(crate) async fn send_with_conditions(
        &self,
        amount_sats: u64,
        conditions: Option<SpendingConditions>,
    ) -> Result<String> {
        if amount_sats == 0 {
            bail!("CashuAmountZero");
        }

        let prepared = self
            .inner
            .prepare_send(
                Amount::from(amount_sats),
                SendOptions {
                    conditions,
                    amount_split_target: SplitTarget::default(),
                    ..Default::default()
                },
            )
            .await
            .map_err(|e| anyhow!("CashuSendFailed: {e}"))?;

        // Kept before `confirm` consumes the handle: it is the only way back to
        // the proofs this send reserved.
        let operation_id = prepared.operation_id();

        let token = match prepared.confirm(None::<SendMemo>).await {
            Ok(token) => token,
            Err(e) => {
                // `prepare_send` reserved the proofs against `operation_id`;
                // `confirm` consumed the handle, so `cancel()` is gone. cdk
                // rolls the reservation back itself only for a *definitive*
                // failure (`wallet/send/saga/mod.rs`) — an ordinary mint
                // timeout is not one, and leaves the proofs reserved, which the
                // UI would show as the balance simply dropping.
                //
                // `revoke_send` is the way back once the saga reached
                // `TokenCreated`. It is not a reclaim of the *send* — the token
                // may exist — which is exactly why it is only ever called on
                // this failure path, never as routine recovery (that is C10).
                return match self.inner.revoke_send(operation_id).await {
                    Ok(reclaimed) => Err(anyhow!("CashuSendFailed: {e} (reclaimed {reclaimed} sat)")),
                    Err(revoke_err) => {
                        // Either cdk already rolled the send back (then nothing
                        // is stuck) or the proofs are still reserved (then they
                        // need C10's reconciliation). This code cannot tell the
                        // two apart, so it claims neither: no "reclaimed 0 sat",
                        // which would read as "your funds are accounted for".
                        log::error!(
                            "[cashu] send {operation_id} failed ({e}) and could not be revoked: {revoke_err}"
                        );
                        Err(anyhow!("CashuSendUnresolved: {e}"))
                    }
                };
            }
        };

        Ok(token.to_string())
    }

    /// Mint `amount_sats` straight from the mint, for tests only.
    ///
    /// Against a `FakeWallet` backend (which is what a local nutshell runs) the
    /// quote settles itself, so this funds a wallet with no Lightning node and
    /// no manual step. Without it the integration tests below assert
    /// "fund the wallet first" and can never pass, which makes them
    /// documentation rather than verification.
    #[cfg(test)]
    pub(crate) async fn mint_for_test(&self, amount_sats: u64) -> Result<u64> {
        use cdk::nuts::PaymentMethod;

        let quote = self
            .inner
            .mint_quote(
                PaymentMethod::BOLT11,
                Some(Amount::from(amount_sats)),
                None,
                None,
            )
            .await
            .map_err(|e| anyhow!("CashuMintQuoteFailed: {e}"))?;

        let proofs = self
            .inner
            .mint(&quote.id, SplitTarget::default(), None)
            .await
            .map_err(|e| anyhow!("CashuMintFailed: {e} (is the mint in FakeWallet mode?)"))?;

        Ok(proofs.iter().map(|p| u64::from(p.amount)).sum())
    }

    /// Ask the mint about proofs this wallet still holds as pending and forget
    /// the ones it reports spent (NUT-07).
    ///
    /// **Housekeeping, not recovery — nothing comes back from this call.** Two
    /// facts about `cdk`'s `check_all_pending_proofs` (`wallet/proofs.rs`,
    /// cdk 0.17.3) decide that:
    ///
    /// * it looks only at proofs no operation owns
    ///   (`p.used_by_operation.is_none()`), and `prepare_send` reserves
    ///   *against* an operation id (`wallet/send/saga/mod.rs`) — so it skips, by
    ///   construction, every proof a send of ours reserved;
    /// * the proofs the mint still calls live are left exactly as they are; only
    ///   the spent ones are dropped from the store.
    ///
    /// Which is why this returns nothing rather than a number that would read as
    /// "reclaimed". A token of ours that nobody redeemed is reclaimed with
    /// `revoke_send` over `get_pending_sends`, and doing that safely — deciding
    /// a token is abandoned — is reconciliation, phase C10.
    pub async fn sweep_spent_proofs(&self) -> Result<()> {
        // The return value is the *unresolved* remainder among orphaned proofs,
        // not a reclaim. Logged, because it is a diagnostic and nothing more.
        let unresolved = self
            .inner
            .check_all_pending_proofs()
            .await
            .map_err(|e| anyhow!("CashuStateCheckFailed: {e}"))?;
        log::info!("[cashu] swept spent proofs ({unresolved} sat still unresolved)");
        Ok(())
    }
}

/// Strip whitespace and the `cashu:` URI scheme.
///
/// QR payloads routinely carry `cashu:cashuB…`, and a wallet that rejects them
/// tells the user their token is from another mint or already spent — three
/// wrong explanations for one missing prefix strip.
pub(crate) fn normalize_token(encoded: &str) -> String {
    let trimmed = encoded.trim();
    trimmed
        .strip_prefix("cashu://")
        .or_else(|| trimmed.strip_prefix("cashu:"))
        .unwrap_or(trimmed)
        .trim()
        .to_string()
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    /// Integration tests need a real mint. Point this at a local
    /// [nutshell](https://github.com/cashubtc/nutshell):
    ///
    /// ```text
    /// docker run -p 3338:3338 cashubtc/nutshell:latest poetry run mint
    /// MOSTRO_TEST_MINT_URL=http://localhost:3338 cargo test -- --ignored
    /// ```
    ///
    /// They are `#[ignore]` so CI stays green without one. A mock is not an
    /// option here: it would have to fake blind signatures and DLEQ proofs, and
    /// a wallet that passes against faked cryptography has proven nothing.
    fn test_mint_url() -> String {
        std::env::var("MOSTRO_TEST_MINT_URL")
            .expect("set MOSTRO_TEST_MINT_URL to run the Cashu integration tests")
    }

    /// A seed unique to this process *and* this call.
    ///
    /// cdk derives blinding secrets deterministically from the seed and a
    /// counter kept in the wallet DB (NUT-13). These tests create a fresh DB
    /// each time, so a fixed seed replays the same blinded messages and the
    /// mint answers "already signed" on the second run. Unique seeds make the
    /// suite re-runnable, which is the whole point of a reviewer being able to
    /// run it.
    fn unique_seed() -> zeroize::Zeroizing<[u8; 64]> {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let mut seed = [0u8; 64];
        let pid = std::process::id() as u64;
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        seed[..8].copy_from_slice(&pid.to_le_bytes());
        seed[8..16].copy_from_slice(&n.to_le_bytes());
        seed[16..24].copy_from_slice(
            &std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos() as u64)
                .unwrap_or(0)
                .to_le_bytes(),
        );
        zeroize::Zeroizing::new(seed)
    }

    fn temp_db_path() -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU32, Ordering};
        static COUNTER: AtomicU32 = AtomicU32::new(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir().join(format!("mostro_cashu_test_{}_{n}.db", std::process::id()))
    }

    #[test]
    fn a_mint_missing_any_requirement_is_unusable() {
        // Arrange — everything present.
        let all = MintCapabilities {
            nut07_state_check: true,
            nut11_p2pk: true,
            nut12_dleq: true,
            has_sat_keyset: true,
        };

        // Assert
        assert!(all.is_usable());
        assert!(all.missing().is_empty());

        // Act / Assert — dropping any single requirement closes the door, and
        // the marker says which. There is no partial "works for now" state.
        for (dropped, marker) in [
            (
                MintCapabilities {
                    nut07_state_check: false,
                    ..all.clone()
                },
                "nut07",
            ),
            (
                MintCapabilities {
                    nut11_p2pk: false,
                    ..all.clone()
                },
                "nut11",
            ),
            (
                MintCapabilities {
                    nut12_dleq: false,
                    ..all.clone()
                },
                "nut12",
            ),
            (
                MintCapabilities {
                    has_sat_keyset: false,
                    ..all.clone()
                },
                "sat_keyset",
            ),
        ] {
            assert!(!dropped.is_usable(), "{marker} must be required");
            assert_eq!(dropped.missing(), vec![marker]);
        }
    }

    #[test]
    fn a_scanned_token_uri_is_accepted() {
        // Arrange — the shapes a QR scanner actually hands over. Rejecting any
        // of these tells the user their token is from another mint or already
        // spent, which is three wrong explanations for a missing prefix strip.
        for input in [
            "cashuBtoken",
            "  cashuBtoken\n",
            "cashu:cashuBtoken",
            "cashu://cashuBtoken",
            "  cashu: cashuBtoken ",
        ] {
            assert_eq!(normalize_token(input), "cashuBtoken", "input: {input:?}");
        }
    }

    #[test]
    fn normalisation_leaves_a_token_body_alone() {
        // Assert — only the scheme is stripped, never a prefix that happens to
        // look like one inside the payload.
        assert_eq!(normalize_token("cashuBcashu:inner"), "cashuBcashu:inner");
    }

    #[test]
    fn a_fresh_capability_set_is_unusable() {
        // Assert — the default must fail closed, so a probe that never ran
        // cannot be mistaken for a usable mint.
        let unknown = MintCapabilities::default();
        assert!(!unknown.is_usable());
        assert_eq!(unknown.missing().len(), 4);
    }

    #[tokio::test]
    #[ignore = "requires a local nutshell mint (MOSTRO_TEST_MINT_URL)"]
    async fn connects_to_a_real_mint_and_starts_empty() {
        // Arrange / Act
        let path = temp_db_path();
        let wallet = CashuWallet::connect(&test_mint_url(), unique_seed(), path.to_str().unwrap())
            .await
            .expect("nutshell must be reachable");

        // Assert
        assert!(wallet.capabilities().is_usable());
        assert_eq!(wallet.balance().await.unwrap(), 0);

        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    #[ignore = "requires a local nutshell mint (MOSTRO_TEST_MINT_URL)"]
    async fn an_unreachable_mint_fails_with_a_marker() {
        // Arrange — a port nothing listens on.
        let path = temp_db_path();

        // Act
        let err = CashuWallet::connect("http://127.0.0.1:1", unique_seed(), path.to_str().unwrap())
            .await
            .unwrap_err();

        // Assert — the marker is what Dart localizes; the cause is for the log.
        assert!(err.to_string().contains("CashuMintUnreachable"), "got {err}");

        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    #[ignore = "requires a local nutshell mint (MOSTRO_TEST_MINT_URL)"]
    async fn a_token_round_trips_between_two_wallets() {
        // Arrange — two wallets at the same mint, funded from the mint itself.
        let sender_path = temp_db_path();
        let receiver_path = temp_db_path();
        let mint = test_mint_url();

        let sender = CashuWallet::connect(&mint, unique_seed(), sender_path.to_str().unwrap())
            .await
            .unwrap();
        let receiver = CashuWallet::connect(&mint, unique_seed(), receiver_path.to_str().unwrap())
            .await
            .unwrap();

        sender.mint_for_test(64).await.expect("mint must fund the wallet");
        let funded = sender.balance().await.unwrap();
        assert!(funded >= 8, "minting should have funded the wallet");

        // Act
        let token = sender.create_token(8).await.unwrap();
        let received = receiver.receive_token(&token).await.unwrap();

        // Assert — the sender parted with the token's face value; the receiver
        // gets that minus whatever the mint charges to swap (nutshell's default
        // keyset has a non-zero input fee, and a real mint may too).
        assert!(
            received > 0 && received <= 8,
            "received {received} sat for an 8 sat token"
        );
        assert_eq!(receiver.balance().await.unwrap(), received);
        assert_eq!(sender.balance().await.unwrap(), funded - 8);

        let _ = std::fs::remove_file(&sender_path);
        let _ = std::fs::remove_file(&receiver_path);
    }

    /// The guarantee C2 promises on receive, exercised the only way that proves
    /// anything: take a genuine token, strip its DLEQ proofs, and hand it back.
    /// cdk's own receive path would accept this one — it verifies a proof only
    /// when the proof is there — so a pass here is the explicit check working,
    /// not cdk's.
    #[tokio::test]
    #[ignore = "requires a local nutshell mint (MOSTRO_TEST_MINT_URL)"]
    async fn a_token_stripped_of_its_dleq_proofs_is_refused() {
        // Arrange — a real token from a funded wallet.
        let path = temp_db_path();
        let receiver_path = temp_db_path();
        let mint = test_mint_url();

        let sender = CashuWallet::connect(&mint, unique_seed(), path.to_str().unwrap())
            .await
            .unwrap();
        let receiver = CashuWallet::connect(&mint, unique_seed(), receiver_path.to_str().unwrap())
            .await
            .unwrap();
        sender.mint_for_test(64).await.expect("mint must fund the wallet");

        let encoded = sender.create_token(8).await.unwrap();
        let token = Token::from_str(&encoded).unwrap();

        // Act — the same token, minus the evidence that the mint issued it.
        let keysets = receiver.inner.load_mint_keysets().await.unwrap();
        let stripped: Vec<_> = token
            .proofs(&keysets)
            .unwrap()
            .into_iter()
            .map(|mut p| {
                p.dleq = None;
                p
            })
            .collect();
        let no_dleq = Token::new(
            token.mint_url().unwrap(),
            stripped,
            None,
            CurrencyUnit::Sat,
        );

        let err = receiver
            .receive_token(&no_dleq.to_string())
            .await
            .unwrap_err();

        // Assert — refused, and with the marker that says *why*, not the
        // generic receive failure a user would read as "bad token".
        assert!(
            err.to_string().contains("CashuTokenUnverified"),
            "got {err}"
        );
        // And the genuine one still goes through, so the check is not simply
        // refusing everything.
        assert!(receiver.receive_token(&encoded).await.unwrap() > 0);

        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(&receiver_path);
    }

    /// Pins the honest half of [`CashuWallet::sweep_spent_proofs`]: a token this
    /// wallet created and nobody redeemed is **not** recovered by it, because
    /// cdk's state check skips proofs an operation reserved. The test exists so
    /// that a future "the sweep should bring it back" reading of the name gets
    /// a failing test instead of a wrong balance — reclaiming is C10.
    #[tokio::test]
    #[ignore = "requires a local nutshell mint (MOSTRO_TEST_MINT_URL)"]
    async fn an_unredeemed_token_is_not_recovered_by_the_sweep() {
        // Arrange
        let path = temp_db_path();
        let wallet = CashuWallet::connect(&test_mint_url(), unique_seed(), path.to_str().unwrap())
            .await
            .unwrap();
        wallet.mint_for_test(64).await.expect("mint must fund the wallet");
        let funded = wallet.balance().await.unwrap();

        // Act — export a token and abandon it.
        let _abandoned = wallet.create_token(8).await.unwrap();
        let after_send = wallet.balance().await.unwrap();
        wallet.sweep_spent_proofs().await.unwrap();

        // Assert — the sats are still out of reach, and the sweep said nothing
        // to the contrary.
        assert_eq!(after_send, funded - 8, "the send should have left the balance");
        assert_eq!(
            wallet.balance().await.unwrap(),
            after_send,
            "the sweep must not be mistaken for a reclaim"
        );

        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    #[ignore = "requires a local nutshell mint (MOSTRO_TEST_MINT_URL)"]
    async fn creating_a_zero_token_is_rejected_before_touching_the_mint() {
        let path = temp_db_path();
        let wallet = CashuWallet::connect(&test_mint_url(), unique_seed(), path.to_str().unwrap())
            .await
            .unwrap();

        let err = wallet.create_token(0).await.unwrap_err();
        assert!(err.to_string().contains("CashuAmountZero"), "got {err}");

        let _ = std::fs::remove_file(&path);
    }
}
