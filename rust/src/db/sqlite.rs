/// SQLite storage backend — native platforms only.
use anyhow::Result;
use sqlx::{sqlite::SqlitePoolOptions, SqlitePool};

use crate::api::types::{
    ChatMessage, IdentityInfo, OrderInfo, QueuedMessageStatus, RelayInfo, TradeInfo,
};
use crate::db::{schema::SQLITE_INIT_SQL, settings_keys, Storage};
use crate::queue::outbox::QueuedMessage;

pub struct SqliteStorage {
    pool: SqlitePool,
}

impl SqliteStorage {
    pub async fn open(path: &str) -> Result<Self> {
        let pool = SqlitePoolOptions::new()
            .max_connections(4)
            .connect(&format!("sqlite://{}?mode=rwc", path))
            .await?;
        Self::migrate(&pool).await?;
        sqlx::query(SQLITE_INIT_SQL).execute(&pool).await?;
        Ok(Self { pool })
    }

    /// Applies any schema migrations needed before the main DDL runs.
    ///
    /// Each migration checks for a specific old-schema marker and drops/recreates
    /// the affected table.  Data loss is acceptable for tables that held no
    /// user-critical data (e.g. cached order/trade state that is rebuilt from
    /// the network), but the migration logs a warning so it is visible in debug
    /// output.
    async fn migrate(pool: &SqlitePool) -> Result<()> {
        // Migration 1 → 2: trades table changed from individual columns to a
        // single JSON `data` blob.  Detect the old schema by checking for the
        // `order_id` column which does not exist in the new schema.
        let old_trades: bool = sqlx::query_scalar(
            "SELECT COUNT(*) > 0 FROM pragma_table_info('trades') WHERE name = 'order_id'",
        )
        .fetch_one(pool)
        .await
        .unwrap_or(false);

        if old_trades {
            log::warn!("[db] migrating trades table from schema v1 to v2 (dropping old rows)");
            sqlx::query("DROP TABLE IF EXISTS trades")
                .execute(pool)
                .await?;
        }

        // Repair: a prior version of `update_trade_fields` bound `amount_sats`
        // as a raw text parameter, so SQLite's `json_set` stored it as a JSON
        // string (e.g. `"6307"`) instead of a JSON integer. Rows in that state
        // cannot be deserialized back into `TradeInfo` (`amount_sats: Option<u64>`)
        // and are silently skipped by `list_trades()`, which breaks the
        // seller pay-invoice screen. Walk the table once and rewrite any
        // offending rows so the field becomes a JSON number.
        //
        // The `pragma_table_info` check guards against running on a table
        // that doesn't exist yet (first boot after the CREATE TABLE below).
        let trades_exists: bool = sqlx::query_scalar(
            "SELECT COUNT(*) > 0 FROM sqlite_master WHERE type = 'table' AND name = 'trades'",
        )
        .fetch_one(pool)
        .await
        .unwrap_or(false);
        if trades_exists {
            let repaired: Result<u64, _> = sqlx::query(
                "UPDATE trades \
                 SET data = json_set( \
                     data, \
                     '$.order.amount_sats', \
                     CAST(json_extract(data, '$.order.amount_sats') AS INTEGER) \
                 ) \
                 WHERE json_type(data, '$.order.amount_sats') = 'text'",
            )
            .execute(pool)
            .await
            .map(|r| r.rows_affected());
            match repaired {
                Ok(0) => {}
                Ok(n) => log::warn!(
                    "[db] repaired {n} trade row(s) with string-encoded amount_sats"
                ),
                Err(e) => log::warn!("[db] amount_sats repair failed: {e}"),
            }
        }

        // Migration 1 → 3: the original `messages` table stored one column per
        // field (`sender_pubkey`, `content_encrypted`, …) instead of the JSON
        // `data` blob. It also carries the FK, so without this the v2 → v3
        // rebuild below fires and its `SELECT … data … FROM messages` aborts
        // `open()` with "no such column: data" — killing the ENTIRE database
        // (orders, trades, identity, outbox), not just chat.
        //
        // The rows are dropped rather than converted: `content_encrypted` holds
        // ciphertext the current chat code cannot read back, so there is nothing
        // to recover. Dropping the table takes its legacy indexes with it.
        let messages_exists: bool = sqlx::query_scalar(
            "SELECT COUNT(*) > 0 FROM sqlite_master WHERE type = 'table' AND name = 'messages'",
        )
        .fetch_one(pool)
        .await
        .unwrap_or(false);
        let messages_has_data: bool = sqlx::query_scalar(
            "SELECT COUNT(*) > 0 FROM pragma_table_info('messages') WHERE name = 'data'",
        )
        .fetch_one(pool)
        .await
        .unwrap_or(false);
        if messages_exists && !messages_has_data {
            log::warn!(
                "[db] migrating messages table from schema v1 (dropping unreadable rows)"
            );
            sqlx::query("DROP TABLE IF EXISTS messages")
                .execute(pool)
                .await?;
        }

        // Migration 2 → 3: drop the messages → trades foreign key. Chat keys
        // (and therefore `messages.trade_id`) are per **order id**, while a
        // taker's trades row uses a fresh UUID — with the FK in place every
        // taker `save_message` failed and chat history/replay-dedup was lost
        // on restart (PR #247 review). Rows are preserved.
        //
        // Gated on `data` as well: the rebuild copies that column, so it must
        // never run against a schema that lacks it (the v1 case handled above).
        let messages_has_fk: bool = sqlx::query_scalar(
            "SELECT COUNT(*) > 0 FROM pragma_foreign_key_list('messages')",
        )
        .fetch_one(pool)
        .await
        .unwrap_or(false);
        if messages_has_fk && messages_has_data {
            log::warn!("[db] migrating messages table from schema v2 to v3 (dropping FK)");
            sqlx::query(crate::db::schema::SQLITE_DROP_MESSAGES_FK_SQL)
                .execute(pool)
                .await?;
        }

        Ok(())
    }
}

