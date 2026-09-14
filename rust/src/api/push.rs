//! Push registration: the I/O around the rules in `mostro::push`
//! (docs/PUSH_NOTIFICATIONS.md §7.1, §8.2).
//!
//! Dart owns the device: it obtains the FCM token and hands it over with
//! [`set_push_token`]. Rust owns everything after that — which trade pubkeys
//! the push server holds a token for, when each is re-sent, what is let go —
//! persisted in the settings store so a restart, a token refresh or an
//! opt-out act on the full set. Every path runs the same [`reconcile_push`]:
//! startup, resume, a timer, a token or toggle change, and every trade row or
//! claim write that changes what is wanted.
//!
//! The server is content-free and forgets silently, so nothing here is
//! fatal: a failure backs off and is retried, and the app trades whether the
//! push server is up or not.

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, Ordering};

use anyhow::{anyhow, bail, Result};
use tokio::sync::broadcast::{self, error::RecvError};

use crate::api::types::{PushPlatform, PushStatus};
use crate::db::settings_keys;
use crate::db::Storage;
use crate::mostro::push::{
    self as rules, Action, PushRegistration, Refusals, Wanted, NODE_REFUSAL_SECS,
};

/// Per-request timeout, on every platform.
#[cfg_attr(test, allow(dead_code))]
const REQUEST_TIMEOUT_SECS: u64 = 10;

/// A burst of triggers (a restore writes many rows) runs one reconcile.
const COALESCE_SECS: u64 = 2;

/// While the app runs, a reconcile at least this often: the server's TTL is
/// 48 h and the refresh rule re-sends past 12 h, so this only has to be more
/// frequent than the refresh.
const TIMER_SECS: u64 = 6 * 3600;

// ── The server ──────────────────────────────────────────────────────────────

/// One answer from the push server, reduced to what the rules react to.
#[derive(Debug, Clone, PartialEq, Eq)]
#[flutter_rust_bridge::frb(ignore)]
pub(crate) enum ServerOutcome {
    /// `200` / `202`.
    Accepted,
    /// `403`: the operator does not accept keys issued by this node.
    Refused,
    /// `429`, with `Retry-After` in seconds when the server sent one.
    RateLimited { retry_after: Option<i64> },
    /// `400`: a client bug — logged, never retried on its own.
    BadRequest(String),
    /// Transport error, timeout, or any other status.
    Failed(String),
}

/// The three calls the client makes (§3.1). A trait so the reconcile can be
/// exercised against a fake, and so the HTTP details stay in one place.
#[flutter_rust_bridge::frb(ignore)]
pub(crate) trait PushServer {
    fn register(
        &self,
        trade_pubkey: &str,
        token: &str,
        platform: PushPlatform,
        mostro_pubkey: &str,
    ) -> impl std::future::Future<Output = ServerOutcome>;
    fn unregister(&self, trade_pubkey: &str) -> impl std::future::Future<Output = ServerOutcome>;
}

/// The real server over HTTPS. Nothing but the JSON bodies of §3.1 is ever
/// sent: no `Authorization`, no request id, no sender — the server refuses
/// them by design.
#[cfg_attr(test, allow(dead_code))]
#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct HttpPushServer;

#[cfg_attr(test, allow(dead_code))]
#[flutter_rust_bridge::frb(ignore)]
impl HttpPushServer {
    fn client() -> Result<reqwest::Client> {
        static CLIENT: std::sync::OnceLock<reqwest::Client> = std::sync::OnceLock::new();
        if let Some(c) = CLIENT.get() {
            return Ok(c.clone());
        }
        let builder = reqwest::Client::builder();
        #[cfg(not(target_arch = "wasm32"))]
        let builder = builder.timeout(std::time::Duration::from_secs(REQUEST_TIMEOUT_SECS));
        let client = builder
            .build()
            .map_err(|e| anyhow!("push client build failed: {e}"))?;
        Ok(CLIENT.get_or_init(|| client).clone())
    }

    async fn post(path: &str, body: serde_json::Value) -> ServerOutcome {
        let client = match Self::client() {
            Ok(c) => c,
            Err(e) => return ServerOutcome::Failed(e.to_string()),
        };
        let url = format!("{}{path}", crate::config::push_server_url());
        let send = client.post(&url).json(&body).send();
        let response = match crate::rt::time::timeout(
            crate::rt::time::Duration::from_secs(REQUEST_TIMEOUT_SECS),
            send,
        )
        .await
        {
            Ok(Ok(r)) => r,
            Ok(Err(e)) => return ServerOutcome::Failed(format!("transport: {e}")),
            Err(_) => return ServerOutcome::Failed("timeout".into()),
        };
        let status = response.status().as_u16();
        let retry_after = response
            .headers()
            .get("retry-after")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.trim().parse::<i64>().ok());
        let body = response.text().await.unwrap_or_default();
        classify(status, retry_after, &body)
    }
}

