/// IndexedDB storage backend — WASM (Web) platform only.
/// Uses indexed_db_futures for async IndexedDB access.
///
/// All 11 entities use separate IndexedDB object stores with the same
/// logical schema as the SQLite backend. Records are stored as JSON.

use indexed_db_futures::prelude::*;
use wasm_bindgen::JsValue;

use crate::storage::{
    DisputeRecord, FileAttachmentRecord, IdentityRecord, MessageRecord, NwcWalletRecord,
    OrderRecord, QueuedMessage, RatingRecord, RelayRecord, Storage, StorageError, StorageResult,
    TradeRecord,
};

const DB_NAME: &str = "mostro_v2";
const DB_VERSION: u32 = 1;

/// Object store names — one per entity
const STORE_IDENTITY: &str = "identity";
const STORE_ORDERS: &str = "orders";
const STORE_TRADES: &str = "trades";
const STORE_MESSAGES: &str = "messages";
const STORE_RELAYS: &str = "relays";
const STORE_SETTINGS: &str = "settings";
const STORE_QUEUE: &str = "message_queue";
const STORE_WALLETS: &str = "nwc_wallets";
const STORE_ATTACHMENTS: &str = "file_attachments";
const STORE_RATINGS: &str = "ratings";
const STORE_DISPUTES: &str = "disputes";

pub struct IndexedDbStorage {
    db: IdbDatabase,
}

impl IndexedDbStorage {
    pub async fn open() -> StorageResult<Self> {
        let mut db_req = IdbDatabase::open_u32(DB_NAME, DB_VERSION)
            .map_err(|e| StorageError::Other(format!("IDB open error: {:?}", e)))?;

        db_req.set_on_upgrade_needed(Some(
            |evt: &IdbVersionChangeEvent| -> Result<(), JsValue> {
                let db = evt.db();
                let stores = [
                    STORE_IDENTITY,
                    STORE_ORDERS,
                    STORE_TRADES,
                    STORE_MESSAGES,
                    STORE_RELAYS,
                    STORE_SETTINGS,
                    STORE_QUEUE,
                    STORE_WALLETS,
                    STORE_ATTACHMENTS,
                    STORE_RATINGS,
                    STORE_DISPUTES,
                ];
                for &store in &stores {
                    if !db.object_store_names().any(|n| n == store) {
                        db.create_object_store(store)?;
                    }
                }
                Ok(())
            },
        ));

        let db = db_req
            .into_future()
            .await
            .map_err(|e| StorageError::Other(format!("IDB init failed: {:?}", e)))?;

        Ok(Self { db })
    }

    async fn put(&self, store: &str, key: &str, value: &impl serde::Serialize) -> StorageResult<()> {
        let json = serde_json::to_string(value)?;
        let tx = self
            .db
            .transaction_on_one_with_mode(store, IdbTransactionMode::Readwrite)
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?;
        let obj_store = tx.object_store(store)
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?;
        obj_store
            .put_key_val_owned(key, &JsValue::from_str(&json))
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?;
        tx.await.into_result()
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?;
        Ok(())
    }

    async fn get<T: serde::de::DeserializeOwned>(&self, store: &str, key: &str) -> StorageResult<Option<T>> {
        let tx = self
            .db
            .transaction_on_one_with_mode(store, IdbTransactionMode::Readonly)
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?;
        let obj_store = tx.object_store(store)
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?;
        let val: Option<JsValue> = obj_store
            .get_owned(key)
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?
            .await
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?;
        match val {
            None => Ok(None),
            Some(v) => {
                let s = v.as_string().unwrap_or_default();
                Ok(Some(serde_json::from_str(&s)?))
            }
        }
    }

    async fn delete(&self, store: &str, key: &str) -> StorageResult<()> {
        let tx = self
            .db
            .transaction_on_one_with_mode(store, IdbTransactionMode::Readwrite)
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?;
        let obj_store = tx.object_store(store)
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?;
        obj_store
            .delete_owned(key)
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?;
        tx.await.into_result()
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?;
        Ok(())
    }

