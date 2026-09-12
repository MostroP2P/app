//! The anti-abuse bond policy the active Mostro node advertises.
//!
//! Phase 0 of `docs/ANTI_ABUSE_BOND.md`. Same shape as [`crate::mostro::pow`]
//! and [`crate::mostro::escrow_mode`]: a pure parser over the daemon's Kind
//! 38385 tags plus a process-global snapshot for the active node, refreshed
//! whenever the relay pool comes online or the active node changes.
//!
//! The parser mirrors the validation the About screen already applies in Dart
//! (`MostroInstance.fromTags`) so the two never disagree about the same event:
//! an empty or whitespace-only value is *missing*, every parameter is gated on
//! `bond_enabled = true`, and an out-of-range value reads as absent rather than
//! as a number the UI would then show.
//!
//! Nothing here decides whether a bond is due — the daemon does, by sending
//! `pay-bond-invoice`. The policy exists so the UI can warn the user *before*
//! they commit, and so the deadline arithmetic of a payout claim has a window
//! to work with.

use std::sync::RwLock;

use crate::api::types::{BondApplyTo, BondPolicy, BondPolicyInfo};

// ── Pure helpers ────────────────────────────────────────────────────────────

/// Read the seven `bond_*` tags out of a Kind 38385 tag list.
pub fn parse_tags(tags: &[Vec<String>]) -> BondPolicyInfo {
    let value_of = |name: &str| -> Option<&str> {
        tags.iter()
            .find(|t| t.first().map(String::as_str) == Some(name))
            .and_then(|t| t.get(1))
            .map(String::as_str)
            .map(str::trim)
            .filter(|v| !v.is_empty())
    };

    let policy = match value_of("bond_enabled")
        .map(str::to_ascii_lowercase)
        .as_deref()
    {
        Some("true") => BondPolicy::Enabled,
        Some("false") => BondPolicy::Disabled,
        // Absent, blank or malformed: the daemon did not say it speaks bond.
        // A corrupt payload must never masquerade as an intentional policy.
        _ => BondPolicy::Unsupported,
    };
    if policy != BondPolicy::Enabled {
        return BondPolicyInfo {
            policy,
            ..BondPolicyInfo::default()
        };
    }

    let apply_to = match value_of("bond_apply_to")
        .map(str::to_ascii_lowercase)
        .as_deref()
    {
        Some("take") => Some(BondApplyTo::Take),
        Some("make") => Some(BondApplyTo::Make),
        Some("both") => Some(BondApplyTo::Both),
        _ => None,
    };

    // Finite and non-negative; `max` caps the upper bound only where the
    // protocol constrains it (the daemon validates `slash_node_share_pct` to
    // `<= 1.0`, but `amount_pct` is an unbounded fraction).
    let fraction = |name: &str, max: Option<f64>| -> Option<f64> {
        let v: f64 = value_of(name)?.parse().ok()?;
        if !v.is_finite() || v < 0.0 {
            return None;
        }
        if max.is_some_and(|m| v > m) {
            return None;
        }
        Some(v)
    };
    let bool_of = |name: &str| -> Option<bool> {
        match value_of(name).map(str::to_ascii_lowercase).as_deref() {
            Some("true") => Some(true),
            Some("false") => Some(false),
            _ => None,
        }
    };

    BondPolicyInfo {
        policy,
        apply_to,
        amount_pct: fraction("bond_amount_pct", None),
        // `u64::parse` already rejects a sign, which is the `>= 0` rule.
        base_amount_sats: value_of("bond_base_amount_sats").and_then(|v| v.parse().ok()),
        slash_on_waiting_timeout: bool_of("bond_slash_on_waiting_timeout"),
        slash_node_share_pct: fraction("bond_slash_node_share_pct", Some(1.0)),
        payout_claim_window_days: value_of("bond_payout_claim_window_days")
            .and_then(|v| v.parse::<u32>().ok())
            .filter(|d| *d > 0),
    }
}

