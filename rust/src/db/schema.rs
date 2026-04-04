/// Database schema version. Currently unused at runtime — kept as a reference
/// for future migration logic (e.g. ALTER TABLE guards or schema-diff checks).
pub const SCHEMA_VERSION: u32 = 2;

/// SQLite DDL executed unconditionally on every `SqliteStorage::open()` call.
/// Safe to run repeatedly because every statement uses `CREATE TABLE IF NOT
/// EXISTS` / `CREATE INDEX IF NOT EXISTS`.
#[cfg(not(target_arch = "wasm32"))]
pub const SQLITE_INIT_SQL: &str = r#"
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS orders (
    id              TEXT PRIMARY KEY,
    data            TEXT NOT NULL,   -- JSON-serialised OrderInfo
    status          TEXT NOT NULL,
    is_mine         INTEGER NOT NULL,
    created_at      INTEGER NOT NULL,
    expires_at      INTEGER
);

CREATE TABLE IF NOT EXISTS trades (
    id              TEXT PRIMARY KEY,
    data            TEXT NOT NULL,   -- JSON-serialised TradeInfo
    status          TEXT NOT NULL,
    started_at      INTEGER NOT NULL,
    completed_at    INTEGER
);

CREATE TABLE IF NOT EXISTS messages (
    id              TEXT PRIMARY KEY,
    trade_id        TEXT NOT NULL,
    data            TEXT NOT NULL,   -- JSON-serialised ChatMessage
    is_read         INTEGER NOT NULL DEFAULT 0,
    created_at      INTEGER NOT NULL,
    FOREIGN KEY (trade_id) REFERENCES trades(id)
);
CREATE INDEX IF NOT EXISTS idx_messages_trade ON messages(trade_id);

CREATE TABLE IF NOT EXISTS relays (
    url             TEXT PRIMARY KEY,
    data            TEXT NOT NULL    -- JSON-serialised RelayInfo
);

CREATE TABLE IF NOT EXISTS identity (
    id              INTEGER PRIMARY KEY CHECK (id = 1),
    data            TEXT NOT NULL    -- JSON-serialised IdentityInfo
);

CREATE TABLE IF NOT EXISTS queued_messages (
    id              TEXT PRIMARY KEY,
    data            TEXT NOT NULL,   -- JSON-serialised QueuedMessage
    status          TEXT NOT NULL DEFAULT 'Pending',
    created_at      INTEGER NOT NULL,
    retry_count     INTEGER NOT NULL DEFAULT 0,
    next_retry_at   INTEGER
);

-- Generic key-value settings store (Mostro node, preferences, etc.).
CREATE TABLE IF NOT EXISTS settings (
    key             TEXT PRIMARY KEY,
    value           TEXT NOT NULL
);

-- Maps order_id → BIP-32 trade key index used when taking/creating that order.
-- Persists across restarts so fiat-sent, release, and cancel can re-derive the
-- correct signing key even after the app is killed between protocol steps.
CREATE TABLE IF NOT EXISTS trade_keys (
    order_id        TEXT PRIMARY KEY,
    key_index       INTEGER NOT NULL
);
"#;