    async fn get_all<T: serde::de::DeserializeOwned>(&self, store: &str) -> StorageResult<Vec<T>> {
        let tx = self
            .db
            .transaction_on_one_with_mode(store, IdbTransactionMode::Readonly)
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?;
        let obj_store = tx.object_store(store)
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?;
        let all: Vec<JsValue> = obj_store
            .get_all()
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?
            .await
            .map_err(|e| StorageError::Other(format!("{:?}", e)))?
            .iter()
            .collect();

        let mut results = Vec::with_capacity(all.len());
        for v in all {
            let s = v.as_string().unwrap_or_default();
            results.push(serde_json::from_str(&s)?);
        }
        Ok(results)
    }
}

// JSON-serializable wrappers for IDB storage (serde derives on the record types)
// These are newtype wrappers with serde so we can store/retrieve via JSON.
// The Storage trait impl below handles conversion.

use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
struct IdbIdentity {
    id: String,
    public_key: String,
    encrypted_private_key: Vec<u8>,
    mnemonic_hash: String,
    display_name: Option<String>,
    created_at: i64,
    last_used_at: i64,
    trade_key_index: u32,
    privacy_mode: bool,
    derivation_path: String,
}

#[derive(Serialize, Deserialize)]
struct IdbOrder {
    id: String,
    kind: String,
    status: String,
    amount_sats: Option<i64>,
    fiat_amount: Option<f64>,
    fiat_amount_min: Option<f64>,
    fiat_amount_max: Option<f64>,
    fiat_code: String,
    payment_method: String,
    premium: f64,
    creator_pubkey: String,
    created_at: i64,
    expires_at: Option<i64>,
    nostr_event_id: Option<String>,
    is_mine: bool,
    cached_at: i64,
}

#[derive(Serialize, Deserialize)]
struct IdbTrade {
    id: String,
    order_id: String,
    role: String,
    counterparty_pubkey: String,
    current_step: String,
    hold_invoice: Option<String>,
    buyer_invoice: Option<String>,
    trade_key_index: u32,
    cooperative_cancel_state: Option<String>,
    timeout_at: Option<i64>,
    started_at: i64,
    completed_at: Option<i64>,
    outcome: Option<String>,
}

#[derive(Serialize, Deserialize)]
struct IdbMessage {
    id: String,
    trade_id: String,
    sender_pubkey: String,
    content_encrypted: Vec<u8>,
    message_type: String,
    is_mine: bool,
    is_read: bool,
    attachment_id: Option<String>,
    created_at: i64,
}

#[derive(Serialize, Deserialize)]
struct IdbQueuedMessage {
    id: String,
    event_json: String,
    target_relays: String,
    status: String,
    attempts: i32,
    created_at: i64,
    last_attempt_at: Option<i64>,
}

#[derive(Serialize, Deserialize)]
struct IdbWallet {
    id: String,
    nwc_uri_encrypted: Vec<u8>,
    alias: Option<String>,
    relay_urls: String,
    wallet_pubkey: String,
    is_active: bool,
    created_at: i64,
}

#[derive(Serialize, Deserialize)]
struct IdbAttachment {
    id: String,
    message_id: String,
    trade_id: String,
    file_name: String,
    mime_type: String,
    file_size: i64,
    blossom_url: Option<String>,
    local_path: Option<String>,
    download_status: String,
    upload_complete: bool,
    created_at: i64,
}

#[derive(Serialize, Deserialize)]
struct IdbRating {
    id: String,
    trade_id: String,
    rater_pubkey: String,
    rated_pubkey: String,
    score: i32,
    created_at: i64,
}

#[derive(Serialize, Deserialize)]
struct IdbDispute {
    id: String,
    trade_id: String,
    order_id: String,
    raised_by_pubkey: String,
    status: String,
    resolution: Option<String>,
    admin_pubkey: Option<String>,
    evidence_urls: Option<String>,
    notes: Option<String>,
    created_at: i64,
    resolved_at: Option<i64>,
}

#[derive(Serialize, Deserialize)]
struct IdbRelay {
    id: String,
    url: String,
    is_active: bool,
    is_default: bool,
    source: String,
    is_blacklisted: bool,
    last_connected_at: Option<i64>,
    last_error: Option<String>,
}

impl Storage for IndexedDbStorage {
    async fn save_identity(&self, r: IdentityRecord) -> StorageResult<()> {
        let idb = IdbIdentity {
            id: r.id.clone(),
            public_key: r.public_key,
            encrypted_private_key: r.encrypted_private_key,
            mnemonic_hash: r.mnemonic_hash,
            display_name: r.display_name,
            created_at: r.created_at,
            last_used_at: r.last_used_at,
            trade_key_index: r.trade_key_index,
            privacy_mode: r.privacy_mode,
            derivation_path: r.derivation_path,
        };
        self.put(STORE_IDENTITY, "singleton", &idb).await
    }

