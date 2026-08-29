//! Log sink — captures `log` crate records, mirrors them to the platform
//! console, and exposes them to Flutter via a flutter_rust_bridge stream.
//!
//! [`install_log_bridge`] makes [`BridgeLogger`] the global `log` backend, and
//! every record it accepts goes to the platform console, to a bounded ring
//! buffer readable with [`recent_logs`], and to the live [`on_log_entry`]
//! stream.
//!
//! Dependency logs arrive here too: `nostr-sdk`, `nostr-relay-pool` and `sqlx`
//! emit through `tracing`, which the crate wires into `log` — see the comment
//! on that dependency in `Cargo.toml`.

use std::cell::Cell;
use std::collections::VecDeque;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Mutex, OnceLock};

use tokio::sync::broadcast;

use crate::api::types::{LogEntry, LogLevel};

/// Entries kept for [`recent_logs`] — a session's worth at `Info` level.
const BUFFER_CAPACITY: usize = 1000;

/// Lag tolerance for a slow live subscriber, not history.
const BROADCAST_CAPACITY: usize = 512;

// ── Shared state ─────────────────────────────────────────────────────────────

static LOG_TX: OnceLock<broadcast::Sender<LogEntry>> = OnceLock::new();
static BUFFER: OnceLock<Mutex<VecDeque<LogEntry>>> = OnceLock::new();

/// Monotonic entry id — how a consumer merging [`recent_logs`] with the live
/// stream drops the overlap.
static COUNTER: AtomicU32 = AtomicU32::new(0);

fn log_sender() -> &'static broadcast::Sender<LogEntry> {
    LOG_TX.get_or_init(|| broadcast::channel(BROADCAST_CAPACITY).0)
}

fn buffer() -> &'static Mutex<VecDeque<LogEntry>> {
    BUFFER.get_or_init(|| Mutex::new(VecDeque::with_capacity(BUFFER_CAPACITY)))
}

// ── Installation and verbosity ───────────────────────────────────────────────

/// Install the log capture bridge. Called once from `init_app()`; until it
/// runs, `log::` records go nowhere.
pub fn install_log_bridge() {
    static INSTALLED: std::sync::Once = std::sync::Once::new();
    INSTALLED.call_once(|| {
        // Unconditional: the filter defaults to `Off`, and `bridge_log` checks
        // it even when the branch below loses the logger.
        log::set_max_level(default_max_level());

        // flutter_rust_bridge installs its own logger in
        // `setup_default_user_utils()`, which this crate never calls. If this
        // fires, `log::` macros bypass us and only `blog_*` reaches the UI.
        if let Err(e) = log::set_logger(&BRIDGE_LOGGER) {
            eprintln!("[logging] set_logger failed ({e}) — another logger is already active");
        }
    });
}

/// Verbosity before the user opts in: verbose while developing, `Info` in a
/// shipped build so `debug!` call sites cost nothing.
fn default_max_level() -> log::LevelFilter {
    if cfg!(debug_assertions) {
        log::LevelFilter::Debug
    } else {
        log::LevelFilter::Info
    }
}

/// Applies the "logging enabled" setting to the global filter.
pub(crate) fn set_verbose_logging(enabled: bool) {
    log::set_max_level(if enabled {
        log::LevelFilter::Debug
    } else {
        default_max_level()
    });
}

/// Dependency targets dropped at every level: `nostr-relay-pool` logs raw relay
/// messages verbatim at `Debug` (`relay/inner.rs:818`, `:1092`) *and* at `Error`
/// (`:1073`, `:1915`), so no level ceiling separates its diagnostics from its
/// payloads. Per-relay lifecycle is instrumented from our own pool wrapper
/// instead, where the message text is ours (#241).
const EXCLUDED_TARGETS: &[&str] = &["nostr_relay_pool"];

/// Per-target ceiling, never above the global filter.
fn max_level_for(target: &str) -> log::LevelFilter {
    if EXCLUDED_TARGETS.iter().any(|t| target.starts_with(t)) {
        log::LevelFilter::Off
    } else {
        log::max_level()
    }
}

// ── Logger ───────────────────────────────────────────────────────────────────

static BRIDGE_LOGGER: BridgeLogger = BridgeLogger;

struct BridgeLogger;

thread_local! {
    /// Set while this thread is inside [`BridgeLogger::log`]: a console sink
    /// that logs would otherwise recurse until the stack runs out.
    static IN_LOG: Cell<bool> = const { Cell::new(false) };
}

