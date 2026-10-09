/// The user's own reputation on the active node (issue #755).
///
/// The node answers `user-info` with the same aggregate it shows other users
/// about this identity (<https://mostro.network/protocol/user_info.html>):
/// rating, number of ratings received, and the day of the first trade. Each
/// node keeps its own users, so the answer is per node.
///
/// The last answer of every node is **cached** (`settings_keys::MY_REPUTATION`)
/// with the identity that asked, so the Account screen shows it at once and a
/// reply that lands after an identity swap is never shown to the new user.
/// [`refresh_my_reputation`] asks the active node again; it runs at startup,
/// when the Account screen opens, when the user picks another node, and once
/// they rate a counterpart. Every stored answer is broadcast to
/// [`MyReputationStream`].
///
/// Full privacy mode has no reputation by design: nothing is sent, and the
/// UI says why instead of showing zeros.
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::OnceLock;

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast::{self, error::RecvError};
use tokio::sync::Mutex;

use crate::db::{settings_keys, Storage};

/// How long a refresh waits for the relay handshakes it may race with at
/// startup. A no-op once they are connected.
const CONNECT_WAIT_SECS: u64 = 5;

const CHANNEL_CAPACITY: usize = 8;

/// The user's reputation as one node last reported it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MyReputation {
    /// The node that answered, 64-char hex.
    pub node_pubkey: String,
    /// Aggregated rating, the node's `total_rating`. Meaningless when
    /// [`Self::reviews`] is `0`.
    pub rating: f64,
    /// Ratings received. `0` reads as "no reputation yet".
    pub reviews: u32,
    /// Unix seconds of the first trade, truncated to its UTC day. `None` for
    /// an identity with no trades on this node.
    pub since: Option<i64>,
    /// Deprecated day count (`operating_days`), the fallback when the node
    /// sends no `since`.
    pub operating_days: u32,
    /// When this client stored the answer, unix seconds.
    pub fetched_at: i64,
}

/// One cached answer and the identity it belongs to.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
struct CachedReputation {
    /// Identity pubkey (hex) the request proved.
    identity: String,
    reputation: MyReputation,
}

/// Node pubkey (hex) → its last answer.
type ReputationCache = HashMap<String, CachedReputation>;

struct Store {
    /// In front of the stored map; `None` until first read.
    cache: Mutex<Option<ReputationCache>>,
    /// Bumped when the identity is forgotten: an answer asked before that
    /// belongs to the deleted identity and is refused.
    generation: AtomicU64,
    /// One request at a time; the next waits its turn, then asks.
    refresh: Mutex<()>,
    /// A background refresh is queued and not yet started ([`spawn_refresh`]).
    queued: AtomicBool,
    tx: broadcast::Sender<MyReputation>,
}

static STORE: OnceLock<Store> = OnceLock::new();

fn store() -> &'static Store {
    STORE.get_or_init(Store::new)
}

// ── Pure helpers ─────────────────────────────────────────────────────────────

/// True only for the reply to THIS request: `user-info` echoing our nonce.
/// A reply without one may answer an earlier request, so it is not ours.
fn is_matching_user_info_reply(kind: &mostro_core::message::MessageKind, request_id: u64) -> bool {
    kind.action == mostro_core::message::Action::UserInfo && kind.request_id == Some(request_id)
}

/// The reputation a `user-info` reply carries, or `None` when it carries no
/// `user_info` payload. Values no real node sends are clamped rather than
/// wrapped: a negative count reads as `0`, a `since` past `i64` as no date.
fn reputation_from_reply(
    node_pubkey: &str,
    kind: &mostro_core::message::MessageKind,
    fetched_at: i64,
) -> Option<MyReputation> {
    let Some(mostro_core::message::Payload::UserInfo(info)) = &kind.payload else {
        return None;
    };
    Some(MyReputation {
        node_pubkey: node_pubkey.to_string(),
        rating: if info.rating.is_finite() {
            info.rating
        } else {
            0.0
        },
        reviews: u32::try_from(info.reviews.max(0)).unwrap_or(u32::MAX),
        since: info.since.and_then(|s| i64::try_from(s).ok()),
        operating_days: u32::try_from(info.operating_days).unwrap_or(u32::MAX),
        fetched_at,
    })
}