    async fn get_identity(&self) -> StorageResult<Option<IdentityRecord>> {
        let idb: Option<IdbIdentity> = self.get(STORE_IDENTITY, "singleton").await?;
        Ok(idb.map(|r| IdentityRecord {
            id: r.id,
            public_key: r.public_key,
            encrypted_private_key: r.encrypted_private_key,
            mnemonic_hash: r.mnemonic_hash,
            display_name: r.display_name,
            created_at: r.created_at,
            last_used_at: r.last_used_at,
            trade_key_index: r.trade_key_index,
            privacy_mode: r.privacy_mode,
            derivation_path: r.derivation_path,
        }))
    }

    async fn update_trade_key_index(&self, index: u32) -> StorageResult<()> {
        if let Some(mut rec) = self.get_identity().await? {
            rec.trade_key_index = index;
            self.save_identity(rec).await
        } else {
            Ok(())
        }
    }

    async fn delete_identity(&self) -> StorageResult<()> {
        self.delete(STORE_IDENTITY, "singleton").await
    }

    async fn upsert_order(&self, r: OrderRecord) -> StorageResult<()> {
        let idb = IdbOrder {
            id: r.id.clone(),
            kind: r.kind,
            status: r.status,
            amount_sats: r.amount_sats,
            fiat_amount: r.fiat_amount,
            fiat_amount_min: r.fiat_amount_min,
            fiat_amount_max: r.fiat_amount_max,
            fiat_code: r.fiat_code,
            payment_method: r.payment_method,
            premium: r.premium,
            creator_pubkey: r.creator_pubkey,
            created_at: r.created_at,
            expires_at: r.expires_at,
            nostr_event_id: r.nostr_event_id,
            is_mine: r.is_mine,
            cached_at: r.cached_at,
        };
        self.put(STORE_ORDERS, &idb.id.clone(), &idb).await
    }

    async fn get_order(&self, id: &str) -> StorageResult<Option<OrderRecord>> {
        let idb: Option<IdbOrder> = self.get(STORE_ORDERS, id).await?;
        Ok(idb.map(|r| OrderRecord {
            id: r.id,
            kind: r.kind,
            status: r.status,
            amount_sats: r.amount_sats,
            fiat_amount: r.fiat_amount,
            fiat_amount_min: r.fiat_amount_min,
            fiat_amount_max: r.fiat_amount_max,
            fiat_code: r.fiat_code,
            payment_method: r.payment_method,
            premium: r.premium,
            creator_pubkey: r.creator_pubkey,
            created_at: r.created_at,
            expires_at: r.expires_at,
            nostr_event_id: r.nostr_event_id,
            is_mine: r.is_mine,
            cached_at: r.cached_at,
        }))
    }

    async fn list_orders(&self, _status: Option<&str>) -> StorageResult<Vec<OrderRecord>> {
        let all: Vec<IdbOrder> = self.get_all(STORE_ORDERS).await?;
        Ok(all
            .into_iter()
            .map(|r| OrderRecord {
                id: r.id,
                kind: r.kind,
                status: r.status,
                amount_sats: r.amount_sats,
                fiat_amount: r.fiat_amount,
                fiat_amount_min: r.fiat_amount_min,
                fiat_amount_max: r.fiat_amount_max,
                fiat_code: r.fiat_code,
                payment_method: r.payment_method,
                premium: r.premium,
                creator_pubkey: r.creator_pubkey,
                created_at: r.created_at,
                expires_at: r.expires_at,
                nostr_event_id: r.nostr_event_id,
                is_mine: r.is_mine,
                cached_at: r.cached_at,
            })
            .collect())
    }

    async fn delete_order(&self, id: &str) -> StorageResult<()> {
        self.delete(STORE_ORDERS, id).await
    }

    async fn save_trade(&self, r: TradeRecord) -> StorageResult<()> {
        let idb = IdbTrade {
            id: r.id.clone(),
            order_id: r.order_id,
            role: r.role,
            counterparty_pubkey: r.counterparty_pubkey,
            current_step: r.current_step,
            hold_invoice: r.hold_invoice,
            buyer_invoice: r.buyer_invoice,
            trade_key_index: r.trade_key_index,
            cooperative_cancel_state: r.cooperative_cancel_state,
            timeout_at: r.timeout_at,
            started_at: r.started_at,
            completed_at: r.completed_at,
            outcome: r.outcome,
        };
        self.put(STORE_TRADES, &idb.id.clone(), &idb).await
    }

