/// Relay pool — manages connections to Nostr relays.
///
/// Subscribes to:
///   - Kind 38383 (public order book, `s=Pending` tag)
///   - Kind 14 (protocol-v2 NIP-44 direct Mostro replies, authored by the
///     node and p-tagged to our trade keys)
///
/// Connection state is derived: Online if ≥1 relay connected,
/// Reconnecting if attempting, Offline otherwise.
use anyhow::{anyhow, Result};
use nostr_sdk::prelude::*;
// The SDK re-exports its own `RelayStatus` via the prelude. Alias it to avoid
// conflicting with our internal `RelayStatus` from `crate::api::types`.
use nostr_sdk::RelayStatus as SdkRelayStatus;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{broadcast, RwLock};

use crate::api::types::{ConnectionState, RelayInfo, RelaySource, RelayStatus};

/// How often the background task polls each relay's SDK status (seconds).
const STATUS_POLL_INTERVAL_SECS: u64 = 2;

/// How often the silence watchdog checks for a dead-but-Connected socket.
const WATCHDOG_POLL_INTERVAL_SECS: u64 = 30;
/// Silence longer than this (while Online) triggers a forced reconnect. Above
/// the ~60s Android relay-drop cycle, well under the 22-min failure window.
const SILENCE_TIMEOUT_SECS: u64 = 210;

/// Shared relay pool state.
pub struct RelayPool {
    client: Arc<Client>,
    relays: Arc<RwLock<Vec<RelayInfo>>>,
    conn_tx: broadcast::Sender<ConnectionState>,
    relay_tx: broadcast::Sender<RelayInfo>,
    /// Unix-seconds timestamp of the last event or message from any relay.
    /// Bumped by `spawn_liveness_observer`; read by `spawn_silence_watchdog`
    /// to detect a socket that reports Connected but has gone silent (#291).
    last_event_at: Arc<AtomicU64>,
}

impl RelayPool {
    /// Create a new pool with the given relay URLs.
    pub async fn new(relay_urls: Vec<String>) -> Result<Arc<Self>> {
        let ephemeral_keys = Keys::generate();
        let client = Arc::new(Client::new(ephemeral_keys));

        let (conn_tx, _) = broadcast::channel(16);
        let (relay_tx, _) = broadcast::channel(64);

        let pool = Arc::new(Self {
            client: client.clone(),
            relays: Arc::new(RwLock::new(Vec::new())),
            conn_tx,
            relay_tx,
            last_event_at: Arc::new(AtomicU64::new(0)),
        });

        for url in relay_urls {
            pool.add_relay_internal(&url, RelaySource::Default).await?;
        }

        client.connect().await;
        // Seed the liveness baseline at connect time so a socket that is silent
        // from the very first moment (never delivers an initial event) is still
        // measured against SILENCE_TIMEOUT_SECS rather than being ignored (#291).
        pool.last_event_at
            .store(unix_now() as u64, Ordering::Relaxed);

        // Give the SDK a moment to initiate WebSocket handshakes before the
        // first status poll.  Without this the initial broadcast is always
        // Reconnecting (every relay is still in Pending/Connecting state).
        crate::rt::time::sleep(Duration::from_millis(500)).await;

        // Broadcast initial connection state after all relays are wired up.
        pool.broadcast_connection_state().await;

        pool.spawn_status_monitor();
        pool.spawn_liveness_observer();
        pool.spawn_silence_watchdog();
        Ok(pool)
    }

    async fn add_relay_internal(&self, url: &str, source: RelaySource) -> Result<RelayInfo> {
        self.client
            .add_relay(url)
            .await
            .map_err(|e| anyhow!("add relay failed: {e}"))?;

        let info = RelayInfo {
            url: url.to_string(),
            is_active: true,
            is_default: matches!(source, RelaySource::Default),
            source,
            is_blacklisted: false,
            status: RelayStatus::Connecting,
            last_connected_at: None,
            last_error: None,
        };

        self.relays.write().await.push(info.clone());
        let _ = self.relay_tx.send(info.clone());
        self.broadcast_connection_state().await;
        Ok(info)
    }

