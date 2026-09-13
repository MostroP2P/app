//! Payout claims on slashed bonds (`docs/ANTI_ABUSE_BOND.md` §6.4): the
//! phase machine the `add-bond-invoice` cadence drives, the local
//! resolution of a `CantDo` on a submission, and the set of nodes whose
//! claim traffic the kind-14 filter must keep receiving after a node switch.
//!
//! Protocol state, not bridge surface (#120): `api/bond.rs` owns the calls
//! Dart makes and the persistence; everything here is pure or in-memory.

use std::collections::HashSet;
use std::sync::{OnceLock, RwLock};

use crate::api::types::{BondClaim, BondClaimPhase};

/// The claim window when the node advertises none (§6.4).
pub const DEFAULT_CLAIM_WINDOW_DAYS: u32 = 15;

/// `slashed_at + window`, the deadline frozen into a claim at first receipt.
pub fn claim_deadline(slashed_at: i64, window_days: Option<u32>) -> i64 {
    let days = i64::from(window_days.unwrap_or(DEFAULT_CLAIM_WINDOW_DAYS));
    slashed_at.saturating_add(days.saturating_mul(86_400))
}

/// What an `add-bond-invoice` carries, reduced to what the claim keeps.
#[derive(Debug, Clone, PartialEq)]
pub struct PayoutRequest {
    pub order_id: String,
    pub node_pubkey: String,
    pub amount_sats: u64,
    pub slashed_at: i64,
    pub fiat_code: String,
    pub fiat_amount: Option<f64>,
    pub payment_method: String,
}

/// Why the user should hear about a claim after an `add-bond-invoice`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClaimNotice {
    /// A share is on offer for the first time.
    New,
    /// The daemon accepted an invoice, could not pay it, and asks again.
    Reprompt,
}

/// The phase-aware upsert of §6.4, on the claim as stored (`None` for a
/// first receipt). Returns the claim to persist — `None` when nothing
/// changes — and whether the user should be told.
///
/// | stored | result |
/// |---|---|
/// | none | `Pending` (`Expired` when already past the deadline on arrival) |
/// | `Pending` / `Submitted` | no-op: a cadence retry, or one that crossed our reply |
/// | `Acknowledged` | re-prompt: back to `Pending`, invoice cleared, notify |
/// | `Completed` | ignored: the daemon never re-prompts a paid bond |
/// | `Expired` | re-evaluated against the frozen deadline |
///
/// A different `slashed_at` for the same order replaces the claim outright.
pub fn upsert_claim(
    stored: Option<&BondClaim>,
    request: &PayoutRequest,
    window_days: Option<u32>,
    now: i64,
) -> (Option<BondClaim>, Option<ClaimNotice>) {
    let fresh = |deadline_at: i64| {
        let expired = now > deadline_at;
        BondClaim {
            order_id: request.order_id.clone(),
            node_pubkey: request.node_pubkey.clone(),
            amount_sats: request.amount_sats,
            slashed_at: request.slashed_at,
            deadline_at,
            phase: if expired {
                BondClaimPhase::Expired
            } else {
                BondClaimPhase::Pending
            },
            submitted_invoice: None,
            fiat_code: request.fiat_code.clone(),
            fiat_amount: request.fiat_amount,
            payment_method: request.payment_method.clone(),
            updated_at: now,
        }
    };
    let Some(stored) = stored else {
        let claim = fresh(claim_deadline(request.slashed_at, window_days));
        let notice = (claim.phase == BondClaimPhase::Pending).then_some(ClaimNotice::New);
        return (Some(claim), notice);
    };
    if stored.slashed_at != request.slashed_at {
        let claim = fresh(claim_deadline(request.slashed_at, window_days));
        let notice = (claim.phase == BondClaimPhase::Pending).then_some(ClaimNotice::New);
        return (Some(claim), notice);
    }
    match stored.phase {
        BondClaimPhase::Pending | BondClaimPhase::Submitted | BondClaimPhase::Completed => {
            (None, None)
        }
        BondClaimPhase::Acknowledged => {
            let mut claim = stored.clone();
            claim.phase = BondClaimPhase::Pending;
            claim.submitted_invoice = None;
            claim.updated_at = now;
            (Some(claim), Some(ClaimNotice::Reprompt))
        }
        BondClaimPhase::Expired => {
            if now > stored.deadline_at {
                return (None, None);
            }
            let mut claim = stored.clone();
            claim.phase = BondClaimPhase::Pending;
            claim.updated_at = now;
            (Some(claim), Some(ClaimNotice::New))
        }
    }
}