    async fn get_trade(&self, id: &str) -> StorageResult<Option<TradeRecord>> {
        let idb: Option<IdbTrade> = self.get(STORE_TRADES, id).await?;
        Ok(idb.map(|r| TradeRecord {
            id: r.id,
            order_id: r.order_id,
            role: r.role,
            counterparty_pubkey: r.counterparty_pubkey,
            current_step: r.current_step,
            hold_invoice: r.hold_invoice,
            buyer_invoice: r.buyer_invoice,
            trade_key_index: r.trade_key_index,
            cooperative_cancel_state: r.cooperative_cancel_state,
            timeout_at: r.timeout_at,
            started_at: r.started_at,
            completed_at: r.completed_at,
            outcome: r.outcome,
        }))
    }

    async fn get_active_trade(&self) -> StorageResult<Option<TradeRecord>> {
        let all: Vec<IdbTrade> = self.get_all(STORE_TRADES).await?;
        let active = all.into_iter().find(|t| t.completed_at.is_none());
        Ok(active.map(|r| TradeRecord {
            id: r.id,
            order_id: r.order_id,
            role: r.role,
            counterparty_pubkey: r.counterparty_pubkey,
            current_step: r.current_step,
            hold_invoice: r.hold_invoice,
            buyer_invoice: r.buyer_invoice,
            trade_key_index: r.trade_key_index,
            cooperative_cancel_state: r.cooperative_cancel_state,
            timeout_at: r.timeout_at,
            started_at: r.started_at,
            completed_at: r.completed_at,
            outcome: r.outcome,
        }))
    }

    async fn update_trade(&self, r: TradeRecord) -> StorageResult<()> {
        self.save_trade(r).await
    }

    async fn save_message(&self, r: MessageRecord) -> StorageResult<()> {
        let idb = IdbMessage {
            id: r.id.clone(),
            trade_id: r.trade_id,
            sender_pubkey: r.sender_pubkey,
            content_encrypted: r.content_encrypted,
            message_type: r.message_type,
            is_mine: r.is_mine,
            is_read: r.is_read,
            attachment_id: r.attachment_id,
            created_at: r.created_at,
        };
        self.put(STORE_MESSAGES, &idb.id.clone(), &idb).await
    }

    async fn list_messages(&self, trade_id: &str) -> StorageResult<Vec<MessageRecord>> {
        let all: Vec<IdbMessage> = self.get_all(STORE_MESSAGES).await?;
        let mut filtered: Vec<MessageRecord> = all
            .into_iter()
            .filter(|m| m.trade_id == trade_id)
            .map(|r| MessageRecord {
                id: r.id,
                trade_id: r.trade_id,
                sender_pubkey: r.sender_pubkey,
                content_encrypted: r.content_encrypted,
                message_type: r.message_type,
                is_mine: r.is_mine,
                is_read: r.is_read,
                attachment_id: r.attachment_id,
                created_at: r.created_at,
            })
            .collect();
        filtered.sort_by_key(|m| m.created_at);
        Ok(filtered)
    }

    async fn mark_messages_read(&self, trade_id: &str) -> StorageResult<()> {
        let all: Vec<IdbMessage> = self.get_all(STORE_MESSAGES).await?;
        for mut m in all {
            if m.trade_id == trade_id && !m.is_mine && !m.is_read {
                m.is_read = true;
                self.put(STORE_MESSAGES, &m.id.clone(), &m).await?;
            }
        }
        Ok(())
    }

    async fn get_unread_count(&self, trade_id: &str) -> StorageResult<u32> {
        let all: Vec<IdbMessage> = self.get_all(STORE_MESSAGES).await?;
        Ok(all
            .iter()
            .filter(|m| m.trade_id == trade_id && !m.is_mine && !m.is_read)
            .count() as u32)
    }

    async fn set_setting(&self, key: &str, value: &str) -> StorageResult<()> {
        self.put(STORE_SETTINGS, key, &value.to_string()).await
    }

    async fn get_setting(&self, key: &str) -> StorageResult<Option<String>> {
        self.get::<String>(STORE_SETTINGS, key).await
    }