/// The status line and body, as the rules see them (§3.1).
fn classify(status: u16, retry_after: Option<i64>, body: &str) -> ServerOutcome {
    let message = || {
        serde_json::from_str::<serde_json::Value>(body)
            .ok()
            .and_then(|v| {
                v.get("message")
                    .and_then(|m| m.as_str())
                    .map(str::to_string)
            })
            .unwrap_or_else(|| body.chars().take(120).collect())
    };
    match status {
        200 | 202 => ServerOutcome::Accepted,
        403 => ServerOutcome::Refused,
        429 => ServerOutcome::RateLimited { retry_after },
        400 => ServerOutcome::BadRequest(message()),
        other => ServerOutcome::Failed(format!("HTTP {other}: {}", message())),
    }
}

#[cfg_attr(test, allow(dead_code))]
#[flutter_rust_bridge::frb(ignore)]
impl PushServer for HttpPushServer {
    async fn register(
        &self,
        trade_pubkey: &str,
        token: &str,
        platform: PushPlatform,
        mostro_pubkey: &str,
    ) -> ServerOutcome {
        Self::post(
            "/api/register",
            serde_json::json!({
                "trade_pubkey": trade_pubkey,
                "token": token,
                "platform": platform.as_wire(),
                "mostro_pubkey": mostro_pubkey,
            }),
        )
        .await
    }

    async fn unregister(&self, trade_pubkey: &str) -> ServerOutcome {
        Self::post(
            "/api/unregister",
            serde_json::json!({ "trade_pubkey": trade_pubkey }),
        )
        .await
    }
}

// ── Persisted state ─────────────────────────────────────────────────────────

/// Everything the reconcile reads and writes back, in one place.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct PushState {
    pub enabled: bool,
    pub token: Option<String>,
    pub platform: Option<PushPlatform>,
    pub registrations: HashMap<String, PushRegistration>,
    pub refusals: Refusals,
}

async fn load_state(db: &impl Storage) -> PushState {
    let get = |key: &'static str| async move { db.get_setting(key).await.ok().flatten() };
    PushState {
        enabled: get(settings_keys::PUSH_ENABLED).await.as_deref() != Some("false"),
        token: get(settings_keys::PUSH_TOKEN)
            .await
            .filter(|t| !t.is_empty()),
        platform: get(settings_keys::PUSH_PLATFORM)
            .await
            .and_then(|p| PushPlatform::from_wire(&p)),
        registrations: get(settings_keys::PUSH_REGISTRATIONS)
            .await
            .and_then(|json| serde_json::from_str(&json).ok())
            .unwrap_or_default(),
        refusals: get(settings_keys::PUSH_NODE_REFUSALS)
            .await
            .and_then(|json| serde_json::from_str(&json).ok())
            .unwrap_or_default(),
    }
}

async fn save_registrations(db: &impl Storage, state: &PushState) {
    for (key, value) in [
        (
            settings_keys::PUSH_REGISTRATIONS,
            serde_json::to_string(&state.registrations).unwrap_or_default(),
        ),
        (
            settings_keys::PUSH_NODE_REFUSALS,
            serde_json::to_string(&state.refusals).unwrap_or_default(),
        ),
    ] {
        if let Err(e) = db.set_setting(key, &value).await {
            log::warn!("[push] {key} not persisted: {e}");
        }
    }
    write_mirror(state);
}

/// The small file the OS-scheduled refresh (T1.5) re-POSTs from: the token
/// and the accepted registrations, nothing else. Native only, next to the
/// database; removed when there is nothing to refresh.
fn write_mirror(state: &PushState) {
    #[cfg(not(target_arch = "wasm32"))]
    {
        let Some(path) = mirror_path() else {
            return;
        };
        let live: Vec<serde_json::Value> = state
            .registrations
            .values()
            .filter(|r| r.is_registered())
            .map(|r| {
                serde_json::json!({
                    "trade_pubkey": r.trade_pubkey,
                    "mostro_pubkey": r.mostro_pubkey,
                })
            })
            .collect();
        let result = match (&state.token, state.enabled, live.is_empty()) {
            (Some(token), true, false) => std::fs::write(
                &path,
                serde_json::json!({
                    "token": token,
                    "platform": state.platform.map(|p| p.as_wire()),
                    "registrations": live,
                })
                .to_string(),
            ),
            _ => match std::fs::remove_file(&path) {
                Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e),
                _ => Ok(()),
            },
        };
        if let Err(e) = result {
            log::warn!("[push] mirror not written: {e}");
        }
    }
    #[cfg(target_arch = "wasm32")]
    let _ = state;
}

