/// Database schema version. Currently unused at runtime — kept as a reference
/// for future migration logic (e.g. ALTER TABLE guards or schema-diff checks).
pub const SCHEMA_VERSION: u32 = 4;

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
    id              TEXT PRIMARY KEY, -- the row's own id, NOT the order's
    data            TEXT NOT NULL,   -- JSON-serialised TradeInfo
    status          TEXT NOT NULL,
    started_at      INTEGER NOT NULL,
    completed_at    INTEGER
);

-- `trades.id` is the row's own id: a fresh UUID for a take made here, the
-- order id itself for a row rebuilt from a replayed message or a restored
-- bond. Since it may or may not match, every lookup by order id reaches
-- inside the JSON blob instead. The expression here must stay byte-identical to
-- the one in the six `WHERE json_extract(data, '$.order.id') = ?` queries in
-- sqlite.rs, or SQLite silently falls back to a full scan that re-parses every
-- row — on the ingest path that runs once per non-pending order event.
CREATE INDEX IF NOT EXISTS idx_trades_order_id
    ON trades(json_extract(data, '$.order.id'));

-- Chat history + durable replay dedup (issue #246). `trade_id` here is the
-- **order id** — the identity chat keys are derived from — which a row's own
-- `trades.id` is not bound to match, so deliberately NO foreign key to
-- trades(id): with one, save_message failed its FK check for every row whose
-- two ids diverged, and history/dedup silently vanished on restart.
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

-- Chat attachments (#589), cached as downloaded: the blob is still
-- ChaCha20-Poly1305 ciphertext, keyed by its SHA-256 (the Blossom address).
-- Decrypted only in memory, when shown. Identity-scoped (clear_identity_data).
CREATE TABLE IF NOT EXISTS attachment_blobs (
    sha256          TEXT PRIMARY KEY NOT NULL,
    data            BLOB NOT NULL,
    size            INTEGER NOT NULL,
    created_at      INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_attachment_blobs_created ON attachment_blobs(created_at);

-- Payout claims on slashed bonds (docs/ANTI_ABUSE_BOND.md §6.4, §7.3).
-- Independent of `trades`: the winner's row may be gone by the time the
-- daemon asks for an invoice. Keyed by the issuing node and the order,
-- since the user can switch nodes while a claim is open.
CREATE TABLE IF NOT EXISTS bond_claims (
    id              TEXT PRIMARY KEY NOT NULL,   -- "<node_pubkey>:<order_id>"
    node_pubkey     TEXT NOT NULL,
    data            TEXT NOT NULL,               -- JSON-serialised BondClaim
    phase           TEXT NOT NULL,
    deadline_at     INTEGER NOT NULL,
    updated_at      INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_bond_claims_node ON bond_claims(node_pubkey, phase);
"#;
