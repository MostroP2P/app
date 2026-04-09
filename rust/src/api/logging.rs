//! Log sink — captures `log` crate records and exposes them to Flutter
//! via a flutter_rust_bridge stream.
//!
//! [`install_log_bridge`] sets the global `log` backend to a [`BridgeLogger`]
//! that sends every record to both stderr (logcat on Android) **and** the
//! Flutter [`on_log_entry`] stream.

use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{mpsc, Mutex, OnceLock};

use tokio::sync::broadcast;

use crate::api::types::{LogEntry, LogLevel};

// ── Global broadcast channel for log entries ─────────────────────────────────

static LOG_TX: OnceLock<broadcast::Sender<LogEntry>> = OnceLock::new();

fn log_sender() -> &'static broadcast::Sender<LogEntry> {
    LOG_TX.get_or_init(|| {
        let (tx, _) = broadcast::channel(512);
        tx
    })
}

// ── Forwarding bridge (sync → async) ────────────────────────────────────────

static LOG_STD_TX: OnceLock<Mutex<mpsc::Sender<LogEntry>>> = OnceLock::new();

/// Monotonically increasing ID for log entries.
static COUNTER: AtomicU32 = AtomicU32::new(0);

/// Install the log capture bridge.
///
/// Must be called once during app initialization (from `init_app()`).
/// After this call, every `log::info!()` / `log::warn!()` etc. in Rust
/// is forwarded to the Flutter `on_log_entry()` stream.
pub fn install_log_bridge() {
    static INSTALLED: std::sync::Once = std::sync::Once::new();
    INSTALLED.call_once(|| {
        let tx = log_sender().clone();
        let (std_tx, std_rx) = mpsc::channel::<LogEntry>();

        // Background thread: reads from the std mpsc channel and broadcasts
        // to the tokio broadcast channel.
        std::thread::spawn(move || {
            while let Ok(entry) = std_rx.recv() {
                let _ = tx.send(entry);
            }
        });

        LOG_STD_TX.get_or_init(|| Mutex::new(std_tx));

        // Install a custom log::Log that forwards every record.
        // max_level is set to Debug so Info/Warn/Error all flow through.
        // If a dependency already set a logger, this fails silently —
        // the eprintln! fallback in BridgeLogger::log still works, but the
        // Flutter stream won't receive entries via the log crate.
        match log::set_logger(&BRIDGE_LOGGER) {
            Ok(()) => log::set_max_level(log::LevelFilter::Debug),
            Err(e) => eprintln!(
                "[logging] WARN: set_logger failed ({e}), another logger is already active. \
                 Using direct bridge for Flutter stream."
            ),
        }
    });
}

/// Global logger instance that forwards records to the Flutter stream
/// and prints to stderr (logcat on Android).
static BRIDGE_LOGGER: BridgeLogger = BridgeLogger;

struct BridgeLogger;

impl log::Log for BridgeLogger {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.level() <= log::Level::Debug
    }

    fn log(&self, record: &log::Record) {
        if !self.enabled(record.metadata()) {
            return;
        }

        // Forward to Flutter stream.
        forward_log(record.level(), record.target(), &record.args().to_string());

        // Also print to stderr so adb logcat / terminal output still works.
        eprintln!(
            "[{level}] {target}: {msg}",
            level = record.level(),
            target = record.target(),
            msg = record.args(),
        );
    }

    fn flush(&self) {}
}

/// Forward a log record to the Flutter stream.
pub(crate) fn forward_log(level: log::Level, target: &str, message: &str) {
    if let Some(tx) = LOG_STD_TX.get() {
        let entry = LogEntry {
            id: COUNTER.fetch_add(1, Ordering::Relaxed),
            level: match level {
                log::Level::Error => LogLevel::Error,
                log::Level::Warn => LogLevel::Warning,
                log::Level::Info => LogLevel::Info,
                _ => LogLevel::Debug,
            },
            tag: target.split("::").last().unwrap_or(target).to_string(),
            message: message.to_string(),
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs() as i64,
        };
        if let Ok(g) = tx.lock() {
            let _ = g.send(entry);
        }
    }
}

/// Send a log entry directly to the Flutter stream, bypassing the `log` crate.
///
/// Use this when the `log` crate logger may have been hijacked by a dependency.
/// The entry is also printed to stderr for terminal visibility.
pub(crate) fn bridge_log(level: log::Level, tag: &str, message: &str) {
    eprintln!("[{level}] {tag}: {message}");
    forward_log(level, tag, message);
}

/// Shorthand helpers — always reach both stderr and the Flutter log stream.
pub(crate) fn blog_info(tag: &str, msg: String) { bridge_log(log::Level::Info, tag, &msg); }
pub(crate) fn blog_warn(tag: &str, msg: String) { bridge_log(log::Level::Warn, tag, &msg); }
pub(crate) fn blog_debug(tag: &str, msg: String) { bridge_log(log::Level::Debug, tag, &msg); }


// ── FRB stream ───────────────────────────────────────────────────────────────

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
/// Each call returns a new independent stream.  Call [`install_log_bridge`]
/// during initialization or no entries will be emitted.
pub fn on_log_entry() -> LogEntryStream {
    LogEntryStream {
        rx: log_sender().subscribe(),
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

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

        let entry = tokio::time::timeout(
            std::time::Duration::from_secs(2),
            stream.next(),
        )
        .await
        .expect("timed out waiting for log entry")
        .expect("stream closed unexpectedly");

        assert_eq!(entry.level, LogLevel::Warning);
        assert_eq!(entry.tag, "client");
        assert_eq!(entry.message, "test warning");
    }
}