#[cfg(not(target_arch = "wasm32"))]
fn mirror_path() -> Option<std::path::PathBuf> {
    let db_path = std::path::Path::new(crate::db::app_db::app_db_path()?);
    Some(db_path.with_file_name("push_mirror.json"))
}

// ── Reconcile ───────────────────────────────────────────────────────────────

/// What one reconcile did, for the log and the tests.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct ReconcileReport {
    pub registered: u32,
    pub unregistered: u32,
    pub failed: u32,
    pub refused: u32,
    pub last_error: Option<String>,
}

/// Apply the rules to `state` against `server`, mutating `state` into what
/// must be persisted. No storage here: the caller loads and saves, so the
/// whole decision path runs against a fake server in tests.
pub(crate) async fn reconcile_core(
    server: &impl PushServer,
    state: &mut PushState,
    wanted: &Wanted,
    now: i64,
) -> ReconcileReport {
    let mut report = ReconcileReport::default();
    let (Some(token), Some(platform), true) = (state.token.clone(), state.platform, state.enabled)
    else {
        // Disabled, or no device token: the server should hold nothing.
        let mut keys: Vec<String> = state.registrations.keys().cloned().collect();
        keys.sort();
        for key in keys {
            let registered = state.registrations[&key].is_registered();
            if !registered {
                state.registrations.remove(&key);
                continue;
            }
            match server.unregister(&key).await {
                ServerOutcome::Accepted => {
                    state.registrations.remove(&key);
                    report.unregistered += 1;
                }
                outcome => note_failure(state, &key, &outcome, now, &mut report),
            }
        }
        return report;
    };

    let token_hash = rules::token_hash(&token);
    for action in rules::plan(
        wanted,
        &state.registrations,
        &token_hash,
        &state.refusals,
        now,
    ) {
        match action {
            Action::Register {
                trade_pubkey,
                mostro_pubkey,
            } => {
                match server
                    .register(&trade_pubkey, &token, platform, &mostro_pubkey)
                    .await
                {
                    ServerOutcome::Accepted => {
                        state
                            .registrations
                            .entry(trade_pubkey.clone())
                            .or_insert_with(|| {
                                PushRegistration::pending(&trade_pubkey, &mostro_pubkey)
                            })
                            .note_accepted(&mostro_pubkey, &token_hash, now);
                        report.registered += 1;
                    }
                    ServerOutcome::Refused => {
                        state.refusals.insert(mostro_pubkey.clone(), now);
                        report.refused += 1;
                        report.last_error = Some("PushNodeRefused".into());
                        log::warn!(
                            "[push] node {} refused by the push server; its keys are skipped for {}h",
                            crate::api::logging::short_id(&mostro_pubkey),
                            NODE_REFUSAL_SECS / 3600
                        );
                    }
                    outcome => {
                        state
                            .registrations
                            .entry(trade_pubkey.clone())
                            .or_insert_with(|| {
                                PushRegistration::pending(&trade_pubkey, &mostro_pubkey)
                            });
                        note_failure(state, &trade_pubkey, &outcome, now, &mut report);
                    }
                }
            }
            Action::Unregister { trade_pubkey } => match server.unregister(&trade_pubkey).await {
                ServerOutcome::Accepted => {
                    state.registrations.remove(&trade_pubkey);
                    report.unregistered += 1;
                }
                outcome => note_failure(state, &trade_pubkey, &outcome, now, &mut report),
            },
            Action::NoteUnwanted { trade_pubkey } => {
                if let Some(r) = state.registrations.get_mut(&trade_pubkey) {
                    r.unwanted_since = Some(now);
                }
            }
            Action::NoteWanted { trade_pubkey } => {
                if let Some(r) = state.registrations.get_mut(&trade_pubkey) {
                    r.unwanted_since = None;
                }
            }
            Action::Forget { trade_pubkey } => {
                state.registrations.remove(&trade_pubkey);
            }
        }
    }
    // A refusal is kept one window past its expiry (a retry that fails again
    // re-arms it in place), then dropped so the map does not grow with every
    // node ever refused.
    state
        .refusals
        .retain(|_, at| now - *at < 2 * NODE_REFUSAL_SECS);
    report
}