/// `node`'s cached answer, only when `identity` asked for it.
fn cached_for(cache: &ReputationCache, identity: &str, node: &str) -> Option<MyReputation> {
    cache
        .get(node)
        .filter(|entry| entry.identity == identity)
        .map(|entry| entry.reputation.clone())
}

/// `cache` with `reputation` as its node's answer for `identity`.
fn with_answer(
    cache: &ReputationCache,
    identity: &str,
    reputation: MyReputation,
) -> ReputationCache {
    let mut next = cache.clone();
    next.insert(
        reputation.node_pubkey.clone(),
        CachedReputation {
            identity: identity.to_string(),
            reputation,
        },
    );
    next
}

// ── Cache ────────────────────────────────────────────────────────────────────

/// The stored map, or an empty one: a corrupt or unreadable blob costs one
/// request, nothing else.
async fn load_cache<S: Storage>(db: Option<&S>) -> ReputationCache {
    let Some(db) = db else {
        return ReputationCache::new();
    };
    match db.get_setting(settings_keys::MY_REPUTATION).await {
        Ok(Some(json)) => serde_json::from_str(&json).unwrap_or_default(),
        Ok(None) => ReputationCache::new(),
        Err(e) => {
            log::warn!("[my_reputation] cache unreadable: {e}");
            ReputationCache::new()
        }
    }
}

impl Store {
    fn new() -> Self {
        let (tx, _rx) = broadcast::channel(CHANNEL_CAPACITY);
        Store {
            cache: Mutex::new(None),
            generation: AtomicU64::new(0),
            refresh: Mutex::new(()),
            queued: AtomicBool::new(false),
            tx,
        }
    }

    /// What a request captures before it goes out, for [`Self::store_answer`].
    fn generation(&self) -> u64 {
        self.generation.load(Ordering::SeqCst)
    }

    /// The cached answers, read from `db` on first use.
    async fn cache<S: Storage>(&self, db: Option<&S>) -> ReputationCache {
        let mut guard = self.cache.lock().await;
        if let Some(cache) = guard.as_ref() {
            return cache.clone();
        }
        let loaded = load_cache(db).await;
        *guard = Some(loaded.clone());
        loaded
    }

    /// Keep `reputation` as its node's answer for `identity` and tell the
    /// listeners — unless the identity was forgotten since the request went
    /// out at `generation`. Returns whether it was kept. Without a store it
    /// lives for the session.
    async fn store_answer<S: Storage>(
        &self,
        db: Option<&S>,
        generation: u64,
        identity: &str,
        reputation: MyReputation,
    ) -> bool {
        // Held across the write so a forget cannot land between the check
        // and the write.
        let mut guard = self.cache.lock().await;
        if self.generation() != generation {
            return false;
        }
        let base = match guard.as_ref() {
            Some(cache) => cache.clone(),
            None => load_cache(db).await,
        };
        let next = with_answer(&base, identity, reputation.clone());
        if let Some(db) = db {
            let written = match serde_json::to_string(&next) {
                Ok(json) => db.set_setting(settings_keys::MY_REPUTATION, &json).await,
                Err(e) => Err(e.into()),
            };
            if let Err(e) = written {
                log::warn!("[my_reputation] answer not persisted: {e}");
            }
        }
        *guard = Some(next);
        drop(guard);
        let _ = self.tx.send(reputation);
        true
    }

    /// Drop the deleted identity's answers (issue #533), the stored copy
    /// too, and refuse any still in flight.
    async fn forget<S: Storage>(&self, db: Option<&S>) {
        let mut guard = self.cache.lock().await;
        self.generation.fetch_add(1, Ordering::SeqCst);
        *guard = Some(ReputationCache::new());
        if let Some(db) = db {
            if let Err(e) = db.delete_setting(settings_keys::MY_REPUTATION).await {
                log::warn!("[my_reputation] stored answers not dropped: {e}");
            }
        }
    }
}

