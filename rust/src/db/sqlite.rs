/// SQLite storage backend — native platforms only.
use anyhow::Result;
use sqlx::{sqlite::SqlitePoolOptions, SqlitePool};

use crate::api::types::{
    ChatMessage, IdentityInfo, OrderInfo, QueuedMessageStatus, RelayInfo, TradeInfo,
};
use crate::db::{schema::SQLITE_INIT_SQL, Storage};
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
        let rows: Vec<(String,)> =
            sqlx::query_as("SELECT data FROM trades ORDER BY started_at DESC")
                .fetch_all(&self.pool)
                .await?;
        rows.into_iter()
            .map(|(data,)| serde_json::from_str(&data).map_err(Into::into))
            .collect()
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

    async fn mark_messages_read(&self, trade_id: &str) -> Result<()> {
        sqlx::query(
            "UPDATE messages SET is_read = 1 WHERE trade_id = ? AND is_read = 0",
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

    async fn save_mostro_node(&self, node: &crate::api::types::MostroNodeInfo) -> Result<()> {
        let json = serde_json::to_string(node)?;
        sqlx::query(
            "INSERT OR REPLACE INTO settings (key, value) VALUES ('active_mostro_node', ?)",
        )
        .bind(&json)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn get_active_mostro_node(
        &self,
    ) -> Result<Option<crate::api::types::MostroNodeInfo>> {
        let row: Option<(String,)> = sqlx::query_as(
            "SELECT value FROM settings WHERE key = 'active_mostro_node'",
        )
        .fetch_optional(&self.pool)
        .await?;
        match row {
            None => Ok(None),
            Some((json,)) => Ok(Some(serde_json::from_str(&json)?)),
        }
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
}