    /// Add a relay and connect to it.
    pub async fn add_relay(&self, url: &str) -> Result<RelayInfo> {
        let relays = self.relays.read().await;
        if relays.iter().any(|r| r.url == url) {
            return Err(anyhow!("RelayAlreadyExists"));
        }
        drop(relays);
        self.add_relay_internal(url, RelaySource::UserAdded).await
    }

    /// Remove a relay and disconnect.
    pub async fn remove_relay(&self, url: &str) -> Result<()> {
        let mut relays = self.relays.write().await;
        let active_count = relays.iter().filter(|r| r.is_active).count();
        if active_count <= 1 {
            return Err(anyhow!("LastRelay"));
        }
        let pos = relays
            .iter()
            .position(|r| r.url == url)
            .ok_or_else(|| anyhow!("RelayNotFound"))?;
        let mut removed = relays.remove(pos);
        removed.status = RelayStatus::Disconnected;
        drop(relays);

        self.client
            .remove_relay(url)
            .await
            .map_err(|e| anyhow!("remove relay failed: {e}"))?;

        let _ = self.relay_tx.send(removed);
        self.broadcast_connection_state().await;
        Ok(())
    }

    pub async fn get_relays(&self) -> Vec<RelayInfo> {
        self.relays.read().await.clone()
    }

    pub async fn connection_state(&self) -> ConnectionState {
        derive_connection_state(&self.relays.read().await)
    }

    pub fn subscribe_connection_state(&self) -> broadcast::Receiver<ConnectionState> {
        self.conn_tx.subscribe()
    }

    pub fn subscribe_relay_status(&self) -> broadcast::Receiver<RelayInfo> {
        self.relay_tx.subscribe()
    }

