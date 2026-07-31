//! Escrow primitives — phase C4 of `docs/cashu/README.md`.
//!
//! The cryptographic heart of Cashu-mode trading, deliberately UI-free so a
//! review can be about correctness and nothing else.
//!
//! The escrow is a NUT-11 P2PK secret locked 2-of-3 (§2 of the doc):
//!
//! ```text
//! data          = P_S                      (seller)
//! pubkeys       = [P_B, P_M]               (buyer, Mostro)
//! n_sigs        = 2                        (any two of the three)
//! sigflag       = SIG_INPUTS
//! locktime      = now + escrow_locktime_days
//! refund        = [P_S]                    (seller alone, after locktime)
//! n_sigs_refund = 1
//! ```
//!
//! Two things this module exists to get right, both of which fail silently if
//! wrong:
//!
//! - **Key encoding.** Nostr trade keys are x-only (32 bytes); Cashu P2PK wants
//!   compressed SEC1 (33 bytes). The daemon prefixes `02`
//!   (`cashu_pubkey_from_xonly_hex`) and the client must do the identical
//!   thing, or the token locks to a key nobody holds.
//! - **Per-order keys.** Every party is identified by the *trade* key for that
//!   order, never the identity key. That is a privacy requirement of the
//!   upstream spec, not a preference.

use anyhow::{anyhow, bail, Result};
use cdk::amount::SplitTarget;
use cdk::nuts::nut10::{Conditions, SpendingConditions};
use cdk::nuts::nut11::SigFlag;
use cdk::nuts::{Proof, PublicKey, SecretKey, Token, Witness};
use cdk::wallet::{ReceiveOptions, SendMemo, SendOptions};
use cdk::Amount;

use super::CashuWallet;

/// The three keys an escrow is locked to, already in Cashu (compressed) form.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EscrowParties {
    /// `P_B` — buyer's per-order trade key.
    pub buyer: PublicKey,
    /// `P_S` — seller's per-order trade key. Also the refund key.
    pub seller: PublicKey,
    /// `P_M` — the Mostro node's key.
    pub mostro: PublicKey,
}

impl EscrowParties {
    /// Build from the x-only hex keys the protocol carries.
    pub fn from_xonly_hex(buyer: &str, seller: &str, mostro: &str) -> Result<Self> {
        let parties = Self {
            buyer: xonly_to_cashu_pubkey(buyer)?,
            seller: xonly_to_cashu_pubkey(seller)?,
            mostro: xonly_to_cashu_pubkey(mostro)?,
        };
        parties.ensure_distinct()?;
        Ok(parties)
    }

    /// Three different keys, or it is not a 2-of-3.
    ///
    /// A duplicate collapses the threshold: whether one signature can satisfy
    /// `n_sigs = 2` under a repeated key is mint-implementation-defined, which
    /// is precisely the thing not to leave to the mint. Rejected on the way in
    /// and on the way out.
    pub fn ensure_distinct(&self) -> Result<()> {
        if self.buyer == self.seller || self.buyer == self.mostro || self.seller == self.mostro {
            bail!("InvalidEscrowParties: buyer, seller and Mostro must be three different keys");
        }
        Ok(())
    }
}

/// One signature over one proof, keyed by that proof's own secret so order does
/// not matter on the wire.
///
/// Mirrors `mostro_core`'s `CashuProofSignature` without depending on it — this
/// module is about cryptography; the wire mapping belongs to C5.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProofSignature {
    /// The proof's secret, verbatim, as it appears in the token.
    pub secret: String,
    /// BIP-340 signature over that secret, hex.
    pub signature: String,
}

/// Map a Nostr x-only public key (32 bytes, hex) to a Cashu compressed key.
///
/// The `02` prefix is not a choice: it is what the daemon does, so any other
/// parity yields a key the counterparty cannot sign for. Anything that is not
/// exactly 64 hex characters is rejected rather than padded or truncated — a
/// silently reinterpreted key would lock funds to nobody.
pub fn xonly_to_cashu_pubkey(xonly_hex: &str) -> Result<PublicKey> {
    let hex = xonly_hex.trim();
    if hex.len() != 64 || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
        bail!("InvalidTradeKey: expected 64 hex characters, got {:?}", hex);
    }
    PublicKey::from_hex(format!("02{hex}"))
        .map_err(|e| anyhow!("InvalidTradeKey: {hex} is not a valid point ({e})"))
}

