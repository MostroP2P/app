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
/// **Every store is implemented** (#233). Each record is one JSON document
/// keyed the way the SQLite table keys its row: trades by `TradeInfo::id`
/// (patched with [`crate::db::trade_json`] exactly as SQLite patches rows with
/// `json_set`), trade keys by order id, orders by id, relays by URL, the
/// single identity under a fixed key, queued messages by id. Once `init_db`
/// opens this store on the web, `derive_trade_key` requires identity
/// persistence to succeed before it hands out a key, so a stub here would
/// stop every order from being created.
use anyhow::{anyhow, Result};
use indexed_db_futures::prelude::*;
use web_sys::wasm_bindgen::JsValue;

use crate::api::types::{
    ChatMessage, IdentityInfo, OrderInfo, QueuedMessageStatus, RelayInfo, TradeInfo,
};
use crate::db::{trade_json, web_lock, Storage};
use crate::queue::outbox::QueuedMessage;

/// Bumped when a store is added; `open_db` creates whatever is missing.
const DB_VERSION: u32 = 3;
const MESSAGES_STORE: &str = "messages";
const SETTINGS_STORE: &str = "settings";
const TRADES_STORE: &str = "trades";
const TRADE_KEYS_STORE: &str = "trade_keys";
const ORDERS_STORE: &str = "orders";
const RELAYS_STORE: &str = "relays";
const IDENTITY_STORE: &str = "identity";
const OUTBOX_STORE: &str = "queued_messages";
/// The single identity document's key, mirroring SQLite's `id = 1` row.
const IDENTITY_KEY: &str = "1";
/// Origin-wide lock names (see [`web_lock`]): one per store whose documents
/// are read, changed and written back as a whole.
const TRADES_LOCK: &str = "mostro:db:trades";
const OUTBOX_LOCK: &str = "mostro:db:queued_messages";
const ALL_STORES: [&str; 8] = [
    MESSAGES_STORE,
    SETTINGS_STORE,
    TRADES_STORE,
    TRADE_KEYS_STORE,
    ORDERS_STORE,
    RELAYS_STORE,
    IDENTITY_STORE,
    OUTBOX_STORE,
];

/// Map an opaque JS-side error into an `anyhow` error the trait can carry.
fn js_err(context: &str, e: impl std::fmt::Debug) -> anyhow::Error {
    anyhow!("{context}: {e:?}")
}

pub struct IndexedDbStorage {
    /// IndexedDB database name, from `init_db`'s path argument.
    db_name: String,
    /// Serialises every read-modify-write on a stored document within this
    /// context; [`web_lock`] extends the same exclusion across the origin's
    /// other tabs and workers, which share the database.
    ///
    /// The daemon's status sync, the peer reveal, the reputation follow-up
    /// and the rating marker can all patch the same trade within moments of
    /// each other. Each patch reads the document, changes one field and
    /// writes the whole document back; two of them interleaving would each
    /// write a full copy and the later one would silently drop the other's
    /// field. SQLite avoids that with `json_set` in one statement. Holding
    /// one IndexedDB transaction across the read and the write is not an
    /// option here: a transaction is only active while its own request
    /// callbacks run, and the Rust future that continues after `await` is
    /// polled from a later task, so the write would hit an inactive
    /// transaction.
    patch_serial: tokio::sync::Mutex<()>,
}