    pub fn client(&self) -> Arc<Client> {
        self.client.clone()
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    async fn broadcast_connection_state(&self) {
        let state = derive_connection_state(&self.relays.read().await);
        let _ = self.conn_tx.send(state);
    }

    /// Spawn a background task that polls each relay's SDK status every
    /// `STATUS_POLL_INTERVAL_SECS` seconds and broadcasts changes on
    /// `relay_tx` / `conn_tx` when a relay transitions between states.
    ///
    /// `RelayPoolNotification` in nostr-sdk 0.44 does not expose relay-level
    /// status transitions, so polling `client.relay(url).status()` is the
    /// available mechanism.
    fn spawn_status_monitor(self: &Arc<Self>) {
        let client = self.client.clone();
        let relays = self.relays.clone();
        let conn_tx = self.conn_tx.clone();
        let relay_tx = self.relay_tx.clone();

        crate::rt::spawn(async move {
            loop {
                crate::rt::time::sleep(Duration::from_secs(STATUS_POLL_INTERVAL_SECS)).await;

                let relay_urls: Vec<String> =
                    relays.read().await.iter().map(|r| r.url.clone()).collect();

                let mut any_changed = false;

                for url in relay_urls {
                    let Ok(sdk_relay) = client.relay(&url).await else {
                        continue;
                    };
                    let new_status = map_sdk_status(sdk_relay.status());

                    let mut relays_w = relays.write().await;
                    if let Some(info) = relays_w.iter_mut().find(|r| r.url == url) {
                        if info.status != new_status {
                            // Gaining/losing a connection is the signal that
                            // matters (INFO); the connecting↔disconnected
                            // retry churn of an unreachable relay stays at
                            // DEBUG so it doesn't drown a shipped build's log.
                            // Host-only display: a user-added relay URL may
                            // carry tokens/userinfo that must not be retained.
                            let line = format!(
                                "relay {} {:?}→{new_status:?}",
                                crate::api::logging::display_relay(&url),
                                info.status,
                            );
                            if matches!(info.status, RelayStatus::Connected)
                                || matches!(new_status, RelayStatus::Connected)
                            {
                                crate::api::logging::blog_info("relay", line);
                            } else {
                                crate::api::logging::blog_debug("relay", line);
                            }
                            info.status = new_status;
                            if matches!(info.status, RelayStatus::Connected) {
                                info.last_connected_at = Some(unix_now());
                            }
                            any_changed = true;
                            let _ = relay_tx.send(info.clone());
                        }
                    }
                    drop(relays_w);
                }

                if any_changed {
                    let state = derive_connection_state(&relays.read().await);
                    let _ = conn_tx.send(state);
                }
            }
        });
    }

    /// Bump `last_event_at` on every event or message from any relay.
    ///
    /// This is the liveness signal for the silence watchdog: a socket that the
    /// SDK still reports as Connected but which has silently stopped delivering
    /// (issue #291) is exactly one where this timestamp stops advancing. We
    /// listen on a single pool-owned `notifications()` receiver rather than
    /// instrumenting each transient consumer, so the signal survives any one
    /// subscription being dropped and rebuilt. `Message` fires on every relay
    /// message (not just novel events), giving the broadest "traffic flowing"
    /// signal.
    fn spawn_liveness_observer(self: &Arc<Self>) {
        let client = self.client.clone();
        let last_event_at = self.last_event_at.clone();
        crate::rt::spawn(async move {
            let mut rx = client.notifications();
            loop {
                match rx.recv().await {
                    Ok(RelayPoolNotification::Event { .. })
                    | Ok(RelayPoolNotification::Message { .. }) => {
                        last_event_at.store(unix_now() as u64, Ordering::Relaxed);
                    }
                    Ok(RelayPoolNotification::Shutdown) => break,
                    Err(broadcast::error::RecvError::Lagged(_)) => {
                        last_event_at.store(unix_now() as u64, Ordering::Relaxed);
                        continue;
                    }
                    Err(broadcast::error::RecvError::Closed) => break,
                }
            }
        });
    }

    /// Every WATCHDOG_POLL_INTERVAL_SECS, if the pool is Online yet no traffic
    /// has arrived for longer than SILENCE_TIMEOUT_SECS, force a reconnect.
    /// This catches the #291 failure where the SDK still reports Connected but
    /// the socket has silently died. The forced disconnect/connect drives the
    /// existing Online→resubscribe path in `api::nostr`, which rebuilds the
    /// order and chat subscriptions.
    fn spawn_silence_watchdog(self: &Arc<Self>) {
        let this = self.clone();
        crate::rt::spawn(async move {
            loop {
                crate::rt::time::sleep(Duration::from_secs(WATCHDOG_POLL_INTERVAL_SECS)).await;
                let state = this.connection_state().await;
                let last = this.last_event_at.load(Ordering::Relaxed);
                let now = unix_now() as u64;
                if should_force_reconnect(state, last, now, SILENCE_TIMEOUT_SECS) {
                    crate::api::logging::blog_info(
                        "relay",
                        format!(
                            "silence watchdog: {}s without traffic while Online — forcing reconnect (#291)",
                            now.saturating_sub(last)
                        ),
                    );
                    this.client.disconnect().await;
                    crate::rt::time::sleep(Duration::from_millis(200)).await;
                    this.client.connect().await;
                    // Rearm the baseline so the next silence window is measured from
                    // this reconnect, not the stale pre-reconnect timestamp —
                    // otherwise a still-silent socket would reconnect every poll.
                    this.last_event_at
                        .store(unix_now() as u64, Ordering::Relaxed);
                }
            }
        });
    }
}

// ── Pure helpers ──────────────────────────────────────────────────────────────

fn derive_connection_state(relays: &[RelayInfo]) -> ConnectionState {
    let any_connected = relays
        .iter()
        .any(|r| matches!(r.status, RelayStatus::Connected));
    let any_connecting = relays
        .iter()
        .any(|r| matches!(r.status, RelayStatus::Connecting));

    if any_connected {
        ConnectionState::Online
    } else if any_connecting {
        ConnectionState::Reconnecting
    } else {
        ConnectionState::Offline
    }
}

/// Map an SDK `RelayStatus` to our internal `RelayStatus`.
fn map_sdk_status(s: SdkRelayStatus) -> RelayStatus {
    match s {
        SdkRelayStatus::Connected => RelayStatus::Connected,
        SdkRelayStatus::Connecting | SdkRelayStatus::Pending => RelayStatus::Connecting,
        SdkRelayStatus::Disconnected
        | SdkRelayStatus::Terminated
        | SdkRelayStatus::Initialized
        | SdkRelayStatus::Sleeping => RelayStatus::Disconnected,
        SdkRelayStatus::Banned => RelayStatus::Error,
    }
}

use crate::rt::unix_now;

/// Decide whether the silence watchdog should force a reconnect.
///
/// Returns true only when the pool believes it is Online yet no event or
/// message has arrived for longer than `threshold_secs`. A `last_event_at`
/// of 0 (no traffic ever seen) is treated as "not yet a basis for judgement",
/// so a freshly-started pool is never force-reconnected before its first
/// event — that startup window is the SDK's own connect path to handle.
fn should_force_reconnect(
    state: ConnectionState,
    last_event_at: u64,
    now: u64,
    threshold_secs: u64,
) -> bool {
    if !matches!(state, ConnectionState::Online) {
        return false;
    }
    if last_event_at == 0 {
        return false;
    }
    now.saturating_sub(last_event_at) > threshold_secs
}

#[cfg(test)]
mod watchdog_tests {
    use super::*;