/// The 2-of-3 escrow condition of §2.
///
/// `locktime` is an absolute unix timestamp; `cdk` rejects one in the past, so
/// a caller that miscomputes it fails here rather than minting an escrow that
/// is already refundable.
pub fn escrow_conditions(parties: &EscrowParties, locktime: u64) -> Result<SpendingConditions> {
    parties.ensure_distinct()?;

    let conditions = Conditions::new(
        Some(locktime),
        // `data` carries the seller, so the extra pubkeys are the other two.
        Some(vec![parties.buyer, parties.mostro]),
        // After locktime the seller alone can reclaim.
        Some(vec![parties.seller]),
        Some(2),
        Some(SigFlag::SigInputs),
        Some(1),
    )
    .map_err(|e| anyhow!("InvalidEscrowConditions: {e}"))?;

    Ok(SpendingConditions::P2PKConditions {
        data: parties.seller,
        conditions: Some(conditions),
    })
}

/// The fee token's condition: 1-of-1 to Mostro, no locktime.
///
/// The fee is not escrowed — it is a straight payment the node redeems when the
/// trade settles, so it carries none of the escrow's conditions.
pub fn fee_conditions(mostro: PublicKey) -> SpendingConditions {
    SpendingConditions::P2PKConditions {
        data: mostro,
        conditions: None,
    }
}

/// Check a parsed condition against what this trade requires.
///
/// Defense in depth: the daemon runs the same check, and a client that submits
/// a token failing it only finds out through a `CantDo` rejection, with the
/// funds already locked at the mint.
pub fn verify_conditions(
    conditions: &SpendingConditions,
    parties: &EscrowParties,
    min_locktime: u64,
) -> Result<()> {
    parties.ensure_distinct()?;

    let SpendingConditions::P2PKConditions { data, conditions } = conditions else {
        bail!("InvalidEscrowToken: not a P2PK secret");
    };

    if *data != parties.seller {
        bail!("InvalidEscrowToken: locked to the wrong seller key");
    }

    let c = conditions
        .as_ref()
        .ok_or_else(|| anyhow!("InvalidEscrowToken: no spending conditions"))?;

    let pubkeys = c
        .pubkeys
        .as_ref()
        .ok_or_else(|| anyhow!("InvalidEscrowToken: no additional pubkeys"))?;

    // Exactly two, and exactly these two. Checking only that the buyer and
    // Mostro are *present* would accept `[P_B, P_M, P_attacker]`: with
    // `n_sigs = 2` and `data = P_S`, the seller plus a key they also control
    // satisfies the condition, and they can drain the escrow the moment it is
    // funded. Every other field here is matched exactly; so is this one.
    if pubkeys.len() != 2 {
        bail!(
            "InvalidEscrowToken: expected exactly 2 additional pubkeys, got {}",
            pubkeys.len()
        );
    }
    if !pubkeys.contains(&parties.buyer) || !pubkeys.contains(&parties.mostro) {
        bail!("InvalidEscrowToken: buyer or Mostro key missing");
    }

    if c.num_sigs != Some(2) {
        bail!("InvalidEscrowToken: n_sigs must be 2, got {:?}", c.num_sigs);
    }
    if c.sig_flag != SigFlag::SigInputs {
        bail!("InvalidEscrowToken: sigflag must be SIG_INPUTS");
    }

    match c.locktime {
        // Too short a locktime is the dangerous direction: the seller could
        // reclaim before the buyer has had time to pay.
        Some(l) if l >= min_locktime => {}
        Some(l) => bail!("InvalidEscrowToken: locktime {l} is before {min_locktime}"),
        None => bail!("InvalidEscrowToken: no locktime"),
    }

    match c.refund_keys.as_ref() {
        Some(keys) if keys == &vec![parties.seller] => {}
        _ => bail!("InvalidEscrowToken: refund key must be the seller alone"),
    }
    if c.num_sigs_refund.unwrap_or(1) != 1 {
        bail!("InvalidEscrowToken: n_sigs_refund must be 1");
    }

    Ok(())
}

impl CashuWallet {
    /// Swap `amount_sats` of wallet proofs into an escrow token.
    ///
    /// The proofs leave the spendable balance the moment this returns: they are
    /// locked to a condition this wallet alone cannot satisfy.
    pub async fn build_escrow_token(
        &self,
        amount_sats: u64,
        parties: &EscrowParties,
        locktime: u64,
    ) -> Result<String> {
        self.build_locked_token(amount_sats, escrow_conditions(parties, locktime)?)
            .await
    }

    /// Swap `amount_sats` into a token payable to Mostro alone.
    pub async fn build_fee_token(&self, amount_sats: u64, mostro: PublicKey) -> Result<String> {
        self.build_locked_token(amount_sats, fee_conditions(mostro))
            .await
    }