impl Storage for SqliteStorage {
    async fn save_order(&self, order: &OrderInfo) -> Result<()> {
        let data = serde_json::to_string(order)?;
        let status = format!("{:?}", order.status);
        let is_mine = order.is_mine as i64;
        sqlx::query(
            "INSERT OR REPLACE INTO orders (id, data, status, is_mine, created_at, expires_at)
             VALUES (?, ?, ?, ?, ?, ?)",
        )
        .bind(&order.id)
        .bind(&data)
        .bind(&status)
        .bind(is_mine)
        .bind(order.created_at)
        .bind(order.expires_at)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn get_order(&self, id: &str) -> Result<Option<OrderInfo>> {
        let row: Option<(String,)> =
            sqlx::query_as("SELECT data FROM orders WHERE id = ?")
                .bind(id)
                .fetch_optional(&self.pool)
                .await?;
        Ok(row.map(|(data,)| serde_json::from_str(&data)).transpose()?)
    }

    async fn delete_order(&self, id: &str) -> Result<()> {
        sqlx::query("DELETE FROM orders WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn list_orders(&self) -> Result<Vec<OrderInfo>> {
        let rows: Vec<(String,)> =
            sqlx::query_as("SELECT data FROM orders ORDER BY created_at DESC")
                .fetch_all(&self.pool)
                .await?;
        rows.into_iter()
            .map(|(data,)| serde_json::from_str(&data).map_err(Into::into))
            .collect()
    }

    async fn save_trade(&self, trade: &TradeInfo) -> Result<()> {
        let data = serde_json::to_string(trade)?;
        let status = format!("{:?}", trade.order.status);
        sqlx::query(
            "INSERT OR REPLACE INTO trades (id, data, status, started_at, completed_at)
             VALUES (?, ?, ?, ?, ?)",
        )
        .bind(&trade.id)
        .bind(&data)
        .bind(&status)
        .bind(trade.started_at)
        .bind(trade.completed_at)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn get_trade(&self, id: &str) -> Result<Option<TradeInfo>> {
        let row: Option<(String,)> =
            sqlx::query_as("SELECT data FROM trades WHERE id = ?")
                .bind(id)
                .fetch_optional(&self.pool)
                .await?;
        Ok(row.map(|(data,)| serde_json::from_str(&data)).transpose()?)
    }

    async fn list_trades(&self) -> Result<Vec<TradeInfo>> {
        let rows: Vec<(String, String)> =
            sqlx::query_as("SELECT id, data FROM trades ORDER BY started_at DESC")
                .fetch_all(&self.pool)
                .await?;
        let mut trades = Vec::with_capacity(rows.len());
        for (id, data) in rows {
            match serde_json::from_str::<TradeInfo>(&data) {
                Ok(trade) => trades.push(trade),
                Err(e) => {
                    log::warn!("[db] skipping trade {id}: deserialization failed: {e}");
                }
            }
        }
        Ok(trades)
    }

    async fn save_message(&self, msg: &ChatMessage) -> Result<()> {
        let data = serde_json::to_string(msg)?;
        let is_read = msg.is_read as i64;
        sqlx::query(
            "INSERT OR REPLACE INTO messages (id, trade_id, data, is_read, created_at)
             VALUES (?, ?, ?, ?, ?)",
        )
        .bind(&msg.id)
        .bind(&msg.trade_id)
        .bind(&data)
        .bind(is_read)
        .bind(msg.created_at)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn list_messages(&self, trade_id: &str) -> Result<Vec<ChatMessage>> {
        let rows: Vec<(String,)> = sqlx::query_as(
            "SELECT data FROM messages WHERE trade_id = ? ORDER BY created_at ASC",
        )
        .bind(trade_id)
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter()
            .map(|(data,)| serde_json::from_str(&data).map_err(Into::into))
            .collect()
    }

    async fn message_exists(&self, id: &str) -> Result<bool> {
        let row: Option<(i64,)> = sqlx::query_as("SELECT 1 FROM messages WHERE id = ?")
            .bind(id)
            .fetch_optional(&self.pool)
            .await?;
        Ok(row.is_some())
    }

    async fn mark_messages_read(&self, trade_id: &str) -> Result<()> {
        // `list_messages` reconstructs ChatMessage from the JSON `data` blob,
        // so the flag must be rewritten there too — updating only the
        // denormalized column resurrects unread badges after a restart.
        // `json('true')` keeps the field a JSON boolean (json_set with a bare
        // 1 would turn it into a number and break deserialization).
        sqlx::query(
            "UPDATE messages
             SET is_read = 1,
                 data = json_set(data, '$.is_read', json('true'))
             WHERE trade_id = ? AND is_read = 0",
        )
        .bind(trade_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn save_relay(&self, relay: &RelayInfo) -> Result<()> {
        let data = serde_json::to_string(relay)?;
        sqlx::query("INSERT OR REPLACE INTO relays (url, data) VALUES (?, ?)")
            .bind(&relay.url)
            .bind(&data)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn delete_relay(&self, url: &str) -> Result<()> {
        sqlx::query("DELETE FROM relays WHERE url = ?")
            .bind(url)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn list_relays(&self) -> Result<Vec<RelayInfo>> {
        let rows: Vec<(String,)> = sqlx::query_as("SELECT data FROM relays")
            .fetch_all(&self.pool)
            .await?;
        rows.into_iter()
            .map(|(data,)| serde_json::from_str(&data).map_err(Into::into))
            .collect()
    }

    async fn save_identity(&self, identity: &IdentityInfo) -> Result<()> {
        let data = serde_json::to_string(identity)?;
        sqlx::query("INSERT OR REPLACE INTO identity (id, data) VALUES (1, ?)")
            .bind(&data)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn get_identity(&self) -> Result<Option<IdentityInfo>> {
        let row: Option<(String,)> =
            sqlx::query_as("SELECT data FROM identity WHERE id = 1")
                .fetch_optional(&self.pool)
                .await?;
        Ok(row.map(|(data,)| serde_json::from_str(&data)).transpose()?)
    }

    async fn delete_identity(&self) -> Result<()> {
        sqlx::query("DELETE FROM identity")
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn save_queued_message(&self, msg: &QueuedMessage) -> Result<()> {
        let data = serde_json::to_string(msg)?;
        let status = format!("{:?}", msg.status);
        sqlx::query(
            "INSERT OR REPLACE INTO queued_messages
             (id, data, status, created_at, retry_count, next_retry_at)
             VALUES (?, ?, ?, ?, ?, ?)",
        )
        .bind(&msg.id)
        .bind(&data)
        .bind(&status)
        .bind(msg.created_at)
        .bind(msg.retry_count as i64)
        .bind(msg.next_retry_at)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn list_queued_messages(&self) -> Result<Vec<QueuedMessage>> {
        let rows: Vec<(String,)> = sqlx::query_as(
            "SELECT data FROM queued_messages
             WHERE status = 'Pending'
             ORDER BY created_at ASC",
        )
        .fetch_all(&self.pool)
        .await?;
        rows.into_iter()
            .map(|(data,)| serde_json::from_str(&data).map_err(Into::into))
            .collect()
    }

    async fn update_queued_message_status(
        &self,
        id: &str,
        status: QueuedMessageStatus,
    ) -> Result<()> {
        // Load the existing row, update the status field inside the JSON blob,
        // then persist both the `status` column and the `data` blob together so
        // they never diverge when `list_queued_messages` deserialises `data`.
        let row: Option<(String,)> =
            sqlx::query_as("SELECT data FROM queued_messages WHERE id = ?")
                .bind(id)
                .fetch_optional(&self.pool)
                .await?;

        let Some((data,)) = row else {
            return Ok(()); // nothing to update
        };

        let mut msg: crate::queue::outbox::QueuedMessage = serde_json::from_str(&data)?;
        msg.status = status;
        let new_data = serde_json::to_string(&msg)?;
        let status_str = format!("{:?}", msg.status);

        sqlx::query(
            "UPDATE queued_messages SET status = ?, data = ? WHERE id = ?",
        )
        .bind(&status_str)
        .bind(&new_data)
        .bind(id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn delete_queued_message(&self, id: &str) -> Result<()> {
        sqlx::query("DELETE FROM queued_messages WHERE id = ?")
            .bind(id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn save_trade_key(&self, order_id: &str, key_index: u32) -> Result<()> {
        sqlx::query(
            "INSERT OR REPLACE INTO trade_keys (order_id, key_index) VALUES (?, ?)",
        )
        .bind(order_id)
        .bind(key_index as i64)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn get_trade_key(&self, order_id: &str) -> Result<Option<u32>> {
        let row: Option<(i64,)> =
            sqlx::query_as("SELECT key_index FROM trade_keys WHERE order_id = ?")
                .bind(order_id)
                .fetch_optional(&self.pool)
                .await?;
        Ok(row.map(|(idx,)| idx as u32))
    }

    async fn get_order_id_by_trade_index(&self, key_index: u32) -> Result<Option<String>> {
        let row: Option<(String,)> =
            sqlx::query_as("SELECT order_id FROM trade_keys WHERE key_index = ? LIMIT 1")
                .bind(key_index as i64)
                .fetch_optional(&self.pool)
                .await?;
        Ok(row.map(|(id,)| id))
    }

    async fn delete_trade_key(&self, order_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM trade_keys WHERE order_id = ?")
            .bind(order_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn clear_trade_keys(&self) -> Result<()> {
        sqlx::query("DELETE FROM trade_keys")
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn get_setting(&self, key: &str) -> Result<Option<String>> {
        let row: Option<(String,)> =
            sqlx::query_as("SELECT value FROM settings WHERE key = ?")
                .bind(key)
                .fetch_optional(&self.pool)
                .await?;
        Ok(row.map(|(v,)| v))
    }

    async fn set_setting(&self, key: &str, value: &str) -> Result<()> {
        sqlx::query("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)")
            .bind(key)
            .bind(value)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn delete_setting(&self, key: &str) -> Result<()> {
        sqlx::query("DELETE FROM settings WHERE key = ?")
            .bind(key)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    // The active node lives in the same k/v table under a fixed key. These two
    // stay as named accessors so callers never handle the key string, but they
    // delegate rather than duplicate the SQL.

    async fn save_active_mostro_pubkey(&self, pubkey: &str) -> Result<()> {
        self.set_setting(settings_keys::ACTIVE_MOSTRO_PUBKEY, pubkey)
            .await
    }

    async fn get_active_mostro_pubkey(&self) -> Result<Option<String>> {
        self.get_setting(settings_keys::ACTIVE_MOSTRO_PUBKEY).await
    }

    async fn get_trade_by_order_id(&self, order_id: &str) -> Result<Option<TradeInfo>> {
        // The `data` column holds the full JSON-serialised TradeInfo; use
        // SQLite's json_extract to filter by the nested order id without
        // deserialising every row.
        let row: Option<(String,)> = sqlx::query_as(
            "SELECT data FROM trades \
             WHERE json_extract(data, '$.order.id') = ? \
             LIMIT 1",
        )
        .bind(order_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|(data,)| serde_json::from_str(&data)).transpose()?)
    }

    async fn delete_trade_by_order_id(&self, order_id: &str) -> Result<()> {
        // Same nested-id filter as `get_trade_by_order_id`: `trades.id` is a
        // fresh UUID for takers, so the row must be found via the order id
        // stored inside the JSON blob.
        sqlx::query(
            "DELETE FROM trades WHERE json_extract(data, '$.order.id') = ?",
        )
        .bind(order_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn update_trade_order_id(
        &self,
        old_order_id: &str,
        new_order_id: &str,
    ) -> Result<()> {
        // Atomic single-statement update via json_set — no read-modify-write race.
        sqlx::query(
            "UPDATE trades \
             SET data = json_set(data, '$.order.id', ?) \
             WHERE json_extract(data, '$.order.id') = ?",
        )
        .bind(new_order_id)
        .bind(old_order_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn update_trade_fields(
        &self,
        order_id: &str,
        status: Option<crate::api::types::OrderStatus>,
        hold_invoice: Option<String>,
        amount_sats: Option<u64>,
    ) -> Result<()> {
        // Build the update atomically with json_set to avoid read-modify-write races.
        // Start from `data` and layer each mutation.
        let mut set_expr = String::from("data");
        let mut binds: Vec<String> = Vec::new();

        if let Some(ref s) = status {
            let status_json = serde_json::to_string(s)?;
            set_expr = format!("json_set({set_expr}, '$.order.status', json(?))");
            binds.push(status_json);
        }
        if let Some(ref inv) = hold_invoice {
            set_expr = format!("json_set({set_expr}, '$.hold_invoice', ?)");
            binds.push(inv.clone());
        }
        if let Some(sats) = amount_sats {
            // Bind via json(?) so SQLite parses "6307" as a JSON integer,
            // otherwise json_set stores it as a JSON string and the row
            // fails to deserialize back into TradeInfo (amount_sats: Option<u64>).
            set_expr = format!("json_set({set_expr}, '$.order.amount_sats', json(?))");
            binds.push(sats.to_string());
        }

        if binds.is_empty() {
            return Ok(());
        }

        // Also update the denormalised `status` column when status changes.
        let status_col_update = if status.is_some() {
            ", status = ?"
        } else {
            ""
        };

        let sql = format!(
            "UPDATE trades SET data = {set_expr}{status_col_update} \
             WHERE json_extract(data, '$.order.id') = ?"
        );

        let mut query = sqlx::query(&sql);
        for val in &binds {
            query = query.bind(val);
        }
        if let Some(ref s) = status {
            query = query.bind(format!("{s:?}"));
        }
        query = query.bind(order_id);
        query.execute(&self.pool).await?;
        Ok(())
    }

    async fn update_trade_peer_reputation(
        &self,
        order_id: &str,
        rating: f64,
        reviews: u32,
        days: u32,
    ) -> Result<()> {
        // Layer the three scalars with json_set in one statement. Bind rating
        // via json(?) so SQLite stores it as a JSON number, not a string — a
        // string would fail to deserialize back into `Option<f64>`. reviews and
        // days go through json(?) for the same reason (they map to Option<u32>).
        let sql = "UPDATE trades SET data = json_set(\
             data, \
             '$.peer_rating', json(?), \
             '$.peer_reviews', json(?), \
             '$.peer_days', json(?)) \
             WHERE json_extract(data, '$.order.id') = ?";
        sqlx::query(sql)
            .bind(rating.to_string())
            .bind(reviews.to_string())
            .bind(days.to_string())
            .bind(order_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn mark_trade_rated(&self, order_id: &str, rated_at: i64) -> Result<()> {
        // Bind via json(?) so SQLite stores the timestamp as a JSON number, not
        // a string — a string would fail to deserialize back into Option<i64>.
        let sql = "UPDATE trades SET data = json_set(\
             data, '$.rated_at', json(?)) \
             WHERE json_extract(data, '$.order.id') = ?";
        sqlx::query(sql)
            .bind(rated_at.to_string())
            .bind(order_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};

    /// Build a unique temp DB path so parallel tests never collide.
    fn temp_db_path() -> std::path::PathBuf {
        static COUNTER: AtomicU32 = AtomicU32::new(0);
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir().join(format!("mostro_test_{}_{n}.db", std::process::id()))
    }

    #[tokio::test]
    async fn message_exists_is_durable_replay_dedup() {
        use crate::api::types::*;

        let path = temp_db_path();
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();

        // Chat persists under the ORDER id — for takers there is no trades
        // row with that id (trades.id is a fresh UUID), so this must succeed
        // without any trades row at all (the old FK broke exactly this).
        let trade_id = "order-dedup-1".to_string();

        let inner_id = "3f".repeat(32);
        assert!(!storage.message_exists(&inner_id).await.unwrap());

        let msg = ChatMessage {
            id: inner_id.clone(),
            trade_id,
            sender_pubkey: "peer".into(),
            content: "I sent the fiat".into(),
            message_type: MessageType::Peer,
            is_mine: false,
            is_read: false,
            has_attachment: false,
            attachment: None,
            created_at: 2,
        };
        storage.save_message(&msg).await.unwrap();

        // A re-wrapped replay carries the same inner id — now known, durably.
        assert!(storage.message_exists(&inner_id).await.unwrap());
        assert!(!storage.message_exists("un".repeat(32).as_str()).await.unwrap());

        drop(storage);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn delete_trade_by_order_id_removes_only_the_matching_row() {
        use crate::api::types::*;

        let path = temp_db_path();
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();

        // Taker-shaped rows: trades.id is a fresh UUID, distinct from the
        // order id — deletion must go through the nested JSON order id.
        let trade = |row_id: &str, order_id: &str| TradeInfo {
            id: row_id.into(),
            order: OrderInfo {
                id: order_id.into(),
                kind: OrderKind::Sell,
                status: OrderStatus::WaitingBuyerInvoice,
                amount_sats: None,
                fiat_amount: Some(100.0),
                fiat_amount_min: None,
                fiat_amount_max: None,
                fiat_code: "CUP".into(),
                payment_method: "bank".into(),
                premium: 0.0,
                creator_pubkey: "maker".into(),
                created_at: 1,
                expires_at: None,
                is_mine: false,
                rating: 0.0,
                total_reviews: 0,
                days_active: 0,
            },
            role: TradeRole::Buyer,
            counterparty_pubkey: String::new(),
            current_step: TradeStep::Buyer(BuyerStep::OrderTaken),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 1,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
        };
        storage.save_trade(&trade("row-a", "order-a")).await.unwrap();
        storage.save_trade(&trade("row-b", "order-b")).await.unwrap();

        storage.delete_trade_by_order_id("order-a").await.unwrap();

        assert!(storage
            .get_trade_by_order_id("order-a")
            .await
            .unwrap()
            .is_none());
        let remaining = storage.list_trades().await.unwrap();
        assert_eq!(remaining.len(), 1);
        assert_eq!(remaining[0].order.id, "order-b");

        // Unknown order id: no-op, not an error.
        storage.delete_trade_by_order_id("order-missing").await.unwrap();
        assert_eq!(storage.list_trades().await.unwrap().len(), 1);

        drop(storage);
        let _ = std::fs::remove_file(&path);
    }

    /// The taker reputation snapshot (issue #305) round-trips through the
    /// nested-JSON update: written by order id, read back as numbers on
    /// `TradeInfo`, and stored on a row whose `trades.id` differs from the
    /// order id (taker-shaped), so the update must go through `$.order.id`.
    #[tokio::test]
    async fn update_trade_peer_reputation_round_trips_by_order_id() {
        use crate::api::types::*;

        let path = temp_db_path();
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();

        let trade = |row_id: &str, order_id: &str| TradeInfo {
            id: row_id.into(),
            order: OrderInfo {
                id: order_id.into(),
                kind: OrderKind::Sell,
                status: OrderStatus::WaitingBuyerInvoice,
                amount_sats: None,
                fiat_amount: Some(100.0),
                fiat_amount_min: None,
                fiat_amount_max: None,
                fiat_code: "CUP".into(),
                payment_method: "bank".into(),
                premium: 0.0,
                creator_pubkey: "maker".into(),
                created_at: 1,
                expires_at: None,
                is_mine: false,
                rating: 0.0,
                total_reviews: 0,
                days_active: 0,
            },
            role: TradeRole::Buyer,
            counterparty_pubkey: String::new(),
            current_step: TradeStep::Buyer(BuyerStep::OrderTaken),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 1,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
        };
        storage.save_trade(&trade("row-a", "order-a")).await.unwrap();
        storage.save_trade(&trade("row-b", "order-b")).await.unwrap();

        // The reproduction's numbers: rating 4.375, 4 reviews, 64 days.
        storage
            .update_trade_peer_reputation("order-a", 4.375, 4, 64)
            .await
            .unwrap();

        let a = storage
            .get_trade_by_order_id("order-a")
            .await
            .unwrap()
            .expect("order-a survives");
        assert_eq!(a.peer_rating, Some(4.375));
        assert_eq!(a.peer_reviews, Some(4));
        assert_eq!(a.peer_days, Some(64));

        // The sibling row is untouched — the update is scoped by order id.
        let b = storage
            .get_trade_by_order_id("order-b")
            .await
            .unwrap()
            .expect("order-b survives");
        assert_eq!(b.peer_rating, None);
        assert_eq!(b.peer_reviews, None);
        assert_eq!(b.peer_days, None);

        // A brand-new taker persists as all-zeros, not as absent — the UI
        // shows the raw numbers rather than guessing "new user".
        storage
            .update_trade_peer_reputation("order-b", 0.0, 0, 0)
            .await
            .unwrap();
        let b = storage
            .get_trade_by_order_id("order-b")
            .await
            .unwrap()
            .expect("order-b survives");
        assert_eq!(b.peer_rating, Some(0.0));
        assert_eq!(b.peer_reviews, Some(0));
        assert_eq!(b.peer_days, Some(0));

        drop(storage);
        let _ = std::fs::remove_file(&path);
    }

    /// The durable rated marker (issue #339) round-trips as a JSON number, is
    /// scoped to a single order id, and is absent until written.
    #[tokio::test]
    async fn mark_trade_rated_round_trips_by_order_id() {
        use crate::api::types::*;

        let path = temp_db_path();
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();

        let trade = |row_id: &str, order_id: &str| TradeInfo {
            id: row_id.into(),
            order: OrderInfo {
                id: order_id.into(),
                kind: OrderKind::Sell,
                status: OrderStatus::WaitingBuyerInvoice,
                amount_sats: None,
                fiat_amount: Some(100.0),
                fiat_amount_min: None,
                fiat_amount_max: None,
                fiat_code: "CUP".into(),
                payment_method: "bank".into(),
                premium: 0.0,
                creator_pubkey: "maker".into(),
                created_at: 1,
                expires_at: None,
                is_mine: false,
                rating: 0.0,
                total_reviews: 0,
                days_active: 0,
            },
            role: TradeRole::Buyer,
            counterparty_pubkey: String::new(),
            current_step: TradeStep::Buyer(BuyerStep::OrderTaken),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 1,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
        };
        storage.save_trade(&trade("row-a", "order-a")).await.unwrap();
        storage.save_trade(&trade("row-b", "order-b")).await.unwrap();

        // Absent until written.
        let a = storage
            .get_trade_by_order_id("order-a")
            .await
            .unwrap()
            .expect("order-a survives");
        assert_eq!(a.rated_at, None);

        storage.mark_trade_rated("order-a", 1_700_000_000).await.unwrap();

        // Stored as a JSON number that deserializes back into Option<i64>.
        let a = storage
            .get_trade_by_order_id("order-a")
            .await
            .unwrap()
            .expect("order-a survives");
        assert_eq!(a.rated_at, Some(1_700_000_000));

        // The sibling row is untouched — the update is scoped by order id.
        let b = storage
            .get_trade_by_order_id("order-b")
            .await
            .unwrap()
            .expect("order-b survives");
        assert_eq!(b.rated_at, None);

        drop(storage);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn mark_messages_read_survives_rehydration() {
        use crate::api::types::*;

        let path = temp_db_path();
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();

        let trade_id = "order-read-1".to_string();
        storage
            .save_message(&ChatMessage {
                id: "read-msg-1".into(),
                trade_id: trade_id.clone(),
                sender_pubkey: "peer".into(),
                content: "hola".into(),
                message_type: MessageType::Peer,
                is_mine: false,
                is_read: false,
                has_attachment: false,
                attachment: None,
                created_at: 1,
            })
            .await
            .unwrap();

        storage.mark_messages_read(&trade_id).await.unwrap();

        // Reopen: list_messages deserializes the JSON blob — the read flag
        // must have been rewritten there, not only in the column.
        drop(storage);
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();
        let msgs = storage.list_messages(&trade_id).await.unwrap();
        assert_eq!(msgs.len(), 1);
        assert!(msgs[0].is_read, "is_read lost on rehydration");

        drop(storage);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn v2_messages_fk_is_dropped_and_rows_survive() {
        let path = temp_db_path();
        let url = format!("sqlite://{}?mode=rwc", path.to_str().unwrap());

        // Build a v2-era database by hand: messages with the old FK and one
        // row referencing a trades row (the maker case, which used to work).
        {
            let pool = SqlitePoolOptions::new().connect(&url).await.unwrap();
            sqlx::query(
                "CREATE TABLE trades (
                     id TEXT PRIMARY KEY, data TEXT NOT NULL, status TEXT NOT NULL,
                     started_at INTEGER NOT NULL, completed_at INTEGER);
                 CREATE TABLE messages (
                     id TEXT PRIMARY KEY, trade_id TEXT NOT NULL, data TEXT NOT NULL,
                     is_read INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL,
                     FOREIGN KEY (trade_id) REFERENCES trades(id));
                 -- Leftover from a previous interrupted migration attempt:
                 -- the rebuild must drop and recreate it, not fail.
                 CREATE TABLE messages_v3 (leftover INTEGER);
                 INSERT INTO trades VALUES ('t1', '{}', 'Active', 1, NULL);
                 INSERT INTO messages VALUES ('m1', 't1',
                     '{\"id\":\"m1\",\"trade_id\":\"t1\",\"sender_pubkey\":\"p\",\"content\":\"x\",\"message_type\":\"Peer\",\"is_mine\":false,\"is_read\":false,\"has_attachment\":false,\"attachment\":null,\"created_at\":1}',
                     0, 1);",
            )
            .execute(&pool)
            .await
            .unwrap();
            pool.close().await;
        }

        // open() must detect the FK, rebuild the table, and keep the row.
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();
        assert!(storage.message_exists("m1").await.unwrap());

        // And an order-id message with no trades row now persists fine.
        let msgs = storage.list_messages("t1").await.unwrap();
        assert_eq!(msgs.len(), 1);

        drop(storage);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn pre_v2_messages_table_is_rebuilt_not_copied() {
        let path = temp_db_path();
        let url = format!("sqlite://{}?mode=rwc", path.to_str().unwrap());

        // Build a v1-era database by hand: `messages` still stores one column
        // per field (no JSON `data` blob) and carries the FK to trades. The
        // v2 → v3 rebuild copies `data`, so triggering it here used to abort
        // `open()` with "no such column: data" — taking the WHOLE database
        // down, not just chat (orders, trades, identity, outbox).
        {
            let pool = SqlitePoolOptions::new().connect(&url).await.unwrap();
            sqlx::query(
                "CREATE TABLE trades (
                     id TEXT PRIMARY KEY, data TEXT NOT NULL, status TEXT NOT NULL,
                     started_at INTEGER NOT NULL, completed_at INTEGER);
                 CREATE TABLE messages (
                     id                TEXT NOT NULL PRIMARY KEY,
                     trade_id          TEXT NOT NULL REFERENCES trades(id),
                     sender_pubkey     TEXT NOT NULL,
                     content_encrypted BLOB NOT NULL,
                     message_type      TEXT NOT NULL,
                     is_mine           INTEGER NOT NULL DEFAULT 0,
                     is_read           INTEGER NOT NULL DEFAULT 0,
                     attachment_id     TEXT,
                     created_at        INTEGER NOT NULL);
                 CREATE INDEX idx_messages_trade_id ON messages(trade_id);
                 CREATE INDEX idx_messages_is_read  ON messages(is_read);
                 INSERT INTO trades VALUES ('t1', '{}', 'Active', 1, NULL);
                 INSERT INTO messages VALUES
                     ('m0', 't1', 'p', x'00', 'Peer', 0, 0, NULL, 1);",
            )
            .execute(&pool)
            .await
            .unwrap();
            pool.close().await;
        }

        // open() must succeed — the legacy table is dropped, not copied.
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();

        // The rebuilt table is v3: JSON `data`, no foreign key.
        let cols: Vec<(String,)> =
            sqlx::query_as("SELECT name FROM pragma_table_info('messages')")
                .fetch_all(&storage.pool)
                .await
                .unwrap();
        let cols: Vec<String> = cols.into_iter().map(|(c,)| c).collect();
        assert!(cols.contains(&"data".to_string()), "columns: {cols:?}");
        assert!(
            !cols.contains(&"content_encrypted".to_string()),
            "legacy column survived: {cols:?}"
        );
        let fks: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM pragma_foreign_key_list('messages')")
                .fetch_one(&storage.pool)
                .await
                .unwrap();
        assert_eq!(fks, 0, "messages still has a foreign key");

        // And it is usable: an order-id message with no matching trades row.
        storage
            .save_message(&crate::api::types::ChatMessage {
                id: "m1".into(),
                trade_id: "order-1".into(),
                sender_pubkey: "peer".into(),
                content: "hola".into(),
                message_type: crate::api::types::MessageType::Peer,
                is_mine: false,
                is_read: false,
                has_attachment: false,
                attachment: None,
                created_at: 1,
            })
            .await
            .unwrap();
        assert_eq!(storage.list_messages("order-1").await.unwrap().len(), 1);

        drop(storage);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn active_mostro_pubkey_round_trip() {
        let path = temp_db_path();
        let path_str = path.to_str().unwrap().to_string();
        let storage = SqliteStorage::open(&path_str).await.unwrap();

        // Absent until the user selects a node.
        assert_eq!(storage.get_active_mostro_pubkey().await.unwrap(), None);

        // Save then read back.
        let pk = "82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390";
        storage.save_active_mostro_pubkey(pk).await.unwrap();
        assert_eq!(
            storage.get_active_mostro_pubkey().await.unwrap().as_deref(),
            Some(pk)
        );

        // INSERT OR REPLACE overwrites in place — no duplicate "active" row.
        let pk2 = "0000000000000000000000000000000000000000000000000000000000000001";
        storage.save_active_mostro_pubkey(pk2).await.unwrap();
        assert_eq!(
            storage.get_active_mostro_pubkey().await.unwrap().as_deref(),
            Some(pk2)
        );

        drop(storage);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn settings_kv_round_trip() {
        // Arrange
        let path = temp_db_path();
        let path_str = path.to_str().unwrap().to_string();
        let storage = SqliteStorage::open(&path_str).await.unwrap();

        // Assert — an unwritten key reads as absent, not as an empty string.
        assert_eq!(
            storage
                .get_setting(settings_keys::ESCROW_MODE_OVERRIDE)
                .await
                .unwrap(),
            None
        );

        // Act / Assert — write, overwrite, read back.
        storage
            .set_setting(settings_keys::ESCROW_MODE_OVERRIDE, "auto")
            .await
            .unwrap();
        storage
            .set_setting(settings_keys::ESCROW_MODE_OVERRIDE, "force_cashu")
            .await
            .unwrap();
        assert_eq!(
            storage
                .get_setting(settings_keys::ESCROW_MODE_OVERRIDE)
                .await
                .unwrap()
                .as_deref(),
            Some("force_cashu")
        );

        // Assert — keys are independent; writing one does not disturb another.
        storage
            .set_setting(settings_keys::CASHU_MINT_URL_OVERRIDE, "http://localhost:3338")
            .await
            .unwrap();
        assert_eq!(
            storage
                .get_setting(settings_keys::ESCROW_MODE_OVERRIDE)
                .await
                .unwrap()
                .as_deref(),
            Some("force_cashu")
        );

        // Act — clearing a preference.
        storage
            .delete_setting(settings_keys::CASHU_MINT_URL_OVERRIDE)
            .await
            .unwrap();

        // Assert — deleted reads as absent, and deleting again is not an error.
        assert_eq!(
            storage
                .get_setting(settings_keys::CASHU_MINT_URL_OVERRIDE)
                .await
                .unwrap(),
            None
        );
        storage
            .delete_setting(settings_keys::CASHU_MINT_URL_OVERRIDE)
            .await
            .unwrap();

        drop(storage);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn the_active_node_accessors_share_the_kv_store() {
        // Arrange — the named accessors are wrappers; a value written through
        // one must be visible through the other, or a future refactor could
        // silently split them into two rows.
        let path = temp_db_path();
        let path_str = path.to_str().unwrap().to_string();
        let storage = SqliteStorage::open(&path_str).await.unwrap();
        let pk = "82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390";

        // Act
        storage.save_active_mostro_pubkey(pk).await.unwrap();

        // Assert
        assert_eq!(
            storage
                .get_setting(settings_keys::ACTIVE_MOSTRO_PUBKEY)
                .await
                .unwrap()
                .as_deref(),
            Some(pk)
        );

        drop(storage);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn identity_round_trip_preserves_trade_key_index() {
        let path = temp_db_path();
        let path_str = path.to_str().unwrap().to_string();
        let storage = SqliteStorage::open(&path_str).await.unwrap();

        // Absent until the first save.
        assert!(storage.get_identity().await.unwrap().is_none());

        let mut identity = IdentityInfo {
            public_key: "abc123".to_string(),
            display_name: None,
            privacy_mode: false,
            trade_key_index: 21,
            created_at: 1_700_000_000,
        };
        storage.save_identity(&identity).await.unwrap();
        let loaded = storage.get_identity().await.unwrap().unwrap();
        assert_eq!(loaded.public_key, "abc123");
        assert_eq!(loaded.trade_key_index, 21);

        // INSERT OR REPLACE keeps a single row with the latest counter.
        identity.trade_key_index = 22;
        storage.save_identity(&identity).await.unwrap();
        let loaded = storage.get_identity().await.unwrap().unwrap();
        assert_eq!(loaded.trade_key_index, 22);

        drop(storage);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn delete_identity_clears_row_and_trade_keys() {
        let path = temp_db_path();
        let path_str = path.to_str().unwrap().to_string();
        let storage = SqliteStorage::open(&path_str).await.unwrap();

        let identity = IdentityInfo {
            public_key: "abc123".to_string(),
            display_name: None,
            privacy_mode: false,
            trade_key_index: 7,
            created_at: 1_700_000_000,
        };
        storage.save_identity(&identity).await.unwrap();
        storage.save_trade_key("order-1", 5).await.unwrap();
        storage.save_trade_key("order-2", 6).await.unwrap();

        storage.delete_identity().await.unwrap();
        storage.clear_trade_keys().await.unwrap();

        assert!(storage.get_identity().await.unwrap().is_none());
        assert_eq!(storage.get_trade_key("order-1").await.unwrap(), None);
        assert_eq!(storage.get_trade_key("order-2").await.unwrap(), None);

        // Deleting again on empty tables is a no-op, not an error.
        storage.delete_identity().await.unwrap();
        storage.clear_trade_keys().await.unwrap();

        drop(storage);
        let _ = std::fs::remove_file(&path);
    }
}