    async fn enqueue_message(&self, r: QueuedMessage) -> StorageResult<()> {
        let idb = IdbQueuedMessage {
            id: r.id.clone(),
            event_json: r.event_json,
            target_relays: r.target_relays,
            status: r.status,
            attempts: r.attempts,
            created_at: r.created_at,
            last_attempt_at: r.last_attempt_at,
        };
        self.put(STORE_QUEUE, &idb.id.clone(), &idb).await
    }

    async fn list_pending_messages(&self) -> StorageResult<Vec<QueuedMessage>> {
        let all: Vec<IdbQueuedMessage> = self.get_all(STORE_QUEUE).await?;
        let mut pending: Vec<QueuedMessage> = all
            .into_iter()
            .filter(|m| m.status == "Pending" && m.attempts < 10)
            .map(|r| QueuedMessage {
                id: r.id,
                event_json: r.event_json,
                target_relays: r.target_relays,
                status: r.status,
                attempts: r.attempts,
                created_at: r.created_at,
                last_attempt_at: r.last_attempt_at,
            })
            .collect();
        pending.sort_by_key(|m| m.created_at);
        Ok(pending)
    }

    async fn update_message_status(&self, id: &str, status: &str, attempts: i32) -> StorageResult<()> {
        if let Some(mut m) = self.get::<IdbQueuedMessage>(STORE_QUEUE, id).await? {
            m.status = status.to_string();
            m.attempts = attempts;
            let now = js_sys::Date::now() as i64 / 1000;
            m.last_attempt_at = Some(now);
            self.put(STORE_QUEUE, id, &m).await?;
        }
        Ok(())
    }

    async fn prune_sent_messages(&self, older_than: i64) -> StorageResult<()> {
        let all: Vec<IdbQueuedMessage> = self.get_all(STORE_QUEUE).await?;
        for m in all {
            if m.status == "Sent" && m.created_at < older_than {
                self.delete(STORE_QUEUE, &m.id.clone()).await?;
            }
        }
        Ok(())
    }

    async fn save_wallet(&self, r: NwcWalletRecord) -> StorageResult<()> {
        let idb = IdbWallet {
            id: r.id.clone(),
            nwc_uri_encrypted: r.nwc_uri_encrypted,
            alias: r.alias,
            relay_urls: r.relay_urls,
            wallet_pubkey: r.wallet_pubkey,
            is_active: r.is_active,
            created_at: r.created_at,
        };
        self.put(STORE_WALLETS, &idb.id.clone(), &idb).await
    }

    async fn get_active_wallet(&self) -> StorageResult<Option<NwcWalletRecord>> {
        let all: Vec<IdbWallet> = self.get_all(STORE_WALLETS).await?;
        Ok(all.into_iter().find(|w| w.is_active).map(|r| NwcWalletRecord {
            id: r.id,
            nwc_uri_encrypted: r.nwc_uri_encrypted,
            alias: r.alias,
            relay_urls: r.relay_urls,
            wallet_pubkey: r.wallet_pubkey,
            is_active: r.is_active,
            created_at: r.created_at,
        }))
    }

    async fn delete_wallet(&self, id: &str) -> StorageResult<()> {
        self.delete(STORE_WALLETS, id).await
    }

    async fn save_attachment(&self, r: FileAttachmentRecord) -> StorageResult<()> {
        let idb = IdbAttachment {
            id: r.id.clone(),
            message_id: r.message_id,
            trade_id: r.trade_id,
            file_name: r.file_name,
            mime_type: r.mime_type,
            file_size: r.file_size,
            blossom_url: r.blossom_url,
            local_path: r.local_path,
            download_status: r.download_status,
            upload_complete: r.upload_complete,
            created_at: r.created_at,
        };
        self.put(STORE_ATTACHMENTS, &idb.id.clone(), &idb).await
    }

    async fn get_attachment(&self, id: &str) -> StorageResult<Option<FileAttachmentRecord>> {
        let idb: Option<IdbAttachment> = self.get(STORE_ATTACHMENTS, id).await?;
        Ok(idb.map(|r| FileAttachmentRecord {
            id: r.id,
            message_id: r.message_id,
            trade_id: r.trade_id,
            file_name: r.file_name,
            mime_type: r.mime_type,
            file_size: r.file_size,
            blossom_url: r.blossom_url,
            local_path: r.local_path,
            download_status: r.download_status,
            upload_complete: r.upload_complete,
            created_at: r.created_at,
        }))
    }

