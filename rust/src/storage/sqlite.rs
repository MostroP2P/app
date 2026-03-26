/// SQLite storage backend — native platforms only (iOS, Android, macOS, Windows, Linux).
/// Uses sqlx with runtime queries (no compile-time DATABASE_URL required).
use sqlx::{sqlite::SqlitePool, Row};

use crate::storage::{
    DisputeRecord, FileAttachmentRecord, IdentityRecord, MessageRecord, NwcWalletRecord,
    OrderRecord, QueuedMessage, RatingRecord, RelayRecord, Storage, StorageError, StorageResult,
    TradeRecord,
};

pub struct SqliteStorage {
    pool: SqlitePool,
}

impl SqliteStorage {
    pub async fn open(db_path: &str) -> StorageResult<Self> {
        let url = format!("sqlite://{}?mode=rwc", db_path);
        let pool = SqlitePool::connect(&url)
            .await
            .map_err(StorageError::Sqlx)?;

        // Run embedded SQL migrations — split by statement and execute individually.
        // sqlx::query() does not support multiple statements in one call.
        let ddl = include_str!("migrations/001_initial.sql");
        for stmt in ddl
            .split(';')
            .map(|s| s.trim())
            .filter(|s| !s.is_empty() && !s.starts_with("--"))
        {
            sqlx::query(stmt)
                .execute(&pool)
                .await
                .map_err(StorageError::Sqlx)?;
        }

        Ok(Self { pool })
    }
}

// Execute a query and map to StorageError. Pool is passed explicitly to avoid
// `self` hygiene issues with macro_rules! defined at module scope.
macro_rules! qe {
    ($pool:expr, $q:expr) => {
        $q.execute($pool).await.map_err(StorageError::Sqlx)
    };
}