fn note_failure(
    state: &mut PushState,
    trade_pubkey: &str,
    outcome: &ServerOutcome,
    now: i64,
    report: &mut ReconcileReport,
) {
    let (retry_after, marker) = match outcome {
        ServerOutcome::RateLimited { retry_after } => (*retry_after, "PushRateLimited"),
        ServerOutcome::BadRequest(msg) => {
            log::warn!("[push] the server rejected a request as malformed: {msg}");
            (None, "PushBadRequest")
        }
        ServerOutcome::Failed(msg) => {
            log::info!("[push] request failed: {msg}");
            (None, "PushServerUnreachable")
        }
        ServerOutcome::Accepted | ServerOutcome::Refused => return,
    };
    if let Some(r) = state.registrations.get_mut(trade_pubkey) {
        r.note_failed(now, retry_after);
    }
    report.failed += 1;
    report.last_error = Some(marker.into());
}

/// What the push server should hold right now, from the persisted rows
/// (§7.1): the same facts the kind-14 filter is built from.
async fn current_wanted(db: &impl Storage) -> Wanted {
    let trades = db.list_trades().await.unwrap_or_default();
    let claims = db.list_bond_claims().await.unwrap_or_default();
    let indexes: HashSet<u32> = trades
        .iter()
        .map(|t| t.trade_key_index)
        .chain(claims.iter().filter_map(|c| c.trade_index))
        .collect();
    let mut keys: HashMap<u32, String> = HashMap::new();
    for index in indexes {
        if let Ok(k) = crate::api::identity::get_active_trade_keys(index).await {
            keys.insert(index, k.public_key().to_hex());
        }
    }
    rules::wanted_pubkeys(
        &trades,
        &claims,
        &crate::config::active_mostro_pubkey(),
        |index| keys.get(&index).cloned(),
    )
}

/// The issuing nodes of every trade row that can still receive daemon
/// messages, for the kind-14 filter's `authors`: a key the push server is
/// asked to wake the app for must be one the filter hears (§7.1).
pub(crate) async fn issuing_nodes_of_live_trades() -> HashSet<String> {
    let Some(db) = crate::db::app_db::db() else {
        return HashSet::new();
    };
    db.list_trades()
        .await
        .unwrap_or_default()
        .into_iter()
        .filter(|t| !crate::mostro::status::is_hard_terminal(&t.order.status))
        .filter(|t| !t.order.creator_pubkey.is_empty())
        .map(|t| t.order.creator_pubkey.to_lowercase())
        .collect()
}

static RECONCILE_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
static DIRTY: AtomicBool = AtomicBool::new(false);
static SCHEDULED: AtomicBool = AtomicBool::new(false);

/// Ask for a reconcile soon. Cheap and synchronous, so every writer that
/// changes what is wanted can call it; a burst runs one pass after
/// [`COALESCE_SECS`]. A no-op outside an async runtime (unit tests).
pub(crate) fn request_reconcile() {
    DIRTY.store(true, Ordering::Release);
    if SCHEDULED.swap(true, Ordering::AcqRel) {
        return;
    }
    #[cfg(not(target_arch = "wasm32"))]
    if tokio::runtime::Handle::try_current().is_err() {
        SCHEDULED.store(false, Ordering::Release);
        return;
    }
    crate::rt::spawn(async {
        crate::rt::time::sleep(crate::rt::time::Duration::from_secs(COALESCE_SECS)).await;
        SCHEDULED.store(false, Ordering::Release);
        reconcile_push().await;
    });
}

/// Bring what the push server holds in step with what is wanted, now.
/// Single-flight: a pass in progress finishes first, and a request that
/// arrived meanwhile makes it run again rather than in parallel. Nothing
/// here fails: every outcome is logged and reflected in [`get_push_status`].
pub async fn reconcile_push() {
    let _guard = RECONCILE_LOCK.lock().await;
    loop {
        DIRTY.store(false, Ordering::Release);
        reconcile_with(&production_server()).await;
        if !DIRTY.load(Ordering::Acquire) {
            break;
        }
    }
}

pub(crate) async fn reconcile_with(server: &impl PushServer) {
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    let now = crate::rt::unix_now();
    let mut state = load_state(db).await;
    let wanted = if state.enabled && state.token.is_some() {
        current_wanted(db).await
    } else {
        Wanted::new()
    };
    let report = reconcile_core(server, &mut state, &wanted, now).await;
    save_registrations(db, &state).await;
    *last_report().lock().unwrap() = Some((report.clone(), wanted.len() as u32));
    log::info!(
        "[push] reconcile: wanted={} registered={} +{} -{} failed={} refused={}",
        wanted.len(),
        state
            .registrations
            .values()
            .filter(|r| r.is_registered())
            .count(),
        report.registered,
        report.unregistered,
        report.failed,
        report.refused
    );
    emit_status(status_of(&state, &report, wanted.len() as u32, now));
}

