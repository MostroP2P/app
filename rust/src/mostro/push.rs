//! Push registration rules (docs/PUSH_NOTIFICATIONS.md §7.1, §8.1).
//!
//! Which trade pubkeys the push server should hold a token for, when each
//! one must be (re-)registered, and when one is let go. Pure: every function
//! here takes what it needs as arguments and returns a decision; the I/O —
//! reading the trade rows, calling the server, persisting the map — lives in
//! `api::push`. That split is what makes every rule below testable without a
//! database or a network, and what keeps the rules from drifting between the
//! startup, resume, timer and event-driven callers: they all run the same
//! `plan`.
//!
//! The server forgets a token 48 h after its last registration and on every
//! restart, silently, and holds one token per pubkey. The client therefore
//! refreshes periodically rather than on events, treats every `200` as an
//! overwrite, and keeps a persisted record of what it registered so a
//! restart, a token refresh or an opt-out act on the full set.

use std::collections::HashMap;

use sha2::{Digest, Sha256};

use crate::api::types::{BondClaim, TradeInfo};
use crate::mostro::status::is_hard_terminal;

/// A registration older than this is re-sent: a quarter of the server's
/// 48 h TTL, so two consecutive misses still leave a margin.
pub const REFRESH_SECS: i64 = 12 * 3600;

/// How long a key stays registered after it left the wanted set. Covers what
/// still arrives after a terminal status: `rate-received`, a late
/// `bond-slashed`, an admin outcome, the daemon's `Success` after
/// `SettledHoldInvoice`.
pub const GRACE_SECS: i64 = 24 * 3600;

/// How long a `403` from the operator keeps a node's keys unregistered
/// before the next reconcile retries once.
pub const NODE_REFUSAL_SECS: i64 = 24 * 3600;

/// At most one `/api/notify` per peer per this many seconds: a burst of
/// short messages costs one wake and stays far under the server's 30/min.
pub const NOTIFY_DEBOUNCE_SECS: i64 = 10;

/// One trade pubkey the push server holds (or held) a token for, as
/// persisted in the `push_registrations` map.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct PushRegistration {
    /// 64 lowercase hex.
    pub trade_pubkey: String,
    /// The client's clock when the last `200` arrived. The response carries
    /// no server time, and the same clock is `now` in every rule here; a
    /// clock that reads earlier than this is a rollback and the key is due
    /// at once rather than "12 h after a future date".
    pub registered_at: i64,
    /// Hash of the device token the last `200` was for; a different token
    /// means the server holds a stale one.
    pub token_hash: String,
    /// The issuing node the registration was filed under (`mostro_pubkey`).
    pub mostro_pubkey: String,
    /// The first reconcile that found the key outside the wanted set; the
    /// grace clock. `None` while wanted.
    #[serde(default)]
    pub unwanted_since: Option<i64>,
    /// Consecutive failures since the last `200`; drives [`backoff`].
    #[serde(default)]
    pub attempts: u32,
    /// Not before this may the next attempt run, after a failure or a `429`.
    #[serde(default)]
    pub next_attempt_at: i64,
}

impl PushRegistration {
    /// A registration the server just accepted.
    pub fn accepted(trade_pubkey: &str, mostro_pubkey: &str, token_hash: &str, now: i64) -> Self {
        Self {
            trade_pubkey: trade_pubkey.to_string(),
            registered_at: now,
            token_hash: token_hash.to_string(),
            mostro_pubkey: mostro_pubkey.to_string(),
            unwanted_since: None,
            attempts: 0,
            next_attempt_at: 0,
        }
    }

    /// The server accepted a (re-)registration for this key.
    pub fn note_accepted(&mut self, mostro_pubkey: &str, token_hash: &str, now: i64) {
        self.registered_at = now;
        self.token_hash = token_hash.to_string();
        self.mostro_pubkey = mostro_pubkey.to_string();
        self.attempts = 0;
        self.next_attempt_at = 0;
    }

    /// An attempt failed (transport error, `5xx`, or a `429` whose
    /// `Retry-After` is `retry_after`): back off.
    pub fn note_failed(&mut self, now: i64, retry_after: Option<i64>) {
        self.attempts = self.attempts.saturating_add(1);
        let wait = retry_after.unwrap_or_else(|| backoff_secs(self.attempts));
        self.next_attempt_at = now.saturating_add(wait);
    }

