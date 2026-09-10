/// Nostr relay management API exposed to Flutter via flutter_rust_bridge.
///
/// Thin facade over `RelayPool` — keeps all async/relay logic in the pool
/// while exposing a flat function interface for the Dart side.
use anyhow::Result;
use nostr_sdk::prelude::Event;
use std::sync::Arc;
use tokio::sync::OnceCell;

use crate::api::types::{ConnectionState, RelayInfo};
use crate::db::Storage;
use crate::nostr::relay_pool::RelayPool;
use crate::queue::outbox;

/// Global relay pool singleton, initialised once by `initialize()`.
static POOL: OnceCell<Arc<RelayPool>> = OnceCell::const_new();

/// Newly auto-added relay URLs, one message per applied kind 10002 event.
static RELAY_SYNC_TX: std::sync::OnceLock<tokio::sync::broadcast::Sender<Vec<String>>> =
    std::sync::OnceLock::new();

fn relay_sync_tx() -> &'static tokio::sync::broadcast::Sender<Vec<String>> {
    RELAY_SYNC_TX.get_or_init(|| tokio::sync::broadcast::channel(16).0)
}

/// The newest kind 10002 generation applied, per node pubkey. Relays hold
/// different generations of a replaceable event, so the live subscription can
/// deliver an older list after a newer one; only the newest is ever applied.
///
/// A generation is `(created_at, event id)`, not just `created_at`: NIP-01
/// breaks a timestamp tie between two revisions of a replaceable event by
/// keeping the **lowest** event id, so two lists published within the same
/// second must be ordered by id and not both rejected.
type RelayListGeneration = (u64, nostr_sdk::prelude::EventId);

static RELAY_LIST_SEEN: std::sync::OnceLock<
    tokio::sync::Mutex<std::collections::HashMap<String, RelayListGeneration>>,
> = std::sync::OnceLock::new();

fn relay_list_seen(
) -> &'static tokio::sync::Mutex<std::collections::HashMap<String, RelayListGeneration>> {
    RELAY_LIST_SEEN.get_or_init(|| tokio::sync::Mutex::new(std::collections::HashMap::new()))
}

/// Order two generations of the same node's relay list the way NIP-01 orders
/// revisions of a replaceable event: newer `created_at` wins, and on a tie the
/// lower event id wins.
fn generation_is_newer(candidate: RelayListGeneration, applied: RelayListGeneration) -> bool {
    let (cand_at, cand_id) = candidate;
    let (seen_at, seen_id) = applied;
    match cand_at.cmp(&seen_at) {
        std::cmp::Ordering::Greater => true,
        std::cmp::Ordering::Less => false,
        // Same second: NIP-01 retains the lexically lowest id.
        std::cmp::Ordering::Equal => cand_id.as_bytes() < seen_id.as_bytes(),
    }
}

fn pool() -> Result<&'static Arc<RelayPool>> {
    POOL.get().ok_or_else(|| anyhow::anyhow!("NotInitialized"))
}