/// The server every production path talks to. Under `cargo test` it is a
/// stub that fails every call: the trade-row tests trigger reconciles as a
/// side effect, and none of them may reach the real push server.
#[cfg(not(test))]
fn production_server() -> HttpPushServer {
    HttpPushServer
}

#[cfg(test)]
fn production_server() -> tests::UnreachableServer {
    tests::UnreachableServer
}

fn last_report() -> &'static std::sync::Mutex<Option<(ReconcileReport, u32)>> {
    static LAST: std::sync::Mutex<Option<(ReconcileReport, u32)>> = std::sync::Mutex::new(None);
    &LAST
}

fn status_of(state: &PushState, report: &ReconcileReport, wanted: u32, now: i64) -> PushStatus {
    let active = crate::config::active_mostro_pubkey().to_lowercase();
    PushStatus {
        enabled: state.enabled,
        has_token: state.token.is_some(),
        registered: state
            .registrations
            .values()
            .filter(|r| r.is_registered())
            .count() as u32,
        wanted,
        last_success_at: state
            .registrations
            .values()
            .filter(|r| r.is_registered())
            .map(|r| r.registered_at)
            .max(),
        last_error: report.last_error.clone(),
        node_refused_until: state
            .refusals
            .get(&active)
            .copied()
            .filter(|at| rules::refusal_active(*at, now))
            .map(|at| at + NODE_REFUSAL_SECS),
    }
}

// ── Timer ───────────────────────────────────────────────────────────────────

static TIMER_ACTIVE: AtomicBool = AtomicBool::new(false);

/// One reconcile now and then every [`TIMER_SECS`] while the app runs. Called
/// once the relay pool is up and the DM filter seeded — a registration for a
/// key the filter does not cover is a wake the app cannot act on.
pub(crate) fn start_push_timer() {
    request_reconcile();
    if TIMER_ACTIVE.swap(true, Ordering::AcqRel) {
        return;
    }
    crate::rt::spawn(async {
        loop {
            crate::rt::time::sleep(crate::rt::time::Duration::from_secs(TIMER_SECS)).await;
            reconcile_push().await;
        }
    });
}

// ── Bridge surface ──────────────────────────────────────────────────────────

/// Dart hands the device token over (first token, and every refresh).
pub async fn set_push_token(token: String, platform: PushPlatform) -> Result<()> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow!("StorageUnavailable"))?;
    if token.trim().is_empty() {
        bail!("InvalidToken");
    }
    db.set_setting(settings_keys::PUSH_TOKEN, token.trim())
        .await?;
    db.set_setting(settings_keys::PUSH_PLATFORM, platform.as_wire())
        .await?;
    reconcile_push().await;
    Ok(())
}

/// After `deleteToken()` on the device: nothing can be registered any more.
pub async fn clear_push_token() -> Result<()> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow!("StorageUnavailable"))?;
    db.delete_setting(settings_keys::PUSH_TOKEN).await?;
    reconcile_push().await;
    Ok(())
}

/// The master toggle. Off unregisters everything the persisted state knows
/// about, whichever run registered it; on clears every node refusal (the
/// user's "try again") and registers the current set.
pub async fn set_push_enabled(enabled: bool) -> Result<()> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow!("StorageUnavailable"))?;
    db.set_setting(
        settings_keys::PUSH_ENABLED,
        if enabled { "true" } else { "false" },
    )
    .await?;
    if enabled {
        db.delete_setting(settings_keys::PUSH_NODE_REFUSALS).await?;
    }
    reconcile_push().await;
    Ok(())
}

/// What Settings shows. Reads the persisted state, so it is right after a
/// restart before any reconcile ran.
pub async fn get_push_status() -> Result<PushStatus> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow!("StorageUnavailable"))?;
    let state = load_state(db).await;
    let (report, wanted) = last_report().lock().unwrap().clone().unwrap_or_default();
    Ok(status_of(&state, &report, wanted, crate::rt::unix_now()))
}