/// Forget the deleted identity's reputation (issue #533).
pub(crate) async fn forget_identity_reputation() {
    store().forget(crate::db::app_db::db()).await;
}

// ── API ──────────────────────────────────────────────────────────────────────

/// The active node's last answer for the current identity, without asking.
///
/// `None` when that node never answered this identity, or there is no
/// identity yet.
pub async fn cached_my_reputation() -> Result<Option<MyReputation>> {
    let Ok(keys) = crate::api::identity::get_active_keys().await else {
        return Ok(None);
    };
    let node = crate::config::active_mostro_pubkey();
    Ok(cached_for(
        &store().cache(crate::db::app_db::db()).await,
        &keys.public_key().to_hex(),
        &node,
    ))
}

/// Ask the active node for the user's reputation and keep the answer.
///
/// Returns the new answer, or `None` when there is none to have: full privacy
/// mode (nothing is sent), a refusal, or no reply in time. The cached answer
/// is then left as it was.
///
/// The request is signed by a throwaway key: `user-info` is read-only, so it
/// burns no trade index and links no trade key to the identity. A call made
/// while another is in flight waits for it, then asks the node itself: the
/// active node may have changed, or a rating landed, in between.
pub async fn refresh_my_reputation() -> Result<Option<MyReputation>> {
    if crate::api::reputation::get_privacy_mode() {
        return Ok(None);
    }
    // A trigger that lands during another request (a node switch, a rating
    // sent) still asks, once that request is done.
    let _guard = store().refresh.lock().await;
    let generation = store().generation();
    let node = crate::config::active_mostro_pubkey();
    let mostro_pubkey = nostr_sdk::prelude::PublicKey::from_hex(&node)?;
    let identity_keys = crate::api::identity::get_active_keys().await?;
    let trade_keys = nostr_sdk::prelude::Keys::generate();

    let pool = crate::api::nostr::get_pool()?;
    pool.client()
        .connect()
        .and_wait(crate::rt::time::Duration::from_secs(CONNECT_WAIT_SECS))
        .await;
    // Full privacy may have been turned on while this waited for the lock or
    // the relays: the identity proof must not go out then.
    if crate::api::reputation::get_privacy_mode() {
        return Ok(None);
    }

    let request_id = crate::api::orders::fresh_request_id();
    let event_json =
        crate::mostro::actions::user_info(&identity_keys, &trade_keys, &mostro_pubkey, request_id)
            .await?;
    let answer = crate::api::orders::ask_daemon(
        &trade_keys,
        &mostro_pubkey,
        request_id,
        &event_json,
        "UserInfo",
        is_matching_user_info_reply,
    )
    .await?;
    match answer {
        crate::api::orders::DaemonAnswer::Reply(kind, _) => {
            let Some(reputation) = reputation_from_reply(&node, &kind, crate::rt::unix_now())
            else {
                crate::api::logging::blog_warn(
                    "reputation",
                    "UserInfo reply carried no user_info".to_string(),
                );
                return Ok(None);
            };
            let kept = store()
                .store_answer(
                    crate::db::app_db::db(),
                    generation,
                    &identity_keys.public_key().to_hex(),
                    reputation.clone(),
                )
                .await;
            Ok(kept.then_some(reputation))
        }
        crate::api::orders::DaemonAnswer::Refused(reason) => {
            crate::api::logging::blog_warn(
                "reputation",
                format!("UserInfo refused: CantDo({reason})"),
            );
            Ok(None)
        }
        crate::api::orders::DaemonAnswer::Silent => {
            crate::api::logging::blog_warn(
                "reputation",
                "UserInfo: no reply from the node".to_string(),
            );
            Ok(None)
        }
    }
}