/// How a `CantDo` answering the submission resolves locally (§6.4): the
/// daemon's verdict carries no detail, so the claim decides from what it
/// knows. `Ok(phase)` is the phase to persist; `Err(marker)` is the
/// stable marker Dart maps to copy.
pub fn resolve_submission_rejection(claim: &BondClaim, now: i64) -> Result<BondClaimPhase, &'static str> {
    match claim.phase {
        BondClaimPhase::Acknowledged | BondClaimPhase::Completed => Ok(claim.phase),
        _ if now > claim.deadline_at => Ok(BondClaimPhase::Expired),
        _ => Err("BondClaimRejected"),
    }
}

// ── Nodes with open claims ──────────────────────────────────────────────────

fn claim_nodes() -> &'static RwLock<HashSet<String>> {
    static NODES: OnceLock<RwLock<HashSet<String>>> = OnceLock::new();
    NODES.get_or_init(|| RwLock::new(HashSet::new()))
}

/// Replace the set of nodes holding a non-terminal claim with `nodes`.
pub fn set_claim_nodes<I: IntoIterator<Item = String>>(nodes: I) {
    if let Ok(mut set) = claim_nodes().write() {
        *set = nodes.into_iter().collect();
    }
}

/// The nodes whose kind-14 traffic the daemon filter must include besides
/// the active one: their retries and acknowledgements keep arriving after
/// a node switch (§6.4).
pub fn claim_node_pubkeys() -> Vec<String> {
    claim_nodes()
        .read()
        .map(|set| set.iter().cloned().collect())
        .unwrap_or_default()
}

/// Whether `pubkey_hex` is a node with an open claim.
pub fn is_claim_node(pubkey_hex: &str) -> bool {
    claim_nodes()
        .read()
        .map(|set| set.contains(pubkey_hex))
        .unwrap_or(false)
}