/// Selecting a node is the user's "try again" for that node's refusal.
///
/// Under the reconcile lock, and touching the refusals only: a reconcile in
/// flight owns the registration map, and a stale copy written over its
/// result would drop a registration the server just accepted.
pub(crate) async fn clear_node_refusal(node: &str) {
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    {
        let _guard = RECONCILE_LOCK.lock().await;
        let mut refusals: Refusals = db
            .get_setting(settings_keys::PUSH_NODE_REFUSALS)
            .await
            .ok()
            .flatten()
            .and_then(|json| serde_json::from_str(&json).ok())
            .unwrap_or_default();
        if refusals.remove(&node.to_lowercase()).is_some() {
            let json = serde_json::to_string(&refusals).unwrap_or_default();
            if let Err(e) = db
                .set_setting(settings_keys::PUSH_NODE_REFUSALS, &json)
                .await
            {
                log::warn!("[push] refusal not cleared: {e}");
            }
        }
    }
    request_reconcile();
}

/// Before an identity is deleted: a key the user no longer holds must not
/// keep waking the device. Best effort; the server's TTL is the backstop.
pub(crate) async fn unregister_all() {
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    let _guard = RECONCILE_LOCK.lock().await;
    let mut state = load_state(db).await;
    state.enabled = false;
    let report = reconcile_core(
        &production_server(),
        &mut state,
        &Wanted::new(),
        crate::rt::unix_now(),
    )
    .await;
    state.registrations.clear();
    state.refusals.clear();
    save_registrations(db, &state).await;
    log::info!(
        "[push] identity deletion: unregistered {}",
        report.unregistered
    );
}

// ── Status stream ───────────────────────────────────────────────────────────

const STATUS_CHANNEL_CAPACITY: usize = 16;

fn status_tx() -> &'static broadcast::Sender<PushStatus> {
    static TX: std::sync::OnceLock<broadcast::Sender<PushStatus>> = std::sync::OnceLock::new();
    TX.get_or_init(|| broadcast::channel(STATUS_CHANNEL_CAPACITY).0)
}

fn emit_status(status: PushStatus) {
    let _ = status_tx().send(status);
}

/// Push status changes, one per reconcile, for the settings screen.
pub struct PushStatusStream {
    rx: broadcast::Receiver<PushStatus>,
}

impl PushStatusStream {
    /// The next status; a lag skips ahead rather than ending the stream.
    pub async fn next(&mut self) -> Result<PushStatus> {
        loop {
            match self.rx.recv().await {
                Ok(status) => return Ok(status),
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => bail!("PushStatusStream closed: sender dropped"),
            }
        }
    }
}

