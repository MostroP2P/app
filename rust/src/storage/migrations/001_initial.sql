-- Mostro Mobile v2 — Initial Schema
-- All 11 entities per data-model.md

-- ─── Identity ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS identity (
    id                    TEXT NOT NULL PRIMARY KEY,
    public_key            TEXT NOT NULL UNIQUE,
    encrypted_private_key BLOB NOT NULL,
    mnemonic_hash         TEXT NOT NULL,
    display_name          TEXT,
    created_at            INTEGER NOT NULL,
    last_used_at          INTEGER NOT NULL,
    trade_key_index       INTEGER NOT NULL DEFAULT 0,
    privacy_mode          INTEGER NOT NULL DEFAULT 0,  -- 0=false 1=true
    derivation_path       TEXT NOT NULL DEFAULT 'm/44''/1237''/38383''/0'
);

-- ─── Orders ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS orders (
    id               TEXT NOT NULL PRIMARY KEY,
    kind             TEXT NOT NULL,           -- 'Buy' | 'Sell'
    status           TEXT NOT NULL,           -- OrderStatus variant name
    amount_sats      INTEGER,
    fiat_amount      REAL,
    fiat_amount_min  REAL,
    fiat_amount_max  REAL,
    fiat_code        TEXT NOT NULL,
    payment_method   TEXT NOT NULL,
    premium          REAL NOT NULL DEFAULT 0.0,
    creator_pubkey   TEXT NOT NULL,
    created_at       INTEGER NOT NULL,
    expires_at       INTEGER,
    nostr_event_id   TEXT,
    is_mine          INTEGER NOT NULL DEFAULT 0,
    cached_at        INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_orders_status    ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_cached_at ON orders(cached_at);
CREATE INDEX IF NOT EXISTS idx_orders_is_mine   ON orders(is_mine);

-- ─── Trades ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS trades (
    id                      TEXT NOT NULL PRIMARY KEY,
    order_id                TEXT NOT NULL REFERENCES orders(id),
    role                    TEXT NOT NULL,    -- 'Buyer' | 'Seller'
    counterparty_pubkey     TEXT NOT NULL,
    current_step            TEXT NOT NULL,
    hold_invoice            TEXT,
    buyer_invoice           TEXT,
    trade_key_index         INTEGER NOT NULL,
    cooperative_cancel_state TEXT,
    timeout_at              INTEGER,
    started_at              INTEGER NOT NULL,
    completed_at            INTEGER,
    outcome                 TEXT
);

CREATE INDEX IF NOT EXISTS idx_trades_order_id  ON trades(order_id);
CREATE INDEX IF NOT EXISTS idx_trades_completed ON trades(completed_at);

-- ─── Messages ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS messages (
    id                TEXT NOT NULL PRIMARY KEY,
    trade_id          TEXT NOT NULL REFERENCES trades(id),
    sender_pubkey     TEXT NOT NULL,
    content_encrypted BLOB NOT NULL,
    message_type      TEXT NOT NULL,   -- 'Peer' | 'Admin' | 'System'
    is_mine           INTEGER NOT NULL DEFAULT 0,
    is_read           INTEGER NOT NULL DEFAULT 0,
    attachment_id     TEXT,
    created_at        INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_trade_id  ON messages(trade_id);
CREATE INDEX IF NOT EXISTS idx_messages_is_read   ON messages(is_read);
CREATE INDEX IF NOT EXISTS idx_messages_created   ON messages(created_at);

-- ─── Relays ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS relays (
    id                  TEXT NOT NULL PRIMARY KEY,
    url                 TEXT NOT NULL UNIQUE,
    is_active           INTEGER NOT NULL DEFAULT 1,
    is_default          INTEGER NOT NULL DEFAULT 0,
    source              TEXT NOT NULL,  -- 'Default' | 'MostroDiscovered' | 'UserAdded'
    is_blacklisted      INTEGER NOT NULL DEFAULT 0,
    last_connected_at   INTEGER,
    last_error          TEXT
);

-- ─── Settings ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS settings (
    key   TEXT NOT NULL PRIMARY KEY,
    value TEXT NOT NULL
);

-- ─── Message Queue ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS message_queue (
    id               TEXT NOT NULL PRIMARY KEY,
    event_json       TEXT NOT NULL,
    target_relays    TEXT NOT NULL,   -- JSON array of relay URLs
    status           TEXT NOT NULL DEFAULT 'Pending',  -- 'Pending' | 'Sent' | 'Failed'
    attempts         INTEGER NOT NULL DEFAULT 0,
    created_at       INTEGER NOT NULL,
    last_attempt_at  INTEGER
);

CREATE INDEX IF NOT EXISTS idx_queue_status     ON message_queue(status);
CREATE INDEX IF NOT EXISTS idx_queue_created    ON message_queue(created_at);

-- ─── NWC Wallets ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS nwc_wallets (
    id                  TEXT NOT NULL PRIMARY KEY,
    nwc_uri_encrypted   BLOB NOT NULL,
    alias               TEXT,
    relay_urls          TEXT NOT NULL,  -- JSON array
    wallet_pubkey       TEXT NOT NULL,
    is_active           INTEGER NOT NULL DEFAULT 1,
    created_at          INTEGER NOT NULL
);

-- ─── File Attachments ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS file_attachments (
    id               TEXT NOT NULL PRIMARY KEY,
    message_id       TEXT NOT NULL REFERENCES messages(id),
    trade_id         TEXT NOT NULL REFERENCES trades(id),
    file_name        TEXT NOT NULL,
    mime_type        TEXT NOT NULL,
    file_size        INTEGER NOT NULL,
    blossom_url      TEXT,
    local_path       TEXT,
    download_status  TEXT NOT NULL DEFAULT 'Pending',
    upload_complete  INTEGER NOT NULL DEFAULT 0,
    created_at       INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_attachments_trade_id   ON file_attachments(trade_id);
CREATE INDEX IF NOT EXISTS idx_attachments_message_id ON file_attachments(message_id);

-- ─── Ratings ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ratings (
    id             TEXT NOT NULL PRIMARY KEY,
    trade_id       TEXT NOT NULL REFERENCES trades(id),
    rater_pubkey   TEXT NOT NULL,
    rated_pubkey   TEXT NOT NULL,
    score          INTEGER NOT NULL,
    created_at     INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_ratings_rated_pubkey ON ratings(rated_pubkey);
CREATE INDEX IF NOT EXISTS idx_ratings_trade_id     ON ratings(trade_id);

-- ─── Disputes ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS disputes (
    id                TEXT NOT NULL PRIMARY KEY,
    trade_id          TEXT NOT NULL REFERENCES trades(id),
    order_id          TEXT NOT NULL,
    raised_by_pubkey  TEXT NOT NULL,
    status            TEXT NOT NULL DEFAULT 'Open',  -- 'Open' | 'InReview' | 'Resolved'
    resolution        TEXT,
    admin_pubkey      TEXT,
    evidence_urls     TEXT,  -- JSON array
    notes             TEXT,
    created_at        INTEGER NOT NULL,
    resolved_at       INTEGER
);

CREATE INDEX IF NOT EXISTS idx_disputes_trade_id ON disputes(trade_id);
CREATE INDEX IF NOT EXISTS idx_disputes_status   ON disputes(status);
