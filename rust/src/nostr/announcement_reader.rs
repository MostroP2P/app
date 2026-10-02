//! The announcement reader (`specs/006-announcement-channel/spec.md` §5): the
//! single door every announcement passes, the cache it lives in, and the relay
//! subscription that feeds it.
//!
//! An announcement arriving from a relay and one restored from disk go through
//! the same [`door`]: allowlisted author, valid signature, the §3 schema, a
//! `created_at` neither older than 30 days nor more than 5 minutes ahead, an
//! `expiration` still in the future, and a version range that includes this
//! build. The cache holds the signed events, not what a build once parsed, so
//! a restore re-verifies them — and drops, from the list **and** the database,
//! whatever the clock has since aged out, online or not.
//!
//! The parsing and the allowlist live in [`super::announcements`]; this module
//! adds the clock, the cache and the relay.

use std::sync::atomic::{AtomicBool, Ordering};

use nostr_sdk::prelude::*;
use semver::Version;
use serde::{Deserialize, Serialize};

use crate::db::Storage;
use crate::nostr::announcements::{
    self, admit, Announcement, AnnouncementError, Severity, KIND_ANNOUNCEMENT,
};
use crate::nostr::first_answer::replaceable_rank;

/// Oldest `created_at` accepted, in seconds before now (§5.3).
pub const MAX_AGE_SECS: u64 = 30 * 24 * 3600;

/// Clock skew tolerated on `created_at`, in seconds after now (§5.3). Skew,
/// not post-dating: an announcement dated next week must not sit at the top
/// of every inbox until then.
pub const MAX_FUTURE_SKEW_SECS: u64 = 5 * 60;

/// Announcements kept, the newest by `created_at` (§5.4). Also the relay
/// filter's `limit`.
pub const CACHE_CAP: usize = 20;

/// The id of the one announcement subscription.
const SUBSCRIPTION_ID: &str = "announcements";

/// A cached announcement: the signed event as received, and what the user did
/// with it. Read and dismissed belong to this revision — a newer one at the
/// same address replaces the row and starts unread (§5.3).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StoredAnnouncement {
    /// `38387:<author hex>:<d>`, see [`address_of`].
    pub address: String,
    /// The event JSON, re-verified on every restore.
    pub event_json: String,
    /// The event's `created_at`, unix seconds; orders the cache cap.
    pub created_at: u64,
    pub read: bool,
    pub dismissed: bool,
}

/// A cached announcement that passed the door when it was restored.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CurrentAnnouncement {
    pub address: String,
    pub announcement: Announcement,
    pub read: bool,
    pub dismissed: bool,
}

/// Why the door turned an announcement away. Never shown: every failure here
/// is silent to the user (§5.6) and goes to the log.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Rejection {
    /// Not from an allowlisted key, not signed, or not §3.
    Invalid(AnnouncementError),
    /// `created_at` older than [`MAX_AGE_SECS`].
    TooOld,
    /// `created_at` more than [`MAX_FUTURE_SKEW_SECS`] ahead.
    FutureDated,
    /// Its `expiration` has passed.
    Expired,
    /// This build is outside `[min_version, max_version)`.
    OutsideVersionRange,
}

/// What [`ingest`] did with an event.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Ingested {
    /// Turned away by the door; nothing stored.
    Rejected(Rejection),
    /// The address already holds this revision or a newer one.
    AlreadySeen,
    /// Valid, but older than every one of a full cache; nothing stored.
    Crowded,
    /// A new address, stored unread.
    New,
    /// A newer revision at a known address, stored unread in its place.
    Superseded,
}

/// The address of an announcement: `(kind, pubkey, d)`, never `d` alone —
/// two allowlisted keys can pick the same `d` (§5.3).
pub fn address_of(author: &PublicKey, identifier: &str) -> String {
    format!("{KIND_ANNOUNCEMENT}:{}:{identifier}", author.to_hex())
}