pub fn on_push_status_changed() -> PushStatusStream {
    PushStatusStream {
        rx: status_tx().subscribe(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    const NOW: i64 = 1_800_000_000;
    const NODE_A: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const NODE_B: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const K1: &str = "1111111111111111111111111111111111111111111111111111111111111111";
    const K2: &str = "2222222222222222222222222222222222222222222222222222222222222222";

    /// Records every call and answers from a script, `Accepted` once the
    /// script runs out.
    #[derive(Default)]
    struct FakeServer {
        calls: Mutex<Vec<String>>,
        script: Mutex<Vec<ServerOutcome>>,
    }

    impl FakeServer {
        fn answering(outcomes: Vec<ServerOutcome>) -> Self {
            Self {
                calls: Mutex::new(Vec::new()),
                script: Mutex::new(outcomes),
            }
        }
        fn next(&self) -> ServerOutcome {
            let mut script = self.script.lock().unwrap();
            if script.is_empty() {
                ServerOutcome::Accepted
            } else {
                script.remove(0)
            }
        }
        fn calls(&self) -> Vec<String> {
            self.calls.lock().unwrap().clone()
        }
    }

    impl PushServer for FakeServer {
        async fn register(
            &self,
            trade_pubkey: &str,
            token: &str,
            platform: PushPlatform,
            mostro_pubkey: &str,
        ) -> ServerOutcome {
            self.calls.lock().unwrap().push(format!(
                "register {trade_pubkey} {token} {} {mostro_pubkey}",
                platform.as_wire()
            ));
            self.next()
        }
        async fn unregister(&self, trade_pubkey: &str) -> ServerOutcome {
            self.calls
                .lock()
                .unwrap()
                .push(format!("unregister {trade_pubkey}"));
            self.next()
        }
    }

    /// What production paths get under test: a server that is never there.
    pub(super) struct UnreachableServer;

    impl PushServer for UnreachableServer {
        async fn register(&self, _: &str, _: &str, _: PushPlatform, _: &str) -> ServerOutcome {
            ServerOutcome::Failed("no push server under test".into())
        }
        async fn unregister(&self, _: &str) -> ServerOutcome {
            ServerOutcome::Failed("no push server under test".into())
        }
    }

    fn enabled_state() -> PushState {
        PushState {
            enabled: true,
            token: Some("fcm-token".into()),
            platform: Some(PushPlatform::Android),
            registrations: HashMap::new(),
            refusals: Refusals::new(),
        }
    }

    fn wanted(pairs: &[(&str, &str)]) -> Wanted {
        pairs
            .iter()
            .map(|(k, n)| (k.to_string(), n.to_string()))
            .collect()
    }

    #[tokio::test]
    async fn wanted_keys_are_registered_under_their_node_and_recorded() {
        let server = FakeServer::default();
        let mut state = enabled_state();

        let report = reconcile_core(
            &server,
            &mut state,
            &wanted(&[(K1, NODE_A), (K2, NODE_B)]),
            NOW,
        )
        .await;

        assert_eq!(report.registered, 2);
        assert_eq!(
            server.calls(),
            vec![
                format!("register {K1} fcm-token android {NODE_A}"),
                format!("register {K2} fcm-token android {NODE_B}"),
            ]
        );
        let r = &state.registrations[K1];
        assert!(r.is_registered());
        assert_eq!(r.registered_at, NOW);
        assert_eq!(r.mostro_pubkey, NODE_A);
        assert_eq!(r.token_hash, rules::token_hash("fcm-token"));
    }

    #[tokio::test]
    async fn a_second_pass_over_an_unchanged_world_makes_no_request() {
        let server = FakeServer::default();
        let mut state = enabled_state();
        let w = wanted(&[(K1, NODE_A)]);
        reconcile_core(&server, &mut state, &w, NOW).await;
        let before = state.clone();

        let report = reconcile_core(&server, &mut state, &w, NOW + 60).await;

        assert_eq!(report, ReconcileReport::default());
        assert_eq!(server.calls().len(), 1);
        assert_eq!(state, before);
    }

    #[tokio::test]
    async fn disabled_unregisters_everything_the_state_knows_about() {
        // Registrations from "a previous run": the state is what is persisted,
        // so an opt-out after a restart still reaches them.
        let server = FakeServer::default();
        let mut state = enabled_state();
        reconcile_core(
            &server,
            &mut state,
            &wanted(&[(K1, NODE_A), (K2, NODE_A)]),
            NOW,
        )
        .await;
        state.enabled = false;

        let report = reconcile_core(&server, &mut state, &Wanted::new(), NOW + 1).await;

        assert_eq!(report.unregistered, 2);
        assert!(state.registrations.is_empty());
        assert_eq!(
            server.calls()[2..],
            [format!("unregister {K1}"), format!("unregister {K2}")]
        );
    }

    #[tokio::test]
    async fn no_token_means_nothing_registered_and_nothing_asked() {
        let server = FakeServer::default();
        let mut state = enabled_state();
        state.token = None;

        let report = reconcile_core(&server, &mut state, &wanted(&[(K1, NODE_A)]), NOW).await;

        assert_eq!(report, ReconcileReport::default());
        assert!(server.calls().is_empty());
    }

    #[tokio::test]
    async fn a_server_failure_backs_off_and_changes_nothing_else() {
        let server = FakeServer::answering(vec![ServerOutcome::Failed("boom".into())]);
        let mut state = enabled_state();

        let report = reconcile_core(&server, &mut state, &wanted(&[(K1, NODE_A)]), NOW).await;

        assert_eq!(report.failed, 1);
        assert_eq!(report.last_error.as_deref(), Some("PushServerUnreachable"));
        let r = &state.registrations[K1];
        assert!(
            !r.is_registered(),
            "a failed first attempt is not a registration"
        );
        assert_eq!(r.attempts, 1);
        assert_eq!(r.next_attempt_at, NOW + 60);
        // Inside the backoff: no retry. Past it: retried and accepted.
        reconcile_core(&server, &mut state, &wanted(&[(K1, NODE_A)]), NOW + 30).await;
        assert_eq!(server.calls().len(), 1);
        reconcile_core(&server, &mut state, &wanted(&[(K1, NODE_A)]), NOW + 61).await;
        assert!(state.registrations[K1].is_registered());
    }

    #[tokio::test]
    async fn a_429_waits_out_retry_after() {
        let server = FakeServer::answering(vec![ServerOutcome::RateLimited {
            retry_after: Some(7),
        }]);
        let mut state = enabled_state();

        let report = reconcile_core(&server, &mut state, &wanted(&[(K1, NODE_A)]), NOW).await;

        assert_eq!(report.last_error.as_deref(), Some("PushRateLimited"));
        assert_eq!(state.registrations[K1].next_attempt_at, NOW + 7);
    }

    #[tokio::test]
    async fn a_403_refuses_the_node_and_its_keys_are_skipped_afterwards() {
        let server = FakeServer::answering(vec![ServerOutcome::Refused]);
        let mut state = enabled_state();
        let w = wanted(&[(K1, NODE_A), (K2, NODE_B)]);

        let report = reconcile_core(&server, &mut state, &w, NOW).await;

        assert_eq!(report.refused, 1);
        assert_eq!(state.refusals.get(NODE_A), Some(&NOW));
        assert!(
            state.registrations[K2].is_registered(),
            "the other node is unaffected"
        );
        assert!(!state.registrations.contains_key(K1));
        // Next pass: K1 is skipped, no new request for it.
        reconcile_core(&server, &mut state, &w, NOW + 100).await;
        assert!(!server.calls().iter().skip(2).any(|c| c.contains(K1)));
        // The user's "try again" clears it.
        state.refusals.clear();
        reconcile_core(&server, &mut state, &w, NOW + 200).await;
        assert!(state.registrations[K1].is_registered());
    }

    #[tokio::test]
    async fn a_new_token_re_registers_every_key_and_a_grace_ends_in_unregister() {
        let server = FakeServer::default();
        let mut state = enabled_state();
        let w = wanted(&[(K1, NODE_A), (K2, NODE_A)]);
        reconcile_core(&server, &mut state, &w, NOW).await;

        state.token = Some("rotated".into());
        let report = reconcile_core(&server, &mut state, &w, NOW + 1).await;
        assert_eq!(report.registered, 2, "every key, with the new token");
        assert!(server.calls()[2].contains("rotated"));

        // K2 leaves the wanted set: grace starts, then it is let go.
        let only_k1 = wanted(&[(K1, NODE_A)]);
        reconcile_core(&server, &mut state, &only_k1, NOW + 2).await;
        assert_eq!(state.registrations[K2].unwanted_since, Some(NOW + 2));
        reconcile_core(
            &server,
            &mut state,
            &only_k1,
            NOW + 2 + rules::GRACE_SECS + 1,
        )
        .await;
        assert!(!state.registrations.contains_key(K2));
        assert_eq!(server.calls().last().unwrap(), &format!("unregister {K2}"));
    }

    #[test]
    fn statuses_classify_as_the_rules_expect() {
        assert_eq!(
            classify(200, None, r#"{"success":true}"#),
            ServerOutcome::Accepted
        );
        assert_eq!(classify(202, None, ""), ServerOutcome::Accepted);
        assert_eq!(
            classify(403, None, r#"{"message":"Mostro instance not trusted"}"#),
            ServerOutcome::Refused
        );
        assert_eq!(
            classify(
                429,
                Some(3),
                r#"{"success":false,"message":"rate limited"}"#
            ),
            ServerOutcome::RateLimited {
                retry_after: Some(3)
            }
        );
        assert_eq!(
            classify(
                400,
                None,
                r#"{"success":false,"message":"Token cannot be empty"}"#
            ),
            ServerOutcome::BadRequest("Token cannot be empty".into())
        );
        assert!(
            matches!(classify(500, None, "oops"), ServerOutcome::Failed(m) if m.contains("500"))
        );
    }

    #[test]
    fn the_status_reports_the_active_nodes_refusal_and_the_last_success() {
        let mut state = enabled_state();
        state.registrations.insert(
            K1.into(),
            PushRegistration::accepted(K1, NODE_A, "h", NOW - 5),
        );
        state.registrations.insert(
            K2.into(),
            PushRegistration::accepted(K2, NODE_A, "h", NOW - 1),
        );
        let active = crate::config::active_mostro_pubkey().to_lowercase();
        state.refusals.insert(active, NOW - 10);

        let status = status_of(&state, &ReconcileReport::default(), 2, NOW);

        assert_eq!(status.registered, 2);
        assert_eq!(status.last_success_at, Some(NOW - 1));
        assert_eq!(
            status.node_refused_until,
            Some(NOW - 10 + NODE_REFUSAL_SECS)
        );
        assert!(status.has_token && status.enabled);
    }

    #[test]
    fn the_push_server_url_is_the_fly_host_by_default_and_overridable() {
        crate::config::set_push_server_url_override(None);
        assert!(crate::config::push_server_url().starts_with("https://"));
        assert!(!crate::config::push_server_url().ends_with('/'));
        crate::config::set_push_server_url_override(Some("http://127.0.0.1:8080/".into()));
        assert_eq!(crate::config::push_server_url(), "http://127.0.0.1:8080");
        crate::config::set_push_server_url_override(None);
    }
}