    async fn build_locked_token(
        &self,
        amount_sats: u64,
        conditions: SpendingConditions,
    ) -> Result<String> {
        if amount_sats == 0 {
            bail!("CashuAmountZero");
        }

        let prepared = self
            .inner()
            .prepare_send(
                Amount::from(amount_sats),
                SendOptions {
                    conditions: Some(conditions),
                    amount_split_target: SplitTarget::default(),
                    ..Default::default()
                },
            )
            .await
            .map_err(|e| anyhow!("CashuLockFailed: {e}"))?;

        let token = match prepared.confirm(None::<SendMemo>).await {
            Ok(token) => token,
            Err(e) => {
                // The whole escrow amount is reserved at this point and
                // `confirm` consumed the handle, so nothing else can release
                // it. C5 would then report the wallet as short by exactly the
                // amount it just tried to lock.
                let reclaimed = self.check_proofs_state().await.unwrap_or(0);
                bail!("CashuLockFailed: {e} (reclaimed {reclaimed} sat)");
            }
        };

        Ok(token.to_string())
    }

    /// Verify an escrow token someone else built: right mint, right amount, and
    /// the right 2-of-3 condition on **every** proof.
    ///
    /// Per-proof rather than per-token on purpose — a token whose first proof is
    /// correct and whose second is locked to the builder alone would pass a spot
    /// check and walk away with the difference.
    pub async fn verify_escrow_token(
        &self,
        encoded: &str,
        parties: &EscrowParties,
        expected_amount: u64,
        min_locktime: u64,
    ) -> Result<()> {
        let token: Token = encoded
            .trim()
            .parse()
            .map_err(|e| anyhow!("InvalidEscrowToken: unparseable ({e})"))?;

        let token_mint = token
            .mint_url()
            .map_err(|e| anyhow!("InvalidEscrowToken: no mint ({e})"))?
            .to_string();
        if token_mint.trim_end_matches('/') != self.mint_url().trim_end_matches('/') {
            bail!("InvalidEscrowToken: wrong mint ({token_mint})");
        }

        // Unit before amount: `value()` sums proof amounts irrespective of
        // denomination, so a token in another unit with the right numeric total
        // would pass the amount check unnoticed.
        match token.unit() {
            Some(cdk::nuts::CurrencyUnit::Sat) => {}
            other => bail!("InvalidEscrowToken: expected sat, got {other:?}"),
        }

        let value = u64::from(
            token
                .value()
                .map_err(|e| anyhow!("InvalidEscrowToken: unreadable amount ({e})"))?,
        );
        if value != expected_amount {
            bail!("InvalidEscrowToken: expected {expected_amount} sat, got {value}");
        }

        for proof in self.proofs_of(&token).await? {
            let conditions: SpendingConditions = (&proof.secret)
                .try_into()
                .map_err(|e| anyhow!("InvalidEscrowToken: unreadable secret ({e})"))?;
            verify_conditions(&conditions, parties, min_locktime)?;
        }

        Ok(())
    }

    /// Sign every proof in `encoded` with `key`, returning one signature per
    /// proof keyed by that proof's secret.
    ///
    /// This is the seller's release signature and the buyer's cooperative-cancel
    /// signature: each party signs alone and hands the signatures over, and only
    /// the combination of two satisfies the 2-of-3.
    pub async fn sign_proofs(&self, encoded: &str, key: SecretKey) -> Result<Vec<ProofSignature>> {
        let token: Token = encoded
            .trim()
            .parse()
            .map_err(|e| anyhow!("InvalidEscrowToken: unparseable ({e})"))?;

        self.proofs_of(&token)
            .await?
            .into_iter()
            .map(|mut proof| {
                let secret = proof.secret.to_string();
                proof
                    .sign_p2pk(key.clone())
                    .map_err(|e| anyhow!("CashuSignFailed: {e}"))?;
                Ok(ProofSignature {
                    secret,
                    signature: last_signature(&proof)?,
                })
            })
            .collect()
    }