/// What the daemon will ask this user to lock for an order of
/// `order_amount_sats`: `max(round(amount_pct × amount), base_amount_sats)`
/// (`docs/ANTI_ABUSE_BOND.md` §2.1). An **estimate** for the pre-commit
/// warning only — the daemon always sends the exact bolt11.
///
/// `None` unless the policy is enabled and advertises a percentage; a missing
/// floor reads as `0`. Saturates instead of overflowing on absurd inputs.
pub fn estimate_bond_sats(order_amount_sats: u64, policy: &BondPolicyInfo) -> Option<u64> {
    if policy.policy != BondPolicy::Enabled {
        return None;
    }
    let pct = policy.amount_pct?;
    let from_pct = (pct * order_amount_sats as f64).round();
    let from_pct = if from_pct.is_finite() && from_pct >= 0.0 {
        // `as u64` saturates for values past `u64::MAX`.
        from_pct as u64
    } else {
        u64::MAX
    };
    Some(from_pct.max(policy.base_amount_sats.unwrap_or(0)))
}

/// Whether the policy asks the given side to post a bond. `false` for a
/// disabled or unsupported policy, and for an enabled policy that did not
/// say which side (the daemon decides; the UI just does not pre-warn).
pub fn applies_to_taker(policy: &BondPolicyInfo) -> bool {
    policy.policy == BondPolicy::Enabled
        && matches!(policy.apply_to, Some(BondApplyTo::Take | BondApplyTo::Both))
}

/// Maker-side counterpart of [`applies_to_taker`].
pub fn applies_to_maker(policy: &BondPolicyInfo) -> bool {
    policy.policy == BondPolicy::Enabled
        && matches!(policy.apply_to, Some(BondApplyTo::Make | BondApplyTo::Both))
}

// ── Process-global state ────────────────────────────────────────────────────

/// What one node's 38385 tags said, keyed by that node's hex pubkey, or
/// `None` before the first successful fetch. The key is what makes the cache
/// safe across a node switch: a capability fetch that was in flight for the
/// previous node lands here tagged with *that* node, and [`get_for`] refuses
/// to serve it for the new one (same reasoning as `pow::first_contact_pow_for`).
/// Cleared whenever a fetch fails or finds no event, and at the start of a
/// node switch.
static POLICY: RwLock<Option<(String, BondPolicyInfo)>> = RwLock::new(None);

/// Record what `node` (hex pubkey) advertised. A poisoned lock is recovered
/// from rather than propagated: this is a cache of what the node said.
pub fn set_from_tags(node: &str, policy: BondPolicyInfo) {
    *POLICY.write().unwrap_or_else(|e| e.into_inner()) = Some((node.to_string(), policy));
}

/// Forget the cached policy (fetch failed, no event, node switch).
pub fn clear() {
    *POLICY.write().unwrap_or_else(|e| e.into_inner()) = None;
}