struct ReentryGuard;

impl ReentryGuard {
    /// `None` when this thread is already emitting a record.
    fn acquire() -> Option<Self> {
        IN_LOG
            .try_with(|f| if f.replace(true) { None } else { Some(ReentryGuard) })
            .ok()
            .flatten()
    }
}

impl Drop for ReentryGuard {
    fn drop(&mut self) {
        let _ = IN_LOG.try_with(|f| f.set(false));
    }
}

impl log::Log for BridgeLogger {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.level() <= max_level_for(metadata.target())
    }

    fn log(&self, record: &log::Record) {
        if !self.enabled(record.metadata()) {
            return;
        }
        let Some(_guard) = ReentryGuard::acquire() else {
            return;
        };

        // Format once and scrub before ANY sink sees the text, so a leaked
        // secret can reach neither the console/logcat nor the retained buffer.
        let message = scrub_secrets(&record.args().to_string()).into_owned();
        platform_console(record.level(), record.target(), &message);
        forward_log(record.level(), record.target(), &message);
    }

    fn flush(&self) {}
}

// ── Platform console sinks ───────────────────────────────────────────────────

/// Android discards a process's stderr, so records go to logcat. The fixed tag
/// keeps `adb logcat -s mostro` useful; `android_logger` prepends the module
/// path to the message. Takes the pre-scrubbed message text (not the raw
/// record) so redaction happens once, upstream, for every sink.
#[cfg(target_os = "android")]
fn platform_console(level: log::Level, target: &str, message: &str) {
    use log::Log as _;

    static ANDROID: OnceLock<android_logger::AndroidLogger> = OnceLock::new();
    ANDROID
        .get_or_init(|| {
            android_logger::AndroidLogger::new(android_logger::Config::default().with_tag("mostro"))
        })
        .log(
            &log::Record::builder()
                .level(level)
                .target(target)
                .args(format_args!("{message}"))
                .build(),
        );
}

/// `wasm32` has no stderr; devtools filters on the console severity.
#[cfg(target_arch = "wasm32")]
fn platform_console(level: log::Level, target: &str, message: &str) {
    let line = format!("{target}: {message}");
    match level {
        log::Level::Error => web_sys::console::error_1(&line.into()),
        log::Level::Warn => web_sys::console::warn_1(&line.into()),
        log::Level::Info => web_sys::console::info_1(&line.into()),
        _ => web_sys::console::debug_1(&line.into()),
    }
}

/// Desktop and iOS: stderr, which is what `flutter run` shows. The timestamp
/// is UTC time-of-day; the Flutter side renders local time.
#[cfg(all(not(target_os = "android"), not(target_arch = "wasm32")))]
fn platform_console(level: log::Level, target: &str, message: &str) {
    let secs = crate::rt::unix_now();
    eprintln!(
        "{:02}:{:02}:{:02}Z [{:<5}] {}: {}",
        (secs / 3600) % 24,
        (secs / 60) % 60,
        secs % 60,
        level,
        target,
        message,
    );
}

// ── Redaction helpers ────────────────────────────────────────────────────────

/// First 8 chars of an id (event id, order UUID, pubkey) — enough to correlate
/// log lines, deliberately not enough to reconstruct the full identifier.
pub(crate) fn short_id(id: &str) -> &str {
    id.get(..8).unwrap_or(id)
}

/// Safety net applied to every record before any sink: masks `nsec1…` key
/// material wherever it appears, in any casing (bech32 also allows uniform
/// uppercase). Call-site discipline is the primary rule (never log secrets);
/// this guarantees a slip cannot reach the console, logcat, or the retained
/// buffer. Returns the input unchanged (no allocation) when there is nothing
/// to mask.
pub(crate) fn scrub_secrets(message: &str) -> std::borrow::Cow<'_, str> {
    const MARKER: &[u8] = b"nsec1";

    // Case-insensitive marker search without allocating on the clean path.
    fn find_marker(haystack: &str) -> Option<usize> {
        haystack
            .as_bytes()
            .windows(MARKER.len())
            .position(|w| w.eq_ignore_ascii_case(MARKER))
    }

    if find_marker(message).is_none() {
        return std::borrow::Cow::Borrowed(message);
    }
    let mut out = String::with_capacity(message.len());
    let mut rest = message;
    while let Some(pos) = find_marker(rest) {
        let after = pos + MARKER.len();
        out.push_str(&rest[..after]);
        out.push_str("[redacted]");
        // Skip the bech32 payload: the alphanumeric run following the prefix.
        let tail = &rest[after..];
        let skip = tail
            .find(|c: char| !c.is_ascii_alphanumeric())
            .unwrap_or(tail.len());
        rest = &tail[skip..];
    }
    out.push_str(rest);
    std::borrow::Cow::Owned(out)
}