    async fn update_attachment_status(&self, id: &str, status: &str, local_path: Option<&str>) -> StorageResult<()> {
        if let Some(mut a) = self.get::<IdbAttachment>(STORE_ATTACHMENTS, id).await? {
            a.download_status = status.to_string();
            if let Some(p) = local_path {
                a.local_path = Some(p.to_string());
            }
            self.put(STORE_ATTACHMENTS, id, &a).await?;
        }
        Ok(())
    }

    async fn save_rating(&self, r: RatingRecord) -> StorageResult<()> {
        let idb = IdbRating {
            id: r.id.clone(),
            trade_id: r.trade_id,
            rater_pubkey: r.rater_pubkey,
            rated_pubkey: r.rated_pubkey,
            score: r.score,
            created_at: r.created_at,
        };
        self.put(STORE_RATINGS, &idb.id.clone(), &idb).await
    }

    async fn list_ratings_for_pubkey(&self, pubkey: &str) -> StorageResult<Vec<RatingRecord>> {
        let all: Vec<IdbRating> = self.get_all(STORE_RATINGS).await?;
        Ok(all
            .into_iter()
            .filter(|r| r.rated_pubkey == pubkey)
            .map(|r| RatingRecord {
                id: r.id,
                trade_id: r.trade_id,
                rater_pubkey: r.rater_pubkey,
                rated_pubkey: r.rated_pubkey,
                score: r.score,
                created_at: r.created_at,
            })
            .collect())
    }

    async fn save_dispute(&self, r: DisputeRecord) -> StorageResult<()> {
        let idb = IdbDispute {
            id: r.id.clone(),
            trade_id: r.trade_id,
            order_id: r.order_id,
            raised_by_pubkey: r.raised_by_pubkey,
            status: r.status,
            resolution: r.resolution,
            admin_pubkey: r.admin_pubkey,
            evidence_urls: r.evidence_urls,
            notes: r.notes,
            created_at: r.created_at,
            resolved_at: r.resolved_at,
        };
        self.put(STORE_DISPUTES, &idb.id.clone(), &idb).await
    }

    async fn get_dispute(&self, id: &str) -> StorageResult<Option<DisputeRecord>> {
        let idb: Option<IdbDispute> = self.get(STORE_DISPUTES, id).await?;
        Ok(idb.map(|r| DisputeRecord {
            id: r.id,
            trade_id: r.trade_id,
            order_id: r.order_id,
            raised_by_pubkey: r.raised_by_pubkey,
            status: r.status,
            resolution: r.resolution,
            admin_pubkey: r.admin_pubkey,
            evidence_urls: r.evidence_urls,
            notes: r.notes,
            created_at: r.created_at,
            resolved_at: r.resolved_at,
        }))
    }

    async fn update_dispute(&self, r: DisputeRecord) -> StorageResult<()> {
        self.save_dispute(r).await
    }

    async fn upsert_relay(&self, r: RelayRecord) -> StorageResult<()> {
        let idb = IdbRelay {
            id: r.id.clone(),
            url: r.url,
            is_active: r.is_active,
            is_default: r.is_default,
            source: r.source,
            is_blacklisted: r.is_blacklisted,
            last_connected_at: r.last_connected_at,
            last_error: r.last_error,
        };
        self.put(STORE_RELAYS, &idb.id.clone(), &idb).await
    }

    async fn list_relays(&self) -> StorageResult<Vec<RelayRecord>> {
        let all: Vec<IdbRelay> = self.get_all(STORE_RELAYS).await?;
        Ok(all
            .into_iter()
            .map(|r| RelayRecord {
                id: r.id,
                url: r.url,
                is_active: r.is_active,
                is_default: r.is_default,
                source: r.source,
                is_blacklisted: r.is_blacklisted,
                last_connected_at: r.last_connected_at,
                last_error: r.last_error,
            })
            .collect())
    }

    async fn delete_relay(&self, url: &str) -> StorageResult<()> {
        let all: Vec<IdbRelay> = self.get_all(STORE_RELAYS).await?;
        if let Some(r) = all.iter().find(|r| r.url == url) {
            self.delete(STORE_RELAYS, &r.id.clone()).await?;
        }
        Ok(())
    }
}