/// The policy fetched **from `node`** (hex pubkey), `None` until its info
/// event has been fetched — or when the cache holds another node's answer.
pub fn get_for(node: &str) -> Option<BondPolicyInfo> {
    POLICY
        .read()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .filter(|(from, _)| from.eq_ignore_ascii_case(node))
        .map(|(_, policy)| policy.clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tags(pairs: &[(&str, &str)]) -> Vec<Vec<String>> {
        pairs
            .iter()
            .map(|(k, v)| vec![k.to_string(), v.to_string()])
            .collect()
    }

    fn enabled_tags() -> Vec<Vec<String>> {
        tags(&[
            ("bond_enabled", "true"),
            ("bond_apply_to", "take"),
            ("bond_amount_pct", "0.01"),
            ("bond_base_amount_sats", "1000"),
            ("bond_slash_on_waiting_timeout", "false"),
            ("bond_slash_node_share_pct", "0.5"),
            ("bond_payout_claim_window_days", "15"),
        ])
    }

    #[test]
    fn an_enabled_node_fills_every_field() {
        let p = parse_tags(&enabled_tags());
        assert_eq!(p.policy, BondPolicy::Enabled);
        assert_eq!(p.apply_to, Some(BondApplyTo::Take));
        assert_eq!(p.amount_pct, Some(0.01));
        assert_eq!(p.base_amount_sats, Some(1000));
        assert_eq!(p.slash_on_waiting_timeout, Some(false));
        assert_eq!(p.slash_node_share_pct, Some(0.5));
        assert_eq!(p.payout_claim_window_days, Some(15));
    }

    /// `bond_enabled` absent means an old daemon; blank means the same, not
    /// "disabled" — a corrupt payload must not read as an intentional policy.
    #[test]
    fn the_policy_is_tri_state() {
        assert_eq!(
            parse_tags(&tags(&[("d", "x")])).policy,
            BondPolicy::Unsupported
        );
        assert_eq!(
            parse_tags(&tags(&[("bond_enabled", "   ")])).policy,
            BondPolicy::Unsupported
        );
        assert_eq!(
            parse_tags(&tags(&[("bond_enabled", "maybe")])).policy,
            BondPolicy::Unsupported
        );
        assert_eq!(
            parse_tags(&tags(&[("bond_enabled", "FALSE")])).policy,
            BondPolicy::Disabled
        );
        assert_eq!(
            parse_tags(&tags(&[("bond_enabled", "True")])).policy,
            BondPolicy::Enabled
        );
    }

    /// Parameters surface only when the policy is enabled, so a consumer can
    /// key off nullability alone.
    #[test]
    fn parameters_are_gated_on_enabled() {
        let mut t = enabled_tags();
        t[0] = vec!["bond_enabled".into(), "false".into()];
        let p = parse_tags(&t);
        assert_eq!(
            p,
            BondPolicyInfo {
                policy: BondPolicy::Disabled,
                ..BondPolicyInfo::default()
            }
        );
    }

    #[test]
    fn out_of_range_or_malformed_values_read_as_absent() {
        let p = parse_tags(&tags(&[
            ("bond_enabled", "true"),
            ("bond_apply_to", "everyone"),
            ("bond_amount_pct", "-0.01"),
            ("bond_base_amount_sats", "-5"),
            ("bond_slash_on_waiting_timeout", "yes"),
            ("bond_slash_node_share_pct", "1.5"),
            ("bond_payout_claim_window_days", "0"),
        ]));
        assert_eq!(p.policy, BondPolicy::Enabled);
        assert_eq!(p.apply_to, None);
        assert_eq!(p.amount_pct, None);
        assert_eq!(p.base_amount_sats, None);
        assert_eq!(p.slash_on_waiting_timeout, None);
        assert_eq!(p.slash_node_share_pct, None);
        assert_eq!(p.payout_claim_window_days, None);

        let nan = parse_tags(&tags(&[
            ("bond_enabled", "true"),
            ("bond_amount_pct", "NaN"),
        ]));
        assert_eq!(nan.amount_pct, None);
        let inf = parse_tags(&tags(&[
            ("bond_enabled", "true"),
            ("bond_amount_pct", "inf"),
        ]));
        assert_eq!(inf.amount_pct, None);
    }

    /// `amount_pct` is unbounded above (a 150 % bond is a node's business);
    /// `slash_node_share_pct` is a share and stops at 1.0.
    #[test]
    fn only_the_node_share_is_capped_at_one() {
        let p = parse_tags(&tags(&[
            ("bond_enabled", "true"),
            ("bond_amount_pct", "1.5"),
            ("bond_slash_node_share_pct", "1.0"),
        ]));
        assert_eq!(p.amount_pct, Some(1.5));
        assert_eq!(p.slash_node_share_pct, Some(1.0));
    }

    #[test]
    fn apply_to_is_case_insensitive() {
        for (raw, want) in [
            ("Take", BondApplyTo::Take),
            ("MAKE", BondApplyTo::Make),
            ("both", BondApplyTo::Both),
        ] {
            let p = parse_tags(&tags(&[("bond_enabled", "true"), ("bond_apply_to", raw)]));
            assert_eq!(p.apply_to, Some(want), "{raw}");
        }
    }

    fn enabled(pct: Option<f64>, base: Option<u64>) -> BondPolicyInfo {
        BondPolicyInfo {
            policy: BondPolicy::Enabled,
            amount_pct: pct,
            base_amount_sats: base,
            ..BondPolicyInfo::default()
        }
    }

    #[test]
    fn the_estimate_is_the_larger_of_percentage_and_floor() {
        // Percentage dominates.
        assert_eq!(
            estimate_bond_sats(500_000, &enabled(Some(0.01), Some(1000))),
            Some(5000)
        );
        // Floor dominates.
        assert_eq!(
            estimate_bond_sats(20_000, &enabled(Some(0.01), Some(1000))),
            Some(1000)
        );
        // Rounded, not truncated.
        assert_eq!(
            estimate_bond_sats(150, &enabled(Some(0.01), Some(0))),
            Some(2)
        );
        // Zero percent leaves only the floor.
        assert_eq!(
            estimate_bond_sats(500_000, &enabled(Some(0.0), Some(1000))),
            Some(1000)
        );
        // No floor advertised reads as 0.
        assert_eq!(
            estimate_bond_sats(500_000, &enabled(Some(0.02), None)),
            Some(10_000)
        );
    }

    #[test]
    fn no_estimate_without_an_enabled_policy_and_a_percentage() {
        assert_eq!(
            estimate_bond_sats(500_000, &BondPolicyInfo::default()),
            None
        );
        let disabled = BondPolicyInfo {
            policy: BondPolicy::Disabled,
            amount_pct: Some(0.01),
            ..BondPolicyInfo::default()
        };
        assert_eq!(estimate_bond_sats(500_000, &disabled), None);
        assert_eq!(
            estimate_bond_sats(500_000, &enabled(None, Some(1000))),
            None
        );
    }

    #[test]
    fn the_estimate_saturates_instead_of_overflowing() {
        assert_eq!(
            estimate_bond_sats(u64::MAX, &enabled(Some(1e6), None)),
            Some(u64::MAX)
        );
    }

    #[test]
    fn apply_to_helpers_answer_per_side() {
        let mut p = enabled(Some(0.01), None);
        for (apply_to, taker, maker) in [
            (None, false, false),
            (Some(BondApplyTo::Take), true, false),
            (Some(BondApplyTo::Make), false, true),
            (Some(BondApplyTo::Both), true, true),
        ] {
            p.apply_to = apply_to;
            assert_eq!(applies_to_taker(&p), taker, "{apply_to:?}");
            assert_eq!(applies_to_maker(&p), maker, "{apply_to:?}");
        }
        p.policy = BondPolicy::Disabled;
        p.apply_to = Some(BondApplyTo::Both);
        assert!(!applies_to_taker(&p) && !applies_to_maker(&p));
    }

    /// The global is a cache of what one node said: served only for that
    /// node, so a fetch that raced a node switch never answers for the new
    /// node; and cleared on demand.
    #[test]
    fn the_snapshot_is_served_only_for_the_node_it_came_from() {
        clear();
        assert_eq!(get_for("aa"), None);
        set_from_tags("aa", parse_tags(&enabled_tags()));
        assert_eq!(get_for("aa").map(|p| p.policy), Some(BondPolicy::Enabled));
        assert_eq!(get_for("AA").map(|p| p.policy), Some(BondPolicy::Enabled));
        assert_eq!(get_for("bb"), None, "another node's answer is not reused");
        clear();
        assert_eq!(get_for("aa"), None);
    }
}