/// Renders a relay URL as `scheme://host[:port]` only — userinfo, path,
/// query and fragment are dropped so tokenized/private relay URLs never
/// enter a log record.
pub(crate) fn display_relay(url: &str) -> String {
    let Some((scheme, rest)) = url.split_once("://") else {
        return sanitize_relay_text(url);
    };
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host = authority.rsplit('@').next().unwrap_or(authority);
    // The authority may still carry control characters — same policy as any
    // remote-influenced text before it enters a log record.
    sanitize_relay_text(&format!("{scheme}://{host}"))
}

/// Bounds and normalizes text that originates from a remote peer (relay error
/// strings, NOTICE/CLOSED messages) before it enters a log record: control
/// characters are replaced (a newline could forge log-entry boundaries) and
/// the length is capped so a hostile relay cannot bloat the retained buffer.
pub(crate) fn sanitize_relay_text(text: &str) -> String {
    const MAX_CHARS: usize = 200;
    text.chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .take(MAX_CHARS)
        .collect()
}

// ── Buffer and Flutter stream ────────────────────────────────────────────────

/// Record an entry into the ring buffer and publish it to live subscribers.
pub(crate) fn forward_log(level: log::Level, target: &str, message: &str) {
    let entry = buffer_entry(level, target, message);

    // Fails when nobody is listening — that is what the ring buffer covers.
    let _ = log_sender().send(entry);
}

/// Append to the ring buffer, evicting the oldest, and return the entry.
///
/// The id is claimed under the lock so the buffer stays ordered by id when
/// several threads log at once; a poisoned lock costs the entry its history
/// slot, not its trip to the live stream.
fn buffer_entry(level: log::Level, target: &str, message: &str) -> LogEntry {
    let mut buf = buffer().lock().ok();

    let entry = LogEntry {
        id: COUNTER.fetch_add(1, Ordering::Relaxed),
        level: match level {
            log::Level::Error => LogLevel::Error,
            log::Level::Warn => LogLevel::Warning,
            log::Level::Info => LogLevel::Info,
            _ => LogLevel::Debug,
        },
        tag: short_tag(target),
        message: message.to_string(),
        timestamp: crate::rt::unix_now(),
    };

    if let Some(buf) = buf.as_mut() {
        while buf.len() >= BUFFER_CAPACITY {
            buf.pop_front();
        }
        buf.push_back(entry.clone());
    }

    entry
}

/// Last segment of a `log` target, so `rust::nwc::client` displays as `client`.
fn short_tag(target: &str) -> String {
    target.rsplit("::").next().unwrap_or(target).to_string()
}

/// Emit a record under an explicit `tag` instead of the module path that the
/// `log::` macros use as target.
pub(crate) fn bridge_log(level: log::Level, tag: &str, message: &str) {
    log::Log::log(
        &BRIDGE_LOGGER,
        &log::Record::builder()
            .level(level)
            .target(tag)
            .args(format_args!("{message}"))
            .build(),
    );
}

/// Shorthand helpers for tagged records.
pub(crate) fn blog_info(tag: &str, msg: String) {
    bridge_log(log::Level::Info, tag, &msg);
}
pub(crate) fn blog_warn(tag: &str, msg: String) {
    bridge_log(log::Level::Warn, tag, &msg);
}
pub(crate) fn blog_debug(tag: &str, msg: String) {
    bridge_log(log::Level::Debug, tag, &msg);
}

// ── FRB surface ──────────────────────────────────────────────────────────────

/// Stream of log entries for consumption by Flutter.
pub struct LogEntryStream {
    rx: broadcast::Receiver<LogEntry>,
}

