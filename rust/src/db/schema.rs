/// Database schema version. Currently unused at runtime — kept as a reference
/// for future migration logic (e.g. ALTER TABLE guards or schema-diff checks).
pub const SCHEMA_VERSION: u32 = 3;

/// One-off rebuild for databases created while `messages` still carried a
/// foreign key to `trades(id)` (schema v2). SQLite cannot drop a FK in place,
/// so the table is recreated and the rows copied. Runs after the main DDL;
/// `SqliteStorage::open` executes it only when the old FK is detected **and**
/// the table already has the JSON `data` column this SQL copies — a v1
/// database (one column per field) also carries that FK, and running this
/// against it aborts `open()` with "no such column: data", taking the whole
/// database down. `migrate()` drops that older table instead.
/// Crash-safe: the rebuild runs inside one transaction (an interruption
/// rolls back to the untouched v2 table), the stray `messages_v3` a previous
/// interrupted attempt may have left is dropped first, and the
/// `foreign_keys` pragma toggles sit OUTSIDE the transaction — SQLite
/// silently ignores that pragma inside one.
#[cfg(not(target_arch = "wasm32"))]
pub const SQLITE_DROP_MESSAGES_FK_SQL: &str = r#"
PRAGMA foreign_keys = OFF;
BEGIN;
DROP TABLE IF EXISTS messages_v3;
CREATE TABLE messages_v3 (
    id              TEXT PRIMARY KEY,
    trade_id        TEXT NOT NULL,
    data            TEXT NOT NULL,
    is_read         INTEGER NOT NULL DEFAULT 0,
    created_at      INTEGER NOT NULL
);
INSERT INTO messages_v3 SELECT id, trade_id, data, is_read, created_at FROM messages;
DROP TABLE messages;
ALTER TABLE messages_v3 RENAME TO messages;
CREATE INDEX IF NOT EXISTS idx_messages_trade ON messages(trade_id);
COMMIT;
PRAGMA foreign_keys = ON;
"#;

/// SQLite DDL executed unconditionally on every `SqliteStorage::open()` call.
/// Safe to run repeatedly because every statement uses `CREATE TABLE IF NOT
/// EXISTS` / `CREATE INDEX IF NOT EXISTS`.
///
/// Connection pragmas deliberately live in `SqliteStorage::open`'s connect
/// options instead of here: this SQL runs on one pooled connection, and
/// `foreign_keys` is connection-scoped, so setting it here left the rest of
/// the pool with enforcement off.
#[cfg(not(target_arch = "wasm32"))]
pub const SQLITE_INIT_SQL: &str = r#"
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

-- `trades.id` is a fresh UUID for takers, so every lookup by order id has to
-- reach inside the JSON blob. The expression here must stay byte-identical to
-- the one in the six `WHERE json_extract(data, '$.order.id') = ?` queries in
-- sqlite.rs, or SQLite silently falls back to a full scan that re-parses every
-- row — on the ingest path that runs once per non-pending order event.
CREATE INDEX IF NOT EXISTS idx_trades_order_id
    ON trades(json_extract(data, '$.order.id'));

-- Chat history + durable replay dedup (issue #246). `trade_id` here is the
-- **order id** — the identity chat keys are derived from — which for taken
-- orders differs from the `trades.id` UUID, so deliberately NO foreign key
-- to trades(id): with one, every taker's save_message failed its FK check
-- and history/dedup silently vanished on restart.
CREATE TABLE IF NOT EXISTS messages (
    id              TEXT PRIMARY KEY,
    trade_id        TEXT NOT NULL,
    data            TEXT NOT NULL,   -- JSON-serialised ChatMessage
    is_read         INTEGER NOT NULL DEFAULT 0,
    created_at      INTEGER NOT NULL
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