impl Storage for SqliteStorage {
    // ─── Identity ────────────────────────────────────────────────────────
    async fn save_identity(&self, r: IdentityRecord) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "INSERT OR REPLACE INTO identity
             (id, public_key, encrypted_private_key, mnemonic_hash, display_name,
              created_at, last_used_at, trade_key_index, privacy_mode, derivation_path)
             VALUES (?,?,?,?,?,?,?,?,?,?)"
        )
        .bind(&r.id)
        .bind(&r.public_key)
        .bind(&r.encrypted_private_key)
        .bind(&r.mnemonic_hash)
        .bind(&r.display_name)
        .bind(r.created_at)
        .bind(r.last_used_at)
        .bind(r.trade_key_index as i64)
        .bind(r.privacy_mode as i32)
        .bind(&r.derivation_path))?;
        Ok(())
    }

    async fn get_identity(&self) -> StorageResult<Option<IdentityRecord>> {
        let row = sqlx::query(
            "SELECT id, public_key, encrypted_private_key, mnemonic_hash, display_name,
                    created_at, last_used_at, trade_key_index, privacy_mode, derivation_path
             FROM identity LIMIT 1"
        )
        .fetch_optional(&self.pool)
        .await
        .map_err(StorageError::Sqlx)?;

        Ok(row.map(|r| IdentityRecord {
            id: r.get("id"),
            public_key: r.get("public_key"),
            encrypted_private_key: r.get("encrypted_private_key"),
            mnemonic_hash: r.get("mnemonic_hash"),
            display_name: r.get("display_name"),
            created_at: r.get("created_at"),
            last_used_at: r.get("last_used_at"),
            trade_key_index: r.get::<i64, _>("trade_key_index") as u32,
            privacy_mode: r.get::<i32, _>("privacy_mode") != 0,
            derivation_path: r.get("derivation_path"),
        }))
    }

    async fn update_trade_key_index(&self, index: u32) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query("UPDATE identity SET trade_key_index = ?").bind(index as i64))?;
        Ok(())
    }

    async fn delete_identity(&self) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query("DELETE FROM identity"))?;
        Ok(())
    }

    // ─── Orders ──────────────────────────────────────────────────────────
    async fn upsert_order(&self, r: OrderRecord) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "INSERT OR REPLACE INTO orders
             (id, kind, status, amount_sats, fiat_amount, fiat_amount_min, fiat_amount_max,
              fiat_code, payment_method, premium, creator_pubkey, created_at, expires_at,
              nostr_event_id, is_mine, cached_at)
             VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
        )
        .bind(&r.id)
        .bind(&r.kind)
        .bind(&r.status)
        .bind(r.amount_sats)
        .bind(r.fiat_amount)
        .bind(r.fiat_amount_min)
        .bind(r.fiat_amount_max)
        .bind(&r.fiat_code)
        .bind(&r.payment_method)
        .bind(r.premium)
        .bind(&r.creator_pubkey)
        .bind(r.created_at)
        .bind(r.expires_at)
        .bind(&r.nostr_event_id)
        .bind(r.is_mine as i32)
        .bind(r.cached_at))?;
        Ok(())
    }

    async fn get_order(&self, id: &str) -> StorageResult<Option<OrderRecord>> {
        let row = sqlx::query(
            "SELECT id, kind, status, amount_sats, fiat_amount, fiat_amount_min, fiat_amount_max,
                    fiat_code, payment_method, premium, creator_pubkey, created_at, expires_at,
                    nostr_event_id, is_mine, cached_at
             FROM orders WHERE id = ?"
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(StorageError::Sqlx)?;

        Ok(row.map(order_from_row))
    }

    async fn list_orders(&self, status: Option<&str>) -> StorageResult<Vec<OrderRecord>> {
        let rows = if let Some(s) = status {
            sqlx::query(
                "SELECT id, kind, status, amount_sats, fiat_amount, fiat_amount_min,
                        fiat_amount_max, fiat_code, payment_method, premium, creator_pubkey,
                        created_at, expires_at, nostr_event_id, is_mine, cached_at
                 FROM orders WHERE status = ? ORDER BY cached_at DESC"
            )
            .bind(s)
            .fetch_all(&self.pool)
            .await
            .map_err(StorageError::Sqlx)?
        } else {
            sqlx::query(
                "SELECT id, kind, status, amount_sats, fiat_amount, fiat_amount_min,
                        fiat_amount_max, fiat_code, payment_method, premium, creator_pubkey,
                        created_at, expires_at, nostr_event_id, is_mine, cached_at
                 FROM orders ORDER BY cached_at DESC"
            )
            .fetch_all(&self.pool)
            .await
            .map_err(StorageError::Sqlx)?
        };

        Ok(rows.into_iter().map(order_from_row).collect())
    }

    async fn delete_order(&self, id: &str) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query("DELETE FROM orders WHERE id = ?").bind(id))?;
        Ok(())
    }

    // ─── Trades ──────────────────────────────────────────────────────────
    async fn save_trade(&self, r: TradeRecord) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "INSERT OR REPLACE INTO trades
             (id, order_id, role, counterparty_pubkey, current_step, hold_invoice,
              buyer_invoice, trade_key_index, cooperative_cancel_state, timeout_at,
              started_at, completed_at, outcome)
             VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)"
        )
        .bind(&r.id)
        .bind(&r.order_id)
        .bind(&r.role)
        .bind(&r.counterparty_pubkey)
        .bind(&r.current_step)
        .bind(&r.hold_invoice)
        .bind(&r.buyer_invoice)
        .bind(r.trade_key_index as i64)
        .bind(&r.cooperative_cancel_state)
        .bind(r.timeout_at)
        .bind(r.started_at)
        .bind(r.completed_at)
        .bind(&r.outcome))?;
        Ok(())
    }

    async fn get_trade(&self, id: &str) -> StorageResult<Option<TradeRecord>> {
        let row = sqlx::query(
            "SELECT id, order_id, role, counterparty_pubkey, current_step, hold_invoice,
                    buyer_invoice, trade_key_index, cooperative_cancel_state, timeout_at,
                    started_at, completed_at, outcome
             FROM trades WHERE id = ?"
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(StorageError::Sqlx)?;

        Ok(row.map(trade_from_row))
    }

    async fn get_active_trade(&self) -> StorageResult<Option<TradeRecord>> {
        let row = sqlx::query(
            "SELECT id, order_id, role, counterparty_pubkey, current_step, hold_invoice,
                    buyer_invoice, trade_key_index, cooperative_cancel_state, timeout_at,
                    started_at, completed_at, outcome
             FROM trades WHERE completed_at IS NULL ORDER BY started_at DESC LIMIT 1"
        )
        .fetch_optional(&self.pool)
        .await
        .map_err(StorageError::Sqlx)?;

        Ok(row.map(trade_from_row))
    }

    async fn update_trade(&self, r: TradeRecord) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "UPDATE trades SET role=?, counterparty_pubkey=?, current_step=?, hold_invoice=?,
             buyer_invoice=?, trade_key_index=?, cooperative_cancel_state=?, timeout_at=?,
             started_at=?, completed_at=?, outcome=? WHERE id=?"
        )
        .bind(&r.role)
        .bind(&r.counterparty_pubkey)
        .bind(&r.current_step)
        .bind(&r.hold_invoice)
        .bind(&r.buyer_invoice)
        .bind(r.trade_key_index as i64)
        .bind(&r.cooperative_cancel_state)
        .bind(r.timeout_at)
        .bind(r.started_at)
        .bind(r.completed_at)
        .bind(&r.outcome)
        .bind(&r.id))?;
        Ok(())
    }

    // ─── Messages ────────────────────────────────────────────────────────
    async fn save_message(&self, r: MessageRecord) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "INSERT OR IGNORE INTO messages
             (id, trade_id, sender_pubkey, content_encrypted, message_type, is_mine, is_read,
              attachment_id, created_at)
             VALUES (?,?,?,?,?,?,?,?,?)"
        )
        .bind(&r.id)
        .bind(&r.trade_id)
        .bind(&r.sender_pubkey)
        .bind(&r.content_encrypted)
        .bind(&r.message_type)
        .bind(r.is_mine as i32)
        .bind(r.is_read as i32)
        .bind(&r.attachment_id)
        .bind(r.created_at))?;
        Ok(())
    }

    async fn list_messages(&self, trade_id: &str) -> StorageResult<Vec<MessageRecord>> {
        let rows = sqlx::query(
            "SELECT id, trade_id, sender_pubkey, content_encrypted, message_type, is_mine,
                    is_read, attachment_id, created_at
             FROM messages WHERE trade_id = ? ORDER BY created_at ASC"
        )
        .bind(trade_id)
        .fetch_all(&self.pool)
        .await
        .map_err(StorageError::Sqlx)?;

        Ok(rows
            .into_iter()
            .map(|r| MessageRecord {
                id: r.get("id"),
                trade_id: r.get("trade_id"),
                sender_pubkey: r.get("sender_pubkey"),
                content_encrypted: r.get("content_encrypted"),
                message_type: r.get("message_type"),
                is_mine: r.get::<i32, _>("is_mine") != 0,
                is_read: r.get::<i32, _>("is_read") != 0,
                attachment_id: r.get("attachment_id"),
                created_at: r.get("created_at"),
            })
            .collect())
    }

    async fn mark_messages_read(&self, trade_id: &str) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "UPDATE messages SET is_read = 1 WHERE trade_id = ? AND is_mine = 0"
        )
        .bind(trade_id))?;
        Ok(())
    }

    async fn get_unread_count(&self, trade_id: &str) -> StorageResult<u32> {
        let row = sqlx::query(
            "SELECT COUNT(*) as cnt FROM messages WHERE trade_id = ? AND is_read = 0 AND is_mine = 0"
        )
        .bind(trade_id)
        .fetch_one(&self.pool)
        .await
        .map_err(StorageError::Sqlx)?;
        Ok(row.get::<i64, _>("cnt") as u32)
    }

    // ─── Settings ────────────────────────────────────────────────────────
    async fn set_setting(&self, key: &str, value: &str) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query("INSERT OR REPLACE INTO settings (key, value) VALUES (?,?)")
            .bind(key)
            .bind(value))?;
        Ok(())
    }

    async fn get_setting(&self, key: &str) -> StorageResult<Option<String>> {
        let row = sqlx::query("SELECT value FROM settings WHERE key = ?")
            .bind(key)
            .fetch_optional(&self.pool)
            .await
            .map_err(StorageError::Sqlx)?;
        Ok(row.map(|r| r.get("value")))
    }

    // ─── Message Queue ────────────────────────────────────────────────────
    async fn enqueue_message(&self, r: QueuedMessage) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "INSERT INTO message_queue
             (id, event_json, target_relays, status, attempts, created_at, last_attempt_at)
             VALUES (?,?,?,?,?,?,?)"
        )
        .bind(&r.id)
        .bind(&r.event_json)
        .bind(&r.target_relays)
        .bind(&r.status)
        .bind(r.attempts)
        .bind(r.created_at)
        .bind(r.last_attempt_at))?;
        Ok(())
    }

    async fn list_pending_messages(&self) -> StorageResult<Vec<QueuedMessage>> {
        let rows = sqlx::query(
            "SELECT id, event_json, target_relays, status, attempts, created_at, last_attempt_at
             FROM message_queue WHERE status = 'Pending' AND attempts < 10
             ORDER BY created_at ASC"
        )
        .fetch_all(&self.pool)
        .await
        .map_err(StorageError::Sqlx)?;

        Ok(rows
            .into_iter()
            .map(|r| QueuedMessage {
                id: r.get("id"),
                event_json: r.get("event_json"),
                target_relays: r.get("target_relays"),
                status: r.get("status"),
                attempts: r.get("attempts"),
                created_at: r.get("created_at"),
                last_attempt_at: r.get("last_attempt_at"),
            })
            .collect())
    }

    async fn update_message_status(&self, id: &str, status: &str, attempts: i32) -> StorageResult<()> {
        let now = now_secs();
        qe!(&self.pool, sqlx::query(
            "UPDATE message_queue SET status = ?, attempts = ?, last_attempt_at = ? WHERE id = ?"
        )
        .bind(status)
        .bind(attempts)
        .bind(now)
        .bind(id))?;
        Ok(())
    }

    async fn prune_sent_messages(&self, older_than: i64) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "DELETE FROM message_queue WHERE status = 'Sent' AND created_at < ?"
        )
        .bind(older_than))?;
        Ok(())
    }

    // ─── NWC Wallets ──────────────────────────────────────────────────────
    async fn save_wallet(&self, r: NwcWalletRecord) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "INSERT OR REPLACE INTO nwc_wallets
             (id, nwc_uri_encrypted, alias, relay_urls, wallet_pubkey, is_active, created_at)
             VALUES (?,?,?,?,?,?,?)"
        )
        .bind(&r.id)
        .bind(&r.nwc_uri_encrypted)
        .bind(&r.alias)
        .bind(&r.relay_urls)
        .bind(&r.wallet_pubkey)
        .bind(r.is_active as i32)
        .bind(r.created_at))?;
        Ok(())
    }

    async fn get_active_wallet(&self) -> StorageResult<Option<NwcWalletRecord>> {
        let row = sqlx::query(
            "SELECT id, nwc_uri_encrypted, alias, relay_urls, wallet_pubkey, is_active, created_at
             FROM nwc_wallets WHERE is_active = 1 LIMIT 1"
        )
        .fetch_optional(&self.pool)
        .await
        .map_err(StorageError::Sqlx)?;

        Ok(row.map(|r| NwcWalletRecord {
            id: r.get("id"),
            nwc_uri_encrypted: r.get("nwc_uri_encrypted"),
            alias: r.get("alias"),
            relay_urls: r.get("relay_urls"),
            wallet_pubkey: r.get("wallet_pubkey"),
            is_active: r.get::<i32, _>("is_active") != 0,
            created_at: r.get("created_at"),
        }))
    }

    async fn delete_wallet(&self, id: &str) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query("DELETE FROM nwc_wallets WHERE id = ?").bind(id))?;
        Ok(())
    }

    // ─── File Attachments ─────────────────────────────────────────────────
    async fn save_attachment(&self, r: FileAttachmentRecord) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "INSERT OR REPLACE INTO file_attachments
             (id, message_id, trade_id, file_name, mime_type, file_size, blossom_url,
              local_path, download_status, upload_complete, created_at)
             VALUES (?,?,?,?,?,?,?,?,?,?,?)"
        )
        .bind(&r.id)
        .bind(&r.message_id)
        .bind(&r.trade_id)
        .bind(&r.file_name)
        .bind(&r.mime_type)
        .bind(r.file_size)
        .bind(&r.blossom_url)
        .bind(&r.local_path)
        .bind(&r.download_status)
        .bind(r.upload_complete as i32)
        .bind(r.created_at))?;
        Ok(())
    }

    async fn get_attachment(&self, id: &str) -> StorageResult<Option<FileAttachmentRecord>> {
        let row = sqlx::query(
            "SELECT id, message_id, trade_id, file_name, mime_type, file_size, blossom_url,
                    local_path, download_status, upload_complete, created_at
             FROM file_attachments WHERE id = ?"
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(StorageError::Sqlx)?;

        Ok(row.map(|r| FileAttachmentRecord {
            id: r.get("id"),
            message_id: r.get("message_id"),
            trade_id: r.get("trade_id"),
            file_name: r.get("file_name"),
            mime_type: r.get("mime_type"),
            file_size: r.get("file_size"),
            blossom_url: r.get("blossom_url"),
            local_path: r.get("local_path"),
            download_status: r.get("download_status"),
            upload_complete: r.get::<i32, _>("upload_complete") != 0,
            created_at: r.get("created_at"),
        }))
    }

    async fn update_attachment_status(
        &self,
        id: &str,
        status: &str,
        local_path: Option<&str>,
    ) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "UPDATE file_attachments SET download_status = ?, local_path = ? WHERE id = ?"
        )
        .bind(status)
        .bind(local_path)
        .bind(id))?;
        Ok(())
    }

    // ─── Ratings ──────────────────────────────────────────────────────────
    async fn save_rating(&self, r: RatingRecord) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "INSERT OR IGNORE INTO ratings
             (id, trade_id, rater_pubkey, rated_pubkey, score, created_at)
             VALUES (?,?,?,?,?,?)"
        )
        .bind(&r.id)
        .bind(&r.trade_id)
        .bind(&r.rater_pubkey)
        .bind(&r.rated_pubkey)
        .bind(r.score)
        .bind(r.created_at))?;
        Ok(())
    }

    async fn list_ratings_for_pubkey(&self, pubkey: &str) -> StorageResult<Vec<RatingRecord>> {
        let rows = sqlx::query(
            "SELECT id, trade_id, rater_pubkey, rated_pubkey, score, created_at
             FROM ratings WHERE rated_pubkey = ? ORDER BY created_at DESC"
        )
        .bind(pubkey)
        .fetch_all(&self.pool)
        .await
        .map_err(StorageError::Sqlx)?;

        Ok(rows
            .into_iter()
            .map(|r| RatingRecord {
                id: r.get("id"),
                trade_id: r.get("trade_id"),
                rater_pubkey: r.get("rater_pubkey"),
                rated_pubkey: r.get("rated_pubkey"),
                score: r.get("score"),
                created_at: r.get("created_at"),
            })
            .collect())
    }

    // ─── Disputes ─────────────────────────────────────────────────────────
    async fn save_dispute(&self, r: DisputeRecord) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "INSERT OR REPLACE INTO disputes
             (id, trade_id, order_id, raised_by_pubkey, status, resolution, admin_pubkey,
              evidence_urls, notes, created_at, resolved_at)
             VALUES (?,?,?,?,?,?,?,?,?,?,?)"
        )
        .bind(&r.id)
        .bind(&r.trade_id)
        .bind(&r.order_id)
        .bind(&r.raised_by_pubkey)
        .bind(&r.status)
        .bind(&r.resolution)
        .bind(&r.admin_pubkey)
        .bind(&r.evidence_urls)
        .bind(&r.notes)
        .bind(r.created_at)
        .bind(r.resolved_at))?;
        Ok(())
    }

    async fn get_dispute(&self, id: &str) -> StorageResult<Option<DisputeRecord>> {
        let row = sqlx::query(
            "SELECT id, trade_id, order_id, raised_by_pubkey, status, resolution, admin_pubkey,
                    evidence_urls, notes, created_at, resolved_at
             FROM disputes WHERE id = ?"
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await
        .map_err(StorageError::Sqlx)?;

        Ok(row.map(dispute_from_row))
    }

    async fn update_dispute(&self, r: DisputeRecord) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "UPDATE disputes SET status=?, resolution=?, admin_pubkey=?, evidence_urls=?,
             notes=?, resolved_at=? WHERE id=?"
        )
        .bind(&r.status)
        .bind(&r.resolution)
        .bind(&r.admin_pubkey)
        .bind(&r.evidence_urls)
        .bind(&r.notes)
        .bind(r.resolved_at)
        .bind(&r.id))?;
        Ok(())
    }

    // ─── Relays ───────────────────────────────────────────────────────────
    async fn upsert_relay(&self, r: RelayRecord) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query(
            "INSERT OR REPLACE INTO relays
             (id, url, is_active, is_default, source, is_blacklisted, last_connected_at, last_error)
             VALUES (?,?,?,?,?,?,?,?)"
        )
        .bind(&r.id)
        .bind(&r.url)
        .bind(r.is_active as i32)
        .bind(r.is_default as i32)
        .bind(&r.source)
        .bind(r.is_blacklisted as i32)
        .bind(r.last_connected_at)
        .bind(&r.last_error))?;
        Ok(())
    }

    async fn list_relays(&self) -> StorageResult<Vec<RelayRecord>> {
        let rows = sqlx::query(
            "SELECT id, url, is_active, is_default, source, is_blacklisted,
                    last_connected_at, last_error
             FROM relays ORDER BY is_default DESC, url ASC"
        )
        .fetch_all(&self.pool)
        .await
        .map_err(StorageError::Sqlx)?;

        Ok(rows
            .into_iter()
            .map(|r| RelayRecord {
                id: r.get("id"),
                url: r.get("url"),
                is_active: r.get::<i32, _>("is_active") != 0,
                is_default: r.get::<i32, _>("is_default") != 0,
                source: r.get("source"),
                is_blacklisted: r.get::<i32, _>("is_blacklisted") != 0,
                last_connected_at: r.get("last_connected_at"),
                last_error: r.get("last_error"),
            })
            .collect())
    }

    async fn delete_relay(&self, url: &str) -> StorageResult<()> {
        qe!(&self.pool, sqlx::query("DELETE FROM relays WHERE url = ?").bind(url))?;
        Ok(())
    }
}