impl LogEntryStream {
    /// Poll for the next log entry.
    pub async fn next(&mut self) -> Option<LogEntry> {
        loop {
            match self.rx.recv().await {
                Ok(entry) => return Some(entry),
                Err(broadcast::error::RecvError::Lagged(_)) => continue,
                Err(broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

/// Subscribe to the live log stream.
///
/// Each call returns an independent stream that only sees entries emitted
/// after it subscribes — pair it with [`recent_logs`] for history.
pub fn on_log_entry() -> LogEntryStream {
    LogEntryStream {
        rx: log_sender().subscribe(),
    }
}

/// Snapshot of the buffered history, newest first.
///
/// Ids increase monotonically: subscribe to [`on_log_entry`] first, snapshot
/// second, and drop streamed entries the snapshot already holds.
pub fn recent_logs() -> Vec<LogEntry> {
    buffer()
        .lock()
        .map(|buf| buf.iter().rev().cloned().collect())
        .unwrap_or_default()
}

/// Drop the buffered history — log lines can name orders and counterparties,
/// so anything that wipes the user's identity should call this too.
pub fn clear_logs() {
    if let Ok(mut buf) = buffer().lock() {
        buf.clear();
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    /// Tests share the globals, so match on a unique tag, never on position.
    async fn recv_tagged(stream: &mut LogEntryStream, tag: &str) -> LogEntry {
        crate::rt::time::timeout(std::time::Duration::from_secs(2), async {
            loop {
                let entry = stream.next().await.expect("stream closed unexpectedly");
                if entry.tag == tag {
                    return entry;
                }
            }
        })
        .await
        .unwrap_or_else(|_| panic!("timed out waiting for a '{tag}' entry"))
    }

    #[test]
    fn short_id_truncates_without_panicking() {
        assert_eq!(short_id("0ed2bc2f-5d03-427d-a507-920438bb3925"), "0ed2bc2f");
        assert_eq!(short_id("abc"), "abc");
        assert_eq!(short_id(""), "");
    }

    #[test]
    fn scrub_secrets_masks_nsec_and_leaves_clean_text_alone() {
        // Clean text: borrowed through unchanged, no allocation.
        let clean = "order=0ed2bc2f status Pending→Active";
        assert!(matches!(
            scrub_secrets(clean),
            std::borrow::Cow::Borrowed(_)
        ));

        let dirty = "imported key nsec1qyfxw6vlx3s24r0uzkkfnvyd5wsy4751m0nrg2 done";
        let scrubbed = scrub_secrets(dirty);
        assert_eq!(scrubbed, "imported key nsec1[redacted] done");

        // Multiple occurrences, including at the end of the string.
        let double = "a nsec1abc b nsec1def";
        assert_eq!(scrub_secrets(double), "a nsec1[redacted] b nsec1[redacted]");

        // bech32 allows uniform uppercase — the marker must match any casing.
        let upper = "key NSEC1QYFXW6VLX3S24R0UZKK end";
        assert_eq!(scrub_secrets(upper), "key NSEC1[redacted] end");
        let mixed = "key NsEc1abcDEF end";
        assert_eq!(scrub_secrets(mixed), "key NsEc1[redacted] end");
    }

    #[test]
    fn display_relay_keeps_only_scheme_and_host() {
        assert_eq!(display_relay("wss://nos.lol"), "wss://nos.lol");
        assert_eq!(display_relay("wss://relay.example.com:7777"), "wss://relay.example.com:7777");
        assert_eq!(
            display_relay("wss://user:token@relay.example.com/path?secret=x#f"),
            "wss://relay.example.com"
        );
        // Not a URL at all: falls back to plain sanitization.
        assert_eq!(display_relay("not a url"), "not a url");
        // Control characters in the authority cannot forge log boundaries.
        assert_eq!(
            display_relay("wss://relay.example\nforged"),
            "wss://relay.example forged"
        );
    }

    #[test]
    fn sanitize_relay_text_strips_control_chars_and_caps_length() {
        assert_eq!(
            sanitize_relay_text("auth-required:\nplease\tauth"),
            "auth-required: please auth"
        );
        let long = "x".repeat(500);
        assert_eq!(sanitize_relay_text(&long).chars().count(), 200);
        assert_eq!(sanitize_relay_text("plain error"), "plain error");
    }

    /// The #241 invariant: key material logged by mistake must reach neither
    /// the retained buffer (`recent_logs`) nor the live stream.
    #[tokio::test]
    async fn forbidden_material_never_reaches_recent_logs() {
        install_log_bridge();
        let mut stream = on_log_entry();

        log::warn!(target: "scrub_probe", "oops nsec1deadbeefdeadbeef leaked");

        let entry = recv_tagged(&mut stream, "scrub_probe").await;
        assert!(!entry.message.contains("nsec1dead"), "stream leaked: {}", entry.message);
        assert!(entry.message.contains("nsec1[redacted]"));

        let retained = recent_logs();
        assert!(
            retained
                .iter()
                .filter(|e| e.tag == "scrub_probe")
                .all(|e| !e.message.contains("nsec1dead")),
            "recent_logs leaked the key"
        );
    }

    #[test]
    fn forward_log_does_not_panic() {
        // Calling forward_log should not panic regardless of bridge state.
        // If bridge is installed, this forwards; if not, it's a no-op.
        forward_log(log::Level::Info, "test", "should not panic");
    }

    #[tokio::test]
    async fn install_and_receive_log() {
        install_log_bridge();
        let mut stream = on_log_entry();

        forward_log(log::Level::Warn, "nwc::client", "test warning");

        let entry = recv_tagged(&mut stream, "client").await;
        assert_eq!(entry.level, LogLevel::Warning);
        assert_eq!(entry.message, "test warning");
    }

    /// Guards the `tracing`-to-`log` wiring: without it every nostr-sdk and
    /// sqlx event is dropped.
    #[tokio::test]
    async fn tracing_events_reach_the_bridge() {
        install_log_bridge();
        let mut stream = on_log_entry();

        tracing::warn!(target: "tracing_probe", "event from a dependency");

        let entry = recv_tagged(&mut stream, "tracing_probe").await;
        assert_eq!(entry.level, LogLevel::Warning);
        assert!(entry.message.contains("event from a dependency"));
    }

    /// Raw relay traffic must not reach the console or the retained buffer,
    /// where sharing, screenshots and logcat would expose it unredacted. The
    /// payload rides on `Error` records too, so every level has to be covered.
    #[test]
    fn excluded_targets_never_reach_any_sink() {
        use log::Log as _;

        install_log_bridge();
        const TARGET: &str = "nostr_relay_pool::relay::inner";
        const PAYLOAD: &str = "traffic-probe-payload";

        log::debug!(target: TARGET, "Received '{PAYLOAD}'");
        log::info!(target: TARGET, "Connected, {PAYLOAD}");
        log::warn!(target: TARGET, "Rejected, {PAYLOAD}");
        log::error!(target: TARGET, "Impossible to handle relay message, msg={PAYLOAD}");

        assert!(!recent_logs().iter().any(|e| e.message.contains(PAYLOAD)));
        for level in [
            log::Level::Error,
            log::Level::Warn,
            log::Level::Info,
            log::Level::Debug,
        ] {
            assert!(
                !BRIDGE_LOGGER
                    .enabled(&log::Metadata::builder().level(level).target(TARGET).build()),
                "{level} records from an excluded target must be dropped",
            );
        }
        assert!(BRIDGE_LOGGER.enabled(
            &log::Metadata::builder()
                .level(log::Level::Info)
                .target("nostr_sdk::client")
                .build()
        ));
    }

    /// `blog_*` must go through the same fan-out as the `log::` macros.
    #[tokio::test]
    async fn tagged_helpers_reach_the_bridge() {
        install_log_bridge();
        let mut stream = on_log_entry();

        blog_info("blog_probe", "tagged message".to_string());

        let entry = recv_tagged(&mut stream, "blog_probe").await;
        assert_eq!(entry.level, LogLevel::Info);
        assert_eq!(entry.message, "tagged message");
    }

    /// Writes straight to the buffer: flooding the broadcast channel instead
    /// would lag any receiver a concurrent test is holding.
    #[test]
    fn recent_logs_is_bounded_and_newest_first() {
        for i in 0..(BUFFER_CAPACITY + 50) {
            buffer_entry(log::Level::Info, "buffer_probe", &format!("entry {i}"));
        }

        let entries = recent_logs();
        assert!(entries.len() <= BUFFER_CAPACITY);
        assert!(
            entries.windows(2).all(|w| w[0].id > w[1].id),
            "recent_logs must be ordered newest first",
        );
    }

    #[test]
    fn verbose_logging_gates_debug_records() {
        install_log_bridge();

        set_verbose_logging(true);
        assert!(log::log_enabled!(log::Level::Debug));

        // Also restores the filter for anything running concurrently.
        set_verbose_logging(false);
        assert_eq!(log::max_level(), default_max_level());
    }
}