/// Initialize the Nostr client with a relay list.
///
/// If `relays` is empty or `None`, uses the persisted relay set — every
/// active relay the user or a Mostro node's kind 10002 list added, with the
/// user's removals of announced relays restored as the blacklist — and,
/// when nothing is persisted yet, the compiled-in defaults (which are then
/// seeded so later runs read them back).
pub async fn initialize(relays: Option<Vec<String>>) -> Result<()> {
    if POOL.get().is_some() {
        return Err(anyhow::anyhow!("AlreadyInitialized"));
    }

    let urls: Vec<String> = relays
        .unwrap_or_default()
        .into_iter()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();

    let (urls, persisted) = if urls.is_empty() {
        let persisted = load_persisted_relays().await;
        let active: Vec<String> = persisted
            .iter()
            .filter(|r| r.is_active && !r.is_blacklisted)
            .map(|r| r.url.clone())
            .collect();
        if active.is_empty() {
            (default_relays(), persisted)
        } else {
            (active, persisted)
        }
    } else {
        (urls, Vec::new())
    };

    // get_or_try_init is atomic — only one caller creates the pool even if
    // two race past the is_some() guard above.
    let pool_ref = POOL
        .get_or_try_init(|| async { RelayPool::new(urls).await })
        .await?;

    // Restore what a previous session learned: sources of the persisted
    // rows and the blacklist that keeps removed announced relays out.
    pool_ref.restore_persisted(&persisted).await;
    if persisted.is_empty() {
        seed_default_relays().await;
    }

    // Spawn a background task that flushes the outbox whenever the relay pool
    // transitions to Online.  The task exits when the broadcast channel closes.
    let pool_ref = POOL.get().unwrap().clone();
    crate::rt::spawn(async move {
        let mut rx = pool_ref.subscribe_connection_state();
        log::info!("[nostr] connection state watcher started");
        loop {
            match rx.recv().await {
                Ok(ConnectionState::Online) => {
                    log::info!("[nostr] relay pool ONLINE — fetching node capabilities, flushing queue, subscribing orders");
                    // Fetch capabilities first so queued messages are wrapped with the
                    // correct difficulty before being flushed.
                    fetch_and_set_node_capabilities().await;
                    let _ = flush_message_queue().await;
                    // Start (or re-start) Kind 38383 order book subscription.
                    crate::api::orders::subscribe_orders().await;
                    // Rebuild chat listeners for persisted active trades —
                    // sessions are in-memory, so after a restart nothing else
                    // would resubscribe. Idempotent: orders with a live chat
                    // task are skipped by the single-owner guard.
                    crate::api::messages::resubscribe_active_chats().await;
                    // Same rearm for dispute chats: solver assignments are
                    // committed before listener startup, which can fail while
                    // keys or connectivity are missing — coming online is the
                    // retry point (PR #254 review).
                    crate::api::disputes::resubscribe_active_dispute_chats().await;
                }
                Ok(state) => {
                    log::info!("[nostr] connection state changed: {state:?}");
                }
                Err(_) => {
                    log::warn!("[nostr] connection state channel closed");
                    break;
                }
            }
        }
    });

    Ok(())
}

/// Add a new relay and connect to it.
pub async fn add_relay(url: String) -> Result<RelayInfo> {
    let info = pool()?.add_relay(&url).await?;
    persist_relay(&info).await;
    Ok(info)
}

/// Remove a relay and disconnect.
///
/// A relay a Mostro node announced stays persisted as blacklisted, so the
/// node's list cannot bring it back on the next start either.
pub async fn remove_relay(url: String) -> Result<()> {
    let pool = pool()?;
    let removed = pool.get_relays().await.into_iter().find(|r| r.url == url);
    pool.remove_relay(&url).await?;
    match removal_effect(removed) {
        Some(row) => persist_relay(&row).await,
        None => unpersist_relay(&url).await,
    }
    Ok(())
}

/// What removing a relay leaves in storage: `Some(row)` to persist, `None` to
/// delete the row outright.
///
/// A relay a Mostro node announced is kept as a blacklisted row instead of
/// being deleted — the node re-announces its list on every reconnect, so
/// forgetting the removal would bring the relay straight back.
fn removal_effect(removed: Option<RelayInfo>) -> Option<RelayInfo> {
    let mut info = removed?;
    if !matches!(info.source, crate::api::types::RelaySource::MostroDiscovered) {
        return None;
    }
    info.is_active = false;
    info.is_blacklisted = true;
    info.status = crate::api::types::RelayStatus::Disconnected;
    Some(info)
}

/// Stream of relay URLs auto-added from the active node's kind 10002 relay
/// list, one emission per applied event (only when something was added).
pub async fn on_relay_auto_synced() -> Result<RelayAutoSyncStream> {
    Ok(RelayAutoSyncStream {
        rx: relay_sync_tx().subscribe(),
    })
}

/// Wrapper so flutter_rust_bridge can generate a Dart Stream.
pub struct RelayAutoSyncStream {
    rx: tokio::sync::broadcast::Receiver<Vec<String>>,
}

