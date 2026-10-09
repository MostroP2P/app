//! What a restore says is still in progress, and what to make of the rest.
//!
//! After a restore the kind-14 filter covers every recovered trade key, and
//! the relays replay the whole history: each old `new-order`, take and
//! payment message rebuilds a trade row as if it were current. mostrod's
//! restore reply is the authority on what is not history: it lists every
//! order of this identity outside `expired`, `success`, `canceled`,
//! `dispute`, and the admin/cooperative endings (mostro `src/db.rs`,
//! `EXCLUDED_ORDER_STATUSES`) — pending ones included — plus the disputes
//! still open. Every trade this client starts after the restore uses a trade
//! index above the resync floor, so "at or below the floor and not listed"
//! singles out history without trusting any timestamp.
//!
//! History never becomes a trade row: the replay of an old order is dropped
//! like a wiped trade's, and a history pass drops any row that predates
//! the snapshot. An imported account shows what the daemon still counts as
//! in progress, and nothing that ended before this device knew it.

use std::collections::{HashMap, HashSet};

use crate::api::types::{IdentityInfo, OrderStatus, TradeInfo};

/// Settings key the snapshot of the last restore is stored under. Wiped with
/// the identity (#614).
pub const SNAPSHOT_KEY: &str = crate::db::settings_keys::RESTORE_SNAPSHOT;

/// What the last restore reported as still in progress.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct RestoreSnapshot {
    /// The trade-key counter the restore resynced to: every trade started
    /// afterwards has an index above it.
    pub floor: u32,
    /// Order ids the daemon returned, from its orders and open disputes.
    pub live: HashSet<String>,
    /// The other party's trade pubkey per order id, where the daemon sent one
    /// (mostro-core 0.15). Absent in snapshots stored before the field
    /// existed, and for orders nobody has taken.
    #[serde(default)]
    pub peers: HashMap<String, String>,
    /// The identity public key (hex) that ran the restore. Absent in
    /// snapshots stored before the field existed (#614).
    #[serde(default)]
    pub identity: Option<String>,
}

impl RestoreSnapshot {
    /// True when this snapshot describes the trades of [identity], the one
    /// now loaded. [is_history] is only sound under that condition: "at or
    /// below the floor and not listed" singles out history only while every
    /// trade this identity starts gets an index above the floor. Read
    /// otherwise, it takes live trades for history and a pass wipes them
    /// mid-trade (#614). Two things must hold:
    ///
    /// - the snapshot was taken by this identity. Another identity's floor
    ///   covers a fresh identity's first indices, and its live set does not
    ///   list their orders. A snapshot that does not name its identity
    ///   (stored before the field existed) cannot prove it;
    /// - the identity's trade-key counter is still at or above the floor.
    ///   The restore raises it there before storing the snapshot. A counter
    ///   below it means the key sequence started over under the same
    ///   identity (a re-import after a wipe that failed), and the next takes
    ///   would reuse indices the floor covers.
    pub fn applies_to(&self, identity: Option<&IdentityInfo>) -> bool {
        let Some(identity) = identity else {
            return false;
        };
        let same_identity = self
            .identity
            .as_deref()
            .is_some_and(|own| own.eq_ignore_ascii_case(&identity.public_key));
        same_identity && identity.trade_key_index >= self.floor
    }

    /// True when the trade on [order_id] with [trade_index] predates the
    /// restore and the daemon no longer counts it as in progress.
    pub fn is_history(&self, order_id: &str, trade_index: u32) -> bool {
        trade_index <= self.floor && !self.live.contains(order_id)
    }

    /// The peer the restore named for the trade on [order_id], if that trade
    /// predates the restore.
    ///
    /// A trade started afterwards (an index above the floor) is a new take of
    /// the order, possibly by someone else: its peer comes from its own
    /// reveal, never from what the daemon said about the earlier one.
    pub fn peer_of(&self, order_id: &str, trade_index: u32) -> Option<&str> {
        (trade_index <= self.floor)
            .then(|| self.peers.get(order_id))
            .flatten()
            .map(String::as_str)
    }
}

/// Whether a restore reply may be applied: the identity loaded now is the
/// one that sent the request. A reply landing after an identity swap is the
/// previous identity's — its rows, its trade-key floor, its live set — and
/// applied to the new one it would file another user's trades, move the new
/// counter and store a snapshot that wipes the new identity's takes as
/// history (PR #616 review). No identity on either side proves nothing.
pub fn restore_answer_is_for(asked_by: Option<&str>, current: Option<&str>) -> bool {
    matches!(
        (asked_by, current),
        (Some(asked), Some(now)) if asked.eq_ignore_ascii_case(now)
    )
}