    /// Attach `own_key`'s signature plus `peer_signatures` to every proof and
    /// swap the result at the mint into fresh, unconditional proofs.
    ///
    /// The redeeming half of a settled trade: buyer release, or seller reclaim
    /// after a cooperative cancel. Returns the amount received.
    ///
    /// A missing peer signature fails before the mint is contacted, so a
    /// half-signed spend is never attempted.
    pub async fn combine_and_redeem(
        &self,
        encoded: &str,
        own_key: SecretKey,
        peer_signatures: &[ProofSignature],
    ) -> Result<u64> {
        let token: Token = encoded
            .trim()
            .parse()
            .map_err(|e| anyhow!("InvalidEscrowToken: unparseable ({e})"))?;

        let proofs = self.proofs_of(&token).await?;
        let mut signed = Vec::with_capacity(proofs.len());

        // Indexed once rather than scanned per proof: linear in the number of
        // signatures instead of quadratic, and it makes a duplicate secret in
        // the peer's list a visible collision rather than a silent first-wins.
        let by_secret: std::collections::HashMap<&str, &ProofSignature> = peer_signatures
            .iter()
            .map(|s| (s.secret.as_str(), s))
            .collect();

        for mut proof in proofs {
            let secret = proof.secret.to_string();
            let peer = by_secret
                .get(secret.as_str())
                .ok_or_else(|| anyhow!("MissingPeerSignature: none for proof {secret}"))?;

            proof
                .sign_p2pk(own_key.clone())
                .map_err(|e| anyhow!("CashuSignFailed: {e}"))?;

            match proof.witness.as_mut() {
                Some(witness) => witness.add_signatures(vec![peer.signature.clone()]),
                // `sign_p2pk` always leaves a witness, so this is unreachable —
                // reported rather than panicked on.
                None => bail!("CashuSignFailed: signing left no witness"),
            }
            signed.push(proof);
        }

        let amount = self
            .inner()
            .receive_proofs(signed, ReceiveOptions::default(), None, None)
            .await
            .map_err(|e| anyhow!("CashuRedeemFailed: {e}"))?;

        Ok(u64::from(amount))
    }

    /// Spend an escrow through its refund path once the locktime has passed.
    ///
    /// Only the seller can, and only after `locktime`. The mint enforces both,
    /// so a premature call fails there rather than silently doing nothing.
    pub async fn reclaim_after_locktime(
        &self,
        encoded: &str,
        seller_key: SecretKey,
    ) -> Result<u64> {
        let token: Token = encoded
            .trim()
            .parse()
            .map_err(|e| anyhow!("InvalidEscrowToken: unparseable ({e})"))?;

        let proofs = self.proofs_of(&token).await?;
        let mut signed = Vec::with_capacity(proofs.len());

        for mut proof in proofs {
            // The locktime is right there in the secret. Checking it locally
            // turns "the mint rejected your swap" into "the refund path opens
            // in N days", which is the difference between a user waiting and a
            // user filing a bug.
            if let Ok(SpendingConditions::P2PKConditions {
                conditions: Some(c), ..
            }) = SpendingConditions::try_from(&proof.secret)
            {
                if let Some(locktime) = c.locktime {
                    let now = now_unix();
                    if locktime > now {
                        bail!(
                            "CashuLocktimeNotReached: {} seconds remain",
                            locktime - now
                        );
                    }
                }
            }

            proof
                .sign_p2pk(seller_key.clone())
                .map_err(|e| anyhow!("CashuSignFailed: {e}"))?;
            signed.push(proof);
        }

        let amount = self
            .inner()
            .receive_proofs(signed, ReceiveOptions::default(), None, None)
            .await
            .map_err(|e| anyhow!("CashuReclaimFailed: {e}"))?;

        Ok(u64::from(amount))
    }
}