    const T: u64 = 210; // threshold seconds

    #[test]
    fn silent_online_past_threshold_reconnects() {
        assert!(should_force_reconnect(
            ConnectionState::Online,
            1_000,
            1_300,
            T
        ));
    }

    #[test]
    fn recent_traffic_does_not_reconnect() {
        assert!(!should_force_reconnect(
            ConnectionState::Online,
            1_295,
            1_300,
            T
        ));
    }

    #[test]
    fn exactly_at_threshold_does_not_reconnect() {
        assert!(!should_force_reconnect(
            ConnectionState::Online,
            1_090,
            1_300,
            T
        ));
    }

    #[test]
    fn offline_never_reconnects_here() {
        assert!(!should_force_reconnect(
            ConnectionState::Offline,
            1_000,
            2_000,
            T
        ));
        assert!(!should_force_reconnect(
            ConnectionState::Reconnecting,
            1_000,
            2_000,
            T
        ));
    }

    #[test]
    fn zero_last_event_guards_pre_connect_window() {
        // Before the constructor's first connect, last_event_at is 0. The guard
        // prevents a spurious reconnect in that microsecond window. Once Online,
        // Fix 1 guarantees a non-zero baseline, so this path is defensive only.
        assert!(!should_force_reconnect(
            ConnectionState::Online,
            0,
            999_999,
            T
        ));
    }

    #[test]
    fn baseline_set_at_connect_triggers_on_startup_silence() {
        // Fix 1: the constructor seeds last_event_at at connect time, so a socket
        // silent from startup is measured from then. Past threshold, still Online,
        // no traffic → the watchdog fires (previously this was wrongly ignored).
        assert!(should_force_reconnect(
            ConnectionState::Online,
            1_000,
            1_300,
            T
        ));
    }

    #[test]
    fn fresh_baseline_after_reconnect_does_not_retrigger() {
        // Fix 2: the watchdog rearms the baseline right after reconnecting, so the
        // next 30s poll sees a recent baseline and waits the full interval instead
        // of reconnecting again — no thrash loop.
        assert!(!should_force_reconnect(
            ConnectionState::Online,
            1_270,
            1_300,
            T
        ));
    }
}