impl RelayAutoSyncStream {
    pub async fn next(&mut self) -> Option<Vec<String>> {
        loop {
            match self.rx.recv().await {
                Ok(urls) => return Some(urls),
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

/// Apply a kind 10002 relay list published by the active node (the caller
/// checks the author): parse it, add every announced relay we do not have
/// and have not blacklisted, persist the additions, and tell the UI. Older
/// generations than one already applied for this node are ignored.
pub(crate) async fn apply_relay_list_event(event: &Event) {
    let node = event.pubkey.to_hex();
    let generation = (event.created_at.as_secs(), event.id);
    if !note_relay_list_generation(&mut *relay_list_seen().lock().await, &node, generation) {
        return;
    }

    let announced = crate::nostr::relay_list::parse_relay_list(event);
    crate::api::logging::blog_info(
        "relay",
        format!(
            "kind 10002 from node={}: {} relay(s) announced",
            crate::api::logging::short_id(&node),
            announced.len()
        ),
    );
    let Ok(pool) = pool() else {
        return;
    };
    let added = pool.sync_discovered(&announced).await;
    if added.is_empty() {
        return;
    }
    for info in pool.get_relays().await.iter().filter(|r| added.contains(&r.url)) {
        persist_relay(info).await;
    }
    crate::api::logging::blog_info(
        "relay",
        format!(
            "auto-added {} relay(s) from node list: {}",
            added.len(),
            added
                .iter()
                .map(|u| crate::api::logging::display_relay(u))
                .collect::<Vec<_>>()
                .join(", ")
        ),
    );
    let _ = relay_sync_tx().send(added);
}

/// Record `generation` as the newest relay list seen for `node` and say
/// whether it is newer than every one applied before (strictly: a replay of
/// the same generation from another relay is not applied twice).
fn note_relay_list_generation(
    seen: &mut std::collections::HashMap<String, RelayListGeneration>,
    node: &str,
    generation: RelayListGeneration,
) -> bool {
    if seen
        .get(node)
        .is_some_and(|&applied| !generation_is_newer(generation, applied))
    {
        return false;
    }
    seen.insert(node.to_string(), generation);
    true
}

// ── Relay persistence (best effort: web has no relay store yet, #233) ───────

async fn load_persisted_relays() -> Vec<RelayInfo> {
    let Some(db) = crate::db::app_db::db() else {
        return Vec::new();
    };
    match db.list_relays().await {
        Ok(rows) => rows,
        Err(e) => {
            log::warn!("[nostr] relay list not loaded from storage: {e}");
            Vec::new()
        }
    }
}

async fn seed_default_relays() {
    if let Some(db) = crate::db::app_db::db() {
        if let Err(e) = crate::db::seeds::seed_defaults(db).await {
            log::warn!("[nostr] default relays not seeded: {e}");
        }
    }
}

async fn persist_relay(info: &RelayInfo) {
    if let Some(db) = crate::db::app_db::db() {
        if let Err(e) = db.save_relay(info).await {
            log::warn!(
                "[nostr] relay {} not persisted: {e}",
                crate::api::logging::display_relay(&info.url)
            );
        }
    }
}

async fn unpersist_relay(url: &str) {
    if let Some(db) = crate::db::app_db::db() {
        if let Err(e) = db.delete_relay(url).await {
            log::warn!(
                "[nostr] relay {} not removed from storage: {e}",
                crate::api::logging::display_relay(url)
            );
        }
    }
}

/// Get all configured relays with current status.
pub async fn get_relays() -> Result<Vec<RelayInfo>> {
    Ok(pool()?.get_relays().await)
}

/// Get overall connection state.
pub async fn get_connection_state() -> Result<ConnectionState> {
    Ok(pool()?.connection_state().await)
}

/// Attempt to send all queued offline messages.
///
/// Iterates the in-memory outbox, publishes each pending event via the relay
/// pool, and applies exponential backoff on failure.  Events are pruned once
/// sent or after [`MAX_RETRIES`] failures.
///
/// Returns the count of messages successfully published in this pass.
pub async fn flush_message_queue() -> Result<u32> {
    let client = pool()?.client();
    let sent = outbox::outbox()
        .flush(|event_json| {
            let client = client.clone();
            async move {
                let event: Event = serde_json::from_str(&event_json)?;
                client
                    .send_event(&event)
                    .await
                    .map_err(|e| anyhow::anyhow!("{e}"))?;
                Ok(())
            }
        })
        .await;
    Ok(sent)
}

// ── Streams ─────────────────────────────────────────────────────────────────

/// Stream that emits when overall connection state changes.
pub async fn on_connection_state_changed() -> Result<ConnectionStateStream> {
    let rx = pool()?.subscribe_connection_state();
    Ok(ConnectionStateStream { rx })
}

/// Stream that emits when any individual relay's status changes.
pub async fn on_relay_status_changed() -> Result<RelayStatusStream> {
    let rx = pool()?.subscribe_relay_status();
    Ok(RelayStatusStream { rx })
}

/// Wrapper so flutter_rust_bridge can generate a Dart Stream.
pub struct ConnectionStateStream {
    rx: tokio::sync::broadcast::Receiver<ConnectionState>,
}

impl ConnectionStateStream {
    pub async fn next(&mut self) -> Option<ConnectionState> {
        loop {
            match self.rx.recv().await {
                Ok(state) => return Some(state),
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

/// Wrapper so flutter_rust_bridge can generate a Dart Stream.
pub struct RelayStatusStream {
    rx: tokio::sync::broadcast::Receiver<RelayInfo>,
}

impl RelayStatusStream {
    pub async fn next(&mut self) -> Option<RelayInfo> {
        loop {
            match self.rx.recv().await {
                Ok(info) => return Some(info),
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

/// Fetch the Mostro daemon's Kind 38385 (instance status) tags.
///
/// Queries the relay pool for a Kind 38385 event published by `mostro_pubkey_hex`.
/// Returns the raw tag list as `Vec<Vec<String>>` so the Dart layer can parse
/// each tag into the `MostroInstance` model.
///
/// Returns `None` if no matching event arrives within 10 seconds (relay
/// not reachable, or daemon has never published a Kind 38385 event).
pub async fn fetch_mostro_instance_tags(
    mostro_pubkey_hex: String,
) -> Result<Option<Vec<Vec<String>>>> {
    use nostr_sdk::prelude::*;
    use std::time::Duration;

    let client = pool()?.client();

    let pubkey = nostr_sdk::prelude::PublicKey::from_hex(&mostro_pubkey_hex)
        .map_err(|e| anyhow::anyhow!("invalid pubkey hex: {e}"))?;

    // Kind 38385 is a NIP-33 addressable event; the `d` tag uniquely identifies
    // the Mostro instance and equals the daemon's pubkey (hex). Adding the
    // d-tag constraint prevents the relay from returning a stale or unrelated
    // event from the same author.
    let filter = Filter::new()
        .kind(Kind::from(38385u16))
        .author(pubkey)
        .custom_tag(SingleLetterTag::LOWERCASE_D, &mostro_pubkey_hex)
        .limit(1);

    let events = client
        .fetch_events(filter)
        .timeout(Duration::from_secs(10))
        .await
        .map_err(|e| anyhow::anyhow!("fetch_events failed: {e}"))?;

    if let Some(event) = events.first() {
        let tags = event
            .tags
            .iter()
            .map(|t| t.as_slice().to_vec())
            .collect::<Vec<Vec<String>>>();
        Ok(Some(tags))
    } else {
        Ok(None)
    }
}

/// Price of one BTC in `fiat_code`, as published by `mostro_pubkey_hex` in its
/// Kind 30078 (`d` = `mostro-rates`) event.
///
/// Lets the client tell, before submitting, whether a market-price order will
/// land inside the node's sats limits (#337): the daemon prices such an order
/// as `fiat_amount / price * 1E8` from this same aggregate, so this is the
/// number its `OutOfRangeSatsAmount` check will use.
///
/// Returns `None` — never an error — for every "no usable rate" case: the node
/// publishes no rates event (publishing is optional), the one on the relay has
/// expired, its payload is unusable, or it quotes no such currency. Callers
/// must then submit unchecked and let the daemon decide, which is the
/// fail-open behaviour PR #302 chose for fixed-sats amounts. `Err` is reserved
/// for a client that is not initialised, a malformed pubkey, or a relay query
/// that failed outright.
///
/// Answers from a per-node cache bounded by the event's own NIP-40 expiration,
/// so the three amount fields of a range order cost one relay query, not three.
pub async fn fetch_exchange_rate(
    mostro_pubkey_hex: String,
    fiat_code: String,
) -> Result<Option<f64>> {
    use crate::mostro::rates;
    use nostr_sdk::prelude::*;
    use std::time::Duration;

    let now = crate::rt::unix_now();
    if let Some(rate) = rates::cached_rate(&mostro_pubkey_hex, &fiat_code, now) {
        return Ok(Some(rate));
    }

    let client = pool()?.client();

    let pubkey = nostr_sdk::prelude::PublicKey::from_hex(&mostro_pubkey_hex)
        .map_err(|e| anyhow::anyhow!("invalid pubkey hex: {e}"))?;

    let filter = Filter::new()
        .kind(Kind::from(rates::RATES_KIND))
        .author(pubkey)
        .custom_tag(SingleLetterTag::LOWERCASE_D, rates::RATES_D_TAG)
        .limit(1);

    let events = client
        .fetch_events(filter)
        .timeout(Duration::from_secs(10))
        .await
        .map_err(|e| anyhow::anyhow!("fetch_events failed: {e}"))?;

    let Some(event) = select_rates_event(events, &pubkey) else {
        log::warn!("[rates] node {mostro_pubkey_hex} published no usable kind 30078 event");
        rates::clear();
        return Ok(None);
    };

    let expires_at = rates::expires_at(
        event.created_at.as_secs() as i64,
        tag_value(&event, "expiration").and_then(|v| v.parse::<i64>().ok()),
    );
    if now >= expires_at {
        // A relay that ignores NIP-40 must not let a zombie price through.
        log::warn!("[rates] discarding expired kind 30078 event from {mostro_pubkey_hex}");
        rates::clear();
        return Ok(None);
    }

    let Some(parsed) = rates::parse_rates_content(&event.content) else {
        log::warn!("[rates] unusable kind 30078 payload from {mostro_pubkey_hex}");
        rates::clear();
        return Ok(None);
    };

    rates::store(&mostro_pubkey_hex, parsed, expires_at);
    Ok(rates::cached_rate(&mostro_pubkey_hex, &fiat_code, now))
}

/// The newest authentic rates event among `events`, or `None`.
///
/// Defence in depth, as v1 does: a relay is free to answer with events the
/// filter never asked for, and pricing an order off another kind, another
/// d-tag or another author's event would be worse than not checking at all.
///
/// The signature check is what makes the author check mean anything. It was
/// load-bearing under nostr-sdk 0.44, which did not guarantee that a fetched
/// event had been verified before it reached the caller
/// (GHSA-f96q-5f6p-v7cj): a relay could hand us an event carrying the node's
/// pubkey that the node never signed. 0.45 fixed that — every incoming event
/// is verified (and filter-matched) inside the relay before the caller sees
/// it — so this is now defence in depth, kept on purpose: it is the one
/// property of this event the client cannot re-derive, a forged price would
/// silently move the whole range check, and the cost is one signature check
/// on a single event fetched once. Verification runs before the newest-first
/// pick, so a forgery cannot shadow the genuine event by claiming a later
/// `created_at` either.
fn select_rates_event(
    events: impl IntoIterator<Item = nostr_sdk::prelude::Event>,
    pubkey: &nostr_sdk::prelude::PublicKey,
) -> Option<nostr_sdk::prelude::Event> {
    use crate::mostro::rates;
    use nostr_sdk::prelude::*;

    events
        .into_iter()
        .filter(|e| {
            e.kind == Kind::from(rates::RATES_KIND)
                && e.pubkey == *pubkey
                && tag_value(e, "d").as_deref() == Some(rates::RATES_D_TAG)
        })
        .filter(|e| match e.verify() {
            Ok(()) => true,
            Err(err) => {
                log::warn!("[rates] discarding unauthenticated kind 30078 event: {err}");
                false
            }
        })
        .max_by_key(|e| e.created_at)
}

/// First value of the single-letter or named tag `name` on `event`.
fn tag_value(event: &nostr_sdk::prelude::Event, name: &str) -> Option<String> {
    event
        .tags
        .iter()
        .map(|t| t.as_slice())
        .find(|t| t.first().map(String::as_str) == Some(name))
        .and_then(|t| t.get(1).cloned())
}

/// Fetch everything the active Mostro node advertises about itself from its
/// Kind 38385 event and store it globally: the PoW requirement, and (phase C1)
/// the escrow mode plus its Cashu parameters.
///
/// Called each time the relay pool goes Online and after a node switch, so both
/// values stay current for the active node. One fetch serves both — they come
/// from the same event, and a second relay query for the escrow tags would
/// double the traffic for no new information.
pub(crate) async fn fetch_and_set_node_capabilities() {
    use crate::mostro::escrow_mode;

    let mostro_pubkey_hex = crate::config::active_mostro_pubkey();
    match fetch_mostro_instance_tags(mostro_pubkey_hex.clone()).await {
        Ok(Some(tags)) => {
            // Both difficulties: `pow` for every event, `pow_first_contact`
            // for the first event of a trade. An absent first-contact tag is
            // recorded as unknown rather than as `pow`, and both land in one
            // snapshot tagged with the node they came from, so an in-flight
            // first-contact wrap can neither mix generations nor mine at a
            // previous node's (or the startup default's) difficulty — see
            // mostro::pow.
            let (difficulty, first_contact) = crate::mostro::pow::parse_pow_tags(&tags);
            crate::mostro::pow::set_pows(&mostro_pubkey_hex, difficulty, first_contact);

            // Which wire format this node reads. Getting it wrong is silent —
            // the daemon never decrypts the event — so the verdict is stored
            // per node, only on a successful tag fetch (the Ok(None)/Err arms
            // leave it alone, keeping "not fetched" distinct from "fetched,
            // no tag"). See mostro::protocol_version.
            crate::mostro::protocol_version::set_protocol_version(
                &mostro_pubkey_hex,
                crate::mostro::protocol_version::parse_protocol_version(&tags),
            );

            // Today's daemons publish no escrow tags at all, so this resolves
            // to Unknown — which keeps every Cashu path shut. See escrow_mode.
            let (mode, config) = escrow_mode::parse_tags(&tags);
            escrow_mode::set_from_tags(mode, config);
        }
        Ok(None) => {
            log::warn!("[nostr] no Kind 38385 event found — PoW defaults to 0");
            crate::mostro::pow::set_pows(&mostro_pubkey_hex, 0, None);
            // Nothing was advertised: stay Unknown rather than assume
            // Lightning, and leave Cashu closed.
            escrow_mode::clear();
        }
        Err(e) => {
            log::warn!("[nostr] failed to fetch Kind 38385 for node capabilities: {e}");
            // Drop the escrow mode too. A reconnect whose fetch times out must
            // not keep answering "cashu" from the last successful fetch: the
            // module treats unreachable exactly like unfetched, and only a
            // clear makes the gate fail closed in that window. PoW is left
            // alone on purpose — a stale difficulty still gets messages
            // accepted, whereas a stale escrow mode opens a path.
            escrow_mode::clear();
        }
    }
}

// ── Internals ───────────────────────────────────────────────────────────────

fn default_relays() -> Vec<String> {
    crate::config::DEFAULT_RELAYS
        .iter()
        .map(|s| s.to_string())
        .collect()
}

/// Provide access to the global pool for other Rust modules (e.g. orders API).
#[allow(dead_code)]
pub(crate) fn get_pool() -> Result<&'static Arc<RelayPool>> {
    pool()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mostro::rates;
    use nostr_sdk::prelude::*;

    const RATES: &str = r#"{"BTC":{"USD":50000.0}}"#;

    fn rates_event(keys: &Keys, content: &str, created_at: u64) -> Event {
        EventBuilder::new(Kind::from(rates::RATES_KIND), content)
            .tag(Tag::parse(["d", rates::RATES_D_TAG]).unwrap())
            .custom_created_at(Timestamp::from(created_at))
            .finalize(keys)
            .unwrap()
    }

    /// What a hostile relay can do without the node's key: take a real event
    /// and rewrite the price. Everything the field checks look at survives —
    /// kind, author, `d` tag — and only the signature gives it away.
    fn forge_content(event: &Event, content: &str) -> Event {
        let mut json: serde_json::Value = serde_json::from_str(&event.as_json()).unwrap();
        json["content"] = serde_json::Value::String(content.to_string());
        Event::from_json(json.to_string()).unwrap()
    }

    #[test]
    fn selects_a_signed_rates_event() {
        let node = Keys::generate();
        let event = rates_event(&node, RATES, 1000);

        let selected = select_rates_event([event.clone()], &node.public_key());

        assert_eq!(selected.map(|e| e.id), Some(event.id));
    }

    #[test]
    fn selects_the_newest_of_several() {
        let node = Keys::generate();
        let old = rates_event(&node, RATES, 1000);
        let new = rates_event(&node, r#"{"BTC":{"USD":60000.0}}"#, 2000);

        let selected = select_rates_event([old, new.clone()], &node.public_key());

        assert_eq!(selected.map(|e| e.id), Some(new.id));
    }

    #[test]
    fn rejects_a_forged_rates_event() {
        let node = Keys::generate();
        let genuine = rates_event(&node, RATES, 1000);
        let forged = forge_content(&genuine, r#"{"BTC":{"USD":1.0}}"#);

        assert_eq!(forged.pubkey, node.public_key());
        assert!(forged.verify().is_err(), "the forgery must not authenticate");

        assert!(select_rates_event([forged], &node.public_key()).is_none());
    }

    /// A forgery must not be able to bury the real price by claiming a later
    /// `created_at`, which is why the signature check runs before the pick.
    #[test]
    fn a_newer_forgery_does_not_shadow_the_genuine_event() {
        let node = Keys::generate();
        let genuine = rates_event(&node, RATES, 1000);
        let forged = forge_content(&rates_event(&node, RATES, 2000), r#"{"BTC":{"USD":1.0}}"#);

        let selected = select_rates_event([forged, genuine.clone()], &node.public_key());

        assert_eq!(selected.map(|e| e.id), Some(genuine.id));
    }

    #[test]
    fn rejects_another_author_kind_or_d_tag() {
        let node = Keys::generate();
        let other = Keys::generate();

        let wrong_author = rates_event(&other, RATES, 1000);
        assert!(select_rates_event([wrong_author], &node.public_key()).is_none());

        let wrong_kind = EventBuilder::new(Kind::TextNote, RATES)
            .tag(Tag::parse(["d", rates::RATES_D_TAG]).unwrap())
            .finalize(&node)
            .unwrap();
        assert!(select_rates_event([wrong_kind], &node.public_key()).is_none());

        let wrong_d_tag = EventBuilder::new(Kind::from(rates::RATES_KIND), RATES)
            .tag(Tag::parse(["d", "something-else"]).unwrap())
            .finalize(&node)
            .unwrap();
        assert!(select_rates_event([wrong_d_tag], &node.public_key()).is_none());
    }
}

/// The remove → restart → restore → re-add lifecycle, against a real SQLite
/// file rather than an in-memory fixture: a relay the node announced and the
/// user removed must stay out across a restart, and adding it back by hand
/// must lift the blacklist for good.
///
/// Native only: the IndexedDB backend does not persist relays yet (#233).
#[cfg(all(test, not(target_arch = "wasm32")))]
mod relay_blacklist_restart_tests {
    use super::{removal_effect, RelayInfo};
    use crate::db::sqlite::SqliteStorage;
    use crate::db::Storage;
    use crate::nostr::relay_pool::RelayPool;
    use std::sync::atomic::{AtomicU32, Ordering};

    const DEFAULT: &str = "wss://default.example";
    const ANNOUNCED: &str = "wss://announced.example";

    fn temp_db_path() -> std::path::PathBuf {
        static COUNTER: AtomicU32 = AtomicU32::new(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir().join(format!("mostro_relay_bl_{}_{n}.db", std::process::id()))
    }

    /// A fresh pool restored from `storage`, the way `initialize(None)` builds
    /// one at startup.
    async fn boot(storage: &SqliteStorage) -> (std::sync::Arc<RelayPool>, Vec<RelayInfo>) {
        let persisted = storage.list_relays().await.unwrap();
        let urls: Vec<String> = if persisted.is_empty() {
            vec![DEFAULT.to_string()]
        } else {
            persisted
                .iter()
                .filter(|r| !r.is_blacklisted)
                .map(|r| r.url.clone())
                .collect()
        };
        let pool = RelayPool::new(urls).await.unwrap();
        pool.restore_persisted(&persisted).await;
        (pool, persisted)
    }

    #[tokio::test]
    async fn a_removed_announced_relay_stays_out_across_a_restart_until_re_added() {
        let path = temp_db_path();
        let db = path.to_str().unwrap().to_string();

        // ── Session 1: the node announces a relay, the user removes it ──
        {
            let storage = SqliteStorage::open(&db).await.unwrap();
            let (pool, _) = boot(&storage).await;
            let added = pool.sync_discovered(&[ANNOUNCED.to_string()]).await;
            assert_eq!(added, vec![ANNOUNCED.to_string()], "relay not auto-added");
            for info in pool.get_relays().await {
                storage.save_relay(&info).await.unwrap();
            }

            let removed = pool.get_relays().await.into_iter().find(|r| r.url == ANNOUNCED);
            pool.remove_relay(ANNOUNCED).await.unwrap();
            let row = removal_effect(removed).expect("an announced relay is kept, not deleted");
            assert!(row.is_blacklisted);
            storage.save_relay(&row).await.unwrap();
        }

        // ── Session 2: restart — the blacklist comes back from storage ──
        {
            let storage = SqliteStorage::open(&db).await.unwrap();
            let (pool, persisted) = boot(&storage).await;
            assert!(
                persisted.iter().any(|r| r.url == ANNOUNCED && r.is_blacklisted),
                "blacklisted row did not survive the restart"
            );
            assert_eq!(pool.blacklist().await, vec![ANNOUNCED.to_string()]);

            // The node re-announces it on reconnect: it must not come back.
            let added = pool.sync_discovered(&[ANNOUNCED.to_string()]).await;
            assert!(added.is_empty(), "a blacklisted relay was re-added: {added:?}");

            // Adding it by hand lifts the blacklist and persists it as active.
            let info = pool.add_relay(ANNOUNCED).await.unwrap();
            assert!(!info.is_blacklisted);
            assert!(pool.blacklist().await.is_empty());
            storage.save_relay(&info).await.unwrap();
        }

        // ── Session 3: restart again — it is a normal relay now ──
        {
            let storage = SqliteStorage::open(&db).await.unwrap();
            let (pool, _) = boot(&storage).await;
            assert!(pool.blacklist().await.is_empty(), "blacklist not cleared");
            assert!(
                pool.get_relays().await.iter().any(|r| r.url == ANNOUNCED),
                "re-added relay missing after restart"
            );
        }

        let _ = std::fs::remove_file(&path);
    }
}

#[cfg(test)]
mod relay_list_generation_tests {
    use super::{note_relay_list_generation, RelayListGeneration};
    use nostr_sdk::prelude::EventId;
    use std::collections::HashMap;

    /// An event id whose first byte is `lead`; the rest is zero, so ids
    /// compare in the order their `lead` bytes do.
    fn id(lead: u8) -> EventId {
        let mut bytes = [0u8; 32];
        bytes[0] = lead;
        EventId::from_byte_array(bytes)
    }

    fn gen(created_at: u64, lead: u8) -> RelayListGeneration {
        (created_at, id(lead))
    }

    #[test]
    fn first_list_for_a_node_is_applied() {
        let mut seen = HashMap::new();
        assert!(note_relay_list_generation(&mut seen, "node-a", gen(100, 1)));
    }

    #[test]
    fn older_or_replayed_generations_are_ignored() {
        let mut seen = HashMap::new();
        assert!(note_relay_list_generation(&mut seen, "node-a", gen(100, 1)));
        assert!(!note_relay_list_generation(&mut seen, "node-a", gen(100, 1)));
        assert!(!note_relay_list_generation(&mut seen, "node-a", gen(99, 1)));
        assert!(note_relay_list_generation(&mut seen, "node-a", gen(101, 1)));
    }

    #[test]
    fn generations_are_tracked_per_node() {
        let mut seen = HashMap::new();
        assert!(note_relay_list_generation(&mut seen, "node-a", gen(100, 1)));
        assert!(note_relay_list_generation(&mut seen, "node-b", gen(50, 1)));
    }

    /// NIP-01 breaks a `created_at` tie between two revisions of a
    /// replaceable event by keeping the lowest event id — so the winner must
    /// be applied whichever order the two arrive in.
    #[test]
    fn an_equal_timestamp_list_with_a_lower_id_wins() {
        let mut seen = HashMap::new();
        assert!(note_relay_list_generation(&mut seen, "node-a", gen(100, 9)));
        assert!(note_relay_list_generation(&mut seen, "node-a", gen(100, 2)));
    }

    #[test]
    fn an_equal_timestamp_list_with_a_higher_id_loses() {
        let mut seen = HashMap::new();
        assert!(note_relay_list_generation(&mut seen, "node-a", gen(100, 2)));
        assert!(!note_relay_list_generation(&mut seen, "node-a", gen(100, 9)));
    }
}