    /// A placeholder for a key the server has not accepted yet, so a failed
    /// first attempt has somewhere to record its backoff.
    pub fn pending(trade_pubkey: &str, mostro_pubkey: &str) -> Self {
        Self {
            trade_pubkey: trade_pubkey.to_string(),
            registered_at: 0,
            token_hash: String::new(),
            mostro_pubkey: mostro_pubkey.to_string(),
            unwanted_since: None,
            attempts: 0,
            next_attempt_at: 0,
        }
    }

    /// Whether the server ever accepted this key with any token.
    pub fn is_registered(&self) -> bool {
        self.registered_at > 0 && !self.token_hash.is_empty()
    }
}

/// What the push server should hold: pubkey (hex) → the node that issued it.
pub type Wanted = HashMap<String, String>;

/// The keys the push server should hold a token for right now (§7.1): the
/// trade key of every trade row that is not hard-terminal, and the key each
/// open payout claim was addressed to. Never "every key ever derived".
///
/// A live dispute adds nothing: its row reads `Dispute`, which is not
/// terminal, and an admin outcome ends the dispute along with the row. The
/// in-memory dispute record is not consulted on purpose — one an admin
/// outcome never marked resolved would otherwise keep a finished trade's key
/// registered for good. What still arrives after the outcome is covered by
/// the grace.
///
/// `key_for(index)` derives the pubkey for a trade-key index; `None` when it
/// cannot (the identity is not loaded) drops that key from the set rather
/// than registering a placeholder. `active_node` stands in for a row whose
/// `creator_pubkey` is empty — a maker row written before the node was
/// recorded on it — and for nothing else.
pub fn wanted_pubkeys(
    trades: &[TradeInfo],
    claims: &[BondClaim],
    active_node: &str,
    key_for: impl Fn(u32) -> Option<String>,
) -> Wanted {
    let mut wanted = Wanted::new();
    let mut key_of_order: HashMap<&str, u32> = HashMap::new();
    for trade in trades {
        key_of_order.insert(trade.order.id.as_str(), trade.trade_key_index);
        if is_hard_terminal(&trade.order.status) {
            continue;
        }
        let Some(pubkey) = key_for(trade.trade_key_index) else {
            continue;
        };
        let node = if trade.order.creator_pubkey.is_empty() {
            active_node
        } else {
            trade.order.creator_pubkey.as_str()
        };
        wanted.insert(pubkey.to_lowercase(), node.to_lowercase());
    }
    for claim in claims {
        if claim.phase.is_terminal() {
            continue;
        }
        // The key the request was addressed to; an old claim stored before
        // the index was recorded falls back to the order's current key.
        let index = claim
            .trade_index
            .or_else(|| key_of_order.get(claim.order_id.as_str()).copied());
        let Some(pubkey) = index.and_then(&key_for) else {
            continue;
        };
        wanted
            .entry(pubkey.to_lowercase())
            .or_insert_with(|| claim.node_pubkey.to_lowercase());
    }
    wanted
}

/// One step the reconcile must take. State changes are actions too, so the
/// caller applies and persists them in one place and the rules stay pure.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    /// `POST /api/register` for this key under this node.
    Register {
        trade_pubkey: String,
        mostro_pubkey: String,
    },
    /// `POST /api/unregister`; on `200` the caller forgets the key.
    Unregister { trade_pubkey: String },
    /// A registered key left the wanted set just now: start its grace clock.
    NoteUnwanted { trade_pubkey: String },
    /// A key with a running grace clock is wanted again: clear the clock.
    NoteWanted { trade_pubkey: String },
    /// A key the server never accepted and nobody wants any more: drop the
    /// record without a request.
    Forget { trade_pubkey: String },
}

/// Nodes the operator refused, node (hex) → unix seconds of the `403`.
pub type Refusals = HashMap<String, i64>;

/// Whether a `403` recorded at `refused_at` still suppresses registration.
pub fn refusal_active(refused_at: i64, now: i64) -> bool {
    now < refused_at.saturating_add(NODE_REFUSAL_SECS)
}

