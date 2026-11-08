//! Native Cashu wallet over `cdk` — see [`super`] for scope and the wasm split.

use std::collections::HashMap;
use std::future::IntoFuture;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, bail, Result};
use cdk::amount::SplitTarget;
use cdk::cdk_database::{self, WalletDatabase};
use cdk::nuts::nut10::SpendingConditions;
use cdk::mint_url::MintUrl;
use cdk::nuts::MeltQuoteState;
use cdk::nuts::{
    CurrencyUnit, KeySetInfo, MeltMethodSettings, MintMethodSettings, PaymentMethod, Proof, Token,
};
use cdk::wallet::types::KeysetLoadPolicy;
use cdk::wallet::{MeltOutcome, PreparedMelt, ReceiveOptions, SendMemo, SendOptions, Wallet};
use cdk::Amount;
use cdk_sqlite::WalletSqliteDatabase;
use std::str::FromStr;
use uuid::Uuid;

use super::{in_flight, mint_clock};

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
    /// NUT-05 — melt to a `bolt11` invoice in `sat`, and melting not
    /// `disabled`. What "send to Lightning" needs (phase C3b-1).
    ///
    /// **Optional, unlike the four above**: it is not part of
    /// [`Self::is_usable`]. An escrow never melts, so a mint without it still
    /// trades; the wallet screen hides "to Lightning" instead of refusing the
    /// mint.
    pub nut05_bolt11: bool,
    /// The smallest melt the mint accepts, in sats, when it states one.
    pub melt_min_sats: Option<u64>,
    /// The largest melt the mint accepts, in sats, when it states one.
    pub melt_max_sats: Option<u64>,
    /// NUT-04 — mint against a `bolt11` invoice in `sat`, and minting not
    /// `disabled`. What "receive via Lightning" needs (phase C3b-2).
    ///
    /// **Optional**, like [`Self::nut05_bolt11`]: an escrow never mints from
    /// Lightning, so the wallet screen hides "via Lightning" instead of
    /// refusing the mint.
    pub nut04_bolt11: bool,
    /// The smallest invoice the mint issues, in sats, when it states one.
    pub mint_min_sats: Option<u64>,
    /// The largest invoice the mint issues, in sats, when it states one.
    pub mint_max_sats: Option<u64>,
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

/// What paying a Lightning invoice from the wallet costs, as quoted by the mint
/// and priced against the proofs the wallet would spend.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MeltQuoteInfo {
    /// The mint's quote, to pay with [`CashuWallet::melt`].
    pub quote_id: String,
    /// What the invoice asks for.
    pub amount_sats: u64,
    /// The most the mint may spend on Lightning routing. What it does not
    /// spend comes back as change (NUT-08).
    pub fee_reserve_sats: u64,
    /// The mint's input fees: on the melt's inputs and, when the wallet's
    /// proofs do not add up to the exact amount, on the swap that makes them.
    pub input_fee_sats: u64,
    /// The most the payment can take from the balance:
    /// [`melt_max_total`] of the three above.
    pub max_total_sats: u64,
}