impl IndexedDbStorage {
    pub async fn open(db_name: &str) -> Result<Self> {
        let storage = Self {
            db_name: db_name.to_string(),
            patch_serial: tokio::sync::Mutex::new(()),
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
        req.set_on_upgrade_needed(Some(|evt: &IdbVersionChangeEvent| -> Result<(), JsValue> {
            let db = evt.db();
            for store in ALL_STORES {
                if !db.object_store_names().any(|n| n == store) {
                    db.create_object_store(store)?;
                }
            }
            Ok(())
        }));
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
    /// Removes `key` from `store_name`; an absent key is not an error.
    async fn delete_key(&self, store_name: &str, key: &str) -> Result<()> {
        let db = self.open_db().await?;
        let tx = db
            .transaction_on_one_with_mode(store_name, IdbTransactionMode::Readwrite)
            .map_err(|e| js_err("tx open", e))?;
        let store = tx
            .object_store(store_name)
            .map_err(|e| js_err("store open", e))?;
        store.delete_owned(key).map_err(|e| js_err("delete", e))?;
        tx.await.into_result().map_err(|e| js_err("tx commit", e))?;
        Ok(())
    }

    /// Removes every entry of `store_name`.
    async fn clear_store(&self, store_name: &str) -> Result<()> {
        let db = self.open_db().await?;
        let tx = db
            .transaction_on_one_with_mode(store_name, IdbTransactionMode::Readwrite)
            .map_err(|e| js_err("tx open", e))?;
        let store = tx
            .object_store(store_name)
            .map_err(|e| js_err("store open", e))?;
        store.clear().map_err(|e| js_err("clear", e))?;
        tx.await.into_result().map_err(|e| js_err("tx commit", e))?;
        Ok(())
    }

    /// Every stored trade as a JSON document, newest `started_at` first.
    /// A document that no longer parses is skipped with a warning, as the
    /// SQLite backend does, rather than hiding every other trade.
    async fn trade_documents(&self) -> Result<Vec<serde_json::Value>> {
        let mut docs: Vec<serde_json::Value> = self
            .get_all_strings(TRADES_STORE)
            .await?
            .iter()
            .filter_map(|json| match serde_json::from_str(json) {
                Ok(doc) => Some(doc),
                Err(e) => {
                    log::warn!("[db] skipping unreadable trade document: {e}");
                    None
                }
            })
            .collect();
        docs.sort_by_key(|doc| std::cmp::Reverse(trade_json::started_at_of(doc)));
        Ok(docs)
    }

    /// The stored trade document whose `order.id` is `order_id`.
    async fn trade_document_by_order_id(
        &self,
        order_id: &str,
    ) -> Result<Option<serde_json::Value>> {
        Ok(self
            .trade_documents()
            .await?
            .into_iter()
            .find(|doc| trade_json::order_id_of(doc) == Some(order_id)))
    }

    /// Enters the exclusive section for whole-document writes to a store:
    /// this context's mutex plus the origin-wide lock `name` when the
    /// browser provides one. Hold the returned guards for the whole
    /// read-modify-write.
    async fn exclusive(
        &self,
        name: &str,
    ) -> (
        tokio::sync::MutexGuard<'_, ()>,
        Option<web_lock::OriginLock>,
    ) {
        let local = self.patch_serial.lock().await;
        let origin = web_lock::acquire(name).await;
        (local, origin)
    }

    /// Writes one queued message without entering the exclusive section;
    /// callers already hold it.
    async fn put_queued_message(&self, msg: &QueuedMessage) -> Result<()> {
        let json = serde_json::to_string(msg)?;
        self.put_string(OUTBOX_STORE, &msg.id, &json).await
    }

    /// Loads the trade for `order_id`, applies `patch` and writes it back.
    /// No-op when no trade matches, like an `UPDATE` touching zero rows.
    /// Serialised through [`Self::exclusive`], see `patch_serial`.
    async fn patch_trade_by_order_id(
        &self,
        order_id: &str,
        patch: impl FnOnce(&mut serde_json::Value) -> Result<()>,
    ) -> Result<()> {
        let _section = self.exclusive(TRADES_LOCK).await;
        let Some(mut doc) = self.trade_document_by_order_id(order_id).await? else {
            log::warn!(
                "[db] trade update matched no row for order={}",
                crate::api::logging::short_id(order_id)
            );
            return Ok(());
        };
        patch(&mut doc)?;
        let key = doc
            .get("id")
            .and_then(serde_json::Value::as_str)
            .ok_or_else(|| anyhow!("trade document without an id"))?
            .to_owned();
        self.put_string(TRADES_STORE, &key, &doc.to_string()).await
    }
}

impl Storage for IndexedDbStorage {
    async fn save_order(&self, order: &OrderInfo) -> Result<()> {
        let json = serde_json::to_string(order)?;
        self.put_string(ORDERS_STORE, &order.id, &json).await
    }
    async fn get_order(&self, id: &str) -> Result<Option<OrderInfo>> {
        Ok(self
            .get_string(ORDERS_STORE, id)
            .await?
            .map(|json| serde_json::from_str(&json))
            .transpose()?)
    }
    async fn delete_order(&self, id: &str) -> Result<()> {
        self.delete_key(ORDERS_STORE, id).await
    }
    async fn list_orders(&self) -> Result<Vec<OrderInfo>> {
        let mut orders: Vec<OrderInfo> = self
            .get_all_strings(ORDERS_STORE)
            .await?
            .iter()
            .filter_map(|json| serde_json::from_str(json).ok())
            .collect();
        orders.sort_by_key(|o| std::cmp::Reverse(o.created_at));
        Ok(orders)
    }
    async fn save_trade(&self, trade: &TradeInfo) -> Result<()> {
        // A whole-document save joins the patches' exclusive section: a
        // save built from a stale read would otherwise drop a patch landed
        // in between, in this or another tab.
        let _section = self.exclusive(TRADES_LOCK).await;
        let json = serde_json::to_string(trade)?;
        self.put_string(TRADES_STORE, &trade.id, &json).await
    }
    async fn get_trade(&self, id: &str) -> Result<Option<TradeInfo>> {
        Ok(self
            .get_string(TRADES_STORE, id)
            .await?
            .map(|json| serde_json::from_str(&json))
            .transpose()?)
    }
    async fn list_trades(&self) -> Result<Vec<TradeInfo>> {
        Ok(self
            .trade_documents()
            .await?
            .into_iter()
            .filter_map(|doc| match serde_json::from_value::<TradeInfo>(doc) {
                Ok(trade) => Some(trade),
                Err(e) => {
                    log::warn!("[db] skipping trade: deserialization failed: {e}");
                    None
                }
            })
            .collect())
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

    async fn save_relay(&self, relay: &RelayInfo) -> Result<()> {
        let json = serde_json::to_string(relay)?;
        self.put_string(RELAYS_STORE, &relay.url, &json).await
    }
    async fn delete_relay(&self, url: &str) -> Result<()> {
        self.delete_key(RELAYS_STORE, url).await
    }
    async fn list_relays(&self) -> Result<Vec<RelayInfo>> {
        Ok(self
            .get_all_strings(RELAYS_STORE)
            .await?
            .iter()
            .filter_map(|json| serde_json::from_str(json).ok())
            .collect())
    }
    async fn save_identity(&self, identity: &IdentityInfo) -> Result<()> {
        let json = serde_json::to_string(identity)?;
        self.put_string(IDENTITY_STORE, IDENTITY_KEY, &json).await
    }
    async fn get_identity(&self) -> Result<Option<IdentityInfo>> {
        Ok(self
            .get_string(IDENTITY_STORE, IDENTITY_KEY)
            .await?
            .map(|json| serde_json::from_str(&json))
            .transpose()?)
    }
    async fn delete_identity(&self) -> Result<()> {
        self.clear_store(IDENTITY_STORE).await
    }
    async fn save_queued_message(&self, msg: &QueuedMessage) -> Result<()> {
        let _section = self.exclusive(OUTBOX_LOCK).await;
        self.put_queued_message(msg).await
    }
    async fn list_queued_messages(&self) -> Result<Vec<QueuedMessage>> {
        // Pending only, oldest first, as the SQLite query selects.
        let mut pending: Vec<QueuedMessage> = self
            .get_all_strings(OUTBOX_STORE)
            .await?
            .iter()
            .filter_map(|json| serde_json::from_str::<QueuedMessage>(json).ok())
            .filter(|m| m.status == QueuedMessageStatus::Pending)
            .collect();
        pending.sort_by_key(|m| m.created_at);
        Ok(pending)
    }
    async fn update_queued_message_status(
        &self,
        id: &str,
        status: QueuedMessageStatus,
    ) -> Result<()> {
        // Read-modify-write, serialised like the trade patches: the flush
        // marks a message in flight while a retry may touch the same row.
        let _section = self.exclusive(OUTBOX_LOCK).await;
        let Some(json) = self.get_string(OUTBOX_STORE, id).await? else {
            return Ok(());
        };
        let mut msg: QueuedMessage = serde_json::from_str(&json)?;
        msg.status = status;
        self.put_queued_message(&msg).await
    }

    async fn delete_queued_message(&self, id: &str) -> Result<()> {
        let _section = self.exclusive(OUTBOX_LOCK).await;
        self.delete_key(OUTBOX_STORE, id).await
    }

    async fn save_trade_key(&self, order_id: &str, key_index: u32) -> Result<()> {
        self.put_string(TRADE_KEYS_STORE, order_id, &key_index.to_string())
            .await
    }

    async fn get_trade_key(&self, order_id: &str) -> Result<Option<u32>> {
        self.get_string(TRADE_KEYS_STORE, order_id)
            .await?
            .map(|value| {
                value
                    .parse::<u32>()
                    .map_err(|e| anyhow!("trade key for {order_id} is not a u32: {e}"))
            })
            .transpose()
    }

    async fn get_order_id_by_trade_index(&self, key_index: u32) -> Result<Option<String>> {
        // Reverse lookup over a small store: one entry per trade this
        // identity has taken part in.
        let db = self.open_db().await?;
        let tx = db
            .transaction_on_one_with_mode(TRADE_KEYS_STORE, IdbTransactionMode::Readonly)
            .map_err(|e| js_err("tx open", e))?;
        let store = tx
            .object_store(TRADE_KEYS_STORE)
            .map_err(|e| js_err("store open", e))?;
        let keys = store
            .get_all_keys()
            .map_err(|e| js_err("get_all_keys", e))?
            .await
            .map_err(|e| js_err("get_all_keys await", e))?;
        let wanted = key_index.to_string();
        for key in keys.iter().filter_map(|k| k.as_string()) {
            if self.get_string(TRADE_KEYS_STORE, &key).await?.as_deref() == Some(wanted.as_str()) {
                return Ok(Some(key));
            }
        }
        Ok(None)
    }

    async fn delete_trade_key(&self, order_id: &str) -> Result<()> {
        self.delete_key(TRADE_KEYS_STORE, order_id).await
    }

    async fn clear_trade_keys(&self) -> Result<()> {
        self.clear_store(TRADE_KEYS_STORE).await
    }

    // ── Settings KV — fully implemented (chat cursor + preferences, #246) ───

    async fn get_setting(&self, key: &str) -> Result<Option<String>> {
        self.get_string(SETTINGS_STORE, key).await
    }

    async fn set_setting(&self, key: &str, value: &str) -> Result<()> {
        self.put_string(SETTINGS_STORE, key, value).await
    }

    async fn delete_setting(&self, key: &str) -> Result<()> {
        self.delete_key(SETTINGS_STORE, key).await
    }

    async fn save_active_mostro_pubkey(&self, pubkey: &str) -> Result<()> {
        self.set_setting(settings_keys_active_pubkey(), pubkey)
            .await
    }

    async fn get_active_mostro_pubkey(&self) -> Result<Option<String>> {
        self.get_setting(settings_keys_active_pubkey()).await
    }

    async fn get_trade_by_order_id(&self, order_id: &str) -> Result<Option<TradeInfo>> {
        self.trade_document_by_order_id(order_id)
            .await?
            .map(|doc| serde_json::from_value(doc).map_err(Into::into))
            .transpose()
    }

    async fn delete_trade_by_order_id(&self, order_id: &str) -> Result<()> {
        // `trades.id` is a fresh UUID for takers, so documents are found
        // through the order id stored inside them — every one of them, as
        // SQLite's `DELETE … WHERE` does: `take_order` relies on this to leave
        // one row per order after a retake. Messages stay untouched.
        // Serialised with the patches so a delete never races one.
        let _section = self.exclusive(TRADES_LOCK).await;
        for doc in self.trade_documents().await? {
            if trade_json::order_id_of(&doc) != Some(order_id) {
                continue;
            }
            if let Some(id) = doc.get("id").and_then(serde_json::Value::as_str) {
                self.delete_key(TRADES_STORE, id).await?;
            }
        }
        Ok(())
    }

    async fn update_trade_order_id(&self, old_order_id: &str, new_order_id: &str) -> Result<()> {
        self.patch_trade_by_order_id(old_order_id, |doc| {
            trade_json::rename_order_id(doc, new_order_id)
        })
        .await
    }

    async fn update_trade_fields(
        &self,
        order_id: &str,
        status: Option<crate::api::types::OrderStatus>,
        hold_invoice: Option<String>,
        amount_sats: Option<u64>,
    ) -> Result<()> {
        self.patch_trade_by_order_id(order_id, |doc| {
            trade_json::apply_fields(doc, status.as_ref(), hold_invoice.as_deref(), amount_sats)
        })
        .await
    }

    async fn update_trade_peer_reputation(
        &self,
        order_id: &str,
        rating: f64,
        reviews: u32,
        days: u32,
    ) -> Result<()> {
        self.patch_trade_by_order_id(order_id, |doc| {
            trade_json::set_peer_reputation(doc, rating, reviews, days)
        })
        .await
    }

    async fn update_trade_bond(
        &self,
        order_id: &str,
        bond: &crate::api::types::BondInfo,
    ) -> Result<()> {
        self.patch_trade_by_order_id(order_id, |doc| trade_json::set_bond(doc, bond))
            .await
    }

    async fn mark_trade_rated(&self, order_id: &str, rated_at: i64) -> Result<()> {
        self.patch_trade_by_order_id(order_id, |doc| trade_json::mark_rated(doc, rated_at))
            .await
    }

    async fn update_trade_counterparty(
        &self,
        order_id: &str,
        counterparty_pubkey: &str,
    ) -> Result<()> {
        self.patch_trade_by_order_id(order_id, |doc| {
            trade_json::set_counterparty(doc, counterparty_pubkey)
        })
        .await
    }
}

/// The active-node settings key (shared with the SQLite backend).
fn settings_keys_active_pubkey() -> &'static str {
    crate::db::settings_keys::ACTIVE_MOSTRO_PUBKEY
}