/// Seconds since the unix epoch, or 0 if the clock is before it — in which
/// case every locktime reads as "not reached", which is the safe direction.
fn now_unix() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// The signature `sign_p2pk` just appended.
fn last_signature(proof: &Proof) -> Result<String> {
    match proof.witness.as_ref() {
        Some(Witness::P2PKWitness(w)) => w
            .signatures
            .last()
            .cloned()
            .ok_or_else(|| anyhow!("CashuSignFailed: witness carries no signature")),
        _ => bail!("CashuSignFailed: proof has no P2PK witness"),
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    /// A valid x-only key, taken from a fresh compressed key by dropping its
    /// parity byte — the same shape a Nostr trade key has.
    fn xonly() -> String {
        SecretKey::generate().public_key().to_hex()[2..].to_string()
    }

    fn parties() -> EscrowParties {
        EscrowParties::from_xonly_hex(&xonly(), &xonly(), &xonly()).unwrap()
    }

    /// Far enough ahead that `Conditions::new` accepts it in any year this code
    /// runs in.
    fn future_locktime() -> u64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs()
            + 15 * 24 * 60 * 60
    }

    #[test]
    fn an_xonly_key_maps_to_the_daemons_compressed_form() {
        // Arrange — the mapping the daemon applies is a literal `02` prefix.
        let compressed = SecretKey::generate().public_key().to_hex();
        let x_only = &compressed[2..];

        // Act
        let mapped = xonly_to_cashu_pubkey(x_only).unwrap();

        // Assert — same x coordinate, always even parity regardless of the
        // original key's.
        assert_eq!(mapped.to_hex(), format!("02{x_only}"));
    }

    #[test]
    fn a_malformed_trade_key_is_rejected_rather_than_reinterpreted() {
        // Arrange — every shape that could silently become a different key.
        for bad in [
            "",
            "02",
            "deadbeef",
            // a 33-byte compressed key passed where x-only was expected
            "02194603ffa36356f4a56b7df9371fc3192472351453ec7398b8da8117e7c3e104",
            // right length, not hex
            "zz94603ffa36356f4a56b7df9371fc3192472351453ec7398b8da8117e7c3e10",
        ] {
            let err = xonly_to_cashu_pubkey(bad).unwrap_err();
            assert!(
                err.to_string().contains("InvalidTradeKey"),
                "expected rejection for {bad:?}, got {err}"
            );
        }
    }

    #[test]
    fn whitespace_around_a_key_is_tolerated() {
        // Arrange — keys arrive from JSON and the wire; a stray newline must
        // not read as a different key.
        let x_only = xonly();

        // Act / Assert
        assert_eq!(
            xonly_to_cashu_pubkey(&format!("  {x_only}\n")).unwrap(),
            xonly_to_cashu_pubkey(&x_only).unwrap()
        );
    }

    #[test]
    fn the_escrow_condition_matches_the_documented_shape() {
        // Arrange
        let parties = parties();
        let locktime = future_locktime();

        // Act
        let conditions = escrow_conditions(&parties, locktime).unwrap();

        // Assert — every field of §2 individually, so a wrong default cannot
        // hide behind a passing round trip.
        let SpendingConditions::P2PKConditions { data, conditions } = &conditions else {
            panic!("expected P2PK conditions");
        };
        assert_eq!(*data, parties.seller, "data must be the seller");
        let c = conditions.as_ref().unwrap();
        assert_eq!(c.pubkeys, Some(vec![parties.buyer, parties.mostro]));
        assert_eq!(c.num_sigs, Some(2));
        assert_eq!(c.sig_flag, SigFlag::SigInputs);
        assert_eq!(c.locktime, Some(locktime));
        assert_eq!(c.refund_keys, Some(vec![parties.seller]));
        assert_eq!(c.num_sigs_refund, Some(1));
    }

    #[test]
    fn a_locktime_in_the_past_is_refused() {
        // Arrange / Act — an already-refundable escrow is worthless to the
        // buyer, so it must never be built at all.
        let err = escrow_conditions(&parties(), 1).unwrap_err();

        // Assert
        assert!(
            err.to_string().contains("InvalidEscrowConditions"),
            "got {err}"
        );
    }

    #[test]
    fn the_fee_condition_is_a_plain_lock_to_mostro() {
        // Arrange
        let parties = parties();

        // Act
        let conditions = fee_conditions(parties.mostro);

        // Assert — no locktime, no extra keys: the fee is a payment, not an
        // escrow, and conditions would make it unspendable for the node.
        let SpendingConditions::P2PKConditions { data, conditions } = &conditions else {
            panic!("expected P2PK conditions");
        };
        assert_eq!(*data, parties.mostro);
        assert!(conditions.is_none());
    }

    #[test]
    fn a_well_formed_escrow_verifies() {
        // Arrange
        let parties = parties();
        let locktime = future_locktime();
        let conditions = escrow_conditions(&parties, locktime).unwrap();

        // Act / Assert — a longer-than-required locktime still passes: more
        // time is safe for the buyer.
        verify_conditions(&conditions, &parties, locktime).unwrap();
        verify_conditions(&conditions, &parties, locktime - 100).unwrap();
    }

    #[test]
    fn verification_rejects_every_way_an_escrow_can_be_wrong() {
        // Arrange
        let parties = parties();
        let locktime = future_locktime();
        let other = SecretKey::generate().public_key();
        let inner = |c: SpendingConditions| match c {
            SpendingConditions::P2PKConditions { conditions, .. } => conditions,
            _ => unreachable!(),
        };

        let cases: Vec<(SpendingConditions, &str, &str)> = vec![
            (
                // Locked to someone else's key entirely.
                SpendingConditions::P2PKConditions {
                    data: other,
                    conditions: inner(escrow_conditions(&parties, locktime).unwrap()),
                },
                "wrong seller",
                "wrong seller key",
            ),
            (
                // 1-of-N: the seller could spend alone.
                SpendingConditions::P2PKConditions {
                    data: parties.seller,
                    conditions: Some(
                        Conditions::new(
                            Some(locktime),
                            Some(vec![parties.buyer, parties.mostro]),
                            Some(vec![parties.seller]),
                            Some(1),
                            Some(SigFlag::SigInputs),
                            Some(1),
                        )
                        .unwrap(),
                    ),
                },
                "n_sigs 1",
                "n_sigs must be 2",
            ),
            (
                // Refundable to the buyer too — the seller's funds could walk.
                SpendingConditions::P2PKConditions {
                    data: parties.seller,
                    conditions: Some(
                        Conditions::new(
                            Some(locktime),
                            Some(vec![parties.buyer, parties.mostro]),
                            Some(vec![parties.seller, parties.buyer]),
                            Some(2),
                            Some(SigFlag::SigInputs),
                            Some(1),
                        )
                        .unwrap(),
                    ),
                },
                "extra refund key",
                "refund key must be the seller alone",
            ),
            (
                // A bare lock to the seller, no conditions at all.
                SpendingConditions::P2PKConditions {
                    data: parties.seller,
                    conditions: None,
                },
                "bare P2PK",
                "no spending conditions",
            ),
            (
                // The one that matters most: an *extra* key the seller also
                // controls. Every required key is present, so a
                // presence-only check passes it — and then seller + extra is
                // two of four, and the escrow is spendable unilaterally the
                // moment it is funded.
                SpendingConditions::P2PKConditions {
                    data: parties.seller,
                    conditions: Some(
                        Conditions::new(
                            Some(locktime),
                            Some(vec![parties.buyer, parties.mostro, other]),
                            Some(vec![parties.seller]),
                            Some(2),
                            Some(SigFlag::SigInputs),
                            Some(1),
                        )
                        .unwrap(),
                    ),
                },
                "extra pubkey",
                "expected exactly 2 additional pubkeys",
            ),
        ];

        // Act / Assert
        for (conditions, label, expected) in cases {
            let err = verify_conditions(&conditions, &parties, locktime).unwrap_err();
            assert!(
                err.to_string().contains(expected),
                "{label}: expected {expected:?}, got {err}"
            );
        }
    }

    #[test]
    fn a_locktime_shorter_than_required_is_refused() {
        // Arrange — the dangerous direction: the seller could reclaim before
        // the buyer has had time to pay.
        let parties = parties();
        let locktime = future_locktime();
        let conditions = escrow_conditions(&parties, locktime).unwrap();

        // Act
        let err = verify_conditions(&conditions, &parties, locktime + 1).unwrap_err();

        // Assert
        assert!(err.to_string().contains("is before"), "got {err}");
    }

    // ── Integration ──────────────────────────────────────────────────────────
    //
    // The full lock → sign → combine → redeem cycle can only be exercised
    // against a real mint: every step is blind signatures and DLEQ, and a mock
    // that faked them would prove nothing about the escrow. Run with a local
    // nutshell:
    //
    //   docker run -p 3338:3338 cashubtc/nutshell:latest poetry run mint
    //   MOSTRO_TEST_MINT_URL=http://localhost:3338 cargo test -- --ignored
    //
    // The seller wallet must already hold funds; funding is out of band.

    fn test_mint_url() -> String {
        std::env::var("MOSTRO_TEST_MINT_URL")
            .expect("set MOSTRO_TEST_MINT_URL to run the Cashu integration tests")
    }

    fn temp_db_path() -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU32, Ordering};
        static COUNTER: AtomicU32 = AtomicU32::new(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir().join(format!("mostro_escrow_test_{}_{n}.db", std::process::id()))
    }

    /// A seed unique to this process *and* this call — see the note on the
    /// wallet's `unique_seed`: a fixed seed with a fresh DB replays NUT-13
    /// blinding secrets and the mint refuses them on the second run.
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

    /// A party: its secret key, and the x-only hex the protocol carries.
    fn party() -> (SecretKey, String) {
        let sk = SecretKey::generate();
        let x_only = sk.public_key().to_hex()[2..].to_string();
        (sk, x_only)
    }

    #[tokio::test]
    #[ignore = "requires a local nutshell mint (MOSTRO_TEST_MINT_URL)"]
    async fn an_escrow_locks_and_settles_with_two_of_three_signatures() {
        // Arrange — seller funds the escrow, buyer redeems it after release.
        let mint = test_mint_url();
        let seller_db = temp_db_path();
        let buyer_db = temp_db_path();

        let seller = CashuWallet::connect(&mint, unique_seed(), seller_db.to_str().unwrap())
            .await
            .unwrap();
        let buyer = CashuWallet::connect(&mint, unique_seed(), buyer_db.to_str().unwrap())
            .await
            .unwrap();

        seller.mint_for_test(64).await.expect("mint must fund the wallet");
        let funded = seller.balance().await.unwrap();
        assert!(funded >= 16, "minting should have funded the wallet");

        let (seller_sk, seller_pk) = party();
        let (buyer_sk, buyer_pk) = party();
        let (_mostro_sk, mostro_pk) = party();
        let parties = EscrowParties::from_xonly_hex(&buyer_pk, &seller_pk, &mostro_pk).unwrap();
        let locktime = future_locktime();

        // Act — seller locks.
        let token = seller
            .build_escrow_token(16, &parties, locktime)
            .await
            .unwrap();

        // Assert — the buyer verifies before doing anything with it, which is
        // the whole point of verify_escrow_token.
        buyer
            .verify_escrow_token(&token, &parties, 16, locktime)
            .await
            .unwrap();
        // A mint that charges a swap fee (nutshell's default keyset does) makes
        // locking cost the seller slightly more than the face value.
        assert!(
            seller.balance().await.unwrap() <= funded - 16,
            "locking 16 sat must cost the seller at least the face value"
        );

        // Act — seller signs (release), buyer combines and redeems.
        let seller_sigs = seller.sign_proofs(&token, seller_sk).await.unwrap();
        let received = buyer
            .combine_and_redeem(&token, buyer_sk, &seller_sigs)
            .await
            .unwrap();

        // Assert — the face value is what a validator checks; the redeemer
        // receives that minus the mint's swap fee, which is the mint's
        // property, not this code's. Bounded rather than pinned.
        assert!(
            received > 0 && received <= 16,
            "received {received} sat for a 16 sat escrow"
        );
        assert_eq!(buyer.balance().await.unwrap(), received);

        let _ = std::fs::remove_file(&seller_db);
        let _ = std::fs::remove_file(&buyer_db);
    }

    #[tokio::test]
    #[ignore = "requires a local nutshell mint (MOSTRO_TEST_MINT_URL)"]
    async fn one_signature_is_not_enough_to_move_an_escrow() {
        // Arrange — the security property the 2-of-3 exists for: neither party
        // alone can take the funds.
        let mint = test_mint_url();
        let seller_db = temp_db_path();
        let seller = CashuWallet::connect(&mint, unique_seed(), seller_db.to_str().unwrap())
            .await
            .unwrap();
        seller.mint_for_test(64).await.expect("mint must fund the wallet");
        assert!(seller.balance().await.unwrap() >= 8);

        let (seller_sk, seller_pk) = party();
        let (_buyer_sk, buyer_pk) = party();
        let (_mostro_sk, mostro_pk) = party();
        let parties = EscrowParties::from_xonly_hex(&buyer_pk, &seller_pk, &mostro_pk).unwrap();
        let token = seller
            .build_escrow_token(8, &parties, future_locktime())
            .await
            .unwrap();

        // Act — the seller tries to take it back with only their own signature,
        // before the locktime.
        let err = seller
            .reclaim_after_locktime(&token, seller_sk)
            .await
            .unwrap_err();

        // Assert — refused before the mint is even contacted: the locktime is in
        // the secret, so the client can say how long is left instead of
        // relaying an opaque mint error. Either refusal proves the property.
        assert!(
            err.to_string().contains("CashuLocktimeNotReached")
                || err.to_string().contains("CashuReclaimFailed"),
            "got {err}"
        );

        let _ = std::fs::remove_file(&seller_db);
    }

    #[tokio::test]
    #[ignore = "requires a local nutshell mint (MOSTRO_TEST_MINT_URL)"]
    async fn a_signature_from_the_wrong_key_does_not_settle_an_escrow() {
        // Arrange — an attacker holding neither trade key.
        let mint = test_mint_url();
        let seller_db = temp_db_path();
        let buyer_db = temp_db_path();
        let seller = CashuWallet::connect(&mint, unique_seed(), seller_db.to_str().unwrap())
            .await
            .unwrap();
        let buyer = CashuWallet::connect(&mint, unique_seed(), buyer_db.to_str().unwrap())
            .await
            .unwrap();
        seller.mint_for_test(64).await.expect("mint must fund the wallet");
        assert!(seller.balance().await.unwrap() >= 8);

        let (_seller_sk, seller_pk) = party();
        let (buyer_sk, buyer_pk) = party();
        let (_mostro_sk, mostro_pk) = party();
        let (impostor_sk, _) = party();
        let parties = EscrowParties::from_xonly_hex(&buyer_pk, &seller_pk, &mostro_pk).unwrap();
        let token = seller
            .build_escrow_token(8, &parties, future_locktime())
            .await
            .unwrap();

        // Act — buyer combines their own valid signature with an impostor's.
        let impostor_sigs = seller.sign_proofs(&token, impostor_sk).await.unwrap();
        let err = buyer
            .combine_and_redeem(&token, buyer_sk, &impostor_sigs)
            .await
            .unwrap_err();

        // Assert
        assert!(err.to_string().contains("CashuRedeemFailed"), "got {err}");

        let _ = std::fs::remove_file(&seller_db);
        let _ = std::fs::remove_file(&buyer_db);
    }

    #[tokio::test]
    #[ignore = "requires a local nutshell mint (MOSTRO_TEST_MINT_URL)"]
    async fn an_escrow_for_the_wrong_amount_fails_verification() {
        // Arrange — a seller who locks less than the order calls for.
        let mint = test_mint_url();
        let seller_db = temp_db_path();
        let seller = CashuWallet::connect(&mint, unique_seed(), seller_db.to_str().unwrap())
            .await
            .unwrap();
        seller.mint_for_test(64).await.expect("mint must fund the wallet");
        assert!(seller.balance().await.unwrap() >= 8);

        let (_seller_sk, seller_pk) = party();
        let (_buyer_sk, buyer_pk) = party();
        let (_mostro_sk, mostro_pk) = party();
        let parties = EscrowParties::from_xonly_hex(&buyer_pk, &seller_pk, &mostro_pk).unwrap();
        let locktime = future_locktime();
        let token = seller
            .build_escrow_token(8, &parties, locktime)
            .await
            .unwrap();

        // Act — the buyer checks it against the amount they expect.
        let err = seller
            .verify_escrow_token(&token, &parties, 16, locktime)
            .await
            .unwrap_err();

        // Assert
        assert!(
            err.to_string().contains("expected 16 sat, got 8"),
            "got {err}"
        );

        let _ = std::fs::remove_file(&seller_db);
    }

    #[test]
    fn three_parties_must_be_three_different_keys() {
        // Arrange — a duplicate collapses the 2-of-3 into something weaker, and
        // whether one signature then satisfies n_sigs=2 is up to the mint.
        let shared = xonly();
        let third = xonly();

        // Act / Assert — rejected at construction, so a degenerate set never
        // reaches the condition builder.
        for (buyer, seller, mostro, label) in [
            (shared.clone(), shared.clone(), third.clone(), "buyer == seller"),
            (shared.clone(), third.clone(), shared.clone(), "buyer == mostro"),
            (third.clone(), shared.clone(), shared.clone(), "seller == mostro"),
        ] {
            let err = EscrowParties::from_xonly_hex(&buyer, &seller, &mostro).unwrap_err();
            assert!(
                err.to_string().contains("InvalidEscrowParties"),
                "{label}: got {err}"
            );
        }
    }

    #[test]
    fn a_missing_counterparty_key_is_refused() {
        // Arrange — Mostro left out, so buyer and seller could settle without
        // the arbitrator ever being able to intervene.
        let parties = parties();
        let locktime = future_locktime();
        let conditions = SpendingConditions::P2PKConditions {
            data: parties.seller,
            conditions: Some(
                Conditions::new(
                    Some(locktime),
                    Some(vec![parties.buyer]),
                    Some(vec![parties.seller]),
                    Some(2),
                    Some(SigFlag::SigInputs),
                    Some(1),
                )
                .unwrap(),
            ),
        };

        // Act / Assert — the exact-count check catches this first, which is
        // fine: both messages say the key set is not the one this trade needs.
        let err = verify_conditions(&conditions, &parties, locktime).unwrap_err();
        assert!(
            err.to_string().contains("expected exactly 2 additional pubkeys"),
            "got {err}"
        );

        // And with the right *count* but the wrong key, the membership check
        // is the one that fires.
        let wrong_key = SpendingConditions::P2PKConditions {
            data: parties.seller,
            conditions: Some(
                Conditions::new(
                    Some(locktime),
                    Some(vec![parties.buyer, SecretKey::generate().public_key()]),
                    Some(vec![parties.seller]),
                    Some(2),
                    Some(SigFlag::SigInputs),
                    Some(1),
                )
                .unwrap(),
            ),
        };
        let err = verify_conditions(&wrong_key, &parties, locktime).unwrap_err();
        assert!(
            err.to_string().contains("buyer or Mostro key missing"),
            "got {err}"
        );
    }
}