/// Refresh in the background, `reason` naming the trigger in the log.
/// Triggers that land while one is queued and not yet started join it.
pub(crate) fn spawn_refresh(reason: &'static str) {
    if store().queued.swap(true, Ordering::SeqCst) {
        return;
    }
    crate::rt::spawn(async move {
        store().queued.store(false, Ordering::SeqCst);
        if let Err(e) = refresh_my_reputation().await {
            crate::api::logging::blog_warn(
                "reputation",
                format!("UserInfo refresh after {reason} failed: {e}"),
            );
        }
    });
}

/// A stream of the answers [`refresh_my_reputation`] stores, for any node.
pub struct MyReputationStream {
    rx: broadcast::Receiver<MyReputation>,
}

impl MyReputationStream {
    /// The next stored answer; a lag skips ahead rather than ending the stream.
    pub async fn next(&mut self) -> Result<MyReputation> {
        loop {
            match self.rx.recv().await {
                Ok(reputation) => return Ok(reputation),
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => bail!("MyReputationStream closed: sender dropped"),
            }
        }
    }
}

/// Subscribe to the answers [`refresh_my_reputation`] stores.
pub fn on_my_reputation_changed() -> MyReputationStream {
    MyReputationStream {
        rx: store().tx.subscribe(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mostro_core::message::{Action, MessageKind, Payload};
    use mostro_core::user::UserInfo;

    const NODE: &str = "node-a";

    fn reply(request_id: Option<u64>, payload: Option<Payload>) -> MessageKind {
        MessageKind::new(None, request_id, None, Action::UserInfo, payload)
    }

    fn info(rating: f64, reviews: i64, since: Option<u64>, days: u64) -> Payload {
        Payload::UserInfo(UserInfo {
            rating,
            reviews,
            operating_days: days,
            since,
        })
    }

    fn rep(node: &str, reviews: u32) -> MyReputation {
        MyReputation {
            node_pubkey: node.to_string(),
            rating: 4.5,
            reviews,
            since: Some(1_700_784_000),
            operating_days: 3,
            fetched_at: 10,
        }
    }

    #[test]
    fn only_the_user_info_reply_to_this_request_matches() {
        assert!(is_matching_user_info_reply(&reply(Some(9), None), 9));
        assert!(!is_matching_user_info_reply(&reply(Some(8), None), 9));
        // A reply with no nonce may answer an earlier request.
        assert!(!is_matching_user_info_reply(&reply(None, None), 9));
        let other = MessageKind::new(None, Some(9), None, Action::LastTradeIndex, None);
        assert!(!is_matching_user_info_reply(&other, 9));
    }

    #[test]
    fn a_known_identity_reads_its_rating_reviews_and_since() {
        let kind = reply(Some(1), Some(info(4.8, 23, Some(1_700_784_000), 142)));

        let got = reputation_from_reply(NODE, &kind, 99).expect("a reputation");

        assert_eq!(
            got,
            MyReputation {
                node_pubkey: NODE.to_string(),
                rating: 4.8,
                reviews: 23,
                since: Some(1_700_784_000),
                operating_days: 142,
                fetched_at: 99,
            }
        );
    }

    /// "No reputation yet" is a valid answer, not a failure.
    #[test]
    fn an_unknown_identity_reads_as_zeros_without_since() {
        let kind = reply(Some(1), Some(info(0.0, 0, None, 0)));

        let got = reputation_from_reply(NODE, &kind, 5).expect("a reputation");

        assert_eq!(got.reviews, 0);
        assert_eq!(got.since, None);
        assert_eq!(got.operating_days, 0);
    }

    /// Values no real node sends are clamped, never wrapped into a large
    /// count or a date in the far future.
    #[test]
    fn out_of_range_values_are_clamped() {
        let kind = reply(Some(1), Some(info(f64::NAN, -3, Some(u64::MAX), u64::MAX)));

        let got = reputation_from_reply(NODE, &kind, 5).expect("a reputation");

        assert_eq!(got.reviews, 0);
        assert_eq!(got.rating, 0.0);
        assert_eq!(got.since, None);
        assert_eq!(got.operating_days, u32::MAX);
    }

    #[test]
    fn a_reply_without_user_info_carries_no_reputation() {
        assert_eq!(reputation_from_reply(NODE, &reply(Some(1), None), 5), None);
    }

    #[test]
    fn a_cached_answer_is_served_only_to_the_identity_that_asked() {
        let cache = with_answer(&ReputationCache::new(), "alice", rep(NODE, 2));

        assert_eq!(cached_for(&cache, "alice", NODE), Some(rep(NODE, 2)));
        assert_eq!(cached_for(&cache, "bob", NODE), None);
        assert_eq!(cached_for(&cache, "alice", "node-b"), None);
    }

    #[test]
    fn each_node_keeps_its_own_answer_and_the_input_is_not_mutated() {
        let empty = ReputationCache::new();
        let one = with_answer(&empty, "alice", rep(NODE, 2));
        let two = with_answer(&one, "alice", rep("node-b", 7));
        let newer = with_answer(&two, "alice", rep(NODE, 3));

        assert!(empty.is_empty());
        assert_eq!(cached_for(&one, "alice", NODE), Some(rep(NODE, 2)));
        assert_eq!(cached_for(&newer, "alice", NODE), Some(rep(NODE, 3)));
        assert_eq!(
            cached_for(&newer, "alice", "node-b"),
            Some(rep("node-b", 7))
        );
    }

    async fn temp_db() -> crate::db::sqlite::SqliteStorage {
        use std::sync::atomic::AtomicU32;
        static COUNTER: AtomicU32 = AtomicU32::new(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "mostro_my_reputation_{}_{n}.db",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        crate::db::sqlite::SqliteStorage::open(path.to_str().unwrap())
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn a_stored_answer_outlives_the_process() {
        let db = temp_db().await;
        let first = Store::new();
        assert!(
            first
                .store_answer(Some(&db), first.generation(), "alice", rep(NODE, 2))
                .await
        );

        let restarted = Store::new();

        assert_eq!(
            cached_for(&restarted.cache(Some(&db)).await, "alice", NODE),
            Some(rep(NODE, 2))
        );
    }

    /// #533: deleting the identity drops its reputation, stored copy too.
    #[tokio::test]
    async fn forgetting_the_identity_drops_the_stored_answer() {
        let db = temp_db().await;
        let store = Store::new();
        store
            .store_answer(Some(&db), store.generation(), "alice", rep(NODE, 2))
            .await;

        store.forget(Some(&db)).await;

        assert!(store.cache(Some(&db)).await.is_empty());
        assert_eq!(
            db.get_setting(settings_keys::MY_REPUTATION).await.unwrap(),
            None
        );
    }

    /// A reply that lands after the identity was deleted belongs to it:
    /// neither kept nor written back.
    #[tokio::test]
    async fn an_answer_asked_before_a_forget_is_refused() {
        let db = temp_db().await;
        let store = Store::new();
        let asked_at = store.generation();

        store.forget(Some(&db)).await;
        let kept = store
            .store_answer(Some(&db), asked_at, "alice", rep(NODE, 2))
            .await;

        assert!(!kept);
        assert!(store.cache(Some(&db)).await.is_empty());
        assert_eq!(
            db.get_setting(settings_keys::MY_REPUTATION).await.unwrap(),
            None
        );
    }

    /// Full privacy turned on while a refresh waited for another one, or for
    /// the relays, still stops it: the mode is read again right before the
    /// request is sent, never only on entry.
    #[test]
    fn the_privacy_mode_is_read_again_right_before_sending() {
        use crate::source_guard::{item_body, production_code};
        let body = item_body(
            &production_code(include_str!("my_reputation.rs")),
            "pub async fn refresh_my_reputation() -> Result<Option<MyReputation>>",
        )
        .unwrap();
        let connected = body.find(".and_wait(").expect("waits for the relays");
        let checked = body[connected..]
            .find("ifcrate::api::reputation::get_privacy_mode(){returnOk(None);}")
            .map(|at| connected + at)
            .expect("reads the mode again");
        let asked = body.find("crate::api::orders::ask_daemon(").expect("asks");
        assert!(checked < asked);
    }
}
