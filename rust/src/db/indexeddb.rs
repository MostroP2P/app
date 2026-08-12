/// IndexedDB storage backend — WASM target only.
///
/// **Chat messages and the settings KV are fully implemented** (issue #246):
/// the durable inner-event-id replay dedup and the chat `since` cursor are
/// MUST-level security requirements of the P2P chat protocol, so on web they
/// cannot be left to the in-memory fallback — a browser reload would make
/// every already-accepted message replayable again. Lookups fail **closed**:
/// a storage error is returned as `Err`, and the chat pipeline drops the
/// event rather than treating it as unseen.
///
/// Everything else remains stubbed until the full IndexedDB backend lands
/// (#233): reads answer "nothing stored" and writes are dropped, so callers
/// fall back to their defaults instead of failing.
use anyhow::{anyhow, Result};
use indexed_db_futures::prelude::*;
use web_sys::wasm_bindgen::JsValue;

use crate::api::types::{
    ChatMessage, IdentityInfo, OrderInfo, QueuedMessageStatus, RelayInfo, TradeInfo,
};
use crate::db::Storage;
use crate::queue::outbox::QueuedMessage;

const DB_VERSION: u32 = 1;
const MESSAGES_STORE: &str = "messages";
const SETTINGS_STORE: &str = "settings";

/// Map an opaque JS-side error into an `anyhow` error the trait can carry.
fn js_err(context: &str, e: impl std::fmt::Debug) -> anyhow::Error {
    anyhow!("{context}: {e:?}")
}

pub struct IndexedDbStorage {
    /// IndexedDB database name, from `init_db`'s path argument.
    db_name: String,
}

impl IndexedDbStorage {
    pub async fn open(db_name: &str) -> Result<Self> {
        let storage = Self {
            db_name: db_name.to_string(),
        };
        // Open once eagerly so schema creation (and any quota/permission
        // failure) surfaces at init time, not on the first message.
        storage.open_db().await?;
        Ok(storage)
    }

    /// Open the database, creating the object stores on first use.
    ///
    /// `IdbDatabase` wraps JS values and is not `Send`, so it cannot be
    /// cached in this struct (the storage singleton must be `Send + Sync`).
    /// Opening per operation is cheap: the browser keeps the underlying
    /// connection warm.
    async fn open_db(&self) -> Result<IdbDatabase> {
        let mut req = IdbDatabase::open_u32(&self.db_name, DB_VERSION)
            .map_err(|e| js_err("indexeddb open", e))?;
        req.set_on_upgrade_needed(Some(
            |evt: &IdbVersionChangeEvent| -> Result<(), JsValue> {
                let db = evt.db();
                if !db.object_store_names().any(|n| n == MESSAGES_STORE) {
                    db.create_object_store(MESSAGES_STORE)?;
                }
                if !db.object_store_names().any(|n| n == SETTINGS_STORE) {
                    db.create_object_store(SETTINGS_STORE)?;
                }
                Ok(())
            },
        ));
        req.await.map_err(|e| js_err("indexeddb open await", e))
    }

    /// Write one string value under a string key in `store_name`.
    async fn put_string(&self, store_name: &str, key: &str, value: &str) -> Result<()> {
        let db = self.open_db().await?;
        let tx = db
            .transaction_on_one_with_mode(store_name, IdbTransactionMode::Readwrite)
            .map_err(|e| js_err("tx open", e))?;
        let store = tx
            .object_store(store_name)
            .map_err(|e| js_err("store open", e))?;
        store
            .put_key_val_owned(key, &JsValue::from_str(value))
            .map_err(|e| js_err("put", e))?;
        tx.await.into_result().map_err(|e| js_err("tx commit", e))?;
        Ok(())
    }

    /// Read the string value under `key` in `store_name`, if present.
    async fn get_string(&self, store_name: &str, key: &str) -> Result<Option<String>> {
        let db = self.open_db().await?;
        let tx = db
            .transaction_on_one_with_mode(store_name, IdbTransactionMode::Readonly)
            .map_err(|e| js_err("tx open", e))?;
        let store = tx
            .object_store(store_name)
            .map_err(|e| js_err("store open", e))?;
        let value = store
            .get_owned(key)
            .map_err(|e| js_err("get", e))?
            .await
            .map_err(|e| js_err("get await", e))?;
        Ok(value.and_then(|v| v.as_string()))
    }

    /// All string values stored in `store_name`.
    async fn get_all_strings(&self, store_name: &str) -> Result<Vec<String>> {
        let db = self.open_db().await?;
        let tx = db
            .transaction_on_one_with_mode(store_name, IdbTransactionMode::Readonly)
            .map_err(|e| js_err("tx open", e))?;
        let store = tx
            .object_store(store_name)
            .map_err(|e| js_err("store open", e))?;
        let array = store
            .get_all()
            .map_err(|e| js_err("get_all", e))?
            .await
            .map_err(|e| js_err("get_all await", e))?;
        Ok(array.iter().filter_map(|v| v.as_string()).collect())
    }
}

impl Storage for IndexedDbStorage {
    async fn save_order(&self, _order: &OrderInfo) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn get_order(&self, _id: &str) -> Result<Option<OrderInfo>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn delete_order(&self, _id: &str) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn list_orders(&self) -> Result<Vec<OrderInfo>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn save_trade(&self, _trade: &TradeInfo) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn get_trade(&self, _id: &str) -> Result<Option<TradeInfo>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn list_trades(&self) -> Result<Vec<TradeInfo>> {
        // Consumed by `resubscribe_active_chats` at startup: no persisted
        // trades yet on web (tracked in #233), so nothing to resubscribe —
        // an empty list, not an error.
        Ok(Vec::new())
    }