/// Decide what to do, given what is wanted and what the server holds.
///
/// Every rule of §7.1, in one place:
///
/// - a wanted key is registered when the server never accepted it, when it
///   was accepted with another token or filed under another node (a legacy
///   maker row resolves to the active node, which a switch changes), when
///   its registration is older than
///   [`REFRESH_SECS`], or when the clock reads earlier than its
///   `registered_at` (a rollback); a failed attempt is retried only once its
///   backoff has passed; a key issued by a node under an active refusal is
///   skipped;
/// - a registered key that is not wanted starts its grace clock, is left
///   alone inside [`GRACE_SECS`], and is unregistered past it; a key that
///   comes back into the wanted set has its clock cleared;
/// - a record the server never accepted is simply forgotten once unwanted.
///
/// Registration and delivery coverage come from one source: `wanted` is
/// built from the same rows the kind-14 filter is built from.
pub fn plan(
    wanted: &Wanted,
    registrations: &HashMap<String, PushRegistration>,
    token_hash: &str,
    refusals: &Refusals,
    now: i64,
) -> Vec<Action> {
    let mut actions = Vec::new();
    let mut keys: Vec<&String> = wanted.keys().collect();
    keys.sort();
    for pubkey in keys {
        let node = &wanted[pubkey];
        let reg = registrations.get(pubkey);
        if reg.is_some_and(|r| r.unwanted_since.is_some()) {
            actions.push(Action::NoteWanted {
                trade_pubkey: pubkey.clone(),
            });
        }
        if refusals
            .get(node)
            .is_some_and(|refused_at| refusal_active(*refused_at, now))
        {
            continue;
        }
        let due = match reg {
            None => true,
            Some(r) => {
                !r.is_registered()
                    || r.token_hash != token_hash
                    || r.mostro_pubkey != *node
                    || now < r.registered_at
                    || now - r.registered_at >= REFRESH_SECS
                    || r.attempts > 0
            }
        };
        let backing_off = reg.is_some_and(|r| r.attempts > 0 && now < r.next_attempt_at);
        if due && !backing_off {
            actions.push(Action::Register {
                trade_pubkey: pubkey.clone(),
                mostro_pubkey: node.clone(),
            });
        }
    }

    let mut stale: Vec<&PushRegistration> = registrations
        .values()
        .filter(|r| !wanted.contains_key(&r.trade_pubkey))
        .collect();
    stale.sort_by(|a, b| a.trade_pubkey.cmp(&b.trade_pubkey));
    for reg in stale {
        let pubkey = reg.trade_pubkey.clone();
        if !reg.is_registered() {
            actions.push(Action::Forget {
                trade_pubkey: pubkey,
            });
            continue;
        }
        match reg.unwanted_since {
            None => actions.push(Action::NoteUnwanted {
                trade_pubkey: pubkey,
            }),
            Some(since) if now - since > GRACE_SECS => {
                if !(reg.attempts > 0 && now < reg.next_attempt_at) {
                    actions.push(Action::Unregister {
                        trade_pubkey: pubkey,
                    });
                }
            }
            Some(_) => {}
        }
    }
    actions
}

/// Seconds to wait after the `attempts`-th consecutive failure:
/// 1 min → 5 min → 30 min → 2 h, capped there.
pub fn backoff_secs(attempts: u32) -> i64 {
    match attempts {
        0 | 1 => 60,
        2 => 5 * 60,
        3 => 30 * 60,
        _ => 2 * 3600,
    }
}

/// Whether a `/api/notify` for a peer may go out now, given when the last
/// one for the same peer went (§7.3).
pub fn notify_allowed(last_notify_at: Option<i64>, now: i64) -> bool {
    match last_notify_at {
        None => true,
        Some(last) => now - last >= NOTIFY_DEBOUNCE_SECS || now < last,
    }
}