/// The set as derived from the store: every node with a claim that is not
/// `Completed` or `Expired`.
pub fn claim_nodes_of(claims: &[BondClaim]) -> HashSet<String> {
    claims
        .iter()
        .filter(|c| !c.phase.is_terminal())
        .map(|c| c.node_pubkey.clone())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(slashed_at: i64) -> PayoutRequest {
        PayoutRequest {
            order_id: "order-1".into(),
            node_pubkey: "node-a".into(),
            amount_sats: 1_500,
            slashed_at,
            fiat_code: "VES".into(),
            fiat_amount: Some(100.0),
            payment_method: "PagoMovil".into(),
        }
    }

    fn stored(phase: BondClaimPhase) -> BondClaim {
        BondClaim {
            order_id: "order-1".into(),
            node_pubkey: "node-a".into(),
            amount_sats: 1_500,
            slashed_at: 1_000,
            deadline_at: 1_000 + 15 * 86_400,
            phase,
            submitted_invoice: Some("lnbc1x".into()),
            fiat_code: "VES".into(),
            fiat_amount: Some(100.0),
            payment_method: "PagoMovil".into(),
            updated_at: 5,
        }
    }

    #[test]
    fn the_deadline_is_the_slash_plus_the_window_defaulting_to_fifteen_days() {
        assert_eq!(claim_deadline(1_000, Some(3)), 1_000 + 3 * 86_400);
        assert_eq!(claim_deadline(1_000, None), 1_000 + 15 * 86_400);
    }

    #[test]
    fn a_first_receipt_is_pending_with_a_frozen_deadline_and_a_notice() {
        let (claim, notice) = upsert_claim(None, &request(1_000), Some(7), 2_000);
        let claim = claim.expect("persisted");
        assert_eq!(claim.phase, BondClaimPhase::Pending);
        assert_eq!(claim.deadline_at, 1_000 + 7 * 86_400);
        assert_eq!(claim.updated_at, 2_000);
        assert_eq!(notice, Some(ClaimNotice::New));
    }

    #[test]
    fn a_request_already_past_its_deadline_is_expired_and_silent() {
        let late = 1_000 + 15 * 86_400 + 1;
        let (claim, notice) = upsert_claim(None, &request(1_000), None, late);
        assert_eq!(claim.unwrap().phase, BondClaimPhase::Expired);
        assert_eq!(notice, None);
    }

    #[test]
    fn cadence_retries_are_no_ops_while_pending_or_submitted_or_paid() {
        for phase in [
            BondClaimPhase::Pending,
            BondClaimPhase::Submitted,
            BondClaimPhase::Completed,
        ] {
            let (claim, notice) = upsert_claim(Some(&stored(phase)), &request(1_000), None, 3_000);
            assert_eq!(claim, None, "{phase:?}");
            assert_eq!(notice, None);
        }
    }

    #[test]
    fn an_acknowledged_claim_is_re_prompted() {
        let (claim, notice) = upsert_claim(
            Some(&stored(BondClaimPhase::Acknowledged)),
            &request(1_000),
            None,
            3_000,
        );
        let claim = claim.expect("persisted");
        assert_eq!(claim.phase, BondClaimPhase::Pending);
        assert_eq!(claim.submitted_invoice, None);
        assert_eq!(claim.deadline_at, 1_000 + 15 * 86_400, "the deadline stays frozen");
        assert_eq!(notice, Some(ClaimNotice::Reprompt));
    }

    #[test]
    fn an_expired_claim_is_re_evaluated_against_its_frozen_deadline() {
        let (claim, _) = upsert_claim(Some(&stored(BondClaimPhase::Expired)), &request(1_000), None, 2_000);
        assert_eq!(claim.unwrap().phase, BondClaimPhase::Pending, "the clock was wrong");
        let late = 1_000 + 15 * 86_400 + 1;
        let (claim, notice) = upsert_claim(Some(&stored(BondClaimPhase::Expired)), &request(1_000), None, late);
        assert_eq!(claim, None);
        assert_eq!(notice, None);
    }

    #[test]
    fn a_different_slash_anchor_replaces_the_claim() {
        let (claim, notice) = upsert_claim(
            Some(&stored(BondClaimPhase::Completed)),
            &request(9_000),
            Some(1),
            9_500,
        );
        let claim = claim.expect("replaced");
        assert_eq!(claim.slashed_at, 9_000);
        assert_eq!(claim.deadline_at, 9_000 + 86_400);
        assert_eq!(claim.phase, BondClaimPhase::Pending);
        assert_eq!(notice, Some(ClaimNotice::New));
    }

    #[test]
    fn a_rejected_submission_resolves_from_what_the_claim_knows() {
        assert_eq!(
            resolve_submission_rejection(&stored(BondClaimPhase::Submitted), 2_000),
            Err("BondClaimRejected")
        );
        let late = 1_000 + 15 * 86_400 + 1;
        assert_eq!(
            resolve_submission_rejection(&stored(BondClaimPhase::Submitted), late),
            Ok(BondClaimPhase::Expired)
        );
        assert_eq!(
            resolve_submission_rejection(&stored(BondClaimPhase::Acknowledged), late),
            Ok(BondClaimPhase::Acknowledged)
        );
        assert_eq!(
            resolve_submission_rejection(&stored(BondClaimPhase::Completed), 2_000),
            Ok(BondClaimPhase::Completed)
        );
    }

    #[test]
    fn only_open_claims_keep_their_node_on_the_filter() {
        let mut done = stored(BondClaimPhase::Completed);
        done.node_pubkey = "node-done".into();
        let mut gone = stored(BondClaimPhase::Expired);
        gone.node_pubkey = "node-gone".into();
        let nodes = claim_nodes_of(&[stored(BondClaimPhase::Pending), done, gone]);
        assert_eq!(nodes, HashSet::from(["node-a".to_string()]));
        set_claim_nodes(nodes);
        assert!(is_claim_node("node-a"));
        assert!(!is_claim_node("node-done"));
        assert_eq!(claim_node_pubkeys(), vec!["node-a".to_string()]);
        set_claim_nodes(Vec::<String>::new());
    }
}