/// Delete the stored snapshot, but only while it is still [rejected], the
/// JSON a history pass read and found not to apply. A restore may have
/// stored a newer, valid one in between, and deleting by key alone would
/// leave its history unsettled (PR #616 review). The storage has no
/// compare-and-delete, so a write landing between the read and the delete
/// here is still possible — this only narrows it to that instant.
pub async fn drop_snapshot_if_unchanged(db: &impl crate::db::Storage, rejected: &str) {
    match db.get_setting(SNAPSHOT_KEY).await {
        Ok(Some(stored)) if stored == rejected => {
            if let Err(e) = db.delete_setting(SNAPSHOT_KEY).await {
                log::warn!("[restore] stale restore snapshot not dropped: {e}");
            }
        }
        Ok(_) => {}
        Err(e) => log::warn!("[restore] restore snapshot not re-read before drop: {e}"),
    }
}

/// The other party's trade pubkey for each restored order that names one.
///
/// An empty string counts as absent, as it does in a peer reveal.
pub fn restored_peers(info: &mostro_core::message::RestoreSessionInfo) -> HashMap<String, String> {
    info.restore_orders
        .iter()
        .filter_map(|o| {
            let peer = o.counterparty_trade_pubkey.as_deref()?.trim();
            (!peer.is_empty()).then(|| (o.order_id.to_string(), peer.to_string()))
        })
        .collect()
}

/// The peer to record on [trade] from a restore, as lowercase hex, or `None`
/// when the restore has nothing to add.
///
/// The restore is a fallback for the peer reveal, which rebuilds the same
/// value from the replayed daemon messages when the relays still hold them:
/// it only fills a row that has no peer, and never one that has ended. A
/// value that is not a public key, or that names this client, the Mostro node
/// or the order's publisher, would derive chat keys for a conversation that
/// does not exist and hold the order's single chat subscription with them
/// (#334), so it is dropped.
pub fn restored_peer_for(
    trade: &TradeInfo,
    peer_hex: &str,
    own_trade_pubkey: &str,
    mostro_pubkey: &str,
) -> Option<String> {
    if !trade.counterparty_pubkey.is_empty()
        || trade.outcome.is_some()
        || !reads_in_progress(&trade.order.status)
    {
        return None;
    }
    let peer = nostr_sdk::prelude::PublicKey::from_hex(peer_hex.trim())
        .ok()?
        .to_hex();
    let named_elsewhere = [own_trade_pubkey, mostro_pubkey, &trade.order.creator_pubkey]
        .iter()
        .any(|other| other.eq_ignore_ascii_case(&peer));
    (!named_elsewhere).then_some(peer)
}