/// The device token as it is recorded in a registration: never the token
/// itself, which is a credential, only enough to tell two tokens apart.
pub fn token_hash(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::{BondClaimPhase, OrderKind, OrderStatus, TradeRole, TradeStep};

    const NOW: i64 = 1_800_000_000;
    const NODE_A: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const NODE_B: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

    fn key(index: u32) -> Option<String> {
        Some(format!("{index:02x}").repeat(32))
    }

    fn trade(id: &str, index: u32, status: OrderStatus, node: &str) -> TradeInfo {
        TradeInfo {
            id: id.to_string(),
            order: crate::api::types::OrderInfo {
                id: id.to_string(),
                kind: OrderKind::Sell,
                status,
                amount_sats: None,
                fiat_amount: None,
                fiat_amount_min: None,
                fiat_amount_max: None,
                fiat_code: "USD".into(),
                payment_method: "x".into(),
                premium: 0.0,
                creator_pubkey: node.to_string(),
                created_at: 0,
                expires_at: None,
                is_mine: false,
                rating: 0.0,
                total_reviews: 0,
                days_active: 0,
            },
            role: TradeRole::Buyer,
            counterparty_pubkey: String::new(),
            current_step: TradeStep::Disputed,
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: index,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 0,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
            bond: None,
        }
    }

    fn claim(order: &str, index: Option<u32>, phase: BondClaimPhase, node: &str) -> BondClaim {
        BondClaim {
            order_id: order.to_string(),
            node_pubkey: node.to_string(),
            trade_index: index,
            amount_sats: 1,
            slashed_at: 0,
            deadline_at: 0,
            phase,
            submitted_invoice: None,
            fiat_code: "USD".into(),
            fiat_amount: None,
            payment_method: "x".into(),
            updated_at: 0,
        }
    }

    fn registered(pubkey: &str, age: i64) -> PushRegistration {
        PushRegistration::accepted(pubkey, NODE_A, "tok", NOW - age)
    }

    fn regs(list: Vec<PushRegistration>) -> HashMap<String, PushRegistration> {
        list.into_iter()
            .map(|r| (r.trade_pubkey.clone(), r))
            .collect()
    }

    fn register_for<'a>(actions: &'a [Action], pubkey: &str) -> Option<&'a Action> {
        actions
            .iter()
            .find(|a| matches!(a, Action::Register { trade_pubkey, .. } if trade_pubkey == pubkey))
    }

    // ── wanted_pubkeys: the base set ─────────────────────────────────────

    #[test]
    fn live_rows_are_wanted_and_hard_terminal_rows_are_not() {
        let trades = vec![
            trade("o1", 1, OrderStatus::Active, NODE_A),
            trade("o2", 2, OrderStatus::WaitingTakerBond, NODE_A),
            trade("o3", 3, OrderStatus::Success, NODE_A),
            trade("o4", 4, OrderStatus::Canceled, NODE_A),
            trade("o5", 5, OrderStatus::SettledHoldInvoice, NODE_A),
        ];
        let wanted = wanted_pubkeys(&trades, &[], NODE_B, key);
        let mut keys: Vec<_> = wanted.keys().cloned().collect();
        keys.sort();
        assert_eq!(
            keys,
            vec![key(1).unwrap(), key(2).unwrap(), key(5).unwrap()]
        );
        assert_eq!(
            wanted[&key(1).unwrap()],
            NODE_A,
            "the issuing node from the row"
        );
    }

    #[test]
    fn an_admin_outcome_ends_the_dispute_and_the_key_with_it() {
        // The row is what says whether the trade is over; a dispute record
        // that was never marked resolved must not keep the key registered.
        let trades = vec![
            trade("o1", 1, OrderStatus::Dispute, NODE_A),
            trade("o2", 2, OrderStatus::SettledByAdmin, NODE_A),
            trade("o3", 3, OrderStatus::CanceledByAdmin, NODE_A),
        ];
        let wanted = wanted_pubkeys(&trades, &[], NODE_B, key);
        assert!(
            wanted.contains_key(&key(1).unwrap()),
            "a live dispute row is live"
        );
        assert!(!wanted.contains_key(&key(2).unwrap()));
        assert!(!wanted.contains_key(&key(3).unwrap()));
    }

    #[test]
    fn an_open_claim_wants_the_key_it_was_addressed_to_under_its_node() {
        let claims = vec![
            claim("o1", Some(7), BondClaimPhase::Pending, NODE_B),
            claim("o2", Some(8), BondClaimPhase::Completed, NODE_B),
            claim("o3", Some(9), BondClaimPhase::Expired, NODE_B),
        ];
        let wanted = wanted_pubkeys(&[], &claims, NODE_A, key);
        assert_eq!(wanted.len(), 1);
        assert_eq!(wanted[&key(7).unwrap()], NODE_B);
    }

    #[test]
    fn an_old_claim_without_an_index_falls_back_to_the_orders_key() {
        let trades = vec![trade("o1", 3, OrderStatus::Success, NODE_A)];
        let claims = vec![claim("o1", None, BondClaimPhase::Acknowledged, NODE_A)];
        let wanted = wanted_pubkeys(&trades, &claims, NODE_A, key);
        assert!(wanted.contains_key(&key(3).unwrap()));
        let orphan = vec![claim("o9", None, BondClaimPhase::Pending, NODE_A)];
        assert!(wanted_pubkeys(&[], &orphan, NODE_A, key).is_empty());
    }

    #[test]
    fn a_node_switch_changes_nothing_and_an_empty_creator_reads_as_the_active_node() {
        let trades = vec![
            trade("o1", 1, OrderStatus::Active, NODE_A),
            trade("o2", 2, OrderStatus::WaitingMakerBond, ""),
        ];
        let before = wanted_pubkeys(&trades, &[], NODE_A, key);
        let after = wanted_pubkeys(&trades, &[], NODE_B, key);
        assert_eq!(before[&key(1).unwrap()], NODE_A);
        assert_eq!(
            after[&key(1).unwrap()],
            NODE_A,
            "a taken order keeps its issuing node"
        );
        assert_eq!(before[&key(2).unwrap()], NODE_A);
        assert_eq!(
            after[&key(2).unwrap()],
            NODE_B,
            "a legacy maker row reads as the active node"
        );
    }

    #[test]
    fn a_key_that_cannot_be_derived_is_dropped_not_registered_blank() {
        let trades = vec![trade("o1", 1, OrderStatus::Active, NODE_A)];
        assert!(wanted_pubkeys(&trades, &[], NODE_A, |_| None).is_empty());
    }

    #[test]
    fn pubkeys_and_nodes_are_lowercased() {
        let trades = vec![trade("o1", 1, OrderStatus::Active, "AA")];
        let wanted = wanted_pubkeys(&trades, &[], NODE_A, |_| Some("ABCD".into()));
        assert_eq!(wanted.get("abcd").map(String::as_str), Some("aa"));
    }

    // ── plan: registration ───────────────────────────────────────────────

    #[test]
    fn a_wanted_key_the_server_never_accepted_is_registered() {
        let wanted = Wanted::from([(key(1).unwrap(), NODE_A.to_string())]);
        let actions = plan(&wanted, &HashMap::new(), "tok", &Refusals::new(), NOW);
        assert_eq!(
            actions,
            vec![Action::Register {
                trade_pubkey: key(1).unwrap(),
                mostro_pubkey: NODE_A.to_string()
            }]
        );
    }

    #[test]
    fn a_fresh_registration_with_the_same_token_is_left_alone() {
        let k = key(1).unwrap();
        let wanted = Wanted::from([(k.clone(), NODE_A.to_string())]);
        let regs = regs(vec![registered(&k, REFRESH_SECS - 1)]);
        assert!(plan(&wanted, &regs, "tok", &Refusals::new(), NOW).is_empty());
    }

    #[test]
    fn a_registration_older_than_the_refresh_is_re_sent() {
        let k = key(1).unwrap();
        let wanted = Wanted::from([(k.clone(), NODE_A.to_string())]);
        let regs = regs(vec![registered(&k, REFRESH_SECS)]);
        assert!(register_for(&plan(&wanted, &regs, "tok", &Refusals::new(), NOW), &k).is_some());
    }

    #[test]
    fn a_clock_rollback_makes_the_key_due_at_once() {
        let k = key(1).unwrap();
        let wanted = Wanted::from([(k.clone(), NODE_A.to_string())]);
        // Registered "in the future": the clock went backwards since.
        let regs = regs(vec![registered(&k, -3600)]);
        assert!(register_for(&plan(&wanted, &regs, "tok", &Refusals::new(), NOW), &k).is_some());
    }

    #[test]
    fn a_different_token_re_registers_every_key() {
        let (k1, k2) = (key(1).unwrap(), key(2).unwrap());
        let wanted = Wanted::from([
            (k1.clone(), NODE_A.to_string()),
            (k2.clone(), NODE_A.to_string()),
        ]);
        let regs = regs(vec![registered(&k1, 10), registered(&k2, 10)]);
        let actions = plan(&wanted, &regs, "new-token", &Refusals::new(), NOW);
        assert!(register_for(&actions, &k1).is_some());
        assert!(register_for(&actions, &k2).is_some());
    }

    #[test]
    fn a_key_wanted_under_another_node_is_re_registered_at_once() {
        // A legacy maker row reads as the active node; after a switch the key
        // is the same but its node is not, and the server must hold it under
        // the node that now owns it rather than until the next refresh.
        let k = key(1).unwrap();
        let wanted = Wanted::from([(k.clone(), NODE_B.to_string())]);
        let regs = regs(vec![registered(&k, 10)]);
        let actions = plan(&wanted, &regs, "tok", &Refusals::new(), NOW);
        assert_eq!(
            register_for(&actions, &k),
            Some(&Action::Register {
                trade_pubkey: k.clone(),
                mostro_pubkey: NODE_B.to_string()
            })
        );
    }

    #[test]
    fn a_failed_attempt_is_retried_only_once_its_backoff_passed() {
        let k = key(1).unwrap();
        let wanted = Wanted::from([(k.clone(), NODE_A.to_string())]);
        let mut reg = PushRegistration::pending(&k, NODE_A);
        reg.note_failed(NOW, None);
        let regs = regs(vec![reg]);
        assert!(plan(&wanted, &regs, "tok", &Refusals::new(), NOW + 30).is_empty());
        assert!(
            register_for(&plan(&wanted, &regs, "tok", &Refusals::new(), NOW + 60), &k).is_some()
        );
    }

    #[test]
    fn a_429_waits_out_retry_after_instead_of_the_backoff() {
        let k = key(1).unwrap();
        let mut reg = PushRegistration::pending(&k, NODE_A);
        reg.note_failed(NOW, Some(7));
        assert_eq!(reg.next_attempt_at, NOW + 7);
        assert_eq!(reg.attempts, 1);
    }

    #[test]
    fn backoff_grows_then_caps() {
        assert_eq!(backoff_secs(1), 60);
        assert_eq!(backoff_secs(2), 300);
        assert_eq!(backoff_secs(3), 1800);
        assert_eq!(backoff_secs(4), 7200);
        assert_eq!(backoff_secs(40), 7200);
    }

    #[test]
    fn a_refused_node_suppresses_its_keys_only_while_the_refusal_is_active() {
        let (k1, k2) = (key(1).unwrap(), key(2).unwrap());
        let wanted = Wanted::from([
            (k1.clone(), NODE_A.to_string()),
            (k2.clone(), NODE_B.to_string()),
        ]);
        let refusals = Refusals::from([(NODE_A.to_string(), NOW - 10)]);
        let actions = plan(&wanted, &HashMap::new(), "tok", &refusals, NOW);
        assert!(
            register_for(&actions, &k1).is_none(),
            "the refused node's key is skipped"
        );
        assert!(
            register_for(&actions, &k2).is_some(),
            "the other node's key is not"
        );
        // 24 h later the next reconcile retries once.
        let later = NOW - 10 + NODE_REFUSAL_SECS;
        assert!(!refusal_active(NOW - 10, later));
        assert!(register_for(
            &plan(&wanted, &HashMap::new(), "tok", &refusals, later),
            &k1
        )
        .is_some());
    }

    #[test]
    fn an_accepted_registration_resets_its_failure_state() {
        let k = key(1).unwrap();
        let mut reg = PushRegistration::pending(&k, NODE_A);
        reg.note_failed(NOW, None);
        reg.note_failed(NOW + 100, None);
        reg.note_accepted(NODE_B, "tok", NOW + 200);
        assert_eq!(reg.attempts, 0);
        assert_eq!(reg.next_attempt_at, 0);
        assert_eq!(reg.registered_at, NOW + 200);
        assert_eq!(reg.mostro_pubkey, NODE_B);
        assert!(reg.is_registered());
    }

    // ── plan: the grace ──────────────────────────────────────────────────

    #[test]
    fn a_key_that_left_the_wanted_set_starts_its_grace_clock() {
        let k = key(1).unwrap();
        let regs = regs(vec![registered(&k, 10)]);
        let actions = plan(&Wanted::new(), &regs, "tok", &Refusals::new(), NOW);
        assert_eq!(actions, vec![Action::NoteUnwanted { trade_pubkey: k }]);
    }

    #[test]
    fn inside_the_grace_the_key_is_kept_and_past_it_unregistered() {
        let k = key(1).unwrap();
        let mut reg = registered(&k, 10);
        reg.unwanted_since = Some(NOW - GRACE_SECS);
        let regs = regs(vec![reg]);
        assert!(plan(&Wanted::new(), &regs, "tok", &Refusals::new(), NOW).is_empty());
        let actions = plan(&Wanted::new(), &regs, "tok", &Refusals::new(), NOW + 1);
        assert_eq!(actions, vec![Action::Unregister { trade_pubkey: k }]);
    }

    #[test]
    fn a_key_that_comes_back_has_its_grace_clock_cleared() {
        let k = key(1).unwrap();
        let mut reg = registered(&k, 10);
        reg.unwanted_since = Some(NOW - 100);
        let wanted = Wanted::from([(k.clone(), NODE_A.to_string())]);
        let actions = plan(&wanted, &regs(vec![reg]), "tok", &Refusals::new(), NOW);
        assert_eq!(actions, vec![Action::NoteWanted { trade_pubkey: k }]);
    }

    #[test]
    fn a_legacy_registration_without_a_clock_gets_the_full_grace() {
        // Stored before `unwanted_since` existed: the first reconcile that
        // finds it unwanted starts the clock rather than dropping it.
        let k = key(1).unwrap();
        let json = format!(
            r#"{{"trade_pubkey":"{k}","registered_at":{},"token_hash":"tok","mostro_pubkey":"{NODE_A}"}}"#,
            NOW - 10
        );
        let reg: PushRegistration = serde_json::from_str(&json).unwrap();
        assert_eq!(reg.unwanted_since, None);
        let actions = plan(
            &Wanted::new(),
            &regs(vec![reg]),
            "tok",
            &Refusals::new(),
            NOW,
        );
        assert_eq!(actions, vec![Action::NoteUnwanted { trade_pubkey: k }]);
    }

    #[test]
    fn a_never_accepted_record_nobody_wants_is_forgotten_without_a_request() {
        let k = key(1).unwrap();
        let regs = regs(vec![PushRegistration::pending(&k, NODE_A)]);
        let actions = plan(&Wanted::new(), &regs, "tok", &Refusals::new(), NOW);
        assert_eq!(actions, vec![Action::Forget { trade_pubkey: k }]);
    }

    #[test]
    fn a_failed_unregister_backs_off_like_a_registration() {
        let k = key(1).unwrap();
        let mut reg = registered(&k, 10);
        reg.unwanted_since = Some(NOW - GRACE_SECS - 10);
        reg.note_failed(NOW, None);
        let regs = regs(vec![reg]);
        assert!(plan(&Wanted::new(), &regs, "tok", &Refusals::new(), NOW + 1).is_empty());
        assert_eq!(
            plan(&Wanted::new(), &regs, "tok", &Refusals::new(), NOW + 60),
            vec![Action::Unregister { trade_pubkey: k }]
        );
    }

    // ── the rest ─────────────────────────────────────────────────────────

    #[test]
    fn notify_is_debounced_per_peer() {
        assert!(notify_allowed(None, NOW));
        assert!(!notify_allowed(Some(NOW - 3), NOW));
        assert!(notify_allowed(Some(NOW - NOTIFY_DEBOUNCE_SECS), NOW));
        assert!(
            notify_allowed(Some(NOW + 5), NOW),
            "a rollback never blocks forever"
        );
    }

    #[test]
    fn the_token_hash_is_stable_and_never_the_token() {
        let h = token_hash("fcm:abc");
        assert_eq!(h, token_hash("fcm:abc"));
        assert_ne!(h, token_hash("fcm:abd"));
        assert_eq!(h.len(), 64);
        assert!(!h.contains("fcm"));
    }

    #[test]
    fn a_registration_round_trips_through_json() {
        let mut reg = registered(&key(1).unwrap(), 5);
        reg.unwanted_since = Some(NOW);
        reg.note_failed(NOW, None);
        let json = serde_json::to_string(&reg).unwrap();
        assert_eq!(
            serde_json::from_str::<PushRegistration>(&json).unwrap(),
            reg
        );
    }
}