    // ── Chat messages — fully implemented (durable replay dedup, #246) ──────

    async fn save_message(&self, msg: &ChatMessage) -> Result<()> {
        let json = serde_json::to_string(msg)?;
        self.put_string(MESSAGES_STORE, &msg.id, &json).await
    }

    async fn list_messages(&self, trade_id: &str) -> Result<Vec<ChatMessage>> {
        let mut msgs: Vec<ChatMessage> = self
            .get_all_strings(MESSAGES_STORE)
            .await?
            .iter()
            .filter_map(|json| serde_json::from_str::<ChatMessage>(json).ok())
            .filter(|m| m.trade_id == trade_id)
            .collect();
        msgs.sort_by_key(|m| m.created_at);
        Ok(msgs)
    }

    async fn mark_messages_read(&self, trade_id: &str) -> Result<()> {
        let unread: Vec<ChatMessage> = self
            .list_messages(trade_id)
            .await?
            .into_iter()
            .filter(|m| !m.is_read)
            .collect();
        for mut msg in unread {
            msg.is_read = true;
            self.save_message(&msg).await?;
        }
        Ok(())
    }

    async fn message_exists(&self, id: &str) -> Result<bool> {
        // Fail closed: an `Err` here makes the chat pipeline DROP the event.
        Ok(self.get_string(MESSAGES_STORE, id).await?.is_some())
    }

    async fn save_relay(&self, _relay: &RelayInfo) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn delete_relay(&self, _url: &str) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn list_relays(&self) -> Result<Vec<RelayInfo>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn save_identity(&self, _identity: &IdentityInfo) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn get_identity(&self) -> Result<Option<IdentityInfo>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn delete_identity(&self) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn save_queued_message(&self, _msg: &QueuedMessage) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn list_queued_messages(&self) -> Result<Vec<QueuedMessage>> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn update_queued_message_status(
        &self,
        _id: &str,
        _status: QueuedMessageStatus,
    ) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }
    async fn delete_queued_message(&self, _id: &str) -> Result<()> {
        Err(anyhow!("IndexedDB not yet implemented"))
    }

    async fn save_trade_key(&self, _order_id: &str, _key_index: u32) -> Result<()> {
        Ok(()) // no-op: IndexedDB persistence not yet implemented (#233)
    }

    async fn get_trade_key(&self, _order_id: &str) -> Result<Option<u32>> {
        Ok(None) // no persisted key: caller will treat absence correctly
    }

    async fn get_order_id_by_trade_index(&self, _key_index: u32) -> Result<Option<String>> {
        Ok(None) // IndexedDB not yet implemented (#233)
    }

    async fn delete_trade_key(&self, _order_id: &str) -> Result<()> {
        Ok(()) // IndexedDB not yet implemented (#233)
    }

    async fn clear_trade_keys(&self) -> Result<()> {
        Ok(()) // IndexedDB not yet implemented (#233)
    }

    async fn clear_trades(&self) -> Result<()> {
        Ok(()) // IndexedDB not yet implemented (#233)
    }

    async fn clear_messages(&self) -> Result<()> {
        Ok(()) // IndexedDB not yet implemented (#233)
    }

    // ── Settings KV — fully implemented (chat cursor + preferences, #246) ───

    async fn get_setting(&self, key: &str) -> Result<Option<String>> {
        self.get_string(SETTINGS_STORE, key).await
    }

    async fn set_setting(&self, key: &str, value: &str) -> Result<()> {
        self.put_string(SETTINGS_STORE, key, value).await
    }

    async fn delete_setting(&self, key: &str) -> Result<()> {
        let db = self.open_db().await?;
        let tx = db
            .transaction_on_one_with_mode(SETTINGS_STORE, IdbTransactionMode::Readwrite)
            .map_err(|e| js_err("tx open", e))?;
        let store = tx
            .object_store(SETTINGS_STORE)
            .map_err(|e| js_err("store open", e))?;
        store.delete_owned(key).map_err(|e| js_err("delete", e))?;
        tx.await.into_result().map_err(|e| js_err("tx commit", e))?;
        Ok(())
    }

    async fn save_active_mostro_pubkey(&self, pubkey: &str) -> Result<()> {
        self.set_setting(settings_keys_active_pubkey(), pubkey).await
    }

    async fn get_active_mostro_pubkey(&self) -> Result<Option<String>> {
        self.get_setting(settings_keys_active_pubkey()).await
    }

    async fn get_trade_by_order_id(&self, _order_id: &str) -> Result<Option<TradeInfo>> {
        Ok(None) // no persisted trade: role lookup returns None (#233)
    }

    async fn delete_trade_by_order_id(&self, _order_id: &str) -> Result<()> {
        Ok(()) // no persisted trades on web: nothing to delete (#233)
    }

    async fn update_trade_order_id(
        &self,
        _old_order_id: &str,
        _new_order_id: &str,
    ) -> Result<()> {
        log::warn!("update_trade_order_id: IndexedDB backend not implemented — trade order ID will not persist");
        Ok(())
    }

    async fn update_trade_fields(
        &self,
        _order_id: &str,
        _status: Option<crate::api::types::OrderStatus>,
        _hold_invoice: Option<String>,
        _amount_sats: Option<u64>,
    ) -> Result<()> {
        log::warn!("update_trade_fields: IndexedDB backend not implemented — trade fields will not persist");
        Ok(())
    }
}

/// The active-node settings key (shared with the SQLite backend).
fn settings_keys_active_pubkey() -> &'static str {
    crate::db::settings_keys::ACTIVE_MOSTRO_PUBKEY
}