/// True for a row that still reads as in progress: the rows a history pass
/// has to settle. Finished rows already say what happened.
pub fn reads_in_progress(status: &OrderStatus) -> bool {
    !matches!(
        status,
        OrderStatus::Success
            | OrderStatus::Canceled
            | OrderStatus::Expired
            | OrderStatus::CooperativelyCanceled
            | OrderStatus::CanceledByAdmin
            | OrderStatus::SettledByAdmin
            | OrderStatus::CompletedByAdmin
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snapshot() -> RestoreSnapshot {
        RestoreSnapshot {
            floor: 97,
            live: ["disputed-order".to_string()].into_iter().collect(),
            peers: HashMap::new(),
            identity: Some("owner".to_string()),
        }
    }

    #[test]
    fn an_old_trade_the_daemon_did_not_return_is_history() {
        assert!(snapshot().is_history("old-order", 40));
        assert!(snapshot().is_history("old-order", 97));
    }

    #[test]
    fn a_trade_the_daemon_returned_is_not_history() {
        assert!(!snapshot().is_history("disputed-order", 16));
    }

    #[test]
    fn a_trade_started_after_the_restore_is_not_history() {
        // Its index is above the floor, whatever the daemon returned.
        assert!(!snapshot().is_history("new-order", 98));
    }

    #[test]
    fn a_restored_peer_belongs_to_the_trade_that_predates_the_restore() {
        let mut snapshot = snapshot();
        snapshot.peers.insert("taken-order".into(), "peer".into());

        assert_eq!(snapshot.peer_of("taken-order", 97), Some("peer"));
        // A retake after the restore: a new trade, maybe a new peer.
        assert_eq!(snapshot.peer_of("taken-order", 98), None);
        assert_eq!(snapshot.peer_of("untaken-order", 40), None);
    }

    #[test]
    fn the_snapshot_survives_a_round_trip_through_settings() {
        let json = serde_json::to_string(&snapshot()).unwrap();
        let back: RestoreSnapshot = serde_json::from_str(&json).unwrap();
        assert_eq!(back, snapshot());
    }

    /// A restore reply answers the identity that sent the request. One
    /// that lands after a swap must not be applied to the new identity
    /// (PR #616 review): no identity on either side proves nothing either.
    #[test]
    fn a_restore_answer_is_for_the_identity_that_asked() {
        assert!(restore_answer_is_for(Some("aa"), Some("aa")));
        assert!(restore_answer_is_for(Some("aa"), Some("AA")));
        assert!(!restore_answer_is_for(Some("aa"), Some("bb")));
        assert!(!restore_answer_is_for(Some("aa"), None));
        assert!(!restore_answer_is_for(None, Some("aa")));
        assert!(!restore_answer_is_for(None, None));
    }

    /// A sweep that rejected the snapshot it read must not delete a newer
    /// one a restore stored meanwhile (PR #616 review).
    #[cfg(not(target_arch = "wasm32"))]
    #[tokio::test]
    async fn a_rejected_snapshot_is_dropped_only_while_it_is_still_stored() {
        use crate::db::Storage;
        let path = std::env::temp_dir().join(format!(
            "restore_snapshot_drop_{}.db",
            uuid::Uuid::new_v4()
        ));
        let db = crate::db::sqlite::SqliteStorage::open(path.to_str().unwrap())
            .await
            .unwrap();
        let (stale, fresh) = (r#"{"floor":9,"live":[]}"#, r#"{"floor":1,"live":[]}"#);

        // A newer snapshot replaced the rejected one: it stays.
        db.set_setting(SNAPSHOT_KEY, fresh).await.unwrap();
        drop_snapshot_if_unchanged(&db, stale).await;
        assert_eq!(db.get_setting(SNAPSHOT_KEY).await.unwrap().as_deref(), Some(fresh));

        // Still the rejected one: it goes.
        db.set_setting(SNAPSHOT_KEY, stale).await.unwrap();
        drop_snapshot_if_unchanged(&db, stale).await;
        assert_eq!(db.get_setting(SNAPSHOT_KEY).await.unwrap(), None);
    }

    #[test]
    fn a_snapshot_serves_only_the_identity_that_took_it() {
        let snapshot = |identity: Option<&str>| RestoreSnapshot {
            floor: 97,
            live: HashSet::new(),
            peers: HashMap::new(),
            identity: identity.map(str::to_string),
        };
        let loaded = |pubkey: &str, trade_key_index: u32| IdentityInfo {
            public_key: pubkey.to_string(),
            display_name: None,
            privacy_mode: false,
            trade_key_index,
            created_at: 0,
        };
        assert!(snapshot(Some("aa")).applies_to(Some(&loaded("aa", 97))));
        assert!(snapshot(Some("aa")).applies_to(Some(&loaded("AA", 120))));
        // Another identity's history: its floor and live set say nothing
        // about this one's trades (#614).
        assert!(!snapshot(Some("aa")).applies_to(Some(&loaded("bb", 120))));
        assert!(!snapshot(Some("aa")).applies_to(None));
        // Stored before the field existed: whose it is cannot be proven.
        assert!(!snapshot(None).applies_to(Some(&loaded("aa", 120))));
        // Same identity, key sequence started over: its next takes would sit
        // at or below the floor and read as history.
        assert!(!snapshot(Some("aa")).applies_to(Some(&loaded("aa", 0))));
        assert!(!snapshot(Some("aa")).applies_to(Some(&loaded("aa", 96))));
        let legacy: RestoreSnapshot =
            serde_json::from_str(r#"{"floor":97,"live":[]}"#).expect("old shape still reads");
        assert_eq!(legacy.identity, None);
    }

    #[test]
    fn only_rows_still_reading_as_in_progress_need_settling() {
        assert!(reads_in_progress(&OrderStatus::Pending));
        assert!(reads_in_progress(&OrderStatus::SettledHoldInvoice));
        assert!(reads_in_progress(&OrderStatus::Dispute));
        assert!(!reads_in_progress(&OrderStatus::Success));
        assert!(!reads_in_progress(&OrderStatus::Canceled));
    }
}