/// §5.2 steps 1–6, at `now`, for an app at `version`. Step 7 — winning at
/// its address — needs the cache, and is [`ingest`]'s.
pub fn door(
    event: &Event,
    allowlist: &[PublicKey],
    now: Timestamp,
    version: &Version,
) -> Result<Announcement, Rejection> {
    let announcement = admit(event, allowlist).map_err(Rejection::Invalid)?;
    let created_at = announcement.created_at.as_secs();
    let now = now.as_secs();
    if created_at.saturating_add(MAX_AGE_SECS) < now {
        return Err(Rejection::TooOld);
    }
    if created_at > now.saturating_add(MAX_FUTURE_SKEW_SECS) {
        return Err(Rejection::FutureDated);
    }
    // NIP-40: the event is gone from the moment its expiration is reached.
    if announcement.body.expiration.as_secs() <= now {
        return Err(Rejection::Expired);
    }
    if !announcement.body.reaches(version) {
        return Err(Rejection::OutsideVersionRange);
    }
    Ok(announcement)
}

/// The relay filter for `authors` (§5.1), or `None` when there are none: an
/// empty allowlist opens no subscription at all.
pub fn announcement_filter(authors: &[PublicKey], now: Timestamp) -> Option<Filter> {
    if authors.is_empty() {
        return None;
    }
    Some(
        Filter::new()
            .kind(Kind::from(KIND_ANNOUNCEMENT))
            .authors(authors.iter().copied())
            .since(Timestamp::from_secs(
                now.as_secs().saturating_sub(MAX_AGE_SECS),
            ))
            .limit(CACHE_CAP),
    )
}

/// Serialises the cache's read-modify-write passes in this process.
static STORE_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

/// The origin-wide lock name for the same passes on the web, where every tab
/// shares one IndexedDB store.
#[cfg(target_arch = "wasm32")]
const ORIGIN_LOCK: &str = "mostro:db:announcements";

/// Held for a whole read-modify-write of the cache.
struct Exclusive {
    _local: tokio::sync::MutexGuard<'static, ()>,
    #[cfg(target_arch = "wasm32")]
    _origin: Option<crate::db::web_lock::OriginLock>,
}

/// Enter the cache's exclusive section: this process's mutex and, on the
/// web, the origin-wide lock when the browser offers one. Without the second,
/// two tabs could each read the cache, decide, and write an older revision
/// back over a newer one.
async fn exclusive() -> Exclusive {
    let local = STORE_LOCK.lock().await;
    Exclusive {
        _local: local,
        #[cfg(target_arch = "wasm32")]
        _origin: crate::db::web_lock::acquire(ORIGIN_LOCK).await,
    }
}

/// Run `event` through the door and, if it wins at its address, store it
/// unread. Serialised with [`restore`]: both rewrite the cache.
pub async fn ingest<S: Storage>(
    db: &S,
    event: &Event,
    allowlist: &[PublicKey],
    now: Timestamp,
    version: &Version,
) -> anyhow::Result<Ingested> {
    let announcement = match door(event, allowlist, now, version) {
        Ok(announcement) => announcement,
        Err(rejection) => {
            log::debug!("[announcements] {} turned away: {rejection:?}", event.id);
            return Ok(Ingested::Rejected(rejection));
        }
    };
    let address = address_of(&announcement.author, &announcement.body.identifier);

    let _section = exclusive().await;
    // Swept first: a row that expired since the last sweep must not count
    // against the cap, nor be the revision this one is compared with.
    let rows: Vec<StoredAnnouncement> = sweep(db, allowlist, now, version)
        .await?
        .into_iter()
        .map(|(row, _)| row)
        .collect();
    let held = rows.iter().find(|row| row.address == address);
    // The revision is `(created_at, id)`, the lower id winning a tie — the
    // same rank a replaceable event gets everywhere else in the crate.
    let held_rank = held
        .and_then(|row| Event::from_json(&row.event_json).ok())
        .map(|held| replaceable_rank(&held));
    if held_rank.is_some_and(|held| replaceable_rank(event) <= held) {
        return Ok(Ingested::AlreadySeen);
    }

    let evicted = over_the_cap(
        rows.iter()
            .filter(|row| row.address != address)
            .map(|row| (row.created_at, row.address.as_str()))
            .chain([(event.created_at.as_secs(), address.as_str())]),
    );
    if evicted.contains(&address) {
        return Ok(Ingested::Crowded);
    }
    db.save_announcement(&StoredAnnouncement {
        address: address.clone(),
        event_json: event.as_json(),
        created_at: event.created_at.as_secs(),
        read: false,
        dismissed: false,
    })
    .await?;
    for gone in &evicted {
        db.delete_announcement(gone).await?;
    }
    Ok(if held.is_some() {
        Ingested::Superseded
    } else {
        Ingested::New
    })
}