// ─── Row helpers ─────────────────────────────────────────────────────────────

fn order_from_row(r: sqlx::sqlite::SqliteRow) -> OrderRecord {
    OrderRecord {
        id: r.get("id"),
        kind: r.get("kind"),
        status: r.get("status"),
        amount_sats: r.get("amount_sats"),
        fiat_amount: r.get("fiat_amount"),
        fiat_amount_min: r.get("fiat_amount_min"),
        fiat_amount_max: r.get("fiat_amount_max"),
        fiat_code: r.get("fiat_code"),
        payment_method: r.get("payment_method"),
        premium: r.get("premium"),
        creator_pubkey: r.get("creator_pubkey"),
        created_at: r.get("created_at"),
        expires_at: r.get("expires_at"),
        nostr_event_id: r.get("nostr_event_id"),
        is_mine: r.get::<i32, _>("is_mine") != 0,
        cached_at: r.get("cached_at"),
    }
}

fn trade_from_row(r: sqlx::sqlite::SqliteRow) -> TradeRecord {
    TradeRecord {
        id: r.get("id"),
        order_id: r.get("order_id"),
        role: r.get("role"),
        counterparty_pubkey: r.get("counterparty_pubkey"),
        current_step: r.get("current_step"),
        hold_invoice: r.get("hold_invoice"),
        buyer_invoice: r.get("buyer_invoice"),
        trade_key_index: r.get::<i64, _>("trade_key_index") as u32,
        cooperative_cancel_state: r.get("cooperative_cancel_state"),
        timeout_at: r.get("timeout_at"),
        started_at: r.get("started_at"),
        completed_at: r.get("completed_at"),
        outcome: r.get("outcome"),
    }
}

fn dispute_from_row(r: sqlx::sqlite::SqliteRow) -> DisputeRecord {
    DisputeRecord {
        id: r.get("id"),
        trade_id: r.get("trade_id"),
        order_id: r.get("order_id"),
        raised_by_pubkey: r.get("raised_by_pubkey"),
        status: r.get("status"),
        resolution: r.get("resolution"),
        admin_pubkey: r.get("admin_pubkey"),
        evidence_urls: r.get("evidence_urls"),
        notes: r.get("notes"),
        created_at: r.get("created_at"),
        resolved_at: r.get("resolved_at"),
    }
}

fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}