/// How a melt the user confirmed ended.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MeltOutcomeInfo {
    /// The invoice is paid.
    Paid {
        amount_sats: u64,
        /// What the payment cost beyond the invoice: input and swap fees plus
        /// the routing fee the mint kept.
        fee_paid_sats: u64,
    },
    /// The mint accepted the payment and is still routing it. The proofs stay
    /// reserved; [`CashuWallet::finalize_pending_melts`] settles them once
    /// the mint says how it ended.
    Pending,
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
        let wallet = Self {
            inner,
            mint_url: mint_url.to_string(),
            capabilities,
        };
        wallet.recover().await;
        Ok(wallet)
    }

    /// Finish or roll back what a previous session left half done at this
    /// mint: a send or melt whose proofs were reserved but never handed over,
    /// a swap or receive whose outputs were never stored, a melt whose
    /// Lightning payment was still in flight.
    ///
    /// Safe for escrow and exported tokens: cdk compensates only a send still
    /// in `ProofsReserved` — no token exists yet — and never revokes one in
    /// `TokenCreated` (`wallet/send/saga/resume.rs`, cdk 0.18.2). That
    /// reclaim stays C10's. Melts in flight are resumed here too, so connect
    /// does not call [`Self::finalize_pending_melts`] on top.
    ///
    /// **Only at connect, never on Sync.** cdk documents it as crash recovery
    /// ("Call on startup", `wallet/recovery.rs`) and rolls back a send or melt
    /// in `ProofsReserved` with no check that it is still running
    /// (`wallet/send/saga/resume.rs`) — the state of an escrow lock, a token
    /// send or a melt being prepared. Here the wallet is not installed yet, so
    /// nothing runs on it — but an earlier wallet for the same mint, left by
    /// switching mints and back, may still be melting. So recovery waits for
    /// the next connect while a melt holds the mint ([`in_flight`]), and
    /// likewise while its mint quotes are being checked or minted. A send
    /// or escrow lock still running there is not covered: closing that needs
    /// those operations to hold a mark too.
    ///
    /// **Best effort.** The mint has just proven usable, so a failure here is a
    /// round trip that did not come back: it is logged and the connect goes
    /// on. Whatever was not settled is still recorded as a saga and is tried
    /// again at the next connect.
    async fn recover(&self) {
        if in_flight::melt_in_flight(&self.inner.mint_url) {
            log::info!(
                "[cashu] a melt is in flight at this mint: recovery waits for the next connect"
            );
            return;
        }
        // Held for the whole recovery: it resumes issue sagas too, and an
        // invoice screen still polling a wallet for this mint must not run a
        // check against one meanwhile, nor this against its mint.
        let Some(_issuing) = in_flight::try_begin_issue(&self.inner.mint_url) else {
            log::info!(
                "[cashu] mint quotes are being checked at this mint: recovery waits for the next connect"
            );
            return;
        };
        match self.inner.recover_incomplete_sagas().await {
            Ok(report) if report.is_empty() => {}
            Ok(report) => log::info!(
                "[cashu] recovered interrupted operations: {} completed, {} rolled back, {} still pending, {} failed",
                report.recovered,
                report.compensated,
                report.skipped,
                report.failed
            ),
            Err(e) => log::warn!("[cashu] recovering interrupted operations failed: {e}"),
        }
    }

    /// Ask the mint what it supports. Reachability is proven by the same call,
    /// so there is no separate ping.
    async fn probe(wallet: &Wallet) -> Result<MintCapabilities> {
        let info = wallet
            .fetch_mint_info()
            .await
            .map_err(|e| anyhow!("CashuMintUnreachable: {e}"))?
            .ok_or_else(|| anyhow!("CashuMintUnreachable: mint published no info"))?;

        // `Refresh`: the mint was just reached for its info, so ask it rather
        // than trust a keyset list the store kept from an earlier session. cdk
        // returns every keyset of the wallet's unit, rotated ones included, so
        // `active` has to be checked here.
        let keysets = wallet
            .keysets(KeysetLoadPolicy::Refresh)
            .await
            .map_err(|e| anyhow!("CashuMintUnreachable: {e}"))?;

        let melt = bolt11_sat_melt(&info.nuts.nut05);
        let mint = bolt11_sat_mint(&info.nuts.nut04);
        Ok(MintCapabilities {
            nut07_state_check: info.nuts.nut07.supported,
            nut11_p2pk: info.nuts.nut11.supported,
            nut12_dleq: info.nuts.nut12.supported,
            has_sat_keyset: keysets
                .iter()
                .any(|k| k.unit == CurrencyUnit::Sat && k.active == Some(true)),
            nut05_bolt11: melt.is_some(),
            melt_min_sats: melt.as_ref().and_then(|m| m.min_amount).map(u64::from),
            melt_max_sats: melt.as_ref().and_then(|m| m.max_amount).map(u64::from),
            nut04_bolt11: mint.is_some(),
            mint_min_sats: mint.as_ref().and_then(|m| m.min_amount).map(u64::from),
            mint_max_sats: mint.as_ref().and_then(|m| m.max_amount).map(u64::from),
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
    ///
    /// Rotated keysets count: a token minted before a rotation is still ecash
    /// at this mint. That mirrors cdk's own (crate-private) `token_proofs`.
    pub(crate) async fn proofs_of(&self, token: &Token) -> Result<Vec<Proof>> {
        let keysets: Vec<KeySetInfo> = self
            .inner
            .keysets(KeysetLoadPolicy::default())
            .await
            .map_err(|e| anyhow!("CashuMintUnreachable: {e}"))?
            .into_iter()
            .map(|k| KeySetInfo {
                id: k.id,
                unit: k.unit,
                active: k.active.unwrap_or(false),
                input_fee_ppk: k.input_fee_ppk,
                final_expiry: k.final_expiry,
            })
            .collect();
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
    /// (`wallet/receive/saga/mod.rs`, cdk 0.18.2), so a token whose proofs carry
    /// none is accepted on trust. That is the softer guarantee NUT-12 is a hard
    /// connect requirement to avoid — [`Wallet::verify_token_dleq`] rejects the
    /// missing proof instead of skipping it.
    ///
    /// **Errors** (stable markers): `CashuUnsupportedUnit` for a token in any
    /// unit but sats, `CashuTokenUnverified` when the token carries no usable
    /// DLEQ proof, `CashuReceiveFailed` for everything else (malformed, wrong
    /// mint, already spent).
    pub async fn receive_token(&self, encoded: &str) -> Result<u64> {
        let normalized = normalize_token(encoded);
        let token = parse_received_token(&normalized)?;

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

    /// An invoice for `amount_sats`: once it is paid, the mint issues that
    /// much ecash to this wallet — phase C3b-2.
    ///
    /// cdk stores the quote, with its NUT-20 key, before it returns
    /// (`add_mint_quote`), so a paid invoice is collected even if the app is
    /// killed before anyone asks again.
    ///
    /// **Errors** (stable markers): those of [`mint_gate`], and
    /// `CashuMintQuoteFailed` when the mint does not give one.
    pub async fn mint_quote(&self, amount_sats: u64) -> Result<MintQuoteInfo> {
        mint_gate(&self.capabilities, amount_sats)?;
        let quote = self
            .inner
            .mint_quote(
                PaymentMethod::BOLT11,
                Some(Amount::from(amount_sats)),
                None,
                None,
            )
            .await
            .map_err(|e| match e {
                cdk::Error::AmountOutofLimitRange(..) => {
                    anyhow!("CashuMintAmountOutOfRange: {e}")
                }
                cdk::Error::UnsupportedPaymentMethod | cdk::Error::UnsupportedUnit => {
                    anyhow!("CashuMintUnsupported: {e}")
                }
                other => anyhow!("CashuMintQuoteFailed: {other}"),
            })?;
        Ok(MintQuoteInfo {
            quote_id: quote.id,
            invoice: quote.request,
            amount_sats,
            expires_at: quote.expiry,
        })
    }

    /// Ask the mint about the quote `quote_id` and, once it is paid, mint its
    /// ecash into the wallet. What the invoice screen polls.
    ///
    /// Holds this mint's issue mark ([`in_flight`]) for the check and the
    /// mint: cdk's check resumes the quote's issue saga, and would destroy a
    /// mint still running elsewhere. While someone else holds it this round
    /// is skipped, as `Waiting`, with nothing asked. A mint that does not
    /// answer, or a mint call that fails, is `Waiting` too: the next round,
    /// or the next start, tries again.
    ///
    /// **Errors** (stable markers): `CashuMintQuoteUnknown` for a quote this
    /// wallet does not hold at its mint; `CashuMintQuoteFailed` when the store
    /// cannot be read, or the mint has issued a quote whose ecash the wallet
    /// does not hold.
    pub async fn claim_mint_quote(&self, quote_id: &str) -> Result<MintQuoteStatus> {
        let Some(_issuing) = in_flight::try_begin_issue(&self.inner.mint_url) else {
            return Ok(MintQuoteStatus::Waiting);
        };
        let stored = self
            .inner
            .localstore
            .get_mint_quote(quote_id)
            .await
            .map_err(|e| anyhow!("CashuMintQuoteFailed: {e}"))?
            .filter(|quote| quote.mint_url == self.inner.mint_url)
            .ok_or_else(|| anyhow!("CashuMintQuoteUnknown"))?;
        if stored.amount_issued > Amount::ZERO {
            return Ok(mint_quote_status(&stored, unix_now().as_secs()));
        }

        let checked = match self.inner.check_mint_quote_status(quote_id).await {
            Ok(quote) => quote,
            Err(e) => {
                log::info!("[cashu] mint quote not checked this round: {e}");
                return Ok(MintQuoteStatus::Waiting);
            }
        };
        if checked.amount_mintable() > Amount::ZERO {
            return match self
                .inner
                .mint(quote_id, SplitTarget::default(), None)
                .await
            {
                Ok(proofs) => Ok(MintQuoteStatus::Issued {
                    amount_sats: proofs.iter().map(|p| u64::from(p.amount)).sum(),
                }),
                Err(e) => {
                    log::warn!("[cashu] minting a paid quote failed, retried next round: {e}");
                    Ok(MintQuoteStatus::Waiting)
                }
            };
        }
        if checked.state == cdk::nuts::MintQuoteState::Issued
            && checked.amount_issued == Amount::ZERO
        {
            bail!("CashuMintQuoteFailed: issued at the mint, nothing held here");
        }
        let status = mint_quote_status(&checked, unix_now().as_secs());
        if status != MintQuoteStatus::Expired {
            return Ok(status);
        }
        // The device's clock says it ran out; only the mint's may. A phone set
        // ahead runs out early, and the user would be told to give up on an
        // invoice that can still be paid ([`mint_clock`]). A mint whose time
        // cannot be read leaves it waiting.
        Ok(match mint_clock::mint_now(&self.inner.mint_url).await {
            Some(mint_now) => mint_quote_status(&checked, mint_now),
            None => MintQuoteStatus::Waiting,
        })
    }

    /// This mint's [`PendingQuotes`], from the store alone.
    ///
    /// **Errors**: `CashuStoreUnavailable`.
    pub async fn pending_quotes(&self) -> Result<PendingQuotes> {
        let quotes = self
            .inner
            .localstore
            .get_unissued_mint_quotes()
            .await
            .map_err(|e| anyhow!("CashuStoreUnavailable: {e}"))?;
        Ok(pending_quotes_of(
            quotes,
            Some(&self.inner.mint_url),
            unix_now().as_secs(),
        ))
    }

    /// Mint `amount_sats` straight from the mint, for tests only.
    ///
    /// Against a `FakeWallet` backend (which is what a local nutshell runs) the
    /// quote settles itself, so this funds a wallet with no Lightning node and
    /// no manual step. Without it the integration tests below assert
    /// "fund the wallet first" and can never pass, which makes them
    /// documentation rather than verification.
    ///
    /// "Settles itself" is not "settles at once": nutshell marks the quote paid
    /// before it answers, but a `cdk-mintd` fake backend (testnut) pays it
    /// about two seconds later, and minting before that fails. So this waits
    /// for the quote to read `Paid` before minting.
    #[cfg(test)]
    pub(crate) async fn mint_for_test(&self, amount_sats: u64) -> Result<u64> {
        use cdk::nuts::MintQuoteState;

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

        let mut attempts = 0;
        while self
            .inner
            .check_mint_quote_status(&quote.id)
            .await
            .map_err(|e| anyhow!("CashuMintQuoteFailed: {e}"))?
            .state
            != MintQuoteState::Paid
        {
            attempts += 1;
            if attempts == 20 {
                bail!(
                    "CashuMintFailed: quote {} still unpaid after 10 s (is the mint in FakeWallet mode?)",
                    quote.id
                );
            }
            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        }

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
    /// cdk 0.18.2) decide that:
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

    /// Ask the mint how the melts still in flight ended, and settle them: a
    /// paid one keeps its proofs spent and stores its change, a failed one
    /// returns its proofs to the balance. One the mint still calls pending is
    /// left as it is, for the next call.
    ///
    /// Skipped while a melt holds the mint ([`in_flight`]), quoting
    /// included: cdk would resume that melt's saga too, and roll it back on a
    /// mint that has not processed its request yet. The next sync settles it.
    ///
    /// **Errors** (stable markers): `CashuStateCheckFailed` when the store
    /// cannot be read. A single melt the mint does not answer for is logged by
    /// cdk and skipped, not an error.
    pub async fn finalize_pending_melts(&self) -> Result<()> {
        if in_flight::melt_in_flight(&self.inner.mint_url) {
            log::info!(
                "[cashu] a melt is in flight at this mint: pending melts wait for the next sync"
            );
            return Ok(());
        }
        let finalized = self
            .inner
            .finalize_pending_melts()
            .await
            .map_err(|e| anyhow!("CashuStateCheckFailed: {e}"))?;
        if !finalized.is_empty() {
            log::info!("[cashu] settled {} pending melt(s)", finalized.len());
        }
        Ok(())
    }

    /// Quote paying `invoice` from the wallet, reserving nothing.
    ///
    /// The fees are only known once proofs are chosen — cdk computes the
    /// input fee, and whether a swap is needed, in `prepare_melt` alone — so
    /// the melt is prepared and then cancelled at once. A prepared melt
    /// borrows the wallet and cannot outlive this call, and the user reading
    /// the confirmation must not hold any of the balance hostage.
    ///
    /// **Errors** (stable markers): `CashuMeltInFlight` while another melt or
    /// quote holds this mint, those of [`melt_invoice`],
    /// `CashuMeltUnsupported` when the mint does not melt to `bolt11`,
    /// `CashuMeltAmountOutOfRange` outside the mint's limits,
    /// `CashuMeltQuoteFailed` when the mint does not quote or the wallet
    /// cannot price or release the quote, `CashuMeltInsufficientFunds`,
    /// `CashuMeltQuoteExpired`, `CashuMeltFailed` (amount overflow).
    pub async fn melt_quote(&self, invoice: &str) -> Result<MeltQuoteInfo> {
        // Taken first, and held while the quote is priced: pricing reserves
        // proofs for a moment, and a connect's recovery would roll that back.
        // A second payment is refused before its invoice is even read.
        let _in_flight = in_flight::try_begin_melt(&self.inner.mint_url)?;
        let (invoice, amount_sats) = melt_invoice(invoice, unix_now())?;
        melt_gate(&self.capabilities, amount_sats)?;

        let quote = self
            .inner
            .melt_quote(PaymentMethod::BOLT11, invoice, None, None)
            .await
            .map_err(|e| match e {
                cdk::Error::AmountOutofLimitRange(..) => {
                    anyhow!("CashuMeltAmountOutOfRange: {e}")
                }
                cdk::Error::UnsupportedPaymentMethod => anyhow!("CashuMeltUnsupported: {e}"),
                other => anyhow!("CashuMeltQuoteFailed: {other}"),
            })?;

        let prepared = self
            .inner
            .prepare_melt(&quote.id, HashMap::new())
            .await
            // Nothing is being paid yet: not "the payment did not go through".
            .map_err(|e| match e {
                cdk::Error::InsufficientFunds | cdk::Error::ExpiredQuote(..) => {
                    prepare_melt_error(e)
                }
                other => anyhow!("CashuMeltQuoteFailed: {other}"),
            })?;
        let info = quote_info(&prepared);
        // A quote not released is not offered: its saga still holds the quote
        // (`reserve_melt_quote`, `wallet/melt/saga/mod.rs`) as well as the
        // proofs, so paying it would fail. Both stay reserved until the next
        // connect's recovery rolls the saga back.
        prepared
            .cancel()
            .await
            .map_err(|e| anyhow!("CashuMeltQuoteFailed: releasing the quote failed: {e}"))?;
        let info = info?;
        log::info!(
            "[cashu] melt quoted: {} sat, up to {} sat in total",
            info.amount_sats,
            info.max_total_sats
        );
        Ok(info)
    }

    /// Pay the quote `quote_id`, provided it costs no more than
    /// `max_total_sats` — the total the user confirmed.
    ///
    /// Prepared again rather than kept from [`Self::melt_quote`]: the fees
    /// are re-read from the proofs the wallet holds now, and a quote that
    /// expired or now costs more is cancelled before anything leaves.
    ///
    /// Refused, too, while another melt or quote holds this mint
    /// ([`in_flight`]); this one holds it until it returns.
    ///
    /// **Errors** (stable markers): `CashuMeltInFlight`,
    /// `CashuMeltQuoteExpired`, `CashuMeltFeeChanged` (both refused before
    /// paying, nothing spent), `CashuMeltInsufficientFunds`, `CashuMeltFailed`
    /// (nothing was paid and the proofs are back — a quote no longer unpaid
    /// is refused so as well, before anything is sent). A payment the mint has not settled — or could
    /// not be asked about — after an error is `Pending`, not an error: see
    /// [`confirm_error_outcome`].
    pub async fn melt(&self, quote_id: &str, max_total_sats: u64) -> Result<MeltOutcomeInfo> {
        // Held to the last line, even past the point the caller stops
        // waiting: until this returns the request may still be on its way to
        // the mint, and the mint may still pay it.
        let _in_flight = in_flight::try_begin_melt(&self.inner.mint_url)?;
        let prepared = self
            .inner
            .prepare_melt(quote_id, HashMap::new())
            .await
            .map_err(prepare_melt_error)?;

        if let Some(refusal) = melt_refusal(
            prepared.quote(),
            u64::from(prepared.total_fee()),
            &self.inner.mint_url,
            unix_now().as_secs(),
            max_total_sats,
        ) {
            if let Err(e) = prepared.cancel().await {
                log::warn!("[cashu] releasing the refused melt failed: {e}");
            }
            return Err(refusal);
        }

        // Read before `confirm` consumes the handle: cdk's `fee_paid` counts
        // the melt's inputs only, and the swap that made them was paid too.
        let swap_fee = u64::from(prepared.swap_fee());
        let operation_id = prepared.operation_id();
        let localstore = self.inner.localstore.as_ref();
        // From before the request, so the whole payment answers within
        // [`MELT_WAIT`] — the time the request took counts against it.
        let deadline = tokio::time::Instant::now() + MELT_WAIT;

        let finalized = match prepared.confirm_prefer_async().await {
            Ok(MeltOutcome::Paid(finalized)) => finalized,
            // The mint took the payment and answered before routing it — what
            // a mint does with `Prefer: respond-async` (cdk-mintd always does)
            // however fast the payment then settles. Waiting a while turns the
            // common case into its real result: proofs settled, change stored,
            // the fee known. Past the deadline the handle is dropped, which cdk
            // allows ("can be awaited or dropped"): the saga is recorded as
            // in flight and `finalize_pending_melts` settles it at the next
            // sync or connect.
            Ok(MeltOutcome::Pending(pending)) => {
                match tokio::time::timeout_at(deadline, pending.into_future()).await {
                    Ok(Ok(finalized)) => finalized,
                    Ok(Err(e)) => return after_confirm_error(localstore, operation_id, e).await,
                    Err(_) => {
                        log::info!("[cashu] melt still pending {}s in", MELT_WAIT.as_secs());
                        return Ok(MeltOutcomeInfo::Pending);
                    }
                }
            }
            Err(e) => return after_confirm_error(localstore, operation_id, e).await,
        };

        let outcome = melt_outcome(
            finalized.state(),
            u64::from(finalized.amount()),
            u64::from(finalized.fee_paid()),
            swap_fee,
        )?;
        match &outcome {
            MeltOutcomeInfo::Paid {
                amount_sats,
                fee_paid_sats,
            } => log::info!("[cashu] melted {amount_sats} sat ({fee_paid_sats} sat in fees)"),
            MeltOutcomeInfo::Pending => log::info!("[cashu] melt pending"),
        }
        Ok(outcome)
    }
}

/// How long [`CashuWallet::melt`] gives a payment, counted from before its
/// request, before reporting one the mint answered as pending so. Long enough
/// for an ordinary Lightning payment, which settles in seconds; short enough
/// that a held one (a hold invoice, a stuck route) does not keep the
/// confirmation spinning.
///
/// It cannot bound a request the mint holds open, ignoring `respond-async`:
/// cdk sets no timeout on it, and dropping it mid-flight could leave a swap
/// half recorded. The payment dialog stops waiting a little after this
/// instead (`_meltDialogWait` in `cashu_wallet_screen.dart`) — keep it above.
const MELT_WAIT: Duration = Duration::from_secs(30);

/// What an error from confirming the melt `operation_id` means, read against
/// the proof store.
///
/// By then cdk has run `recover_failed_melt_confirm` (`wallet/melt/mod.rs`,
/// cdk 0.18.2), which returns the original error whether it rolled the melt
/// back or left it unresolved. Whether the melt's saga is still on record
/// tells the two apart; see [`confirm_error_outcome`]. A store that cannot be
/// read proves nothing, so it counts as still recorded.
async fn after_confirm_error(
    localstore: &(dyn WalletDatabase<cdk_database::Error> + Send + Sync),
    operation_id: Uuid,
    e: cdk::Error,
) -> Result<MeltOutcomeInfo> {
    let still_recorded = localstore
        .get_saga(&operation_id)
        .await
        .map_or(true, |saga| saga.is_some());
    confirm_error_outcome(still_recorded, e)
}

/// What an error from confirming a melt means for the user, given whether its
/// saga is `still_recorded` once cdk's recovery has run.
///
/// A rolled-back melt has no saga: cdk deletes it with the reservation
/// (`compensate_melt`, `wallet/melt/saga/resume.rs`). One still recorded was
/// sent and the mint did not say how it ended — or could not be asked — so the
/// payment may yet settle: [`MeltOutcomeInfo::Pending`], whatever the error
/// said. Telling the user it failed would invite paying a second invoice.
///
/// **Errors**, for a melt rolled back only: `CashuMeltQuoteExpired` when the
/// mint refused the quote as expired, `CashuMeltFailed` otherwise.
fn confirm_error_outcome(still_recorded: bool, e: cdk::Error) -> Result<MeltOutcomeInfo> {
    if still_recorded {
        log::info!("[cashu] melt unresolved after a confirm error: {e}");
        return Ok(MeltOutcomeInfo::Pending);
    }
    match e {
        cdk::Error::ExpiredQuote(..) => bail!("CashuMeltQuoteExpired"),
        e => bail!("CashuMeltFailed: {e}"),
    }
}

/// What a finalized melt means for the user. `fee_paid` is cdk's, which counts
/// the melt's inputs only; `swap_fee` is the swap that made them, paid too.
///
/// **Errors**: `CashuMeltFailed` for a payment the mint reports failed or
/// unpaid — cdk has already returned its proofs.
fn melt_outcome(
    state: MeltQuoteState,
    amount_sats: u64,
    fee_paid: u64,
    swap_fee: u64,
) -> Result<MeltOutcomeInfo> {
    match state {
        MeltQuoteState::Paid => Ok(MeltOutcomeInfo::Paid {
            amount_sats,
            fee_paid_sats: fee_paid.saturating_add(swap_fee),
        }),
        MeltQuoteState::Pending | MeltQuoteState::Unknown => Ok(MeltOutcomeInfo::Pending),
        other => bail!("CashuMeltFailed: payment {other}"),
    }
}

/// Whether a melt quote was taken at `wallet_mint`. A quote that records no
/// mint is not refused for that alone: cdk fills the field for every quote
/// it takes (`wallet/melt/bolt11.rs`), so only an older store lacks it.
fn quote_is_for(quote_mint: Option<&MintUrl>, wallet_mint: &MintUrl) -> bool {
    quote_mint.is_none_or(|mint| mint == wallet_mint)
}

/// Why [`CashuWallet::melt`] must not pay the prepared `quote`, if it must
/// not: `None` pays it. `input_fee_sats` is the prepared melt's
/// [`PreparedMelt::total_fee`], `max_total_sats` the total the user confirmed.
///
/// A function of plain values so it can be checked without a mint: a
/// [`PreparedMelt`] borrows the wallet and only a mint's quote makes one.
///
/// **Errors** returned (stable markers): `CashuMeltFailed` for a quote taken
/// at another mint or no longer unpaid, `CashuMeltQuoteExpired`,
/// `CashuMeltFeeChanged`, and `CashuMeltFailed` again when the total
/// overflows.
fn melt_refusal(
    quote: &cdk::wallet::MeltQuote,
    input_fee_sats: u64,
    wallet_mint: &MintUrl,
    now_secs: u64,
    max_total_sats: u64,
) -> Option<anyhow::Error> {
    // cdk loads the quote by id from a store shared by every mint and does
    // not check whose it is (`initialize_melt` in `wallet/melt/saga/mod.rs`,
    // cdk 0.18.2): a quote taken at another mint would have this mint's
    // proofs sent to pay it.
    if !quote_is_for(quote.mint_url.as_ref(), wallet_mint) {
        return Some(anyhow!(
            "CashuMeltFailed: the quote belongs to another mint"
        ));
    }
    // cdk checks only the expiry (`initialize_melt`), and a quote that
    // finalized as paid has had its reservation released, so it prepares
    // again. If the mint then refuses the melt with anything but
    // `RequestAlreadyPaid`, cdk reads the quote paid and marks the *new*
    // proofs spent (`execute_async`, `wallet/melt/saga/mod.rs`, cdk 0.18.2).
    if quote.state != MeltQuoteState::Unpaid {
        return Some(anyhow!("CashuMeltFailed: the quote is no longer unpaid"));
    }
    if quote.expiry <= now_secs {
        return Some(anyhow!("CashuMeltQuoteExpired"));
    }
    match quote_info_of(quote, input_fee_sats) {
        Ok(info) if info.max_total_sats > max_total_sats => Some(anyhow!(
            "CashuMeltFeeChanged: {} sat over {max_total_sats} sat confirmed",
            info.max_total_sats
        )),
        Ok(_) => None,
        Err(e) => Some(e),
    }
}

/// [`MeltQuoteInfo`] of a prepared melt.
///
/// cdk 0.18.2 (`wallet/melt/saga/mod.rs`): the proofs are chosen to cover
/// `amount + fee_reserve`, and the input fee, plus the swap fee when they must
/// be swapped to fit, comes on top — [`PreparedMelt::total_fee`]. Only
/// [`PreparedMelt::amount`] is not what its name may suggest: it is the
/// quote's amount, not what the proofs add up to.
fn quote_info(prepared: &PreparedMelt<'_>) -> Result<MeltQuoteInfo> {
    quote_info_of(prepared.quote(), u64::from(prepared.total_fee()))
}

/// [`quote_info`] from the quote and the prepared melt's input fee.
fn quote_info_of(quote: &cdk::wallet::MeltQuote, input_fee_sats: u64) -> Result<MeltQuoteInfo> {
    let amount_sats = u64::from(quote.amount);
    let fee_reserve_sats = u64::from(quote.fee_reserve);
    let max_total_sats = melt_max_total(amount_sats, fee_reserve_sats, input_fee_sats)
        .ok_or_else(|| anyhow!("CashuMeltFailed: amount overflow"))?;
    Ok(MeltQuoteInfo {
        quote_id: quote.id.clone(),
        amount_sats,
        fee_reserve_sats,
        input_fee_sats,
        max_total_sats,
    })
}

/// An invoice to fund the wallet from Lightning, from [`CashuWallet::mint_quote`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MintQuoteInfo {
    /// The mint's quote, to check with [`CashuWallet::claim_mint_quote`].
    pub quote_id: String,
    /// The bolt11 invoice to pay.
    pub invoice: String,
    pub amount_sats: u64,
    /// Unix time after which the invoice can no longer be paid; 0 when the
    /// mint states none.
    pub expires_at: u64,
}

/// Where a mint quote stands, from [`CashuWallet::claim_mint_quote`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MintQuoteStatus {
    /// Not paid yet, or not known to be: the mint did not answer, or the
    /// quote was being checked elsewhere this round. Ask again.
    Waiting,
    /// The mint issued the quote's ecash to this wallet.
    Issued { amount_sats: u64 },
    /// Past its expiry, and still unpaid at the mint.
    Expired,
}

/// How long after its expiry a quote still unpaid at the mint is called
/// [`MintQuoteStatus::Expired`]: a payment that left just before the expiry
/// can take that long to show as paid. Past it, the collector still picks the
/// quote up if it was paid after all.
const MINT_QUOTE_EXPIRY_GRACE_SECS: u64 = 120;

/// The most a melt can take from the balance: the invoice, the routing fee
/// reserve and the mint's input fees. Change from an unspent reserve only
/// ever lowers it.
pub(crate) fn melt_max_total(amount: u64, fee_reserve: u64, input_fee: u64) -> Option<u64> {
    amount.checked_add(fee_reserve)?.checked_add(input_fee)
}

fn prepare_melt_error(e: cdk::Error) -> anyhow::Error {
    match e {
        cdk::Error::InsufficientFunds => anyhow!("CashuMeltInsufficientFunds"),
        cdk::Error::ExpiredQuote(..) => anyhow!("CashuMeltQuoteExpired"),
        other => anyhow!("CashuMeltFailed: {other}"),
    }
}

/// Refuse, from what the mint advertised at connect, a melt it will not do —
/// before it is asked for a quote.
///
/// **Errors** (stable markers): `CashuMeltUnsupported` when the mint does not
/// melt `sat` to `bolt11`, `CashuMeltAmountOutOfRange` outside its NUT-05
/// limits, where it states any.
fn melt_gate(capabilities: &MintCapabilities, amount_sats: u64) -> Result<()> {
    if !capabilities.nut05_bolt11 {
        bail!("CashuMeltUnsupported");
    }
    let above_min = capabilities
        .melt_min_sats
        .is_none_or(|min| amount_sats >= min);
    let below_max = capabilities
        .melt_max_sats
        .is_none_or(|max| amount_sats <= max);
    if !(above_min && below_max) {
        bail!("CashuMeltAmountOutOfRange: {amount_sats} sat");
    }
    Ok(())
}

/// Refuse, from what the mint advertised at connect, an invoice it will not
/// issue — before it is asked for one.
///
/// **Errors** (stable markers): `CashuMintUnsupported` when the mint does not
/// mint `sat` against `bolt11`, `CashuMintAmountOutOfRange` for zero or
/// outside its NUT-04 limits, where it states any.
fn mint_gate(capabilities: &MintCapabilities, amount_sats: u64) -> Result<()> {
    if !capabilities.nut04_bolt11 {
        bail!("CashuMintUnsupported");
    }
    let above_min = capabilities
        .mint_min_sats
        .is_none_or(|min| amount_sats >= min);
    let below_max = capabilities
        .mint_max_sats
        .is_none_or(|max| amount_sats <= max);
    if amount_sats == 0 || !(above_min && below_max) {
        bail!("CashuMintAmountOutOfRange: {amount_sats} sat");
    }
    Ok(())
}

/// What a quote the mint has just been asked about means, once nothing is
/// left to mint from it. `now` is unix time.
///
/// `Issued` reads `amount_issued`, which cdk takes from the mint's answer as
/// well as from its own mints (`apply_mint_quote_response`, cdk 0.18.1): the
/// mint's word that it issued, which only this wallet's NUT-20 key can ask
/// for. A quote the mint calls unpaid is `Expired` only once its expiry is
/// [`MINT_QUOTE_EXPIRY_GRACE_SECS`] behind; an expiry of 0 means none.
fn mint_quote_status(quote: &cdk::wallet::MintQuote, now: u64) -> MintQuoteStatus {
    use cdk::nuts::MintQuoteState;

    if quote.amount_issued > Amount::ZERO {
        return MintQuoteStatus::Issued {
            amount_sats: u64::from(quote.amount_issued),
        };
    }
    let expired = quote.expiry != 0
        && now >= quote.expiry.saturating_add(MINT_QUOTE_EXPIRY_GRACE_SECS);
    if quote.state == MintQuoteState::Unpaid && expired {
        MintQuoteStatus::Expired
    } else {
        MintQuoteStatus::Waiting
    }
}

fn unix_now() -> Duration {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
}

/// The invoice the wallet will pay, and its amount in sats, checked before
/// any mint is asked.
///
/// The invoice is handed on lower-cased, with any `lightning:` prefix and
/// whitespace removed (BOLT11 is case-insensitive). `now` is unix time.
///
/// An amount with a fraction of a sat is refused, not rounded: the wallet
/// holds whole sats, and cdk checks the mint's quote against the invoice's
/// msat amount *floored* to sats (`wallet/melt/bolt11.rs`, cdk 0.18.2), so
/// a mint that rounds up — as it must to pay the invoice in full — has its
/// quote refused anyway, after a round trip. Same rule as
/// [`crate::api::invoice::whole_sats`].
///
/// **Errors** (stable markers): `CashuInvalidInvoice` for anything that is
/// not a BOLT11 invoice, or one with a fraction of a sat;
/// `CashuInvoiceNoAmount` for an open-amount invoice; `CashuInvoiceExpired`.
pub(crate) fn melt_invoice(input: &str, now: Duration) -> Result<(String, u64)> {
    use lightning_invoice::Bolt11Invoice;

    let invoice = crate::api::invoice::normalize(input).to_ascii_lowercase();
    let parsed = Bolt11Invoice::from_str(&invoice).map_err(|_| anyhow!("CashuInvalidInvoice"))?;
    let msat = parsed
        .amount_milli_satoshis()
        .ok_or_else(|| anyhow!("CashuInvoiceNoAmount"))?;
    let sats = crate::api::invoice::whole_sats(Some(msat))
        .ok_or_else(|| anyhow!("CashuInvalidInvoice: {msat} msat is not whole sats"))?;
    if parsed.would_expire(now) {
        bail!("CashuInvoiceExpired");
    }
    Ok((invoice, sats))
}

/// The mint's NUT-05 settings for melting `sat` to a `bolt11` invoice, or
/// `None` when it does not offer that — melting `disabled` included, whatever
/// methods it still lists.
fn bolt11_sat_melt(nut05: &cdk::nuts::nut05::Settings) -> Option<MeltMethodSettings> {
    if nut05.disabled {
        return None;
    }
    nut05.get_settings(&CurrencyUnit::Sat, &PaymentMethod::BOLT11)
}

/// The mint's NUT-04 settings for minting against a `bolt11` invoice in
/// `sat`, or `None` when it does not offer that or has minting disabled.
fn bolt11_sat_mint(nut04: &cdk::nuts::nut04::Settings) -> Option<MintMethodSettings> {
    if nut04.disabled {
        return None;
    }
    nut04.get_settings(&CurrencyUnit::Sat, &PaymentMethod::BOLT11)
}

/// Collect every invoice of the proof store at `db_path` that was paid and
/// not yet minted, at every mint it holds quotes for — phase C3b-2. Returns
/// the sats minted.
///
/// The invoice is usually paid from another app, with this one closed or in
/// the background, so this runs at start, on resume and on Sync. With no
/// unissued quote in the store it returns without contacting any mint, and a
/// store that does not exist is not created.
///
/// cdk's `mint_unissued_quotes` keeps only its wallet's own mint, so a quote
/// at a mint the user has since left would wait until they return to it.
/// Each mint with quotes gets its own pass: on `active` for the mint it is
/// bound to, otherwise on a throwaway `cdk::Wallet` over the same seed and
/// store, never installed and never asked to `recover_incomplete_sagas` — a
/// recovery here could roll back an operation still running on the bound
/// wallet. Each pass holds that mint's issue mark ([`in_flight`]), and a
/// mint already held is skipped: whoever holds it is checking those quotes.
///
/// cdk does not filter by expiry, so a quote paid before it expired is
/// collected whenever this next runs. A mint that does not answer, or a
/// quote that fails, is logged and left for the next run: nothing here is
/// an error but a store that cannot be read.
///
/// A mint whose every quote is [`dormant`] — long expired, and never called
/// unpaid by the mint, which would have had it forgotten — is asked only
/// with [`Collect::Everything`], what Sync asks for. A mint gone for good
/// would otherwise be contacted at every start and resume, forever; its
/// quotes are kept all the same, with their NUT-20 keys, in case it returns.
///
/// **Errors** (stable markers): `CashuStoreUnavailable`.
pub async fn collect_pending_quotes(
    db_path: &str,
    seed: &zeroize::Zeroizing<[u8; 64]>,
    active: Option<&CashuWallet>,
    which: Collect,
) -> Result<u64> {
    if !std::path::Path::new(db_path).exists() {
        return Ok(0);
    }
    let store = Arc::new(
        WalletSqliteDatabase::new(db_path)
            .await
            .map_err(|e| anyhow!("CashuStoreUnavailable: {e}"))?,
    );
    let mut by_mint: std::collections::BTreeMap<MintUrl, Vec<cdk::wallet::MintQuote>> =
        Default::default();
    for quote in store
        .get_unissued_mint_quotes()
        .await
        .map_err(|e| anyhow!("CashuStoreUnavailable: {e}"))?
        .into_iter()
        .filter(|quote| quote.unit == CurrencyUnit::Sat)
    {
        by_mint.entry(quote.mint_url.clone()).or_default().push(quote);
    }

    let now = unix_now().as_secs();
    let mut minted = 0u64;
    for (mint, quotes) in by_mint {
        if which == Collect::Live && quotes.iter().all(|quote| dormant(quote, now)) {
            log::info!("[cashu] quotes at {mint} are long expired: left to Sync");
            continue;
        }
        let Some(_issuing) = in_flight::try_begin_issue(&mint) else {
            log::info!("[cashu] quotes at {mint} are being checked already: skipped");
            continue;
        };
        let throwaway;
        let wallet = match active.filter(|wallet| wallet.inner.mint_url == mint) {
            Some(bound) => &bound.inner,
            None => match Wallet::new(
                &mint.to_string(),
                CurrencyUnit::Sat,
                store.clone(),
                **seed,
                None,
            ) {
                Ok(wallet) => {
                    throwaway = wallet;
                    &throwaway
                }
                Err(e) => {
                    log::warn!("[cashu] no wallet to collect paid invoices at {mint}: {e}");
                    continue;
                }
            },
        };
        forget_expired_unpaid(wallet, &quotes, now).await;
        match wallet.mint_unissued_quotes().await {
            Ok(amount) if amount > Amount::ZERO => {
                log::info!("[cashu] collected {amount} sat of paid invoices at {mint}");
                minted = minted.saturating_add(u64::from(amount));
            }
            Ok(_) => {}
            Err(e) => log::warn!("[cashu] collecting paid invoices at {mint} failed: {e}"),
        }
    }
    Ok(minted)
}

/// Which quotes [`collect_pending_quotes`] asks their mint about.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Collect {
    /// Every mint with a quote that is not [`dormant`]: at start and resume.
    Live,
    /// Every mint with a quote, dormant or not: at Sync, which the user asks
    /// for.
    Everything,
}

/// The invoices of a proof store not minted yet, as the store knows them —
/// phase C3b-2. Read without contacting any mint.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PendingQuotes {
    /// Sats the store knows were paid and not issued yet: a mint that did not
    /// answer, or failed to mint, when it was last asked. Collected at the
    /// next start, resume or Sync.
    pub paid_sats: u64,
    /// Every invoice not minted yet, not forgotten and not [`dormant`], paid
    /// or not. One paid while the app was closed still reads unpaid here
    /// until its mint is asked, so this, not [`Self::paid_sats`], is what a
    /// lost store could cost.
    pub open: u32,
}

/// [`PendingQuotes`] over `quotes`, the store's unissued ones: in sats, at
/// `mint` or at every mint when `None`, leaving out the [`dormant`] ones at
/// `now` (unix time).
fn pending_quotes_of(
    quotes: Vec<cdk::wallet::MintQuote>,
    mint: Option<&MintUrl>,
    now: u64,
) -> PendingQuotes {
    quotes
        .into_iter()
        .filter(|quote| quote.unit == CurrencyUnit::Sat)
        .filter(|quote| mint.is_none_or(|mint| &quote.mint_url == mint))
        .filter(|quote| !dormant(quote, now))
        .fold(PendingQuotes::default(), |pending, quote| PendingQuotes {
            paid_sats: pending
                .paid_sats
                .saturating_add(u64::from(quote.amount_mintable())),
            open: pending.open.saturating_add(1),
        })
}

/// The [`PendingQuotes`] of the proof store at `db_path` — at `mint_url`, or
/// across every mint when `None` — without contacting any. A store that does
/// not exist holds none and is not created.
///
/// **Errors**: `CashuStoreUnavailable`, `InvalidMintUrl`.
pub async fn stored_pending_quotes(db_path: &str, mint_url: Option<&str>) -> Result<PendingQuotes> {
    if !std::path::Path::new(db_path).exists() {
        return Ok(PendingQuotes::default());
    }
    let mint_url = mint_url
        .map(MintUrl::from_str)
        .transpose()
        .map_err(|e| anyhow!("InvalidMintUrl: {e}"))?;
    let store = WalletSqliteDatabase::new(db_path)
        .await
        .map_err(|e| anyhow!("CashuStoreUnavailable: {e}"))?;
    let quotes = store
        .get_unissued_mint_quotes()
        .await
        .map_err(|e| anyhow!("CashuStoreUnavailable: {e}"))?;
    Ok(pending_quotes_of(
        quotes,
        mint_url.as_ref(),
        unix_now().as_secs(),
    ))
}

/// How long after its expiry a quote still unpaid at the mint is forgotten.
/// Not at once: a payment that left just before the expiry can take a while
/// to show as paid.
const MINT_QUOTE_FORGET_AFTER_SECS: u64 = 24 * 60 * 60;

/// How long after its expiry a quote the mint never called unpaid stops
/// being asked about at start and resume, and counted as open ([`dormant`]).
/// A mint that answers gets the quote forgotten a day after its expiry, so
/// only a mint that has not answered for this long gets here: down for good,
/// or one that purged the quote — cdk reads "unknown quote" as a generic
/// error (code 50000), so a mint saying it no longer has it cannot be told
/// from one failing.
const MINT_QUOTE_DORMANT_AFTER_SECS: u64 = 30 * 24 * 60 * 60;

/// Whether `quote` is unpaid as far as the store knows — nothing paid,
/// nothing issued, no operation on it — and expired `margin` seconds before
/// `now`, or longer. An expiry of 0 means none.
fn unpaid_since(quote: &cdk::wallet::MintQuote, now: u64, margin: u64) -> bool {
    quote.state == cdk::nuts::MintQuoteState::Unpaid
        && quote.amount_paid == Amount::ZERO
        && quote.amount_issued == Amount::ZERO
        && quote.used_by_operation.is_none()
        && quote.expiry != 0
        && now >= quote.expiry.saturating_add(margin)
}

/// Whether `quote` is one to forget once the mint confirms it unpaid:
/// expired over [`MINT_QUOTE_FORGET_AFTER_SECS`] before `now`, the mint's
/// time.
fn forgettable(quote: &cdk::wallet::MintQuote, now: u64) -> bool {
    unpaid_since(quote, now, MINT_QUOTE_FORGET_AFTER_SECS)
}

/// Whether `quote` is past being asked about but at Sync: expired over
/// [`MINT_QUOTE_DORMANT_AFTER_SECS`] before `now` and never called unpaid
/// since. Kept, and only set aside: the device's clock decides it, which at
/// worst leaves a quote to Sync early or asks about it a while longer.
fn dormant(quote: &cdk::wallet::MintQuote, now: u64) -> bool {
    unpaid_since(quote, now, MINT_QUOTE_DORMANT_AFTER_SECS)
}

/// Forget the `quotes` of `wallet`'s mint that expired unpaid long ago, so
/// they are not checked at every start — each check links the quotes to one
/// another at the mint. The caller holds that mint's issue mark.
///
/// Only once the mint has said so: a quote the store calls unpaid may have
/// been paid while the app was closed, and the store's word is not enough. A
/// mint that does not answer keeps the quote for the next run.
///
/// And only by the mint's clock ([`mint_clock`]): `now`, the device's, just
/// says whether any quote may be due. A phone set a day ahead would otherwise
/// forget an invoice still being paid, and a payment that lands afterwards
/// would have no quote to mint with. A mint whose time cannot be read keeps
/// every quote.
async fn forget_expired_unpaid(wallet: &Wallet, quotes: &[cdk::wallet::MintQuote], now: u64) {
    if !quotes.iter().any(|quote| forgettable(quote, now)) {
        return;
    }
    let Some(now) = mint_clock::mint_now(&wallet.mint_url).await else {
        log::info!("[cashu] expired mint quotes kept: the mint's clock is unknown");
        return;
    };
    for quote in quotes.iter().filter(|quote| forgettable(quote, now)) {
        match wallet.check_mint_quote_status(&quote.id).await {
            Ok(checked) if forgettable(&checked, now) => {
                match wallet.localstore.remove_mint_quote(&quote.id).await {
                    Ok(()) => log::info!("[cashu] forgot a mint quote that expired unpaid"),
                    Err(e) => log::warn!("[cashu] forgetting an expired mint quote failed: {e}"),
                }
            }
            Ok(_) => {}
            Err(e) => log::info!("[cashu] expired mint quote kept, not checked: {e}"),
        }
    }
}

/// The sats held in the proof store at `db_path` — at `mint_url`, or across
/// every mint when `None` — read without contacting any: what an identity
/// would leave behind if replaced, or what stays at a mint that is not
/// answering right now.
///
/// Every proof not known spent counts — unspent, reserved for a token nobody
/// redeemed yet, or in an operation in flight — since each is still the
/// owner's money. A store that does not exist holds nothing and is not
/// created.
///
/// **Errors**: `CashuStoreUnavailable`.
pub async fn stored_balance(db_path: &str, mint_url: Option<&str>) -> Result<u64> {
    use cdk::cdk_database::WalletDatabase;
    use cdk::nuts::State;

    if !std::path::Path::new(db_path).exists() {
        return Ok(0);
    }
    let mint_url = mint_url
        .map(cdk::mint_url::MintUrl::from_str)
        .transpose()
        .map_err(|e| anyhow!("InvalidMintUrl: {e}"))?;
    let store = WalletSqliteDatabase::new(db_path)
        .await
        .map_err(|e| anyhow!("CashuStoreUnavailable: {e}"))?;
    store
        .get_balance(
            mint_url,
            Some(CurrencyUnit::Sat),
            Some(vec![
                State::Unspent,
                State::Reserved,
                State::Pending,
                State::PendingSpent,
            ]),
        )
        .await
        .map_err(|e| anyhow!("CashuStoreUnavailable: {e}"))
}

/// The mint an encoded token was minted at, as the token names it.
///
/// Read without contacting any mint: it is how a wallet with no mint set yet
/// learns which one to bind to from the first token it receives.
///
/// **Errors**: `CashuReceiveFailed` when the token does not parse or names no
/// single mint, `CashuUnsupportedUnit` when it is not in sats.
pub fn token_mint_url(encoded: &str) -> Result<String> {
    let token = parse_received_token(encoded)?;
    let mint = token
        .mint_url()
        .map_err(|e| anyhow!("CashuReceiveFailed: {e}"))?;
    Ok(mint.to_string())
}

/// Refuse, from the token alone, a token this wallet cannot take.
///
/// Called before a wallet is opened for the token, so a dollar token is not
/// answered by whatever opening its mint happens to fail with.
///
/// **Errors**: those of [`parse_received_token`].
pub fn ensure_receivable(encoded: &str) -> Result<()> {
    parse_received_token(encoded).map(|_| ())
}

/// Decode a token handed to this wallet to receive.
///
/// The one place a received token is read, so every receive path refuses the
/// same tokens for the same reasons.
///
/// The unit is checked here, ahead of everything cdk does: the wallet holds
/// sats only (Mostro amounts are satoshis), and msat is no exception —
/// millisats become sats through a melt and a mint, never a swap. Left to cdk,
/// such a token fails its keyset lookup during the DLEQ check, which reads as
/// a token with no proof of the mint's signature. A v3 token naming no unit
/// passes, as it does in cdk: old sat tokens were written that way.
///
/// **Errors**: `CashuReceiveFailed` when the token does not parse,
/// `CashuUnsupportedUnit: <code>` when it names a unit other than sats — see
/// [`unsupported_unit_code`] for what `<code>` can be.
pub(crate) fn parse_received_token(encoded: &str) -> Result<Token> {
    let token = Token::from_str(&normalize_token(encoded))
        .map_err(|e| anyhow!("CashuReceiveFailed: {e}"))?;
    match token.unit() {
        None | Some(CurrencyUnit::Sat) => Ok(token),
        Some(other) => bail!("CashuUnsupportedUnit: {}", unsupported_unit_code(&other)),
    }
}

/// The unit a refused token is in, as a code Dart can name to the user.
///
/// `msat`, `usd` and `eur` as cdk spells them; a custom unit only when it is
/// three lowercase letters, the shape of a currency code (`gbp`); `other` for
/// everything else, `auth` included. A custom unit is whatever text the
/// token's maker chose, so anything longer never reaches the screen.
fn unsupported_unit_code(unit: &CurrencyUnit) -> String {
    match unit {
        CurrencyUnit::Msat => "msat".to_string(),
        CurrencyUnit::Usd => "usd".to_string(),
        CurrencyUnit::Eur => "eur".to_string(),
        CurrencyUnit::Custom(code)
            if code.len() == 3 && code.chars().all(|c| c.is_ascii_lowercase()) =>
        {
            code.to_string()
        }
        _ => "other".to_string(),
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
    /// MOSTRO_TEST_MINT_URL=http://localhost:3338 cargo test --lib cashu:: -- --ignored
    /// ```
    ///
    /// or, without Docker, at the public test mint, whose Lightning backend is
    /// fake too:
    ///
    /// ```text
    /// MOSTRO_TEST_MINT_URL=https://testnut.cashu.space cargo test --lib cashu:: -- --ignored
    /// ```
    ///
    /// `cashu::` keeps the run to these tests: an unfiltered `--ignored` also
    /// starts the NWC and regtest ones, which fail without their own setup.
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
            ..MintCapabilities::default()
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

    #[tokio::test]
    async fn a_missing_proof_store_holds_nothing_and_is_not_created() {
        // Asked of every identity before it is replaced, most of which never
        // opened a wallet: reading must not leave a file behind.
        let path = temp_db_path();

        assert_eq!(
            stored_balance(path.to_str().unwrap(), None).await.unwrap(),
            0
        );
        assert!(!path.exists());
    }

    #[tokio::test]
    async fn an_empty_proof_store_holds_nothing() {
        let path = temp_db_path();
        drop(
            WalletSqliteDatabase::new(path.to_str().unwrap())
                .await
                .unwrap(),
        );

        assert_eq!(
            stored_balance(path.to_str().unwrap(), None).await.unwrap(),
            0
        );
        assert_eq!(
            stored_balance(path.to_str().unwrap(), Some("https://mint.example.com"))
                .await
                .unwrap(),
            0
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn a_token_names_the_mint_it_was_minted_at() {
        // Arrange — a token needs no mint to be read, only to be redeemed.
        let mint = cdk::mint_url::MintUrl::from_str("https://mint.example.com").unwrap();
        let encoded = Token::new(mint, Vec::new(), None, CurrencyUnit::Sat).to_string();

        // Act / Assert — with or without the URI scheme a wallet may add.
        assert_eq!(
            token_mint_url(&encoded).unwrap(),
            "https://mint.example.com"
        );
        assert_eq!(
            token_mint_url(&format!("cashu:{encoded}")).unwrap(),
            "https://mint.example.com"
        );
        // Something that is not a token names no mint.
        assert!(token_mint_url("cashuBanything")
            .unwrap_err()
            .to_string()
            .contains("CashuReceiveFailed"));
    }

    #[test]
    fn a_token_in_another_unit_is_refused_as_such() {
        // Arrange — the wallet holds sats only, and msat is no exception:
        // turning millisats into sats is a melt and a mint, not a swap.
        let mint = cdk::mint_url::MintUrl::from_str("https://mint.example.com").unwrap();
        let token_in =
            |unit: CurrencyUnit| Token::new(mint.clone(), Vec::new(), None, unit).to_string();

        // Act / Assert — refused for its unit, before any mint is asked.
        // The code after the marker is what Dart names: the known units, a
        // currency-code-shaped custom one, and "other" for any text a token's
        // maker could have put there.
        for (unit, code) in [
            (CurrencyUnit::Msat, "msat"),
            (CurrencyUnit::Usd, "usd"),
            (CurrencyUnit::Eur, "eur"),
            (CurrencyUnit::custom("GBP"), "gbp"),
            (CurrencyUnit::Auth, "other"),
            (CurrencyUnit::custom("sats"), "other"),
            (CurrencyUnit::custom("usd now"), "other"),
            (CurrencyUnit::custom("u$d"), "other"),
        ] {
            let err = parse_received_token(&token_in(unit.clone())).unwrap_err();
            assert_eq!(
                err.to_string(),
                format!("CashuUnsupportedUnit: {code}"),
                "a {unit} token"
            );
        }

        // A sat token is read, and so is a v3 token that names no unit: cdk
        // takes those as sats, and old sat tokens were written that way.
        assert!(parse_received_token(&token_in(CurrencyUnit::Sat)).is_ok());
        let unitless = Token::TokenV3(cdk::nuts::TokenV3 {
            token: vec![cdk::nuts::nut00::token::TokenV3Token::new(
                mint.clone(),
                Vec::new(),
            )],
            memo: None,
            unit: None,
        });
        assert!(parse_received_token(&unitless.to_string()).is_ok());
    }

    #[test]
    fn a_mint_without_lightning_still_trades() {
        // Arrange — every escrow requirement, and neither NUT-04 nor NUT-05.
        let no_lightning = MintCapabilities {
            nut07_state_check: true,
            nut11_p2pk: true,
            nut12_dleq: true,
            has_sat_keyset: true,
            nut05_bolt11: false,
            melt_min_sats: None,
            melt_max_sats: None,
            nut04_bolt11: false,
            mint_min_sats: None,
            mint_max_sats: None,
        };

        // Assert — "to Lightning" and "via Lightning" are hidden, the mint is
        // not refused.
        assert!(no_lightning.is_usable());
        assert!(no_lightning.missing().is_empty());
    }

    #[test]
    fn melting_counts_only_for_bolt11_in_sats_and_not_disabled() {
        use cdk::nuts::nut05::Settings;

        let method = |method: PaymentMethod, unit: CurrencyUnit| MeltMethodSettings {
            method,
            unit,
            method_name: None,
            min_amount: Some(Amount::from(10)),
            max_amount: Some(Amount::from(500_000)),
            options: None,
        };
        let offering =
            |methods: Vec<MeltMethodSettings>, disabled: bool| Settings { methods, disabled };

        // bolt11 in sats: offered, with its limits.
        let melt = bolt11_sat_melt(&offering(
            vec![method(PaymentMethod::BOLT11, CurrencyUnit::Sat)],
            false,
        ))
        .expect("bolt11/sat is a melt this wallet can use");
        assert_eq!(melt.min_amount, Some(Amount::from(10)));
        assert_eq!(melt.max_amount, Some(Amount::from(500_000)));

        // The same method with melting disabled, another unit, another
        // method, or nothing listed: not offered.
        for (settings, why) in [
            (
                offering(vec![method(PaymentMethod::BOLT11, CurrencyUnit::Sat)], true),
                "disabled",
            ),
            (
                offering(
                    vec![method(PaymentMethod::BOLT11, CurrencyUnit::Usd)],
                    false,
                ),
                "usd only",
            ),
            (
                offering(
                    vec![method(PaymentMethod::BOLT12, CurrencyUnit::Sat)],
                    false,
                ),
                "bolt12 only",
            ),
            (offering(Vec::new(), false), "nothing listed"),
        ] {
            assert!(bolt11_sat_melt(&settings).is_none(), "{why}");
        }
    }

    #[test]
    fn minting_counts_only_for_bolt11_in_sats_and_not_disabled() {
        use cdk::nuts::nut04::Settings;

        let method = |method: PaymentMethod, unit: CurrencyUnit| MintMethodSettings {
            method,
            unit,
            method_name: None,
            min_amount: Some(Amount::from(1)),
            max_amount: Some(Amount::from(500_000)),
            options: None,
        };
        let offering =
            |methods: Vec<MintMethodSettings>, disabled: bool| Settings { methods, disabled };

        // bolt11 in sats: offered, with its limits.
        let mint = bolt11_sat_mint(&offering(
            vec![method(PaymentMethod::BOLT11, CurrencyUnit::Sat)],
            false,
        ))
        .expect("bolt11/sat is a mint this wallet can use");
        assert_eq!(mint.min_amount, Some(Amount::from(1)));
        assert_eq!(mint.max_amount, Some(Amount::from(500_000)));

        // The same method with minting disabled, another unit, another
        // method, or nothing listed: not offered.
        for (settings, why) in [
            (
                offering(vec![method(PaymentMethod::BOLT11, CurrencyUnit::Sat)], true),
                "disabled",
            ),
            (
                offering(
                    vec![method(PaymentMethod::BOLT11, CurrencyUnit::Usd)],
                    false,
                ),
                "usd only",
            ),
            (
                offering(
                    vec![method(PaymentMethod::BOLT12, CurrencyUnit::Sat)],
                    false,
                ),
                "bolt12 only",
            ),
            (offering(Vec::new(), false), "nothing listed"),
        ] {
            assert!(bolt11_sat_mint(&settings).is_none(), "{why}");
        }
    }

    /// BOLT11 spec test vector for 9 678 785.340 µBTC: 967 878 534 msat, a
    /// fraction of a sat on top of 967 878 sat.
    const FRACTIONAL_SATS: &str = "lnbc9678785340p1pwmna7lpp5gc3xfm08u9qy06djf8dfflhugl6p7lgza6dsjxq454gxhj9t7a0sd8dgfkx7cmtwd68yetpd5s9xar0wfjn5gpc8qhrsdfq24f5ggrxdaezqsnvda3kkum5wfjkzmfqf3jkgem9wgsyuctwdus9xgrcyqcjcgpzgfskx6eqf9hzqnteypzxz7fzypfhg6trddjhygrcyqezcgpzfysywmm5ypxxjemgw3hxjmn8yptk7untd9hxwg3q2d6xjcmtv4ezq7pqxgsxzmnyyqcjqmt0wfjjq6t5v4khxsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygsxqyjw5qcqp2rzjq0gxwkzc8w6323m55m4jyxcjwmy7stt9hwkwe2qxmy8zpsgg7jcuwz87fcqqeuqqqyqqqqlgqqqqn3qq9q9qrsgqrvgkpnmps664wgkp43l22qsgdw4ve24aca4nymnxddlnp8vh9v2sdxlu5ywdxefsfvm0fq3sesf08uf6q9a2ke0hc9j6z6wlxg5z5kqpu2v9wz";

    /// When `invoice` was issued, as the `now` of [`melt_invoice`]: the spec
    /// vectors expired years ago, and at their own timestamp they have not.
    fn issued_at(invoice: &str) -> Duration {
        lightning_invoice::Bolt11Invoice::from_str(invoice)
            .unwrap()
            .duration_since_epoch()
    }

    /// The stable marker of an error, without the detail after it.
    fn marker_of(e: anyhow::Error) -> String {
        e.to_string()
            .split(':')
            .next()
            .unwrap_or_default()
            .to_string()
    }

    #[test]
    fn an_invoice_to_melt_is_checked_before_any_mint_is_asked() {
        use crate::api::invoice::test_vectors::{COFFEE, DONATION};

        let marker = |input: &str, now: Duration| marker_of(melt_invoice(input, now).unwrap_err());

        // Not an invoice at all — nor a corrupted one, nor an address.
        for garbage in ["", "hello", "lnbc1short", "satoshi@example.com"] {
            assert_eq!(
                marker(garbage, unix_now()),
                "CashuInvalidInvoice",
                "{garbage:?}"
            );
        }
        let corrupted = COFFEE.replacen("lnbc2500u1", "lnbc2500u2", 1);
        assert_eq!(marker(&corrupted, unix_now()), "CashuInvalidInvoice");

        // Open-amount invoices are out of scope, expired ones cannot be paid,
        // and a fraction of a sat is refused rather than rounded.
        assert_eq!(
            marker(DONATION, issued_at(DONATION)),
            "CashuInvoiceNoAmount"
        );
        assert_eq!(marker(COFFEE, unix_now()), "CashuInvoiceExpired");
        assert_eq!(
            marker(FRACTIONAL_SATS, issued_at(FRACTIONAL_SATS)),
            "CashuInvalidInvoice"
        );

        // A live invoice: its amount in sats, and the invoice as cdk will get
        // it — scheme and whitespace stripped, lower-cased.
        let expected = (COFFEE.to_string(), 250_000);
        let now = issued_at(COFFEE);
        assert_eq!(melt_invoice(COFFEE, now).unwrap(), expected);
        let scanned = format!("  lightning:{}\n", COFFEE.to_ascii_uppercase());
        assert_eq!(melt_invoice(&scanned, now).unwrap(), expected);
        // Its expiry is 60 s: past it, it is expired.
        assert_eq!(
            marker(COFFEE, now + Duration::from_secs(61)),
            "CashuInvoiceExpired"
        );
    }

    #[test]
    fn the_confirmed_total_is_amount_plus_reserve_plus_input_fees() {
        // Pins the reading of cdk 0.18.2 behind it: `prepare_melt` selects
        // proofs for `amount + fee_reserve`, and `total_fee()` (input fee,
        // plus the swap's when one is needed) comes on top. This is the most
        // the balance can drop; nothing is left out of it.
        assert_eq!(melt_max_total(100, 2, 1), Some(103));
        assert_eq!(melt_max_total(100, 0, 0), Some(100));
        // Overflow is refused, never wrapped into a small total the user
        // would confirm.
        assert_eq!(melt_max_total(u64::MAX, 1, 0), None);
        assert_eq!(melt_max_total(u64::MAX - 1, 1, 1), None);
    }

    #[test]
    fn a_finalized_melt_reads_as_paid_pending_or_failed() {
        // Paid: the fee the user sees includes the swap that made the inputs.
        assert_eq!(
            melt_outcome(MeltQuoteState::Paid, 1_000, 1, 1).unwrap(),
            MeltOutcomeInfo::Paid {
                amount_sats: 1_000,
                fee_paid_sats: 2,
            }
        );
        // Still routing, or the mint cannot say: pending, settled at sync.
        for state in [MeltQuoteState::Pending, MeltQuoteState::Unknown] {
            assert_eq!(
                melt_outcome(state, 1_000, 0, 0).unwrap(),
                MeltOutcomeInfo::Pending,
                "{state}"
            );
        }
        // Not paid: a failure, never a success with nothing spent.
        for state in [MeltQuoteState::Unpaid, MeltQuoteState::Failed] {
            assert_eq!(
                marker_of(melt_outcome(state, 1_000, 0, 0).unwrap_err()),
                "CashuMeltFailed",
                "{state}"
            );
        }
    }

    #[tokio::test]
    async fn a_confirm_error_reads_pending_while_the_melt_is_still_recorded() {
        use cdk::wallet::types::{
            MeltOperationData, MeltSagaState, OperationData, WalletSaga, WalletSagaState,
        };

        // Arrange — a melt sent to the mint, its saga in `MeltRequested`: what
        // cdk leaves when the mint said pending or unknown, or could not be
        // asked, after a confirm error. A rolled-back melt has no saga.
        let path = temp_db_path();
        let store = WalletSqliteDatabase::new(path.to_str().unwrap())
            .await
            .unwrap();
        let in_flight = Uuid::new_v4();
        store
            .add_saga(WalletSaga::new(
                in_flight,
                WalletSagaState::Melt(MeltSagaState::MeltRequested),
                Amount::from(1_000),
                MintUrl::from_str("https://mint.example.com").unwrap(),
                CurrencyUnit::Sat,
                OperationData::Melt(MeltOperationData {
                    quote_id: "quote".to_string(),
                    amount: Amount::from(1_000),
                    fee_reserve: Amount::from(10),
                    counter_start: None,
                    counter_end: None,
                    change_amount: None,
                    metadata: HashMap::new(),
                    final_proof_ys: None,
                    change_blinded_messages: None,
                }),
            ))
            .await
            .unwrap();
        let rolled_back = Uuid::new_v4();
        let outcome = |operation_id: Uuid, e: cdk::Error| {
            let store = &store;
            async move { after_confirm_error(store, operation_id, e).await }
        };

        // Act / Assert — still recorded, the payment may yet settle: pending,
        // never "failed" or "nothing was paid", whatever the error said. A
        // timeout is the usual one: a connection lost after the request left.
        for e in [cdk::Error::Timeout, cdk::Error::ExpiredQuote(0, 0)] {
            let label = e.to_string();
            assert_eq!(
                outcome(in_flight, e).await.unwrap(),
                MeltOutcomeInfo::Pending,
                "{label}"
            );
        }

        // Rolled back, the proofs are back: the error stands.
        assert_eq!(
            marker_of(outcome(rolled_back, cdk::Error::Timeout).await.unwrap_err()),
            "CashuMeltFailed"
        );
        assert_eq!(
            marker_of(
                outcome(rolled_back, cdk::Error::ExpiredQuote(0, 0))
                    .await
                    .unwrap_err()
            ),
            "CashuMeltQuoteExpired"
        );

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn a_melt_quote_is_paid_only_at_the_mint_that_issued_it() {
        let ours = MintUrl::from_str("https://mint.example.com").unwrap();
        let theirs = MintUrl::from_str("https://other.example.com").unwrap();

        assert!(quote_is_for(Some(&ours), &ours));
        assert!(!quote_is_for(Some(&theirs), &ours));
        // A quote that names no mint is not refused for that alone.
        assert!(quote_is_for(None, &ours));
    }

    #[test]
    fn a_melt_is_gated_on_what_the_mint_advertised() {
        let melts = MintCapabilities {
            nut05_bolt11: true,
            ..MintCapabilities::default()
        };
        let gate = |caps: &MintCapabilities, sats: u64| melt_gate(caps, sats).map_err(marker_of);

        // No NUT-05: unsupported, whatever the amount.
        assert_eq!(
            gate(&MintCapabilities::default(), 100),
            Err("CashuMeltUnsupported".to_string())
        );

        // No stated limits: any amount goes to the mint.
        assert_eq!(gate(&melts, 1), Ok(()));
        assert_eq!(gate(&melts, u64::MAX), Ok(()));

        // Limits are inclusive at both ends.
        let limited = MintCapabilities {
            melt_min_sats: Some(10),
            melt_max_sats: Some(1_000),
            ..melts
        };
        assert_eq!(gate(&limited, 10), Ok(()));
        assert_eq!(gate(&limited, 1_000), Ok(()));
        for outside in [9, 1_001] {
            assert_eq!(
                gate(&limited, outside),
                Err("CashuMeltAmountOutOfRange".to_string()),
                "{outside} sat"
            );
        }
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
        let stripped: Vec<_> = receiver
            .proofs_of(&token)
            .await
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

    // ── A melt in flight, and a quote already paid (#864) ─────────────────────
    //
    // Driven through the wallet itself, not just the pieces: a wallet whose
    // keyset and proofs are seeded in its store prices a melt without asking
    // the mint (`KeysetLoadPolicy::CacheThenNetwork` reads the store first),
    // and its mint is a local listener that counts what reaches it. "Refused
    // before anything was sent" is then something a test can see.

    /// A mint's HTTP endpoint, as far as these tests need one: it counts the
    /// connections it gets and answers each with `body` as JSON, or hangs up
    /// when there is none. Each answer is dated, as every HTTP server's is,
    /// by the device's clock.
    struct StubMint {
        url: String,
        connections: Arc<std::sync::atomic::AtomicUsize>,
    }

    impl StubMint {
        async fn start(body: Option<String>) -> Self {
            Self::start_with_clock(body, Some(0)).await
        }

        /// [`StubMint::start`], with a clock `offset` seconds off the
        /// device's, or no `Date` on its answers when `None`.
        async fn start_with_clock(body: Option<String>, offset: Option<i64>) -> Self {
            use std::sync::atomic::{AtomicUsize, Ordering};
            use tokio::io::{AsyncReadExt, AsyncWriteExt};

            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let url = format!("http://{}", listener.local_addr().unwrap());
            // A port an earlier stub had must not lend this one its clock.
            mint_clock::forget_offset(&MintUrl::from_str(&url).unwrap());
            let connections = Arc::new(AtomicUsize::new(0));
            let counted = connections.clone();
            tokio::spawn(async move {
                while let Ok((mut socket, _)) = listener.accept().await {
                    counted.fetch_add(1, Ordering::SeqCst);
                    let body = body.clone();
                    tokio::spawn(async move {
                        // The request's headers, then the answer; nothing here
                        // reads a body, and every route gets the same one.
                        let mut request = Vec::new();
                        let mut chunk = [0u8; 4096];
                        while !request.windows(4).any(|w| w == b"\r\n\r\n") {
                            match socket.read(&mut chunk).await {
                                Ok(0) | Err(_) => return,
                                Ok(n) => request.extend_from_slice(&chunk[..n]),
                            }
                        }
                        if let Some(body) = body {
                            let date = offset
                                .map(|offset| {
                                    let now = unix_now().as_secs().saturating_add_signed(offset);
                                    format!("date: {}\r\n", mint_clock::http_date(now))
                                })
                                .unwrap_or_default();
                            let answer = format!(
                                "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\n\
                                 {date}content-length: {}\r\nconnection: close\r\n\r\n{body}",
                                body.len()
                            );
                            let _ = socket.write_all(answer.as_bytes()).await;
                        }
                    });
                }
            });
            Self { url, connections }
        }

        fn connections(&self) -> usize {
            self.connections.load(std::sync::atomic::Ordering::SeqCst)
        }
    }

    /// What every seeded wallet holds: one proof of exactly this much, so a
    /// melt of it needs no swap.
    const SEEDED_SATS: u64 = 64;

    /// A wallet at `mint_url` with one [`SEEDED_SATS`] proof under a keyset
    /// seeded in its store, and no fees anywhere.
    async fn seeded_wallet(mint_url: &str) -> CashuWallet {
        seeded_wallet_at(mint_url, &temp_db_path()).await
    }

    /// [`seeded_wallet`], with its store at `db_path`.
    async fn seeded_wallet_at(mint_url: &str, db_path: &std::path::Path) -> CashuWallet {
        use cdk::nuts::{Id, KeySet, Keys, SecretKey, State};
        use cdk::secret::Secret;
        use cdk::wallet::types::ProofInfo;
        use std::collections::BTreeMap;

        let store = WalletSqliteDatabase::new(db_path.to_str().unwrap())
            .await
            .unwrap();
        let mint = MintUrl::from_str(mint_url).unwrap();
        let keys = Keys::new(
            (0..8)
                .map(|bit| {
                    (
                        Amount::from(1u64 << bit),
                        SecretKey::generate().public_key(),
                    )
                })
                .collect::<BTreeMap<_, _>>(),
        );
        let id = Id::v1_from_keys(&keys);
        store.add_mint(mint.clone(), None).await.unwrap();
        store
            .add_mint_keysets(
                mint.clone(),
                vec![KeySetInfo {
                    id,
                    unit: CurrencyUnit::Sat,
                    active: true,
                    input_fee_ppk: 0,
                    final_expiry: None,
                }],
            )
            .await
            .unwrap();
        store
            .add_keys(KeySet {
                id,
                unit: CurrencyUnit::Sat,
                active: Some(true),
                keys,
                input_fee_ppk: 0,
                final_expiry: None,
            })
            .await
            .unwrap();
        let proof = Proof::new(
            Amount::from(SEEDED_SATS),
            id,
            Secret::generate(),
            SecretKey::generate().public_key(),
        );
        store
            .update_proofs(
                vec![ProofInfo::new(proof, mint, State::Unspent, CurrencyUnit::Sat).unwrap()],
                vec![],
            )
            .await
            .unwrap();

        let inner = Wallet::new(
            mint_url,
            CurrencyUnit::Sat,
            Arc::new(store),
            *unique_seed(),
            None,
        )
        .unwrap();
        CashuWallet {
            inner,
            mint_url: mint_url.to_string(),
            capabilities: MintCapabilities {
                nut05_bolt11: true,
                ..MintCapabilities::default()
            },
        }
    }

    /// A melt quote for all of [`SEEDED_SATS`], valid for an hour.
    fn melt_quote_for(id: &str, mint: &MintUrl, state: MeltQuoteState) -> cdk::wallet::MeltQuote {
        cdk::wallet::MeltQuote {
            id: id.to_string(),
            mint_url: Some(mint.clone()),
            unit: CurrencyUnit::Sat,
            amount: Amount::from(SEEDED_SATS),
            request: "lnbcrt640n1placeholder".to_string(),
            fee_reserve: Amount::ZERO,
            state,
            expiry: unix_now().as_secs() + 3_600,
            payment_proof: None,
            estimated_blocks: None,
            fee_index: None,
            payment_method: PaymentMethod::BOLT11,
            used_by_operation: None,
            version: 0,
        }
    }

    async fn unspent_sats(wallet: &CashuWallet) -> u64 {
        wallet
            .inner
            .localstore
            .get_proofs(
                Some(wallet.inner.mint_url.clone()),
                Some(CurrencyUnit::Sat),
                Some(vec![cdk::nuts::State::Unspent]),
                None,
            )
            .await
            .unwrap()
            .iter()
            .map(|p| u64::from(p.proof.amount))
            .sum()
    }

    /// Record in `wallet`'s store what an ongoing melt of quote `quote_id`
    /// looks like once its request has left: the saga in `MeltRequested`, the
    /// quote and the proof reserved by it, the proof pending. Returns the
    /// saga's id.
    async fn record_melt_in_flight(wallet: &CashuWallet, quote_id: &str) -> Uuid {
        use cdk::nuts::State;
        use cdk::wallet::types::{
            MeltOperationData, MeltSagaState, OperationData, WalletSaga, WalletSagaState,
        };

        let store = &wallet.inner.localstore;
        let mint = wallet.inner.mint_url.clone();
        let saga = Uuid::new_v4();
        store
            .add_melt_quote(melt_quote_for(quote_id, &mint, MeltQuoteState::Unpaid))
            .await
            .unwrap();
        store.reserve_melt_quote(quote_id, &saga).await.unwrap();
        let mut proof = store
            .get_proofs(Some(mint.clone()), None, None, None)
            .await
            .unwrap()
            .pop()
            .unwrap();
        proof.state = State::Pending;
        proof.used_by_operation = Some(saga);
        let y = proof.y;
        store.update_proofs(vec![proof], vec![]).await.unwrap();
        store
            .add_saga(WalletSaga::new(
                saga,
                WalletSagaState::Melt(MeltSagaState::MeltRequested),
                Amount::from(SEEDED_SATS),
                mint,
                CurrencyUnit::Sat,
                OperationData::Melt(MeltOperationData {
                    quote_id: quote_id.to_string(),
                    amount: Amount::from(SEEDED_SATS),
                    fee_reserve: Amount::ZERO,
                    counter_start: None,
                    counter_end: None,
                    change_amount: None,
                    metadata: HashMap::new(),
                    final_proof_ys: Some(vec![y]),
                    change_blinded_messages: None,
                }),
            ))
            .await
            .unwrap();
        saga
    }

    /// What a mint answers about quote `quote_id` before it has processed the
    /// melt request: still unpaid, and no preimage. cdk rolls a melt it resumes
    /// back on exactly this.
    fn unpaid_answer(quote_id: &str) -> String {
        format!(
            r#"{{"quote":"{quote_id}","amount":{SEEDED_SATS},"fee_reserve":0,"state":"UNPAID","expiry":{}}}"#,
            unix_now().as_secs() + 3_600
        )
    }

    #[test]
    fn a_quote_the_mint_no_longer_calls_unpaid_is_refused() {
        // Arrange
        let mint = MintUrl::from_str("https://mint.example.com").unwrap();
        let now = unix_now().as_secs();
        let refusal = |quote: &cdk::wallet::MeltQuote, input_fee: u64| {
            melt_refusal(quote, input_fee, &mint, now, SEEDED_SATS).map(|e| e.to_string())
        };

        // Act / Assert — paid, still being paid, failed or unknown: paying it
        // again would have the wallet's proofs marked spent by a mint that never
        // took them. Refused with a reason that says nothing was sent.
        for state in [
            MeltQuoteState::Paid,
            MeltQuoteState::Pending,
            MeltQuoteState::Failed,
            MeltQuoteState::Unknown,
        ] {
            assert_eq!(
                refusal(&melt_quote_for("q", &mint, state), 0).as_deref(),
                Some("CashuMeltFailed: the quote is no longer unpaid"),
                "{state}"
            );
        }

        // An unpaid quote that holds is paid.
        let unpaid = melt_quote_for("q", &mint, MeltQuoteState::Unpaid);
        assert_eq!(refusal(&unpaid, 0), None);

        // And the refusals that were there before still stand.
        let mut elsewhere = unpaid.clone();
        elsewhere.mint_url = Some(MintUrl::from_str("https://other.example.com").unwrap());
        assert_eq!(
            refusal(&elsewhere, 0).as_deref(),
            Some("CashuMeltFailed: the quote belongs to another mint")
        );
        let mut expired = unpaid.clone();
        expired.expiry = now;
        assert_eq!(
            refusal(&expired, 0).as_deref(),
            Some("CashuMeltQuoteExpired")
        );
        assert_eq!(
            refusal(&unpaid, 1)
                .map(|e| marker_of(anyhow!(e)))
                .as_deref(),
            Some("CashuMeltFeeChanged")
        );
    }

    #[tokio::test]
    async fn a_paid_quote_is_refused_before_anything_reaches_the_mint() {
        // Arrange — a quote the wallet's own store records as paid.
        let mint = StubMint::start(None).await;
        let wallet = seeded_wallet(&mint.url).await;
        let quote = melt_quote_for("paid", &wallet.inner.mint_url, MeltQuoteState::Paid);
        wallet.inner.localstore.add_melt_quote(quote).await.unwrap();

        // Act
        let refused = wallet.melt("paid", SEEDED_SATS).await;

        // Assert — refused, nothing sent, the proofs and the quote released.
        assert_eq!(
            refused.unwrap_err().to_string(),
            "CashuMeltFailed: the quote is no longer unpaid"
        );
        assert_eq!(mint.connections(), 0, "nothing may reach the mint");
        assert_eq!(unspent_sats(&wallet).await, SEEDED_SATS);
        let stored = wallet
            .inner
            .localstore
            .get_melt_quote("paid")
            .await
            .unwrap();
        assert_eq!(stored.unwrap().used_by_operation, None);
    }

    #[tokio::test]
    async fn a_melt_is_refused_while_another_is_in_flight_at_its_mint() {
        // Arrange — a quote that would pay, while a melt holds the mint.
        let mint = StubMint::start(None).await;
        let wallet = seeded_wallet(&mint.url).await;
        let quote = melt_quote_for("unpaid", &wallet.inner.mint_url, MeltQuoteState::Unpaid);
        wallet.inner.localstore.add_melt_quote(quote).await.unwrap();
        let _in_flight = in_flight::try_begin_melt(&wallet.inner.mint_url).unwrap();

        // Act / Assert — neither paying nor quoting gets as far as the mint.
        let paying = wallet.melt("unpaid", SEEDED_SATS).await.unwrap_err();
        assert_eq!(marker_of(paying), "CashuMeltInFlight");
        let quoting = wallet.melt_quote("lnbcrt1placeholder").await.unwrap_err();
        assert_eq!(marker_of(quoting), "CashuMeltInFlight");
        assert_eq!(mint.connections(), 0, "nothing may reach the mint");
        assert_eq!(unspent_sats(&wallet).await, SEEDED_SATS);
    }

    #[tokio::test]
    async fn sync_leaves_a_melt_in_flight_alone() {
        // Arrange — a melt whose request the mint has not processed yet: it
        // still calls the quote unpaid. Its `melt()` call is still running.
        let mint = StubMint::start(Some(unpaid_answer("sync"))).await;
        let wallet = seeded_wallet(&mint.url).await;
        let saga = record_melt_in_flight(&wallet, "sync").await;
        let _in_flight = in_flight::try_begin_melt(&wallet.inner.mint_url).unwrap();

        // Act
        wallet.finalize_pending_melts().await.unwrap();

        // Assert — not rolled back: the proof stays out of the balance, where
        // the mint may yet spend it.
        let recorded = wallet.inner.localstore.get_saga(&saga).await.unwrap();
        assert!(
            recorded.is_some(),
            "the melt was rolled back while in flight"
        );
        assert_eq!(unspent_sats(&wallet).await, 0);
        assert_eq!(mint.connections(), 0, "the mint was asked about it");
    }

    #[tokio::test]
    async fn connect_recovery_leaves_a_melt_in_flight_alone() {
        // Arrange — the same melt, seen by the wallet a mint switch and back
        // binds while the earlier one is still paying.
        let mint = StubMint::start(Some(unpaid_answer("connect"))).await;
        let wallet = seeded_wallet(&mint.url).await;
        let saga = record_melt_in_flight(&wallet, "connect").await;
        let _in_flight = in_flight::try_begin_melt(&wallet.inner.mint_url).unwrap();

        // Act
        wallet.recover().await;

        // Assert
        let recorded = wallet.inner.localstore.get_saga(&saga).await.unwrap();
        assert!(
            recorded.is_some(),
            "the melt was rolled back while in flight"
        );
        assert_eq!(unspent_sats(&wallet).await, 0);
        assert_eq!(mint.connections(), 0, "the mint was asked about it");
    }

    // ── Receiving via Lightning (C3b-2) ──────────────────────────────────────

    #[test]
    fn an_invoice_is_gated_on_what_the_mint_advertised() {
        let mints = MintCapabilities {
            nut04_bolt11: true,
            ..MintCapabilities::default()
        };
        let gate = |caps: &MintCapabilities, sats: u64| mint_gate(caps, sats).map_err(marker_of);

        // No NUT-04: unsupported, whatever the amount.
        assert_eq!(
            gate(&MintCapabilities::default(), 100),
            Err("CashuMintUnsupported".to_string())
        );

        // No stated limits: any amount but zero goes to the mint.
        assert_eq!(gate(&mints, 1), Ok(()));
        assert_eq!(gate(&mints, u64::MAX), Ok(()));
        assert_eq!(gate(&mints, 0), Err("CashuMintAmountOutOfRange".to_string()));

        // Limits are inclusive at both ends.
        let limited = MintCapabilities {
            mint_min_sats: Some(10),
            mint_max_sats: Some(1_000),
            ..mints
        };
        assert_eq!(gate(&limited, 10), Ok(()));
        assert_eq!(gate(&limited, 1_000), Ok(()));
        for outside in [9, 1_001] {
            assert_eq!(
                gate(&limited, outside),
                Err("CashuMintAmountOutOfRange".to_string()),
                "{outside} sat"
            );
        }
    }

    /// A bolt11 mint quote for [`SEEDED_SATS`] at `mint`, as cdk stores one.
    fn mint_quote_for(id: &str, mint: &MintUrl, expiry: u64) -> cdk::wallet::MintQuote {
        cdk::wallet::MintQuote::new(
            id.to_string(),
            mint.clone(),
            PaymentMethod::BOLT11,
            Some(Amount::from(SEEDED_SATS)),
            CurrencyUnit::Sat,
            "lnbcrt640n1placeholder".to_string(),
            expiry,
            None,
        )
    }

    #[test]
    fn an_unpaid_quote_expires_only_past_its_grace() {
        use cdk::nuts::MintQuoteState;

        let mint = MintUrl::from_str("https://mint.example.com").unwrap();
        let expiry = 1_000_000;
        let unpaid = mint_quote_for("q", &mint, expiry);
        let at = |quote: &cdk::wallet::MintQuote, now: u64| mint_quote_status(quote, now);

        // Unpaid: waiting until the grace after its expiry has run out.
        assert_eq!(at(&unpaid, expiry - 1), MintQuoteStatus::Waiting);
        assert_eq!(
            at(&unpaid, expiry + MINT_QUOTE_EXPIRY_GRACE_SECS - 1),
            MintQuoteStatus::Waiting
        );
        assert_eq!(
            at(&unpaid, expiry + MINT_QUOTE_EXPIRY_GRACE_SECS),
            MintQuoteStatus::Expired
        );

        // Paid but not minted yet: never expired, whatever the clock says.
        let paid = cdk::wallet::MintQuote {
            state: MintQuoteState::Paid,
            ..unpaid.clone()
        };
        assert_eq!(at(&paid, u64::MAX), MintQuoteStatus::Waiting);

        // Issued: what was issued, expired or not.
        let issued = cdk::wallet::MintQuote {
            state: MintQuoteState::Issued,
            amount_issued: Amount::from(SEEDED_SATS),
            ..unpaid.clone()
        };
        assert_eq!(
            at(&issued, u64::MAX),
            MintQuoteStatus::Issued {
                amount_sats: SEEDED_SATS
            }
        );

        // No expiry stated: never expired.
        let open = mint_quote_for("q", &mint, 0);
        assert_eq!(at(&open, u64::MAX), MintQuoteStatus::Waiting);
    }

    /// How the mint answers a check of `quote_id`: unpaid, with `expiry`.
    fn unpaid_mint_quote_answer(quote_id: &str, expiry: u64) -> String {
        format!(
            r#"{{"quote":"{quote_id}","request":"lnbcrt640n1placeholder","amount":{SEEDED_SATS},"unit":"sat","state":"UNPAID","expiry":{expiry}}}"#
        )
    }

    #[tokio::test]
    async fn a_quote_check_skips_while_the_mint_is_being_issued_to() {
        // Arrange — a quote the mint would call expired, while an issue holds
        // the mint: a mint call may be running on it.
        let mint = StubMint::start(Some(unpaid_mint_quote_answer("held", 1))).await;
        let wallet = seeded_wallet(&mint.url).await;
        let quote = mint_quote_for("held", &wallet.inner.mint_url, 1);
        wallet.inner.localstore.add_mint_quote(quote).await.unwrap();
        let _issuing = in_flight::try_begin_issue(&wallet.inner.mint_url).unwrap();

        // Act
        let status = wallet.claim_mint_quote("held").await.unwrap();

        // Assert — this round is skipped, as waiting, and nothing is asked.
        assert_eq!(status, MintQuoteStatus::Waiting);
        assert_eq!(mint.connections(), 0, "the mint was asked about it");
    }

    #[tokio::test]
    async fn a_quote_check_marks_the_mint_while_it_runs() {
        use tokio::io::AsyncReadExt;

        // Arrange — a mint that takes the request and never answers, so the
        // check is still running when the second one comes.
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let reached = Arc::new(tokio::sync::Notify::new());
        tokio::spawn({
            let reached = reached.clone();
            async move {
                let mut held = Vec::new();
                while let Ok((mut socket, _)) = listener.accept().await {
                    let mut chunk = [0u8; 4096];
                    let _ = socket.read(&mut chunk).await;
                    reached.notify_one();
                    held.push(socket);
                }
            }
        });
        let wallet = Arc::new(seeded_wallet(&url).await);
        let quote = mint_quote_for("slow", &wallet.inner.mint_url, 1);
        wallet.inner.localstore.add_mint_quote(quote).await.unwrap();

        // Act — a check in flight.
        let first = tokio::spawn({
            let wallet = wallet.clone();
            async move { wallet.claim_mint_quote("slow").await }
        });
        reached.notified().await;

        // Assert — the mint is held: another check, or a connect's recovery,
        // skips it. And the mark goes with the check, even one cancelled.
        assert!(in_flight::try_begin_issue(&wallet.inner.mint_url).is_none());
        first.abort();
        let _ = first.await;
        assert!(in_flight::try_begin_issue(&wallet.inner.mint_url).is_some());
    }

    #[tokio::test]
    async fn a_quote_the_mint_calls_unpaid_past_its_expiry_has_expired() {
        // Arrange — expired an hour ago, still unpaid at the mint.
        let expiry = unix_now().as_secs() - 3_600;
        let mint = StubMint::start(Some(unpaid_mint_quote_answer("late", expiry))).await;
        let wallet = seeded_wallet(&mint.url).await;
        let quote = mint_quote_for("late", &wallet.inner.mint_url, expiry);
        wallet.inner.localstore.add_mint_quote(quote).await.unwrap();

        // Act / Assert — asked, and expired.
        let status = wallet.claim_mint_quote("late").await.unwrap();
        assert_eq!(status, MintQuoteStatus::Expired);
        assert!(mint.connections() > 0);
    }

    #[tokio::test]
    async fn a_quote_the_device_calls_expired_waits_until_the_mint_does() {
        // Arrange — the device's clock is an hour ahead of the mint's: by it
        // the invoice ran out ten minutes ago, by the mint's it has fifty
        // minutes left.
        let device_now = unix_now().as_secs();
        let expiry = device_now - 600;
        let mint = StubMint::start_with_clock(
            Some(unpaid_mint_quote_answer("early", expiry)),
            Some(-3_600),
        )
        .await;
        let wallet = seeded_wallet(&mint.url).await;
        let quote = mint_quote_for("early", &wallet.inner.mint_url, expiry);
        wallet.inner.localstore.add_mint_quote(quote).await.unwrap();

        // Act / Assert — still payable, so still waiting.
        let status = wallet.claim_mint_quote("early").await.unwrap();
        assert_eq!(status, MintQuoteStatus::Waiting);
    }

    #[tokio::test]
    async fn a_quote_is_not_called_expired_by_a_mint_that_dates_nothing() {
        // Arrange — long expired by the device's clock, and the mint's time
        // cannot be read.
        let expiry = unix_now().as_secs() - 3_600;
        let mint =
            StubMint::start_with_clock(Some(unpaid_mint_quote_answer("late", expiry)), None).await;
        let wallet = seeded_wallet(&mint.url).await;
        let quote = mint_quote_for("late", &wallet.inner.mint_url, expiry);
        wallet.inner.localstore.add_mint_quote(quote).await.unwrap();

        // Act / Assert
        let status = wallet.claim_mint_quote("late").await.unwrap();
        assert_eq!(status, MintQuoteStatus::Waiting);
    }

    #[tokio::test]
    async fn a_quote_already_issued_is_answered_without_the_mint() {
        // Arrange — the collector, or an earlier round, minted it.
        let mint = StubMint::start(None).await;
        let wallet = seeded_wallet(&mint.url).await;
        let quote = cdk::wallet::MintQuote {
            state: cdk::nuts::MintQuoteState::Issued,
            amount_issued: Amount::from(SEEDED_SATS),
            ..mint_quote_for("done", &wallet.inner.mint_url, 1)
        };
        wallet.inner.localstore.add_mint_quote(quote).await.unwrap();

        // Act / Assert
        let status = wallet.claim_mint_quote("done").await.unwrap();
        assert_eq!(
            status,
            MintQuoteStatus::Issued {
                amount_sats: SEEDED_SATS
            }
        );
        assert_eq!(mint.connections(), 0, "the mint was asked about it");
    }

    #[tokio::test]
    async fn a_quote_unknown_here_or_at_another_mint_is_refused() {
        // Arrange — one quote taken at another mint, in the same store.
        let mint = StubMint::start(None).await;
        let wallet = seeded_wallet(&mint.url).await;
        let elsewhere = MintUrl::from_str("https://other.mint.example").unwrap();
        let quote = mint_quote_for("theirs", &elsewhere, 1);
        wallet.inner.localstore.add_mint_quote(quote).await.unwrap();

        // Act / Assert — neither is checked with this wallet's mint.
        for id in ["missing", "theirs"] {
            let refused = wallet.claim_mint_quote(id).await.unwrap_err();
            assert_eq!(marker_of(refused), "CashuMintQuoteUnknown", "{id}");
        }
        assert_eq!(mint.connections(), 0, "the mint was asked about it");
    }

    #[tokio::test]
    async fn connect_recovery_waits_while_the_mint_is_being_issued_to() {
        // Arrange — an interrupted melt that recovery would settle, while an
        // invoice screen checks a quote at the same mint.
        let mint = StubMint::start(Some(unpaid_answer("issuing"))).await;
        let wallet = seeded_wallet(&mint.url).await;
        let saga = record_melt_in_flight(&wallet, "issuing").await;
        let _issuing = in_flight::try_begin_issue(&wallet.inner.mint_url).unwrap();

        // Act
        wallet.recover().await;

        // Assert — recovery did not run at all: it would resume issue sagas
        // too. The next connect does it.
        let recorded = wallet.inner.localstore.get_saga(&saga).await.unwrap();
        assert!(recorded.is_some(), "recovery ran while the mint was held");
        assert_eq!(mint.connections(), 0, "the mint was asked about it");
    }

    #[tokio::test]
    async fn collecting_from_no_store_creates_none_and_asks_no_mint() {
        let missing = temp_db_path();

        let minted = collect_pending_quotes(
            missing.to_str().unwrap(),
            &unique_seed(),
            None,
            Collect::Live,
        )
        .await
        .unwrap();

        assert_eq!(minted, 0);
        assert!(!missing.exists(), "the store was created");
    }

    #[tokio::test]
    async fn collecting_with_no_quote_asks_no_mint() {
        // Arrange — a wallet with ecash, and no invoice ever asked for.
        let mint = StubMint::start(None).await;
        let db = temp_db_path();
        let wallet = seeded_wallet_at(&mint.url, &db).await;

        // Act
        let minted = collect_pending_quotes(
            db.to_str().unwrap(),
            &unique_seed(),
            Some(&wallet),
            Collect::Live,
        )
        .await
        .unwrap();

        // Assert — the wallet stays lazy.
        assert_eq!(minted, 0);
        assert_eq!(mint.connections(), 0, "a mint was contacted");
    }

    #[tokio::test]
    async fn collecting_asks_every_mint_with_quotes_not_only_the_bound_one() {
        // Arrange — quotes at the bound mint and at one the user left, both
        // still unpaid there.
        let expiry = unix_now().as_secs() + 3_600;
        let bound = StubMint::start(Some(unpaid_mint_quote_answer("here", expiry))).await;
        let left = StubMint::start(Some(unpaid_mint_quote_answer("there", expiry))).await;
        let db = temp_db_path();
        let wallet = seeded_wallet_at(&bound.url, &db).await;
        let store = &wallet.inner.localstore;
        store
            .add_mint_quote(mint_quote_for("here", &wallet.inner.mint_url, expiry))
            .await
            .unwrap();
        let elsewhere = MintUrl::from_str(&left.url).unwrap();
        store
            .add_mint_quote(mint_quote_for("there", &elsewhere, expiry))
            .await
            .unwrap();

        // Act
        let minted = collect_pending_quotes(
            db.to_str().unwrap(),
            &unique_seed(),
            Some(&wallet),
            Collect::Live,
        )
        .await
        .unwrap();

        // Assert — both asked; nothing paid, nothing minted.
        assert_eq!(minted, 0);
        assert!(bound.connections() > 0, "the bound mint was not asked");
        assert!(left.connections() > 0, "the mint the user left was not asked");
    }

    #[tokio::test]
    async fn collecting_skips_a_mint_whose_quotes_are_being_checked() {
        // Arrange — two mints with quotes; an invoice screen holds the first.
        let expiry = unix_now().as_secs() + 3_600;
        let held = StubMint::start(Some(unpaid_mint_quote_answer("held", expiry))).await;
        let free = StubMint::start(Some(unpaid_mint_quote_answer("free", expiry))).await;
        let db = temp_db_path();
        let wallet = seeded_wallet_at(&held.url, &db).await;
        let store = &wallet.inner.localstore;
        store
            .add_mint_quote(mint_quote_for("held", &wallet.inner.mint_url, expiry))
            .await
            .unwrap();
        let other = MintUrl::from_str(&free.url).unwrap();
        store
            .add_mint_quote(mint_quote_for("free", &other, expiry))
            .await
            .unwrap();
        let _issuing = in_flight::try_begin_issue(&wallet.inner.mint_url).unwrap();

        // Act
        collect_pending_quotes(
            db.to_str().unwrap(),
            &unique_seed(),
            Some(&wallet),
            Collect::Live,
        )
        .await
        .unwrap();

        // Assert — the held mint is left to its holder; the other is asked.
        assert_eq!(held.connections(), 0, "the held mint was asked");
        assert!(free.connections() > 0, "the free mint was not asked");
    }

    #[tokio::test]
    async fn collecting_at_a_mint_left_behind_recovers_nothing_there() {
        // Arrange — the mint the user left still has a melt on record, which
        // a recovery would roll back on this "unpaid" answer, and a quote.
        let expiry = unix_now().as_secs() + 3_600;
        let left = StubMint::start(Some(unpaid_answer("melting"))).await;
        let db = temp_db_path();
        let earlier = seeded_wallet_at(&left.url, &db).await;
        let saga = record_melt_in_flight(&earlier, "melting").await;
        earlier
            .inner
            .localstore
            .add_mint_quote(mint_quote_for("quote", &earlier.inner.mint_url, expiry))
            .await
            .unwrap();

        // Act — no wallet bound to it: the collector builds its own.
        collect_pending_quotes(db.to_str().unwrap(), &unique_seed(), None, Collect::Live)
            .await
            .unwrap();

        // Assert — the mint was asked about the quote, and the melt is
        // untouched: the throwaway wallet ran no recovery.
        assert!(left.connections() > 0, "the mint was not asked");
        let recorded = earlier.inner.localstore.get_saga(&saga).await.unwrap();
        assert!(recorded.is_some(), "the melt was rolled back");
        assert_eq!(unspent_sats(&earlier).await, 0);
    }

    #[test]
    fn a_quote_is_forgettable_only_long_after_it_expired_unpaid() {
        use cdk::nuts::MintQuoteState;

        let mint = MintUrl::from_str("https://mint.example.com").unwrap();
        let expiry = 1_000_000;
        let quote = mint_quote_for("q", &mint, expiry);
        let forget_at = expiry + MINT_QUOTE_FORGET_AFTER_SECS;

        assert!(!forgettable(&quote, forget_at - 1), "not yet");
        assert!(forgettable(&quote, forget_at));

        // Anything the mint said was paid or issued, an operation on it, or
        // no expiry at all: kept, whatever the clock says.
        let kept = [
            cdk::wallet::MintQuote {
                state: MintQuoteState::Paid,
                ..quote.clone()
            },
            cdk::wallet::MintQuote {
                amount_paid: Amount::from(SEEDED_SATS),
                ..quote.clone()
            },
            cdk::wallet::MintQuote {
                amount_issued: Amount::from(SEEDED_SATS),
                ..quote.clone()
            },
            cdk::wallet::MintQuote {
                used_by_operation: Some(Uuid::new_v4().to_string()),
                ..quote.clone()
            },
            mint_quote_for("q", &mint, 0),
        ];
        for quote in kept {
            assert!(!forgettable(&quote, u64::MAX), "{quote:?}");
        }
    }

    /// A store at `db` holding one quote at `mint_url`, expired `ago` seconds
    /// ago.
    async fn store_with_expired_quote(mint_url: &str, db: &std::path::Path, ago: u64) {
        let wallet = seeded_wallet_at(mint_url, db).await;
        let expiry = unix_now().as_secs() - ago;
        wallet
            .inner
            .localstore
            .add_mint_quote(mint_quote_for("old", &wallet.inner.mint_url, expiry))
            .await
            .unwrap();
    }

    async fn quote_kept(db: &std::path::Path) -> bool {
        let store = WalletSqliteDatabase::new(db.to_str().unwrap()).await.unwrap();
        store.get_mint_quote("old").await.unwrap().is_some()
    }

    #[tokio::test]
    async fn collecting_forgets_a_quote_the_mint_says_expired_unpaid_long_ago() {
        // Arrange — expired two days ago, and the mint still calls it unpaid.
        let db = temp_db_path();
        let ago = 2 * MINT_QUOTE_FORGET_AFTER_SECS;
        let expiry = unix_now().as_secs() - ago;
        let mint = StubMint::start(Some(unpaid_mint_quote_answer("old", expiry))).await;
        store_with_expired_quote(&mint.url, &db, ago).await;

        // Act
        collect_pending_quotes(db.to_str().unwrap(), &unique_seed(), None, Collect::Live)
            .await
            .unwrap();

        // Assert — gone, so the next start asks nothing.
        assert!(!quote_kept(&db).await);
        let asked = mint.connections();
        collect_pending_quotes(db.to_str().unwrap(), &unique_seed(), None, Collect::Live)
            .await
            .unwrap();
        assert_eq!(mint.connections(), asked, "the mint was asked again");
    }

    #[tokio::test]
    async fn collecting_keeps_a_quote_expired_within_the_margin() {
        // Arrange — expired an hour ago, unpaid at the mint: a payment may
        // still be on its way.
        let db = temp_db_path();
        let expiry = unix_now().as_secs() - 3_600;
        let mint = StubMint::start(Some(unpaid_mint_quote_answer("old", expiry))).await;
        store_with_expired_quote(&mint.url, &db, 3_600).await;

        // Act
        collect_pending_quotes(db.to_str().unwrap(), &unique_seed(), None, Collect::Live)
            .await
            .unwrap();

        // Assert
        assert!(quote_kept(&db).await);
    }

    #[tokio::test]
    async fn collecting_keeps_an_expired_quote_the_mint_did_not_answer_for() {
        // Arrange — long expired, but the mint hangs up: it may have been
        // paid, and only the mint can say it was not.
        let db = temp_db_path();
        let mint = StubMint::start(None).await;
        store_with_expired_quote(&mint.url, &db, 2 * MINT_QUOTE_FORGET_AFTER_SECS).await;

        // Act
        collect_pending_quotes(db.to_str().unwrap(), &unique_seed(), None, Collect::Live)
            .await
            .unwrap();

        // Assert
        assert!(mint.connections() > 0);
        assert!(quote_kept(&db).await);
    }

    #[tokio::test]
    async fn a_device_clock_ahead_forgets_no_invoice_still_payable() {
        // Arrange — the device is two days ahead of the mint. By the device's
        // clock the quote expired two days ago; by the mint's it was asked
        // for a minute ago, and the mint truthfully calls it unpaid.
        let db = temp_db_path();
        let ahead = 2 * MINT_QUOTE_FORGET_AFTER_SECS;
        let expiry = unix_now().as_secs() - ahead + 600;
        let mint = StubMint::start_with_clock(
            Some(unpaid_mint_quote_answer("old", expiry)),
            Some(-(ahead as i64)),
        )
        .await;
        store_with_expired_quote(&mint.url, &db, ahead - 600).await;

        // Act
        collect_pending_quotes(db.to_str().unwrap(), &unique_seed(), None, Collect::Live)
            .await
            .unwrap();

        // Assert — kept: a payment now still has its quote to mint with.
        assert!(mint.connections() > 0);
        assert!(quote_kept(&db).await);
    }

    #[tokio::test]
    async fn collecting_forgets_nothing_at_a_mint_that_dates_nothing() {
        // Arrange — expired two days ago and unpaid at the mint, whose time
        // cannot be read.
        let db = temp_db_path();
        let ago = 2 * MINT_QUOTE_FORGET_AFTER_SECS;
        let expiry = unix_now().as_secs() - ago;
        let mint =
            StubMint::start_with_clock(Some(unpaid_mint_quote_answer("old", expiry)), None).await;
        store_with_expired_quote(&mint.url, &db, ago).await;

        // Act
        collect_pending_quotes(db.to_str().unwrap(), &unique_seed(), None, Collect::Live)
            .await
            .unwrap();

        // Assert
        assert!(quote_kept(&db).await);
    }

    #[tokio::test]
    async fn a_long_silent_mint_is_left_to_sync_and_its_quote_kept() {
        // Arrange — expired over a month ago at a mint that never answers.
        let db = temp_db_path();
        let mint = StubMint::start(None).await;
        store_with_expired_quote(&mint.url, &db, MINT_QUOTE_DORMANT_AFTER_SECS + 60).await;

        // Act — a start or resume.
        collect_pending_quotes(db.to_str().unwrap(), &unique_seed(), None, Collect::Live)
            .await
            .unwrap();

        // Assert — not asked, and not counted as open.
        assert_eq!(mint.connections(), 0, "a dormant mint was asked");
        let pending = stored_pending_quotes(db.to_str().unwrap(), None)
            .await
            .unwrap();
        assert_eq!(pending, PendingQuotes::default());

        // Act — Sync, which the user asks for.
        collect_pending_quotes(
            db.to_str().unwrap(),
            &unique_seed(),
            None,
            Collect::Everything,
        )
        .await
        .unwrap();

        // Assert — asked again, and the quote, with its key, is still there.
        assert!(mint.connections() > 0, "Sync did not ask the dormant mint");
        assert!(quote_kept(&db).await);
    }

    #[test]
    fn a_quote_goes_dormant_only_a_month_after_it_expired_unpaid() {
        let mint = MintUrl::from_str("https://mint.example.com").unwrap();
        let expiry = 1_000_000;
        let quote = mint_quote_for("q", &mint, expiry);
        let dormant_at = expiry + MINT_QUOTE_DORMANT_AFTER_SECS;

        assert!(!dormant(&quote, dormant_at - 1));
        assert!(dormant(&quote, dormant_at));
        // Paid: never dormant, it is money on its way.
        let paid = cdk::wallet::MintQuote {
            state: cdk::nuts::MintQuoteState::Paid,
            ..quote
        };
        assert!(!dormant(&paid, u64::MAX));
    }

    #[test]
    fn pending_quotes_count_every_open_invoice_and_the_paid_sats() {
        use cdk::nuts::MintQuoteState;

        let ours = MintUrl::from_str("https://mint.example.com").unwrap();
        let theirs = MintUrl::from_str("https://other.example.com").unwrap();
        let unpaid = mint_quote_for("unpaid", &ours, 1);
        let paid = cdk::wallet::MintQuote {
            state: MintQuoteState::Paid,
            ..mint_quote_for("paid", &ours, 1)
        };
        let elsewhere = cdk::wallet::MintQuote {
            state: MintQuoteState::Paid,
            ..mint_quote_for("elsewhere", &theirs, 1)
        };
        let usd = cdk::wallet::MintQuote {
            unit: CurrencyUnit::Usd,
            state: MintQuoteState::Paid,
            ..mint_quote_for("usd", &ours, 1)
        };
        let all = vec![unpaid, paid, elsewhere, usd];

        // At this mint: both sat invoices are open, one of them paid.
        assert_eq!(
            pending_quotes_of(all.clone(), Some(&ours), 2),
            PendingQuotes {
                paid_sats: SEEDED_SATS,
                open: 2
            }
        );
        // Across every mint: the one at the other mint too. Never the usd.
        assert_eq!(
            pending_quotes_of(all.clone(), None, 2),
            PendingQuotes {
                paid_sats: 2 * SEEDED_SATS,
                open: 3
            }
        );
        // A month on, the unpaid one has gone dormant: no longer open. The
        // paid ones still are — the mint said so.
        assert_eq!(
            pending_quotes_of(all, None, 1 + MINT_QUOTE_DORMANT_AFTER_SECS),
            PendingQuotes {
                paid_sats: 2 * SEEDED_SATS,
                open: 2
            }
        );
    }

    #[tokio::test]
    async fn pending_quotes_are_read_from_the_store_alone() {
        // Arrange — a paid quote the mint has not issued yet, and no mint up.
        let mint = StubMint::start(None).await;
        let db = temp_db_path();
        let wallet = seeded_wallet_at(&mint.url, &db).await;
        let paid = cdk::wallet::MintQuote {
            state: cdk::nuts::MintQuoteState::Paid,
            ..mint_quote_for("paid", &wallet.inner.mint_url, 1)
        };
        wallet.inner.localstore.add_mint_quote(paid).await.unwrap();
        let expected = PendingQuotes {
            paid_sats: SEEDED_SATS,
            open: 1,
        };

        // Act / Assert — bound or not, the same answer, and no mint asked.
        assert_eq!(wallet.pending_quotes().await.unwrap(), expected);
        let stored = stored_pending_quotes(db.to_str().unwrap(), Some(&mint.url))
            .await
            .unwrap();
        assert_eq!(stored, expected);
        assert_eq!(mint.connections(), 0, "a mint was contacted");
        let missing = temp_db_path();
        assert_eq!(
            stored_pending_quotes(missing.to_str().unwrap(), None)
                .await
                .unwrap(),
            PendingQuotes::default()
        );
        assert!(!missing.exists(), "the store was created");
    }
}