/// The addresses beyond [`CACHE_CAP`], keeping the newest `created_at` and,
/// between equals, the lowest address — the order the stores list in.
fn over_the_cap<'a>(rows: impl Iterator<Item = (u64, &'a str)>) -> Vec<String> {
    let mut rows: Vec<(u64, &str)> = rows.collect();
    rows.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(b.1)));
    rows.into_iter()
        .skip(CACHE_CAP)
        .map(|(_, address)| address.to_string())
        .collect()
}

/// Re-run every cached announcement through the door at `now` (§5.4), delete
/// the ones that fail from the database, and return the rest — `critical`
/// first, then newest first (§3.4).
pub async fn restore<S: Storage>(
    db: &S,
    allowlist: &[PublicKey],
    now: Timestamp,
    version: &Version,
) -> anyhow::Result<Vec<CurrentAnnouncement>> {
    let _section = exclusive().await;
    let mut current: Vec<CurrentAnnouncement> = sweep(db, allowlist, now, version)
        .await?
        .into_iter()
        .map(|(row, announcement)| CurrentAnnouncement {
            address: row.address,
            announcement,
            read: row.read,
            dismissed: row.dismissed,
        })
        .collect();
    // Stable, so equal ranks keep the store's newest-first order.
    current.sort_by_key(|c| {
        (
            c.announcement.body.severity != Severity::Critical,
            std::cmp::Reverse(c.announcement.created_at),
        )
    });
    Ok(current)
}

/// Every cached row through the door again at `now`, newest first; the ones
/// that fail, and any beyond the cap, are deleted. Callers hold
/// [`exclusive`].
async fn sweep<S: Storage>(
    db: &S,
    allowlist: &[PublicKey],
    now: Timestamp,
    version: &Version,
) -> anyhow::Result<Vec<(StoredAnnouncement, Announcement)>> {
    let mut kept = Vec::new();
    for row in db.list_announcements().await? {
        let verdict = recheck(&row, allowlist, now, version).and_then(|announcement| {
            if kept.len() < CACHE_CAP {
                Ok(announcement)
            } else {
                Err("over the cache cap".to_string())
            }
        });
        match verdict {
            Ok(announcement) => kept.push((row, announcement)),
            // Its read and dismissed state go with it: nothing may refer to
            // an address the cache no longer holds.
            Err(reason) => {
                log::info!("[announcements] dropping cached {}: {reason}", row.address);
                db.delete_announcement(&row.address).await?;
            }
        }
    }
    Ok(kept)
}

/// A cached row through the door again, from its signed event.
fn recheck(
    row: &StoredAnnouncement,
    allowlist: &[PublicKey],
    now: Timestamp,
    version: &Version,
) -> Result<Announcement, String> {
    let event = Event::from_json(&row.event_json).map_err(|e| format!("not an event ({e})"))?;
    let announcement =
        door(&event, allowlist, now, version).map_err(|rejection| format!("{rejection:?}"))?;
    if address_of(&announcement.author, &announcement.body.identifier) != row.address {
        return Err("stored under another address".to_string());
    }
    Ok(announcement)
}

static LOOP_ACTIVE: AtomicBool = AtomicBool::new(false);

/// Clears [`LOOP_ACTIVE`] when the loop ends, panics included.
struct LoopGuard;

impl Drop for LoopGuard {
    fn drop(&mut self) {
        LOOP_ACTIVE.store(false, Ordering::Release);
    }
}

/// Bring the channel up to date: re-check the cache against the clock, then
/// start the relay loop or, when it already runs, move its filter's window
/// to now. Called on every `Online` and every resume, like the order book;
/// with an empty allowlist it does nothing at all.
pub async fn subscribe_announcements() {
    let authors = announcements::allowed_authors();
    let version = announcements::app_version();
    // Even with no key left to subscribe to: a release that retires the last
    // one must still sweep what that key left in the cache.
    if let Some(db) = crate::db::app_db::db() {
        if let Err(e) = restore(db, &authors, Timestamp::now(), &version).await {
            log::warn!("[announcements] re-checking the cache failed: {e}");
        }
    }
    let Some(filter) = announcement_filter(&authors, Timestamp::now()) else {
        log::debug!("[announcements] allowlist empty: no subscription");
        return;
    };
    if LOOP_ACTIVE
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        // `live_subs` re-issues the recorded filter on every reconnect; left
        // alone, its `since` would trail further behind each day it runs.
        if let Ok(pool) = crate::api::nostr::get_pool() {
            if let Err(e) = crate::nostr::live_subs::live_subs()
                .replace(&pool.client(), SubscriptionId::new(SUBSCRIPTION_ID), filter)
                .await
            {
                log::warn!("[announcements] refreshing the filter failed: {e}");
            }
        }
        return;
    }
    crate::rt::spawn(async move {
        let _guard = LoopGuard;
        run_subscription(authors, filter, version).await;
    });
}

/// Subscribe on the shared pool — keyed with an ephemeral key, never a trade
/// key (§4.4) — and store whatever wins at its address. Publishes nothing.
async fn run_subscription(authors: Vec<PublicKey>, filter: Filter, version: Version) {
    let Ok(pool) = crate::api::nostr::get_pool() else {
        log::warn!("[announcements] no relay pool: not subscribing");
        return;
    };
    let client = pool.client();
    // Before subscribing, so nothing arrives between the two unheard.
    let mut rx = client.notifications();
    let id = SubscriptionId::new(SUBSCRIPTION_ID);
    if let Err(e) = crate::nostr::live_subs::live_subs()
        .replace(&client, id.clone(), filter)
        .await
    {
        log::warn!("[announcements] subscribe failed: {e}");
        return;
    }
    log::info!("[announcements] subscribed to {} key(s)", authors.len());

    while let Some(notification) = rx.next().await {
        let ClientNotification::Event {
            subscription_id,
            event,
            ..
        } = notification
        else {
            continue;
        };
        if subscription_id != id {
            continue;
        }
        let Some(db) = crate::db::app_db::db() else {
            continue;
        };
        match ingest(db, &event, &authors, Timestamp::now(), &version).await {
            Ok(outcome) => log::debug!("[announcements] {}: {outcome:?}", event.id),
            Err(e) => log::warn!("[announcements] storing {} failed: {e}", event.id),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::sqlite::SqliteStorage;
    use serde_json::{json, Value};
    use std::sync::atomic::AtomicU32;

    const NOW: u64 = 1_900_000_000;
    const DAY: u64 = 24 * 3600;

    fn now() -> Timestamp {
        Timestamp::from_secs(NOW)
    }

    fn app() -> Version {
        Version::new(2, 0, 10)
    }

    fn content(severity: &str, marker: &str) -> Value {
        let locale = |l: &str| json!({ "title": format!("{marker} {l}"), "body": "Body" });
        json!({
            "v": 1,
            "severity": severity,
            "locales": {
                "en": locale("en"), "es": locale("es"), "fr": locale("fr"),
                "de": locale("de"), "it": locale("it"), "nl": locale("nl"),
            },
        })
    }

    /// An announcement builder: `d`, `created_at`, `expiration` and extras.
    struct Draft {
        d: String,
        created_at: u64,
        expiration: u64,
        severity: &'static str,
        marker: String,
        extra: Vec<Tag>,
    }

    fn draft(d: &str) -> Draft {
        Draft {
            d: d.to_string(),
            created_at: NOW,
            expiration: NOW + 7 * DAY,
            severity: "info",
            marker: "Title".to_string(),
            extra: Vec::new(),
        }
    }

    impl Draft {
        fn at(mut self, created_at: u64) -> Self {
            self.created_at = created_at;
            self
        }
        fn expiring(mut self, expiration: u64) -> Self {
            self.expiration = expiration;
            self
        }
        fn severity(mut self, severity: &'static str) -> Self {
            self.severity = severity;
            self
        }
        fn marked(mut self, marker: &str) -> Self {
            self.marker = marker.to_string();
            self
        }
        fn tag(mut self, name: &str, value: &str) -> Self {
            self.extra.push(Tag::custom(name, [value]));
            self
        }
        fn sign(self, keys: &Keys) -> Event {
            let mut tags = vec![
                Tag::identifier(self.d),
                Tag::expiration(Timestamp::from_secs(self.expiration)),
            ];
            tags.extend(self.extra);
            EventBuilder::new(
                Kind::from(KIND_ANNOUNCEMENT),
                content(self.severity, &self.marker).to_string(),
            )
            .tags(tags)
            .custom_created_at(Timestamp::from_secs(self.created_at))
            .finalize(keys)
            .unwrap()
        }
    }

    async fn store() -> SqliteStorage {
        static COUNTER: AtomicU32 = AtomicU32::new(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "mostro_announcements_{}_{n}.db",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        SqliteStorage::open(path.to_str().unwrap()).await.unwrap()
    }

    async fn ingest_now(db: &SqliteStorage, event: &Event, keys: &[PublicKey]) -> Ingested {
        ingest(db, event, keys, now(), &app()).await.unwrap()
    }

    async fn row(db: &SqliteStorage, address: &str) -> Option<StoredAnnouncement> {
        db.list_announcements()
            .await
            .unwrap()
            .into_iter()
            .find(|r| r.address == address)
    }

    async fn mark_read(db: &SqliteStorage, address: &str) {
        let mut stored = row(db, address).await.unwrap();
        stored.read = true;
        db.save_announcement(&stored).await.unwrap();
    }

    // ── The door (§5.2, §5.3, §5.5) ─────────────────────────────────────

    #[test]
    fn a_current_announcement_passes_the_door() {
        let keys = Keys::generate();
        let event = draft("a").sign(&keys);

        let announcement = door(&event, &[keys.public_key()], now(), &app()).unwrap();

        assert_eq!(announcement.event_id, event.id);
    }

    #[test]
    fn an_invalid_announcement_is_refused_with_its_reason() {
        let keys = Keys::generate();
        let event = draft("a").sign(&keys);

        assert_eq!(
            door(&event, &[], now(), &app()),
            Err(Rejection::Invalid(AnnouncementError::AuthorNotAllowed))
        );
    }

    #[test]
    fn older_than_thirty_days_is_too_old() {
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        let old = draft("a").at(NOW - 31 * DAY).sign(&keys);
        let edge = draft("a").at(NOW - 30 * DAY).sign(&keys);

        assert_eq!(door(&old, &allow, now(), &app()), Err(Rejection::TooOld));
        assert!(door(&edge, &allow, now(), &app()).is_ok());
    }

    #[test]
    fn dated_beyond_the_skew_is_refused() {
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        let ahead = draft("a").at(NOW + 10 * 60).sign(&keys);
        let skewed = draft("a").at(NOW + 4 * 60).sign(&keys);

        assert_eq!(
            door(&ahead, &allow, now(), &app()),
            Err(Rejection::FutureDated)
        );
        assert!(door(&skewed, &allow, now(), &app()).is_ok());
    }

    #[test]
    fn expired_on_arrival_is_refused() {
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        let at_expiry = draft("a").expiring(NOW).sign(&keys);
        let before = draft("a").expiring(NOW + 1).sign(&keys);

        assert_eq!(
            door(&at_expiry, &allow, now(), &app()),
            Err(Rejection::Expired)
        );
        assert!(door(&before, &allow, now(), &app()).is_ok());
    }

    #[test]
    fn a_build_outside_the_range_is_refused() {
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        let about_this_build = draft("a").tag("max_version", "2.0.10").sign(&keys);
        let about_the_next = draft("a").tag("max_version", "2.0.11").sign(&keys);

        assert_eq!(
            door(&about_this_build, &allow, now(), &app()),
            Err(Rejection::OutsideVersionRange)
        );
        assert!(door(&about_the_next, &allow, now(), &app()).is_ok());
    }

    // ── The filter (§5.1) ───────────────────────────────────────────────

    #[test]
    fn an_empty_allowlist_opens_no_subscription() {
        assert!(announcement_filter(&[], now()).is_none());
    }

    #[test]
    fn the_filter_asks_for_thirty_days_of_the_allowlisted_keys() {
        let key = Keys::generate().public_key();

        let filter = announcement_filter(&[key], now()).unwrap();

        assert_eq!(
            filter.kinds.unwrap().into_iter().collect::<Vec<_>>(),
            vec![Kind::from(KIND_ANNOUNCEMENT)]
        );
        assert_eq!(
            filter.authors.unwrap().into_iter().collect::<Vec<_>>(),
            vec![key]
        );
        assert_eq!(filter.since, Some(Timestamp::from_secs(NOW - 30 * DAY)));
        assert_eq!(filter.limit, Some(CACHE_CAP));
    }

    #[test]
    fn the_address_is_kind_author_and_d() {
        let key = Keys::generate().public_key();

        assert_eq!(
            address_of(&key, "outage-1"),
            format!("38387:{}:outage-1", key.to_hex())
        );
    }

    // ── Arrival (§5.3) ──────────────────────────────────────────────────

    #[tokio::test]
    async fn a_new_announcement_is_stored_unread() {
        let db = store().await;
        let keys = Keys::generate();
        let event = draft("a").sign(&keys);

        assert_eq!(
            ingest_now(&db, &event, &[keys.public_key()]).await,
            Ingested::New
        );

        let stored = row(&db, &address_of(&keys.public_key(), "a"))
            .await
            .unwrap();
        assert_eq!(stored.event_json, event.as_json());
        assert_eq!(stored.created_at, NOW);
        assert!(!stored.read && !stored.dismissed);
    }

    #[tokio::test]
    async fn a_rejected_announcement_is_not_stored() {
        let db = store().await;
        let keys = Keys::generate();
        let expired = draft("a").expiring(NOW - 1).sign(&keys);

        assert_eq!(
            ingest_now(&db, &expired, &[keys.public_key()]).await,
            Ingested::Rejected(Rejection::Expired)
        );
        assert!(db.list_announcements().await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_redelivery_is_not_re_announced() {
        let db = store().await;
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        let event = draft("a").sign(&keys);
        let address = address_of(&keys.public_key(), "a");
        ingest_now(&db, &event, &allow).await;
        mark_read(&db, &address).await;

        assert_eq!(ingest_now(&db, &event, &allow).await, Ingested::AlreadySeen);
        assert!(row(&db, &address).await.unwrap().read);
    }

    #[tokio::test]
    async fn a_newer_revision_replaces_and_is_unread_again() {
        let db = store().await;
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        let address = address_of(&keys.public_key(), "maintenance");
        let wrong = draft("maintenance").marked("Down at 20:00").sign(&keys);
        let fixed = draft("maintenance")
            .at(NOW + 60)
            .marked("Down at 22:00")
            .sign(&keys);
        ingest_now(&db, &wrong, &allow).await;
        mark_read(&db, &address).await;

        assert_eq!(ingest_now(&db, &fixed, &allow).await, Ingested::Superseded);

        let stored = row(&db, &address).await.unwrap();
        assert_eq!(stored.event_json, fixed.as_json());
        assert!(!stored.read && !stored.dismissed);
    }

    #[tokio::test]
    async fn an_older_revision_does_not_replace() {
        let db = store().await;
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        let newer = draft("a").at(NOW).sign(&keys);
        let older = draft("a").at(NOW - 60).marked("Older").sign(&keys);
        ingest_now(&db, &newer, &allow).await;

        assert_eq!(ingest_now(&db, &older, &allow).await, Ingested::AlreadySeen);
        let stored = row(&db, &address_of(&keys.public_key(), "a")).await;
        assert_eq!(stored.unwrap().event_json, newer.as_json());
    }

    /// Two revisions within one second: the lower id wins, whichever relay
    /// answered first, so two phones never hold two texts of one announcement.
    #[tokio::test]
    async fn on_a_created_at_tie_the_lower_id_wins_in_either_order() {
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        let one = draft("a").marked("One").sign(&keys);
        let two = draft("a").marked("Two").sign(&keys);
        let (low, high) = if one.id.to_hex() < two.id.to_hex() {
            (one, two)
        } else {
            (two, one)
        };
        let address = address_of(&keys.public_key(), "a");

        let high_first = store().await;
        ingest_now(&high_first, &high, &allow).await;
        assert_eq!(
            ingest_now(&high_first, &low, &allow).await,
            Ingested::Superseded
        );
        assert_eq!(
            row(&high_first, &address).await.unwrap().event_json,
            low.as_json()
        );

        let low_first = store().await;
        ingest_now(&low_first, &low, &allow).await;
        assert_eq!(
            ingest_now(&low_first, &high, &allow).await,
            Ingested::AlreadySeen
        );
        assert_eq!(
            row(&low_first, &address).await.unwrap().event_json,
            low.as_json()
        );
    }

    #[tokio::test]
    async fn the_same_d_from_two_keys_is_two_announcements() {
        let db = store().await;
        let first = Keys::generate();
        let successor = Keys::generate();
        let allow = [first.public_key(), successor.public_key()];
        ingest_now(&db, &draft("release").sign(&first), &allow).await;
        mark_read(&db, &address_of(&first.public_key(), "release")).await;

        assert_eq!(
            ingest_now(&db, &draft("release").sign(&successor), &allow).await,
            Ingested::New
        );

        let current = restore(&db, &allow, now(), &app()).await.unwrap();
        assert_eq!(current.len(), 2);
        let successors = current
            .iter()
            .find(|c| c.announcement.author == successor.public_key())
            .unwrap();
        assert!(!successors.read);
    }

    #[tokio::test]
    async fn the_cache_keeps_the_twenty_newest() {
        let db = store().await;
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        for i in 0..=CACHE_CAP as u64 {
            let event = draft(&format!("n{i}")).at(NOW - 100 + i).sign(&keys);
            ingest_now(&db, &event, &allow).await;
        }

        let rows = db.list_announcements().await.unwrap();
        assert_eq!(rows.len(), CACHE_CAP);
        assert!(row(&db, &address_of(&keys.public_key(), "n0"))
            .await
            .is_none());

        let older_than_all = draft("late").at(NOW - 1000).sign(&keys);
        assert_eq!(
            ingest_now(&db, &older_than_all, &allow).await,
            Ingested::Crowded
        );
        assert!(row(&db, &address_of(&keys.public_key(), "late"))
            .await
            .is_none());
    }

    /// A row that expired since the last sweep is dead weight: it must not
    /// crowd out a valid arrival, nor push a live row out of the cache.
    #[tokio::test]
    async fn a_dead_row_does_not_count_against_the_cap() {
        let db = store().await;
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        for i in 0..CACHE_CAP as u64 {
            let mut draft = draft(&format!("n{i}")).at(NOW - 100 + i);
            if i == CACHE_CAP as u64 - 1 {
                draft = draft.expiring(NOW + 10);
            }
            ingest_now(&db, &draft.sign(&keys), &allow).await;
        }
        let later = Timestamp::from_secs(NOW + 20);
        let older_than_all = draft("late").at(NOW - 1000).sign(&keys);

        let outcome = ingest(&db, &older_than_all, &allow, later, &app())
            .await
            .unwrap();

        assert_eq!(outcome, Ingested::New);
        let rows = db.list_announcements().await.unwrap();
        assert_eq!(rows.len(), CACHE_CAP);
        let expired = address_of(&keys.public_key(), &format!("n{}", CACHE_CAP - 1));
        assert!(rows.iter().all(|r| r.address != expired));
    }

    // ── Restore and the offline sweep (§5.4) ────────────────────────────

    #[tokio::test]
    async fn restore_returns_what_was_stored_with_its_state() {
        let db = store().await;
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        let event = draft("a").sign(&keys);
        ingest_now(&db, &event, &allow).await;
        mark_read(&db, &address_of(&keys.public_key(), "a")).await;

        let current = restore(&db, &allow, now(), &app()).await.unwrap();

        assert_eq!(current.len(), 1);
        assert_eq!(current[0].address, address_of(&keys.public_key(), "a"));
        assert_eq!(current[0].announcement.event_id, event.id);
        assert!(current[0].read);
        assert!(!current[0].dismissed);
    }

    /// The device was offline the whole time: nothing arrived to displace
    /// what it holds, and the clock alone must still retire it.
    #[tokio::test]
    async fn restore_sweeps_what_aged_or_expired_while_offline() {
        let db = store().await;
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        let neighbour = draft("neighbour").expiring(NOW + 20 * DAY).sign(&keys);
        let outage = draft("outage").expiring(NOW + 4 * 3600).sign(&keys);
        let ageing = draft("ageing")
            .at(NOW - 29 * DAY)
            .expiring(NOW + 20 * DAY)
            .sign(&keys);
        for event in [&neighbour, &outage, &ageing] {
            assert_eq!(ingest_now(&db, event, &allow).await, Ingested::New);
        }

        let two_days_later = Timestamp::from_secs(NOW + 2 * DAY);
        let current = restore(&db, &allow, two_days_later, &app()).await.unwrap();

        let addresses: Vec<&str> = current.iter().map(|c| c.address.as_str()).collect();
        let neighbour_address = address_of(&keys.public_key(), "neighbour");
        assert_eq!(addresses, vec![neighbour_address.as_str()]);
        let rows = db.list_announcements().await.unwrap();
        assert_eq!(rows.len(), 1, "swept rows must leave the database too");
        assert_eq!(rows[0].address, neighbour_address);
    }

    #[tokio::test]
    async fn a_key_dropped_from_the_allowlist_takes_its_announcements_with_it() {
        let db = store().await;
        let retired = Keys::generate();
        let kept = Keys::generate();
        let both = [retired.public_key(), kept.public_key()];
        ingest_now(&db, &draft("a").sign(&retired), &both).await;
        ingest_now(&db, &draft("b").sign(&kept), &both).await;

        let current = restore(&db, &[kept.public_key()], now(), &app())
            .await
            .unwrap();

        assert_eq!(current.len(), 1);
        assert_eq!(current[0].announcement.author, kept.public_key());
        assert_eq!(db.list_announcements().await.unwrap().len(), 1);
    }

    #[tokio::test]
    async fn an_emptied_allowlist_still_clears_the_cache() {
        let db = store().await;
        let keys = Keys::generate();
        ingest_now(&db, &draft("a").sign(&keys), &[keys.public_key()]).await;

        let current = restore(&db, &[], now(), &app()).await.unwrap();

        assert!(current.is_empty());
        assert!(db.list_announcements().await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_cached_row_that_no_longer_verifies_is_dropped() {
        let db = store().await;
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        let event = draft("a").sign(&keys);
        let mut forged: Value = serde_json::from_str(&event.as_json()).unwrap();
        forged["content"] = json!(content("critical", "Forged").to_string());
        db.save_announcement(&StoredAnnouncement {
            address: address_of(&keys.public_key(), "a"),
            event_json: forged.to_string(),
            created_at: NOW,
            read: false,
            dismissed: false,
        })
        .await
        .unwrap();
        db.save_announcement(&StoredAnnouncement {
            address: "38387:garbage:x".into(),
            event_json: "not an event".into(),
            created_at: NOW,
            read: false,
            dismissed: false,
        })
        .await
        .unwrap();

        assert!(restore(&db, &allow, now(), &app())
            .await
            .unwrap()
            .is_empty());
        assert!(db.list_announcements().await.unwrap().is_empty());
    }

    #[tokio::test]
    async fn restore_lists_critical_first_then_newest() {
        let db = store().await;
        let keys = Keys::generate();
        let allow = [keys.public_key()];
        let old_critical = draft("security")
            .at(NOW - 3600)
            .severity("critical")
            .sign(&keys);
        let newer_info = draft("release").at(NOW - 60).sign(&keys);
        let newest_warning = draft("outage").severity("warning").sign(&keys);
        for event in [&newer_info, &old_critical, &newest_warning] {
            ingest_now(&db, event, &allow).await;
        }

        let current = restore(&db, &allow, now(), &app()).await.unwrap();

        let order: Vec<&str> = current
            .iter()
            .map(|c| c.announcement.body.identifier.as_str())
            .collect();
        assert_eq!(order, vec!["security", "outage", "release"]);
        assert_eq!(current[0].announcement.body.severity, Severity::Critical);
    }

    /// Announcements are addressed to the install: a new identity keeps them
    /// (CLAUDE.md, "every new store must say which side it is on").
    #[tokio::test]
    async fn announcements_survive_an_identity_wipe() {
        let db = store().await;
        let keys = Keys::generate();
        ingest_now(&db, &draft("a").sign(&keys), &[keys.public_key()]).await;

        db.clear_identity_data().await.unwrap();

        assert_eq!(db.list_announcements().await.unwrap().len(), 1);
    }

    #[tokio::test]
    async fn rows_round_trip_through_the_store() {
        let db = store().await;
        let first = StoredAnnouncement {
            address: "38387:aa:x".into(),
            event_json: "{}".into(),
            created_at: 10,
            read: false,
            dismissed: false,
        };
        let second = StoredAnnouncement {
            address: "38387:aa:y".into(),
            created_at: 20,
            ..first.clone()
        };
        db.save_announcement(&first).await.unwrap();
        db.save_announcement(&second).await.unwrap();
        let replaced = StoredAnnouncement {
            read: true,
            ..first.clone()
        };
        db.save_announcement(&replaced).await.unwrap();

        assert_eq!(
            db.list_announcements().await.unwrap(),
            vec![second.clone(), replaced]
        );
        db.delete_announcement("38387:aa:x").await.unwrap();
        db.delete_announcement("38387:aa:absent").await.unwrap();
        assert_eq!(db.list_announcements().await.unwrap(), vec![second]);
    }
}
