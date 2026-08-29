/// Messages API — encrypted P2P chat during trades.
///
/// P2P chat rides the chat envelope of the protocol spec
/// (<https://mostro.network/protocol/chat.html>, issue #246): a kind 14 outer
/// event signed with `K_sign` and `p`-tagged to `pub(K_conv)` — both derived
/// from the trade-key ECDH secret via `crate::crypto::chat_keys` — carrying a
/// NIP-44 encrypted kind 1 inner event signed by the sender's trade key. The
/// old NIP-59 gift wrap — whose random ephemeral authors made third-party
/// flooding unattributable and unfilterable — is neither written nor read:
/// this client speaks protocol v2 only. The admin/dispute chat
/// (api/disputes.rs) rides the same envelope.
///
/// Messages persist to the `messages` table (native; web is memory-only until
/// IndexedDB lands, #233); the in-memory store is a write-through cache. The
/// stored inner-event ids double as the durable replay dedup the spec
/// requires, and the per-order `chat_cursor:` setting bounds the subscription
/// backlog.
///
/// **Isolation invariant**: everything here runs on its own spawned task and
/// bounded channels; a chat failure or flood must never block the order state
/// machine, the daemon transport, or opening a dispute.
///
/// Streams: `on_new_message(trade_id)`, `on_unread_count_changed()`,
/// `on_attachment_progress(message_id)`.
use anyhow::{anyhow, bail, Result};
use std::collections::HashMap;
use std::sync::{Arc, OnceLock};
use tokio::sync::{broadcast, RwLock};

use crate::api::types::{AttachmentInfo, ChatMessage, DownloadStatus, FileType, MessageType};
use crate::db::Storage;
use crate::nostr::blossom;

// ── Types ────────────────────────────────────────────────────────────────────

/// Returned by `download_attachment`.
#[derive(Debug, Clone)]
pub struct FileDownloadResult {
    /// Absolute path to the decrypted file on the local device.
    pub local_path: String,
    pub file_name: String,
    pub mime_type: String,
    pub file_size: u64,
}

// ── Message store ─────────────────────────────────────────────────────────────

struct MessageStore {
    /// Messages keyed by trade_id. Write-through cache over the `messages`
    /// table: adds persist immediately, reads hydrate from the DB once per
    /// trade. Where no DB backend exists (web, unit tests) it degrades to
    /// memory-only.
    messages: Arc<RwLock<HashMap<String, Vec<ChatMessage>>>>,
    /// Trades whose persisted history has been loaded into `messages`.
    hydrated: Arc<RwLock<std::collections::HashSet<String>>>,
    /// Broadcast channel for new messages (payload = trade_id of new message).
    new_message_tx: broadcast::Sender<ChatMessage>,
    /// Broadcast channel for global unread count changes.
    unread_tx: broadcast::Sender<u32>,
    /// Broadcast channel for attachment progress (payload = (message_id, progress 0.0–1.0)).
    attachment_tx: broadcast::Sender<(String, f64)>,
    /// Ids present in memory whose DB write failed — known for replay dedup,
    /// but NOT durable: the `since` cursor must never advance past them, or
    /// a restart loses the message with no relay copy left to refetch
    /// (PR #254 review).
    non_durable: Arc<RwLock<std::collections::HashSet<String>>>,
}

impl MessageStore {
    fn new() -> Self {
        let (new_message_tx, _) = broadcast::channel(64);
        let (unread_tx, _) = broadcast::channel(16);
        let (attachment_tx, _) = broadcast::channel(64);
        Self {
            messages: Arc::new(RwLock::new(HashMap::new())),
            non_durable: Arc::new(RwLock::new(std::collections::HashSet::new())),
            hydrated: Arc::new(RwLock::new(std::collections::HashSet::new())),
            new_message_tx,
            unread_tx,
            attachment_tx,
        }
    }

    /// Load the persisted history for `trade_id` into memory, once.
    ///
    /// Memory wins on id collision: an in-flight message may already sit in
    /// the cache with fresher state (e.g. attachment download progress).
    async fn ensure_hydrated(&self, trade_id: &str) {
        if self.hydrated.read().await.contains(trade_id) {
            return;
        }
        let persisted = match crate::db::app_db::db() {
            Some(db) => match db.list_messages(trade_id).await {
                Ok(msgs) => msgs,
                Err(e) => {
                    log::warn!("[messages] history load failed trade={trade_id}: {e}");
                    Vec::new()
                }
            },
            None => Vec::new(),
        };
        let mut store = self.messages.write().await;
        let entry = store.entry(trade_id.to_string()).or_default();
        for msg in persisted {
            if !entry.iter().any(|m| m.id == msg.id) {
                entry.push(msg);
            }
        }
        drop(store);
        self.hydrated.write().await.insert(trade_id.to_string());
    }

    /// Store a message; returns `true` when it is **durably** stored (DB
    /// write succeeded, or no DB backend exists so memory is the best this
    /// platform offers). The chat `since` cursor must only advance past
    /// events whose messages returned `true` — otherwise a failed write plus
    /// an advanced cursor loses the message permanently.
    async fn add_message(&self, msg: ChatMessage) -> bool {
        // Hydrate first so the persisted history is not masked by a fresher
        // in-memory entry created before the first read.
        self.ensure_hydrated(&msg.trade_id).await;
        {
            let mut store = self.messages.write().await;
            store
                .entry(msg.trade_id.clone())
                .or_default()
                .push(msg.clone());
        }
        // Write-through: chat history and the durable replay dedup both live
        // in the `messages` table. Failure is logged, never propagated — a
        // full disk must not take the chat (let alone the trade) down.
        let stored = match crate::db::app_db::db() {
            Some(db) => match db.save_message(&msg).await {
                Ok(()) => true,
                Err(e) => {
                    log::warn!("[messages] persist failed id={}: {e}", msg.id);
                    false
                }
            },
            None => true,
        };
        // Keep memory-only ids distinct from durably committed ones — the
        // receive path consults this before advancing the cursor.
        if stored {
            self.non_durable.write().await.remove(&msg.id);
        } else {
            self.non_durable.write().await.insert(msg.id.clone());
        }
        let _ = self.new_message_tx.send(msg.clone());
        let unread = self.unread_count_inner().await;
        let _ = self.unread_tx.send(unread);
        stored
    }

    /// `true` if this message id was already accepted, in memory or on disk.
    ///
    /// This is the spec's durable inner-id replay dedup: a re-wrapped inner
    /// event keeps the id it had the first time, so a hit here rejects it.
    /// A storage lookup failure is an `Err` — the caller MUST fail closed
    /// (drop the event) rather than treat it as "not seen".
    async fn is_known(&self, trade_id: &str, id: &str) -> Result<bool> {
        {
            let store = self.messages.read().await;
            if let Some(msgs) = store.get(trade_id) {
                if msgs.iter().any(|m| m.id == id) {
                    return Ok(true);
                }
            }
        }
        match crate::db::app_db::db() {
            Some(db) => db
                .message_exists(id)
                .await
                .map_err(|e| anyhow!("dedup lookup failed: {e}")),
            None => Ok(false),
        }
    }

    /// `true` when the already-known `id` is durably stored, retrying the DB
    /// write for a memory-only copy first. Callers gate cursor advancement on
    /// this: an id whose write failed must keep the cursor put so the relay
    /// copy is refetched after a restart (PR #254 review).
    async fn ensure_durable(&self, trade_id: &str, id: &str) -> bool {
        if !self.non_durable.read().await.contains(id) {
            return true;
        }
        let copy = {
            let store = self.messages.read().await;
            store
                .get(trade_id)
                .and_then(|msgs| msgs.iter().find(|m| m.id == id).cloned())
        };
        let (Some(db), Some(msg)) = (crate::db::app_db::db(), copy) else {
            return false;
        };
        match db.save_message(&msg).await {
            Ok(()) => {
                self.non_durable.write().await.remove(id);
                true
            }
            Err(e) => {
                log::warn!("[messages] persist retry failed id={id}: {e}");
                false
            }
        }
    }

    /// `true` when storing one more incoming message of `incoming_bytes`
    /// would exceed the per-trade retention caps. Bounds durable growth from
    /// a counterparty writing forever at a legitimate rate — the token
    /// bucket limits CPU, this limits memory and disk (isolation invariant).
    async fn quota_exceeded(&self, trade_id: &str, incoming_bytes: usize) -> bool {
        self.ensure_hydrated(trade_id).await;
        let store = self.messages.read().await;
        match store.get(trade_id) {
            None => false,
            Some(msgs) => {
                if msgs.len() >= MAX_STORED_MESSAGES_PER_TRADE {
                    return true;
                }
                let bytes: usize = msgs.iter().map(|m| m.content.len()).sum();
                bytes.saturating_add(incoming_bytes) > MAX_STORED_BYTES_PER_TRADE
            }
        }
    }

    async fn get_messages(&self, trade_id: &str) -> Vec<ChatMessage> {
        self.ensure_hydrated(trade_id).await;
        let store = self.messages.read().await;
        store.get(trade_id).cloned().unwrap_or_default()
    }

    async fn mark_as_read(&self, trade_id: &str) {
        self.ensure_hydrated(trade_id).await;
        let mut store = self.messages.write().await;
        if let Some(msgs) = store.get_mut(trade_id) {
            for m in msgs.iter_mut() {
                m.is_read = true;
            }
        }
        drop(store);
        if let Some(db) = crate::db::app_db::db() {
            if let Err(e) = db.mark_messages_read(trade_id).await {
                log::warn!("[messages] mark_messages_read failed trade={trade_id}: {e}");
            }
        }
        let unread = self.unread_count_inner().await;
        let _ = self.unread_tx.send(unread);
    }

    async fn unread_count_inner(&self) -> u32 {
        let store = self.messages.read().await;
        store
            .values()
            .flat_map(|msgs| msgs.iter())
            .filter(|m| !m.is_read && !m.is_mine)
            .count() as u32
    }
}

// ── Global singleton ──────────────────────────────────────────────────────────

static MESSAGE_STORE: OnceLock<MessageStore> = OnceLock::new();

fn message_store() -> &'static MessageStore {
    MESSAGE_STORE.get_or_init(MessageStore::new)
}

// ── Public API ────────────────────────────────────────────────────────────────

/// The chat-key material for one conversation, derived from the session.
pub(crate) struct ChatContext {
    trade_keys: nostr_sdk::Keys,
    /// `K_conv` — NIP-44 encryption; `pub(K_conv)` is the `p` tag.
    conv: nostr_sdk::Keys,
    /// `K_sign` — outer-event author; what relays and clients filter on.
    sign: nostr_sdk::Keys,
}

/// Derive the conversation keys for a session's trade-key index and peer.
///
/// Cheap enough to derive on demand (one ECDH + two HKDF expands), which
/// keeps the secrets out of long-lived session state.
async fn chat_context(trade_key_index: u32, peer_hex: &str) -> Result<ChatContext> {
    let trade_keys = crate::api::identity::get_active_trade_keys(trade_key_index)
        .await
        .map_err(|e| anyhow!("key retrieval failed: {e}"))?;
    let peer_pubkey = nostr_sdk::PublicKey::from_hex(peer_hex)
        .map_err(|e| anyhow!("invalid peer pubkey: {e}"))?;
    let (conv, sign) = crate::crypto::chat_keys::derive_chat_keys(&trade_keys, &peer_pubkey)?;
    Ok(ChatContext {
        trade_keys,
        conv,
        sign,
    })
}

/// Wrap `payload` in the chat envelope and publish it.
///
/// Returns the signed inner event on success — its id and timestamp are the
/// message's durable identity (shared with the recipient's replay dedup).
/// [`chat_context`] for the dispute channel: the shared secret is with the
/// solver's pubkey from `admin-took-dispute` instead of the counterparty's
/// trade key. Derivation is identical — that is what the spec prescribes.
pub(crate) async fn admin_chat_context(
    trade_key_index: u32,
    admin_pubkey: &nostr_sdk::PublicKey,
) -> Result<ChatContext> {
    chat_context(trade_key_index, &admin_pubkey.to_hex()).await
}

/// Publish over an already-built context. Exposed for the dispute channel,
/// which owns its own send path but must not reimplement the envelope.
pub(crate) async fn publish_chat_payload_for(
    ctx: &ChatContext,
    payload: &str,
) -> Result<nostr_sdk::Event> {
    publish_chat_payload(ctx, payload).await
}

/// Record a message we just sent to the solver, mirroring what `send_message`
/// stores for the peer chat: identified by the inner event id so the relay
/// echo dedups against it, and never unread (we wrote it).
pub(crate) async fn store_outgoing_admin_message(
    trade_id: &str,
    ctx: &ChatContext,
    content: &str,
    inner: &nostr_sdk::Event,
) {
    let msg = ChatMessage {
        id: inner.id.to_hex(),
        trade_id: trade_id.to_string(),
        sender_pubkey: ctx.trade_keys.public_key().to_hex(),
        content: content.to_string(),
        message_type: MessageType::Admin,
        is_mine: true,
        is_read: true,
        has_attachment: false,
        attachment: None,
        created_at: inner.created_at.as_secs() as i64,
    };
    let _ = message_store().add_message(msg).await;
}

async fn publish_chat_payload(ctx: &ChatContext, payload: &str) -> Result<nostr_sdk::Event> {
    let (outer, inner) =
        crate::nostr::transport::mostro_wrap(&ctx.trade_keys, &ctx.conv, &ctx.sign, payload)
            .await?;
    let pool = crate::api::nostr::get_pool().map_err(|_| anyhow!("relay pool not ready"))?;
    let output = pool
        .client()
        .send_event(&outer)
        .await
        .map_err(|e| anyhow!("publish failed: {e}"))?;
    // Envelope metadata only — chat plaintext never enters a log record.
    let eid = outer.id.to_hex();
    for relay in &output.success {
        crate::api::logging::blog_info(
            "publish",
            format!(
                "ev={} kind=14 relay={} OK",
                crate::api::logging::short_id(&eid),
                crate::api::logging::display_relay(&relay.to_string()),
            ),
        );
    }
    for (relay, err) in &output.failed {
        crate::api::logging::blog_warn(
            "publish",
            format!(
                "ev={} kind=14 relay={} FAIL: {}",
                crate::api::logging::short_id(&eid),
                crate::api::logging::display_relay(&relay.to_string()),
                crate::api::logging::sanitize_relay_text(err),
            ),
        );
    }
    Ok(inner)
}

/// Send an encrypted text message to the trade counterparty.
///
/// Validates that `content` is non-empty, wraps it in the chat envelope
/// (kind 14 signed with `K_sign`, inner kind 1 signed with the trade key) and
/// publishes it. If the session, peer, or relay pool is not available the
/// message is stored locally with a warning — same graceful degradation as
/// before, chat never throws for transport reasons.
///
/// Returns the sent `ChatMessage` (with `is_mine: true`).
pub async fn send_message(trade_id: String, content: String) -> Result<ChatMessage> {
    if content.trim().is_empty() {
        bail!("MessageEmpty: content must not be empty");
    }
    if trade_id.trim().is_empty() {
        bail!("TradeNotFound: trade_id must not be empty");
    }

    // Cheap upper bound before any crypto: the NIP-44 ciphertext of a
    // payload this size can never fit under MAX_CONTENT_BYTES, so no
    // receiver would accept it. The exact boundary (padding + JSON
    // escaping) is enforced post-encryption in `mostro_wrap`.
    if content.len() > crate::nostr::transport::MAX_CONTENT_BYTES {
        bail!(
            "MessageTooLarge: {} bytes exceeds the maximum message size",
            content.len()
        );
    }

    // Look up session to get peer pubkey and trade key index.
    // If no session exists (e.g. order not yet active), fall back to local-only.
    let session = crate::mostro::session::session_manager()
        .get_session(&trade_id)
        .await;

    // Local-only defaults, replaced on successful publish by the inner
    // event's identity so both sides agree on the message id.
    let mut id = uuid::Uuid::new_v4().to_string();
    let mut created_at = unix_now();
    let mut sender_pubkey = String::new();

    match &session {
        None => log::warn!("[messages] no session for trade={trade_id} — local-only"),
        Some(s) => match &s.peer_pubkey {
            None => log::warn!("[messages] session exists but peer not yet known — local-only"),
            Some(peer_hex) => match chat_context(s.trade_key_index, peer_hex).await {
                Err(e) => log::warn!("[messages] send_message trade={trade_id}: {e}"),
                Ok(ctx) => {
                    sender_pubkey = ctx.trade_keys.public_key().to_hex();
                    match publish_chat_payload(&ctx, &content).await {
                        // A message every receiver must reject is a caller
                        // error, not a transport hiccup — surface it instead
                        // of storing a "sent" message the peer never sees.
                        Err(e) if e.to_string().contains("MessageTooLarge") => {
                            return Err(e);
                        }
                        Err(e) => log::warn!("[messages] send_message trade={trade_id}: {e}"),
                        Ok(inner) => {
                            id = inner.id.to_hex();
                            created_at = inner.created_at.as_secs() as i64;
                        }
                    }
                }
            },
        },
    }

    let msg = ChatMessage {
        id,
        trade_id: trade_id.clone(),
        sender_pubkey,
        content,
        message_type: MessageType::Peer,
        is_mine: true,
        is_read: true,
        has_attachment: false,
        attachment: None,
        created_at,
    };

    let _ = message_store().add_message(msg.clone()).await;
    Ok(msg)
}

/// Get all messages for a trade, ordered by creation time (oldest first).
pub async fn get_messages(trade_id: String) -> Result<Vec<ChatMessage>> {
    let mut msgs = message_store().get_messages(&trade_id).await;
    msgs.sort_by_key(|m| m.created_at);
    Ok(msgs)
}

/// Mark all messages in a trade as read.
///
/// Emits on the `on_unread_count_changed` stream after updating.
pub async fn mark_as_read(trade_id: String) -> Result<()> {
    message_store().mark_as_read(&trade_id).await;
    Ok(())
}

/// Get total unread message count across all trades.
pub async fn get_unread_count() -> Result<u32> {
    Ok(message_store().unread_count_inner().await)
}

/// Encrypt, upload, and send a file attachment.
///
/// Flow:
/// 1. Validate size (≤ 25 MB) and MIME type.
/// 2. Derive encryption key from ECDH shared key.
/// 3. Encrypt with ChaCha20-Poly1305 (`crate::crypto::file_enc`).
/// 4. Upload encrypted blob to Blossom server.
/// 5. Send Blossom URL + encryption metadata as NIP-59 message.
///
/// Returns the sent `ChatMessage` with `has_attachment: true`.
pub async fn send_file(
    trade_id: String,
    file_bytes: Vec<u8>,
    file_name: String,
    mime_type: String,
) -> Result<ChatMessage> {
    if trade_id.trim().is_empty() {
        bail!("TradeNotFound: trade_id must not be empty");
    }
    if file_bytes.len() > blossom::MAX_BLOB_SIZE {
        bail!(
            "FileTooLarge: {} bytes exceeds 25 MB limit",
            file_bytes.len()
        );
    }
    if !is_supported_mime_type(&mime_type) {
        bail!("UnsupportedFileType: {mime_type}");
    }

    // 1. Fetch session once and extract everything needed for the entire flow.
    let session = crate::mostro::session::session_manager()
        .get_session(&trade_id)
        .await
        .ok_or_else(|| anyhow!("SessionNotFound: {trade_id}"))?;

    let trade_key_index = session.trade_key_index;
    let peer_pubkey_hex = session.peer_pubkey.clone();

    let shared_key: [u8; 32] = if let Some(k) = session.shared_key {
        k
    } else {
        let sender_keys = crate::api::identity::get_active_trade_keys(trade_key_index).await?;
        let peer_hex = peer_pubkey_hex
            .as_deref()
            .ok_or_else(|| anyhow!("PeerUnknown: cannot encrypt attachment without peer pubkey"))?;
        let peer_pubkey = nostr_sdk::PublicKey::from_hex(peer_hex)
            .map_err(|e| anyhow!("invalid peer pubkey: {e}"))?;
        crate::crypto::ecdh::derive_nip04_shared_key(&sender_keys, &peer_pubkey)?
    };

    // 2. Encrypt the file bytes.
    let encrypted_bytes = crate::crypto::file_enc::encrypt_file(&file_bytes, &shared_key)
        .map_err(|e| anyhow!("FileEncryptionFailed: {e}"))?;

    // 3. Upload encrypted blob to Blossom.
    let file_type = mime_to_file_type(&mime_type);
    let file_size = file_bytes.len() as u64;
    let msg_id = uuid::Uuid::new_v4().to_string();
    let _ = message_store().attachment_tx.send((msg_id.clone(), 0.1));

    let blossom_url = blossom::upload_blob(encrypted_bytes, mime_type.clone(), None)
        .await
        .map_err(|e| anyhow!("UploadFailed: {e}"))?;

    let _ = message_store().attachment_tx.send((msg_id.clone(), 1.0));

    // 4. Build attachment metadata and publish via the chat envelope. The
    //    file bytes themselves stay ChaCha20-encrypted on Blossom (step 2) —
    //    only this pointer payload rides the chat channel.
    let payload = serde_json::json!({
        "url": blossom_url,
        "name": file_name,
        "mime_type": mime_type,
        "size": file_size,
        "type": "file",
    })
    .to_string();

    let sender_keys = crate::api::identity::get_active_trade_keys(trade_key_index).await?;
    let sender_pubkey = sender_keys.public_key().to_hex();

    // Local-only defaults, replaced by the inner event identity on publish.
    let mut msg_created_at = unix_now();
    let mut published_id: Option<String> = None;

    if let Some(peer_hex) = &peer_pubkey_hex {
        match chat_context(trade_key_index, peer_hex).await {
            Err(e) => log::warn!("[messages] send_file trade={trade_id}: {e}"),
            Ok(ctx) => match publish_chat_payload(&ctx, &payload).await {
                Err(e) => log::warn!("[messages] send_file trade={trade_id}: {e}"),
                Ok(inner) => {
                    published_id = Some(inner.id.to_hex());
                    msg_created_at = inner.created_at.as_secs() as i64;
                }
            },
        }
    } else {
        log::warn!("[messages] send_file peer not yet known — local-only");
    }

    let attachment = AttachmentInfo {
        file_name: file_name.clone(),
        mime_type: mime_type.clone(),
        file_size,
        file_type,
        download_status: DownloadStatus::Downloaded,
        local_path: None,
    };

    // Prefer the inner event id so the stored message matches the identity
    // the recipient (and our own restart catch-up) dedups on.
    let msg = ChatMessage {
        id: published_id.unwrap_or(msg_id),
        trade_id: trade_id.clone(),
        sender_pubkey,
        content: blossom_url,
        message_type: MessageType::Peer,
        is_mine: true,
        is_read: true,
        has_attachment: true,
        attachment: Some(attachment),
        created_at: msg_created_at,
    };

    let _ = message_store().add_message(msg.clone()).await;
    Ok(msg)
}

/// Download and decrypt a file attachment.
///
/// Returns a `FileDownloadResult` with the local path to the decrypted file.
pub async fn download_attachment(message_id: String) -> Result<FileDownloadResult> {
    // Look up attachment info from message store
    let store = message_store().messages.read().await;
    let msg = store
        .values()
        .flat_map(|msgs| msgs.iter())
        .find(|m| m.id == message_id)
        .ok_or_else(|| anyhow!("AttachmentNotFound: message {message_id}"))?
        .clone();
    drop(store);

    let attachment = msg
        .attachment
        .ok_or_else(|| anyhow!("AttachmentNotFound: message has no attachment"))?;

    // 1. Get Blossom URL from message content.
    let blossom_url = msg.content.clone();
    if blossom_url.is_empty()
        || (!blossom_url.starts_with("http://") && !blossom_url.starts_with("https://"))
    {
        bail!("AttachmentNotFound: message has no valid Blossom URL in content");
    }

    // 2. Get the session shared key to decrypt.
    let session = crate::mostro::session::session_manager()
        .get_session(&msg.trade_id)
        .await;

    let shared_key: [u8; 32] = match session {
        None => bail!("SessionNotFound: cannot decrypt attachment without session"),
        Some(s) => {
            if let Some(k) = s.shared_key {
                k
            } else {
                let sender_keys =
                    crate::api::identity::get_active_trade_keys(s.trade_key_index).await?;
                let peer_hex = s
                    .peer_pubkey
                    .as_deref()
                    .ok_or_else(|| anyhow!("PeerUnknown: cannot derive key without peer pubkey"))?;
                let peer_pubkey = nostr_sdk::PublicKey::from_hex(peer_hex)
                    .map_err(|e| anyhow!("invalid peer pubkey: {e}"))?;
                crate::crypto::ecdh::derive_nip04_shared_key(&sender_keys, &peer_pubkey)?
            }
        }
    };

    // 3. Download encrypted blob from Blossom.
    let _ = message_store()
        .attachment_tx
        .send((message_id.clone(), 0.1));
    let encrypted_bytes = blossom::download_blob(blossom_url)
        .await
        .map_err(|e| anyhow!("DownloadFailed: {e}"))?;

    // 4. Decrypt.
    let plaintext = crate::crypto::file_enc::decrypt_file(&encrypted_bytes, &shared_key)
        .map_err(|e| anyhow!("DecryptionFailed: {e}"))?;

    // 5. Persist the decrypted blob to a local path. Native writes to a temp
    //    file; web has no filesystem, so that path is not supported there yet.
    let local_path =
        persist_decrypted_attachment(&message_id, &attachment.file_name, &plaintext).await?;

    let _ = message_store()
        .attachment_tx
        .send((message_id.clone(), 1.0));

    let result = FileDownloadResult {
        local_path: local_path.clone(),
        file_name: attachment.file_name.clone(),
        mime_type: attachment.mime_type.clone(),
        file_size: plaintext.len() as u64,
    };

    // Update the local message to reflect Downloaded status
    {
        let mut store = message_store().messages.write().await;
        for msgs in store.values_mut() {
            for m in msgs.iter_mut() {
                if m.id == message_id {
                    if let Some(ref mut att) = m.attachment {
                        att.download_status = DownloadStatus::Downloaded;
                        att.local_path = Some(result.local_path.clone());
                    }
                }
            }
        }
    }

    Ok(result)
}

/// Get the attachment download status for a message.
pub async fn get_attachment_status(message_id: String) -> Result<Option<DownloadStatus>> {
    let store = message_store().messages.read().await;
    let status = store
        .values()
        .flat_map(|msgs| msgs.iter())
        .find(|m| m.id == message_id)
        .and_then(|m| m.attachment.as_ref())
        .map(|a| a.download_status.clone());
    Ok(status)
}

// ── Streams ───────────────────────────────────────────────────────────────────

/// Stream that emits new messages for a specific trade.
pub async fn on_new_message(trade_id: String) -> Result<MessageStream> {
    let rx = message_store().new_message_tx.subscribe();
    Ok(MessageStream { rx, trade_id })
}

/// Stream that emits the updated global unread count after any read/write.
pub async fn on_unread_count_changed() -> Result<UnreadCountStream> {
    let rx = message_store().unread_tx.subscribe();
    Ok(UnreadCountStream { rx })
}

/// Stream that emits attachment upload/download progress (0.0–1.0).
pub async fn on_attachment_progress(message_id: String) -> Result<AttachmentProgressStream> {
    let rx = message_store().attachment_tx.subscribe();
    Ok(AttachmentProgressStream { rx, message_id })
}

// ── Stream wrappers ───────────────────────────────────────────────────────────

pub struct MessageStream {
    rx: broadcast::Receiver<ChatMessage>,
    trade_id: String,
}

impl MessageStream {
    pub async fn next(&mut self) -> Option<ChatMessage> {
        loop {
            match self.rx.recv().await {
                Ok(msg) if msg.trade_id == self.trade_id => return Some(msg),
                Ok(_) => continue, // different trade
                Err(broadcast::error::RecvError::Lagged(_)) => continue,
                Err(broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

pub struct UnreadCountStream {
    rx: broadcast::Receiver<u32>,
}

impl UnreadCountStream {
    pub async fn next(&mut self) -> Option<u32> {
        loop {
            match self.rx.recv().await {
                Ok(count) => return Some(count),
                Err(broadcast::error::RecvError::Lagged(_)) => continue,
                Err(broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

pub struct AttachmentProgressStream {
    rx: broadcast::Receiver<(String, f64)>,
    message_id: String,
}

impl AttachmentProgressStream {
    pub async fn next(&mut self) -> Option<f64> {
        loop {
            match self.rx.recv().await {
                Ok((id, pct)) if id == self.message_id => return Some(pct),
                Ok(_) => continue,
                Err(broadcast::error::RecvError::Lagged(_)) => continue,
                Err(broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

use crate::rt::unix_now;

/// Strip directory components from a caller-supplied file name to prevent
/// path traversal (e.g. `../../../etc/passwd` → `passwd`).
/// Returns `"attachment"` for empty or path-only inputs.
// Native-only: the wasm attachment writer errors out before it needs a name.
#[cfg(not(target_arch = "wasm32"))]
fn safe_filename(name: &str) -> String {
    std::path::Path::new(name)
        .file_name()
        .and_then(|n| n.to_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("attachment")
        .to_string()
}

/// Persist a decrypted attachment to a local path the UI can open.
///
/// Native writes to the OS temp dir. `wasm32` has no filesystem, so this is not
/// supported on web yet and returns an error.
#[cfg(not(target_arch = "wasm32"))]
async fn persist_decrypted_attachment(
    message_id: &str,
    file_name: &str,
    data: &[u8],
) -> Result<String> {
    let unique_name = format!("{message_id}_{}", safe_filename(file_name));
    let local_path = std::env::temp_dir()
        .join(&unique_name)
        .to_string_lossy()
        .into_owned();
    tokio::fs::write(&local_path, data)
        .await
        .map_err(|e| anyhow!("WriteFailed: {e}"))?;
    Ok(local_path)
}

#[cfg(target_arch = "wasm32")]
async fn persist_decrypted_attachment(
    _message_id: &str,
    _file_name: &str,
    _data: &[u8],
) -> Result<String> {
    Err(anyhow!("attachment download to disk is not supported on web"))
}

fn is_supported_mime_type(mime: &str) -> bool {
    mime.starts_with("image/")
        || mime.starts_with("video/")
        || mime.starts_with("text/")
        || mime == "application/pdf"
}

fn mime_to_file_type(mime: &str) -> FileType {
    if mime.starts_with("image/") {
        FileType::Image
    } else if mime.starts_with("video/") {
        FileType::Video
    } else {
        FileType::Document
    }
}

// ── Incoming-chat subscription ────────────────────────────────────────────────

/// Cap on the backlog requested from relays in one subscription.
const CHAT_BACKLOG_LIMIT: usize = 500;

/// Token bucket sizing per the spec: ~30 messages/minute sustained with a
/// burst of 60, refused **before** any cryptographic work.
const RATE_CAPACITY: f64 = 60.0;
const RATE_PER_SEC: f64 = 0.5;

/// Consecutive rejected events before the conversation is marked flooded and
/// processing stops. At the sustained rate this is several minutes of pure
/// garbage from the only author able to produce it — the counterparty.
const FLOOD_TRIP_REJECTIONS: u32 = 180;

/// Entries kept in the outer-event-id LRU. Pre-decryption filter against
/// duplicate relay deliveries only — the security-bearing dedup is the
/// durable inner-id check in `MessageStore::is_known`.
const OUTER_LRU_CAP: usize = 512;

/// Per-trade retention caps (protocol spec: "Clients SHOULD also cap the
/// number of messages and total bytes stored per trade"). Excess incoming
/// messages are dropped and logged; the trade itself is unaffected.
const MAX_STORED_MESSAGES_PER_TRADE: usize = 1000;
const MAX_STORED_BYTES_PER_TRADE: usize = 5 * 1024 * 1024;

/// Subscription id for the chat envelope of one order — explicit so every
/// exit path can unsubscribe and a lingering relay subscription never
/// outlives its task.
fn chat_subscription_id(channel: ChatChannel, order_id: &str) -> nostr_sdk::SubscriptionId {
    nostr_sdk::SubscriptionId::new(format!("mostro-chat-{}{order_id}", channel.id_prefix()))
}

/// Which conversation an envelope subscription serves.
///
/// Both use the identical envelope and key derivation — the difference is who
/// the shared secret is with, and therefore which key pair `derive_chat_keys`
/// produces (<https://mostro.network/protocol/dispute_chat.html>).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum ChatChannel {
    /// Buyer ↔ seller, keyed to the counterparty's trade key.
    Peer,
    /// Party ↔ solver, keyed to the admin pubkey from `admin-took-dispute`.
    /// Each party has its own independent conversation with the admin.
    Dispute,
}

impl ChatChannel {
    /// Distinguishes the two conversations of one order everywhere they are
    /// tracked by id: subscription ids and the single-owner guard. Without it
    /// a dispute chat would be mistaken for the peer chat already running for
    /// that order and silently never start.
    fn id_prefix(self) -> &'static str {
        match self {
            ChatChannel::Peer => "",
            ChatChannel::Dispute => "dispute-",
        }
    }

    fn guard_key(self, order_id: &str) -> String {
        format!("{}{order_id}", self.id_prefix())
    }

    fn message_type(self) -> MessageType {
        match self {
            ChatChannel::Peer => MessageType::Peer,
            ChatChannel::Dispute => MessageType::Admin,
        }
    }

    /// Durable `since`-cursor key for this channel of `order_id`.
    ///
    /// Channel-scoped (PR #254 review): the peer and dispute subscriptions
    /// are independent event streams, and a shared cursor would let either
    /// advance past backlog the other has not seen — e.g. a solver with a
    /// slightly slower clock dating a reply before the peer cursor, which
    /// the dispute filter would then never fetch. The peer key keeps its
    /// historical shape so existing installs do not refetch their backlog.
    fn cursor_key(self, order_id: &str) -> String {
        crate::db::settings_keys::chat_cursor(&format!("{}{order_id}", self.id_prefix()))
    }

}

/// Orders with a live chat task. Single-owner guard: `on_peer_pubkey_received`
/// fires again on daemon replays and reconnect backfills, and a second task
/// for the same order would double-process events and race on the cursor.
static ACTIVE_CHATS: OnceLock<tokio::sync::Mutex<std::collections::HashSet<String>>> =
    OnceLock::new();

fn active_chats() -> &'static tokio::sync::Mutex<std::collections::HashSet<String>> {
    ACTIVE_CHATS.get_or_init(|| tokio::sync::Mutex::new(std::collections::HashSet::new()))
}

/// Bounded insert-only id set with FIFO eviction (outer-id LRU, step 5).
struct BoundedIdSet {
    set: std::collections::HashSet<String>,
    order: std::collections::VecDeque<String>,
    cap: usize,
}

impl BoundedIdSet {
    fn new(cap: usize) -> Self {
        Self {
            set: std::collections::HashSet::new(),
            order: std::collections::VecDeque::new(),
            cap,
        }
    }

    /// Insert `id`; returns `false` if it was already present.
    fn insert(&mut self, id: &str) -> bool {
        if self.set.contains(id) {
            return false;
        }
        if self.order.len() >= self.cap {
            if let Some(evicted) = self.order.pop_front() {
                self.set.remove(&evicted);
            }
        }
        self.set.insert(id.to_string());
        self.order.push_back(id.to_string());
        true
    }
}

/// Token bucket refilled continuously, drained one token per event (step 6).
struct TokenBucket {
    tokens: f64,
    last: crate::rt::time::Instant,
}

impl TokenBucket {
    fn new(now: crate::rt::time::Instant) -> Self {
        Self {
            tokens: RATE_CAPACITY,
            last: now,
        }
    }

    /// Take one token at time `now`; `false` when the budget is exhausted.
    fn try_take(&mut self, now: crate::rt::time::Instant) -> bool {
        let elapsed = now.duration_since(self.last).as_secs_f64();
        self.last = now;
        self.tokens = (self.tokens + elapsed * RATE_PER_SEC).min(RATE_CAPACITY);
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            true
        } else {
            false
        }
    }
}

/// Read the persisted `since` cursor for one channel of `order_id`, if any.
async fn load_chat_cursor(channel: ChatChannel, order_id: &str) -> Option<i64> {
    let db = crate::db::app_db::db()?;
    db.get_setting(&channel.cursor_key(order_id))
        .await
        .ok()
        .flatten()?
        .parse()
        .ok()
}

/// Persist the `since` cursor. Best-effort: on web this is a no-op until
/// IndexedDB lands (#233), so the backlog bound degrades to per-process.
async fn store_chat_cursor(channel: ChatChannel, order_id: &str, ts: i64) {
    if let Some(db) = crate::db::app_db::db() {
        let key = channel.cursor_key(order_id);
        if let Err(e) = db.set_setting(&key, &ts.to_string()).await {
            log::warn!("[messages] cursor persist failed order={order_id}: {e}");
        }
    }
}

/// Interpret a validated inner-event payload.
///
/// Attachments travel as a JSON pointer object (`type: "file"`) — everything
/// else is plaintext. Returns `(content, attachment)` where `content` is the
/// display text (the Blossom URL for attachments, mirroring `send_file`).
fn parse_chat_payload(payload: &str) -> (String, Option<AttachmentInfo>) {
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(payload) {
        if v.get("type").and_then(|t| t.as_str()) == Some("file") {
            if let (Some(url), Some(name), Some(mime)) = (
                v.get("url").and_then(|x| x.as_str()),
                v.get("name").and_then(|x| x.as_str()),
                v.get("mime_type").and_then(|x| x.as_str()),
            ) {
                let attachment = AttachmentInfo {
                    file_name: name.to_string(),
                    mime_type: mime.to_string(),
                    file_size: v.get("size").and_then(|s| s.as_u64()).unwrap_or(0),
                    file_type: mime_to_file_type(mime),
                    download_status: DownloadStatus::Pending,
                    local_path: None,
                };
                return (url.to_string(), Some(attachment));
            }
        }
    }
    (payload.to_string(), None)
}

/// Spawn-able listener for the P2P chat conversation of one order.
///
/// Subscribes with **`authors = [pub(K_sign)]`** — the rule that eliminates
/// third-party flooding: relays drop everything not signed by the
/// conversation key, so junk never reaches us — bounded by the persisted
/// `since` cursor plus a `limit`, so a restart never re-downloads an
/// unbounded backlog. Kind 14 is the only shape read: this client speaks
/// protocol v2 only and never subscribes to the superseded gift wrap.
///
/// Incoming events run the spec's cheapest-check-first pipeline: author →
/// outer-id LRU → rate-limit budget → `mostro_unwrap` (p tag, timestamp
/// bounds, size, both signatures, allowed signers) → durable inner-id dedup
/// (fail-closed) → retention quota. The budget is only metered on the
/// **live** stream (after the relay's EOSE): stored catch-up above the burst
/// size is legitimate history, and dropping it would permanently lose
/// messages the advancing cursor never re-fetches. Two deliberate ordering
/// deviations from the spec text: the LRU and budget run before the p-tag /
/// timestamp / size checks (all are O(1) compares; what matters is that no
/// signature or decryption work happens before the budget gate).
///
/// Lifecycle: exactly one task per order (`ACTIVE_CHATS` guard — daemon
/// replays re-invoke `on_peer_pubkey_received` and must be no-ops), explicit
/// subscription ids unsubscribed on every exit path, and **no idle timeout**:
/// the listener lives until relay-pool shutdown or a flood trip, because a
/// quiet half hour is normal in a fiat trade and the next peer message must
/// still arrive. After a restart, `resubscribe_active_chats` rebuilds the
/// listeners for persisted active trades.
///
/// Isolation: this is its own task over a bounded notification channel. It
/// only ever drops chat events; it cannot touch the order state machine, the
/// daemon transport, or dispute flows.
pub(crate) async fn subscribe_incoming_chat(
    channel: ChatChannel,
    order_id: String,
    trade_keys: nostr_sdk::Keys,
    peer_pubkey: nostr_sdk::PublicKey,
    conv: nostr_sdk::Keys,
    sign: nostr_sdk::Keys,
) {
    // Single-owner guard: a second spawn for the same order is a no-op.
    {
        let mut active = active_chats().lock().await;
        if !active.insert(channel.guard_key(&order_id)) {
            log::debug!("[messages] chat task already active order={order_id}");
            return;
        }
    }

    run_chat_subscription(channel, &order_id, &trade_keys, &peer_pubkey, &conv, &sign).await;

    // Cleanup on every exit path: release ownership and drop the relay
    // subscriptions so they never outlive the task.
    active_chats().lock().await.remove(&channel.guard_key(&order_id));
    if let Ok(pool) = crate::api::nostr::get_pool() {
        let client = pool.client();
        client
            .unsubscribe(&chat_subscription_id(channel, &order_id))
            .await;
    }
    log::debug!("[messages] incoming-chat subscription exiting order={order_id}");
}

/// Mutable per-conversation receive state (see `subscribe_incoming_chat`).
struct ChatRxState {
    channel: ChatChannel,
    outer_seen: BoundedIdSet,
    bucket: TokenBucket,
    consecutive_rejected: u32,
    /// `true` once a relay reported EOSE for one of our subscriptions —
    /// from then on the token bucket meters arrivals; before that, events
    /// are stored catch-up already bounded by the filter `limit`.
    live: bool,
    cursor: i64,
    flooded: bool,
}

impl ChatRxState {
    fn new(channel: ChatChannel, cursor: i64) -> Self {
        Self {
            channel,
            outer_seen: BoundedIdSet::new(OUTER_LRU_CAP),
            bucket: TokenBucket::new(crate::rt::time::Instant::now()),
            consecutive_rejected: 0,
            live: false,
            cursor,
            flooded: false,
        }
    }

    /// Count one rejected event; trips the flood breaker on sustained abuse.
    fn reject(&mut self, order_id: &str) {
        self.consecutive_rejected += 1;
        if self.consecutive_rejected >= FLOOD_TRIP_REJECTIONS {
            self.flooded = true;
            log::error!(
                "[messages] conversation flooded — halting chat for order={order_id}; \
                 the trade itself stays fully operational"
            );
            crate::api::logging::blog_info(
                "messages",
                format!("chat flooded, processing stopped order={order_id}"),
            );
        }
    }

    /// Live-stream budget check (no-op during stored catch-up).
    fn budget_ok(&mut self, order_id: &str) -> bool {
        if !self.live {
            return true;
        }
        if self.bucket.try_take(crate::rt::time::Instant::now()) {
            true
        } else {
            self.reject(order_id);
            false
        }
    }

    /// Advance the persisted cursor to `event_ts` clamped to our own clock,
    /// so a counterparty dating events at the skew-tolerance edge can never
    /// push it into the future and silence the conversation. Callers only
    /// invoke this once the corresponding message is durably stored (or was
    /// already known/durable).
    async fn advance_cursor(&mut self, order_id: &str, event_ts: i64) {
        let accepted = event_ts.min(unix_now());
        if accepted > self.cursor {
            self.cursor = accepted;
            store_chat_cursor(self.channel, order_id, accepted).await;
        }
    }
}

async fn run_chat_subscription(
    channel: ChatChannel,
    order_id: &str,
    trade_keys: &nostr_sdk::Keys,
    peer_pubkey: &nostr_sdk::PublicKey,
    conv: &nostr_sdk::Keys,
    sign: &nostr_sdk::Keys,
) {
    use nostr_sdk::RelayPoolNotification;
    use tokio::sync::broadcast;

    let Ok(pool) = crate::api::nostr::get_pool() else {
        log::warn!("[messages] subscribe_incoming_chat: relay pool not initialized");
        return;
    };
    let client = pool.client();

    let sign_pubkey = sign.public_key();
    let my_trade_pubkey = trade_keys.public_key();
    let allowed_signers = [my_trade_pubkey, *peer_pubkey];

    // `since` from the persisted cursor: everything older is already stored
    // locally (the cursor only advances on durably stored messages).
    let cursor = load_chat_cursor(channel, order_id).await.unwrap_or(0);
    let sub_id = chat_subscription_id(channel, order_id);

    let mut filter = nostr_sdk::Filter::new()
        .kind(nostr_sdk::Kind::PrivateDirectMessage)
        .author(sign_pubkey)
        .limit(CHAT_BACKLOG_LIMIT);
    if cursor > 0 {
        filter = filter.since(nostr_sdk::Timestamp::from_secs(cursor as u64));
    }

    // Obtain the receiver BEFORE subscribing — same pattern as subscribe_daemon_messages.
    // This avoids a race where an event arrives between subscribe() and notifications()
    // and would otherwise be missed.
    let mut rx = client.notifications();

    if let Err(e) = client.subscribe_with_id(sub_id.clone(), filter, None).await {
        log::warn!("[messages] subscribe_incoming_chat subscribe failed: {e}");
        return;
    }

    log::info!(
        "[messages] incoming-chat subscription active order={order_id} author={} since={cursor}",
        sign_pubkey.to_hex(),
    );

    let mut state = ChatRxState::new(channel, cursor);

    loop {
        match rx.recv().await {
            Ok(RelayPoolNotification::Event {
                subscription_id,
                event,
                ..
            }) => {
                if subscription_id == sub_id {
                    handle_chat_event(channel, order_id, &allowed_signers, conv, &sign_pubkey, &my_trade_pubkey, &event, &mut state)
                        .await;
                }
                if state.flooded {
                    return;
                }
            }
            Ok(RelayPoolNotification::Message { message, .. }) => {
                // EOSE for one of our subscriptions: stored catch-up is over,
                // the token bucket meters everything from here on.
                if let nostr_sdk::RelayMessage::EndOfStoredEvents(sid) = message {
                    if *sid == sub_id {
                        state.live = true;
                    }
                }
            }
            Ok(RelayPoolNotification::Shutdown) => break,
            Err(broadcast::error::RecvError::Lagged(n)) => {
                // The bounded notification channel dropped n events under
                // pressure — chat data loss, never trade-traffic loss.
                log::warn!("[messages] incoming-chat lagged by {n} messages");
                continue;
            }
            Err(broadcast::error::RecvError::Closed) => break,
        }
    }
}

/// Validate and store one incoming chat-envelope event (see
/// `subscribe_incoming_chat` for the pipeline description).
// One more argument than clippy's default: the channel joins parameters this
// function already threaded, and bundling them into a struct would just move
// the same values behind a name that adds nothing.
#[allow(clippy::too_many_arguments)]
async fn handle_chat_event(
    channel: ChatChannel,
    order_id: &str,
    allowed_signers: &[nostr_sdk::PublicKey],
    conv: &nostr_sdk::Keys,
    sign_pubkey: &nostr_sdk::PublicKey,
    my_trade_pubkey: &nostr_sdk::PublicKey,
    event: &nostr_sdk::Event,
    state: &mut ChatRxState,
) {
    if event.kind != nostr_sdk::Kind::PrivateDirectMessage {
        return;
    }
    // Step 1 — author. Kind 14 is shared with the daemon transport; a
    // different author is somebody else's traffic, not a violation.
    if event.pubkey != *sign_pubkey {
        return;
    }
    // Step 5 — outer-id LRU: duplicate relay deliveries cost one hash lookup.
    if !state.outer_seen.insert(&event.id.to_hex()) {
        return;
    }
    // Step 6 — rate-limit budget, before any cryptographic work.
    if !state.budget_ok(order_id) {
        return;
    }

    // Steps 2,3,4,7–11,13 — the crypto-side validation.
    let inner = match crate::nostr::transport::mostro_unwrap(
        conv,
        sign_pubkey,
        allowed_signers,
        event,
        nostr_sdk::Timestamp::now(),
    ) {
        Ok(inner) => inner,
        Err(e) => {
            // Only the counterparty can author a validly-signed outer event,
            // so failures here are attributable.
            log::warn!("[messages] incoming-chat rejected order={order_id}: {e}");
            state.reject(order_id);
            return;
        }
    };
    state.consecutive_rejected = 0;

    // Step 12 — durable replay dedup on the inner id, fail-closed: a lookup
    // error drops the event (and leaves the cursor put, so it is re-fetched
    // once storage recovers) instead of accepting a possible replay.
    let inner_id = inner.id.to_hex();
    match message_store().is_known(order_id, &inner_id).await {
        Err(e) => {
            log::warn!("[messages] {e} — dropping event order={order_id}");
            return;
        }
        Ok(true) => {
            // An echo of our own send, or a replay. Only advance the cursor
            // if the known copy really is durable — a memory-only record
            // (its DB write failed) gets one retry here, and failing that
            // the cursor stays put so the relay copy survives a restart.
            log::debug!("[messages] incoming-chat duplicate inner id={inner_id}");
            if message_store().ensure_durable(order_id, &inner_id).await {
                state
                    .advance_cursor(order_id, event.created_at.as_secs() as i64)
                    .await;
            }
            return;
        }
        Ok(false) => {}
    }

    // Retention quota — bounds durable growth at a legitimate send rate.
    if message_store()
        .quota_exceeded(order_id, inner.content.len())
        .await
    {
        log::warn!("[messages] retention quota reached order={order_id} — dropping message");
        return;
    }

    // An unknown echo of our own message (this device lost its local copy,
    // or another device of ours sent it): store it as ours so history
    // reconstructs, but never as unread.
    let is_echo = inner.pubkey == *my_trade_pubkey;
    let (content, attachment) = parse_chat_payload(&inner.content);

    let msg = ChatMessage {
        id: inner_id,
        trade_id: order_id.to_string(),
        sender_pubkey: inner.pubkey.to_hex(),
        content,
        message_type: channel.message_type(),
        is_mine: is_echo,
        is_read: is_echo,
        has_attachment: attachment.is_some(),
        attachment,
        // Presentation orders by the inner timestamp, which the relative
        // bound has already tied to the outer one.
        created_at: inner.created_at.as_secs() as i64,
    };

    log::debug!("[messages] incoming-chat rx order={order_id} id={}", msg.id);
    // Cursor moves only past durably stored messages: a failed write with an
    // advanced cursor would lose the message permanently.
    if message_store().add_message(msg).await {
        state
            .advance_cursor(order_id, event.created_at.as_secs() as i64)
            .await;
    }
}

/// Rebuild the chat listeners for every persisted trade that can still chat.
///
/// Called once the relay pool is up (`api::nostr::initialize`): sessions are
/// in-memory, so after a process restart nothing else would resubscribe and
/// the next peer message would be lost until the daemon happened to resend a
/// peer-pubkey notification.
pub(crate) async fn resubscribe_active_chats() {
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    let trades = match db.list_trades().await {
        Ok(t) => t,
        Err(e) => {
            log::warn!("[messages] resubscribe: list_trades failed: {e}");
            return;
        }
    };
    for trade in trades.into_iter().filter(chat_still_relevant) {
        let order_id = trade.order.id.clone();
        let Ok(trade_keys) =
            crate::api::identity::get_active_trade_keys(trade.trade_key_index).await
        else {
            continue;
        };
        let Ok(peer) = nostr_sdk::PublicKey::from_hex(&trade.counterparty_pubkey) else {
            continue;
        };
        let Ok((conv, sign)) = crate::crypto::chat_keys::derive_chat_keys(&trade_keys, &peer)
        else {
            continue;
        };
        log::info!("[messages] resubscribing chat order={order_id}");
        crate::rt::spawn(subscribe_incoming_chat(
            ChatChannel::Peer, order_id, trade_keys, peer, conv, sign,
        ));
    }
}

/// A persisted trade still needs a live chat listener: it has a known peer
/// and has not reached a terminal outcome.
fn chat_still_relevant(trade: &crate::api::types::TradeInfo) -> bool {
    use crate::api::types::OrderStatus::*;
    trade.outcome.is_none()
        && !trade.counterparty_pubkey.is_empty()
        && matches!(
            trade.order.status,
            Pending
                | WaitingBuyerInvoice
                | WaitingPayment
                | Active
                | FiatSent
                | SettledHoldInvoice
                | Dispute
                | InProgress
        )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_two_channels_of_one_order_never_collide() {
        let order = "order-1";

        // Same order, different conversations: the single-owner guard and the
        // relay subscription id must tell them apart, or starting the dispute
        // chat would be a no-op because the peer chat already "owns" the order.
        assert_ne!(
            ChatChannel::Peer.guard_key(order),
            ChatChannel::Dispute.guard_key(order)
        );
        assert_ne!(
            chat_subscription_id(ChatChannel::Peer, order),
            chat_subscription_id(ChatChannel::Dispute, order)
        );
    }

    #[test]
    fn the_peer_channel_keeps_its_wire_identity() {
        // The peer subscription id is unchanged by the channel refactor: a
        // different string would orphan subscriptions across an app upgrade.
        assert_eq!(
            chat_subscription_id(ChatChannel::Peer, "order-1"),
            nostr_sdk::SubscriptionId::new("mostro-chat-order-1")
        );
    }

    /// PR #254 review: the peer and dispute streams are independent, so each
    /// channel owns its own durable cursor (peer keeps the historical key so
    /// existing installs do not refetch) and its own subscription ids.
    #[test]
    fn cursors_and_subscription_ids_are_channel_scoped() {
        assert_eq!(
            ChatChannel::Peer.cursor_key("o1"),
            crate::db::settings_keys::chat_cursor("o1"),
        );
        assert_eq!(
            ChatChannel::Dispute.cursor_key("o1"),
            crate::db::settings_keys::chat_cursor("dispute-o1"),
        );
        assert_ne!(
            ChatChannel::Peer.cursor_key("o1"),
            ChatChannel::Dispute.cursor_key("o1"),
        );
    }

    /// Protocol v1 is not spoken in either direction: the chat pipeline reads
    /// kind 14 only, so a gift wrap addressed to us is somebody else's traffic
    /// and must never reach the store — not even during a migration window,
    /// because there is no longer one.
    #[tokio::test]
    async fn a_gift_wrap_never_reaches_the_chat_store() {
        use nostr_sdk::prelude::*;

        let sign = Keys::generate();
        let trade = Keys::generate();
        let conv = Keys::generate();
        let order_id = uuid::Uuid::new_v4().to_string();

        // Authored by the very key the subscription pins, so the only thing
        // standing between this event and the store is the kind check.
        let gift_wrap = EventBuilder::new(Kind::GiftWrap, "ciphertext")
            .tag(Tag::public_key(trade.public_key()))
            .sign_with_keys(&sign)
            .unwrap();

        let mut state = ChatRxState::new(ChatChannel::Peer, 0);
        handle_chat_event(
            ChatChannel::Peer,
            &order_id,
            &[trade.public_key(), sign.public_key()],
            &conv,
            &sign.public_key(),
            &trade.public_key(),
            &gift_wrap,
            &mut state,
        )
        .await;

        assert!(
            get_messages(order_id).await.unwrap().is_empty(),
            "a kind-1059 event must not be read by the chat pipeline"
        );
        // Observing the store alone would pass for the wrong reason — the
        // ciphertext is junk, so it would be dropped further down anyway.
        // The LRU insert is the first side effect after the kind check, so a
        // still-unseen id is what proves the event was rejected *on its kind*.
        assert!(
            state.outer_seen.insert(&gift_wrap.id.to_hex()),
            "the gift wrap must be rejected on its kind, before any other work"
        );
    }

    #[test]
    fn each_channel_stores_its_own_message_type() {
        assert_eq!(ChatChannel::Peer.message_type(), MessageType::Peer);
        assert_eq!(ChatChannel::Dispute.message_type(), MessageType::Admin);
    }

    #[tokio::test]
    async fn send_and_get_messages() {
        let trade_id = uuid::Uuid::new_v4().to_string();
        let msg = send_message(trade_id.clone(), "hello".to_string())
            .await
            .unwrap();
        assert!(msg.is_mine);
        assert!(!msg.has_attachment);

        let msgs = get_messages(trade_id.clone()).await.unwrap();
        assert_eq!(msgs.len(), 1);
        assert_eq!(msgs[0].content, "hello");
    }

    #[tokio::test]
    async fn empty_message_is_rejected() {
        let trade_id = uuid::Uuid::new_v4().to_string();
        let result = send_message(trade_id, "  ".to_string()).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn file_too_large_is_rejected() {
        let trade_id = uuid::Uuid::new_v4().to_string();
        let big = vec![0u8; blossom::MAX_BLOB_SIZE + 1];
        let result = send_file(
            trade_id,
            big,
            "test.jpg".to_string(),
            "image/jpeg".to_string(),
        )
        .await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn unsupported_mime_is_rejected() {
        let trade_id = uuid::Uuid::new_v4().to_string();
        let result = send_file(
            trade_id,
            vec![1, 2, 3],
            "test.bin".to_string(),
            "application/octet-stream".to_string(),
        )
        .await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn mark_as_read_updates_count() {
        let trade_id = uuid::Uuid::new_v4().to_string();

        // Simulate an incoming message (not is_mine)
        let store = message_store();
        let incoming = ChatMessage {
            id: uuid::Uuid::new_v4().to_string(),
            trade_id: trade_id.clone(),
            sender_pubkey: "peer".to_string(),
            content: "incoming".to_string(),
            message_type: MessageType::Peer,
            is_mine: false,
            is_read: false,
            has_attachment: false,
            attachment: None,
            created_at: unix_now(),
        };
        store.add_message(incoming).await;

        // Assert on THIS trade's messages, not the global unread counter:
        // the store is a process-wide singleton and other tests add unread
        // messages concurrently, so global comparisons are racy (this
        // exact flake took CI down on PR #247).
        let unread_before = get_messages(trade_id.clone())
            .await
            .unwrap()
            .iter()
            .filter(|m| !m.is_read)
            .count();
        assert_eq!(unread_before, 1);

        mark_as_read(trade_id.clone()).await.unwrap();

        let unread_after = get_messages(trade_id)
            .await
            .unwrap()
            .iter()
            .filter(|m| !m.is_read)
            .count();
        assert_eq!(unread_after, 0);
    }

    #[test]
    fn safe_filename_strips_path_traversal() {
        assert_eq!(safe_filename("../../../etc/passwd"), "passwd");
        assert_eq!(safe_filename("/etc/passwd"), "passwd");
        assert_eq!(safe_filename("normal.jpg"), "normal.jpg");
        assert_eq!(safe_filename(""), "attachment");
        assert_eq!(safe_filename("/"), "attachment");
    }

    #[tokio::test]
    async fn send_file_fails_without_session() {
        let trade_id = uuid::Uuid::new_v4().to_string();
        let result = send_file(
            trade_id,
            vec![1, 2, 3],
            "photo.jpg".to_string(),
            "image/jpeg".to_string(),
        )
        .await;
        assert!(result.is_err());
        let msg = result.unwrap_err().to_string();
        assert!(msg.contains("SessionNotFound"), "got: {msg}");
    }

    #[tokio::test]
    async fn download_attachment_fails_without_session() {
        let trade_id = uuid::Uuid::new_v4().to_string();
        let store = message_store();
        let msg_id = uuid::Uuid::new_v4().to_string();
        let fake_att = AttachmentInfo {
            file_name: "file.jpg".to_string(),
            mime_type: "image/jpeg".to_string(),
            file_size: 100,
            file_type: FileType::Image,
            download_status: DownloadStatus::Pending,
            local_path: None,
        };
        let msg = ChatMessage {
            id: msg_id.clone(),
            trade_id: trade_id.clone(),
            sender_pubkey: "peer".to_string(),
            content: "https://blossom.example.com/abc123".to_string(),
            message_type: MessageType::Peer,
            is_mine: false,
            is_read: false,
            has_attachment: true,
            attachment: Some(fake_att),
            created_at: unix_now(),
        };
        store.add_message(msg).await;

        let result = download_attachment(msg_id).await;
        assert!(result.is_err());
        let err = result.unwrap_err().to_string();
        assert!(err.contains("SessionNotFound"), "got: {err}");
    }

    #[test]
    fn mime_type_validation() {
        assert!(is_supported_mime_type("image/jpeg"));
        assert!(is_supported_mime_type("image/png"));
        assert!(is_supported_mime_type("video/mp4"));
        assert!(is_supported_mime_type("text/plain"));
        assert!(is_supported_mime_type("application/pdf"));
        assert!(!is_supported_mime_type("application/octet-stream"));
        assert!(!is_supported_mime_type("application/zip"));
    }

    /// Verify that the Rust message store does NOT deduplicate by id.
    ///
    /// Two `ChatMessage`s with the same `id` are both stored. Deduplication is
    /// the responsibility of the Dart layer (`_onIncomingMessage` checks `id`
    /// before appending to the local list).
    #[tokio::test]
    async fn add_duplicate_message_is_not_deduplicated_in_store() {
        let trade_id = uuid::Uuid::new_v4().to_string();
        let store = message_store();
        let msg = ChatMessage {
            id: "dup-id".to_string(),
            trade_id: trade_id.clone(),
            sender_pubkey: "peer".to_string(),
            content: "hi".to_string(),
            message_type: MessageType::Peer,
            is_mine: false,
            is_read: false,
            has_attachment: false,
            attachment: None,
            created_at: unix_now(),
        };
        // Add the same logical id twice (different objects).
        store.add_message(msg.clone()).await;
        store
            .add_message(ChatMessage {
                id: "dup-id".to_string(),
                ..msg
            })
            .await;

        let msgs = get_messages(trade_id).await.unwrap();
        // Both are stored at the Rust layer; dedup is in the Dart layer.
        // This test documents that the Rust store does NOT deduplicate —
        // so the Dart screen must check `id` before appending.
        assert_eq!(msgs.len(), 2);
    }

    #[test]
    fn token_bucket_sustains_the_spec_rate_and_burst() {
        use crate::rt::time::{Duration, Instant};

        let start = Instant::now();
        let mut bucket = TokenBucket::new(start);

        // Full burst available immediately.
        for i in 0..RATE_CAPACITY as u32 {
            assert!(bucket.try_take(start), "burst token {i} refused");
        }
        // Exhausted: the 61st in the same instant is refused.
        assert!(!bucket.try_take(start));

        // After 2 seconds one token has refilled (0.5/s), not two.
        let later = start + Duration::from_secs(2);
        assert!(bucket.try_take(later));
        assert!(!bucket.try_take(later));

        // A long quiet period refills only up to the cap.
        let much_later = start + Duration::from_secs(24 * 3600);
        for _ in 0..RATE_CAPACITY as u32 {
            assert!(bucket.try_take(much_later));
        }
        assert!(!bucket.try_take(much_later));
    }

    #[test]
    fn outer_id_lru_dedups_and_evicts_fifo() {
        let mut set = BoundedIdSet::new(2);
        assert!(set.insert("a"));
        assert!(!set.insert("a"), "duplicate must be refused");
        assert!(set.insert("b"));
        // Capacity 2: inserting c evicts a (FIFO)…
        assert!(set.insert("c"));
        assert!(set.insert("a"), "evicted id is acceptable again");
        // …which is exactly why this LRU carries no security requirement:
        // the durable inner-id dedup does.
    }

    #[test]
    fn chat_payload_parses_files_and_plaintext() {
        // Attachment pointer → content is the URL, attachment populated.
        let file = serde_json::json!({
            "url": "https://blossom.example.com/abc",
            "name": "receipt.jpg",
            "mime_type": "image/jpeg",
            "size": 12345,
            "type": "file",
        })
        .to_string();
        let (content, att) = parse_chat_payload(&file);
        assert_eq!(content, "https://blossom.example.com/abc");
        let att = att.expect("attachment expected");
        assert_eq!(att.file_name, "receipt.jpg");
        assert_eq!(att.file_size, 12345);
        assert!(matches!(att.file_type, FileType::Image));
        assert!(matches!(att.download_status, DownloadStatus::Pending));

        // Plaintext stays as-is.
        let (content, att) = parse_chat_payload("hola, ¿pagaste?");
        assert_eq!(content, "hola, ¿pagaste?");
        assert!(att.is_none());

        // JSON that is not a file pointer is displayed verbatim, not
        // misinterpreted.
        let (content, att) = parse_chat_payload(r#"{"type":"file","url":"x"}"#);
        assert_eq!(content, r#"{"type":"file","url":"x"}"#);
        assert!(att.is_none(), "incomplete pointer must not become an attachment");
    }

    #[test]
    fn bucket_is_bypassed_during_stored_catchup() {
        use crate::rt::time::Instant;

        // Pre-EOSE (catch-up): a backlog far above the burst size is all
        // accepted — dropping stored history would lose it permanently
        // because the cursor advances past it.
        let mut state = ChatRxState::new(ChatChannel::Peer, 0);
        assert!(!state.live);
        for _ in 0..(RATE_CAPACITY as u32 * 5) {
            assert!(state.budget_ok("order-x"));
        }
        assert_eq!(state.consecutive_rejected, 0);

        // Post-EOSE (live): the bucket meters normally.
        state.live = true;
        let now = Instant::now();
        state.bucket = TokenBucket::new(now);
        let mut accepted = 0;
        for _ in 0..(RATE_CAPACITY as u32 + 10) {
            if state.budget_ok("order-x") {
                accepted += 1;
            }
        }
        assert_eq!(accepted, RATE_CAPACITY as u32);
        assert!(state.consecutive_rejected > 0);
    }

    #[tokio::test]
    async fn quota_bounds_messages_and_bytes_per_trade() {
        let trade_id = uuid::Uuid::new_v4().to_string();
        let store = message_store();

        // Byte cap: one huge stored message + an incoming one that would
        // cross the byte quota.
        let _ = store
            .add_message(ChatMessage {
                id: uuid::Uuid::new_v4().to_string(),
                trade_id: trade_id.clone(),
                sender_pubkey: "peer".into(),
                content: "x".repeat(MAX_STORED_BYTES_PER_TRADE - 10),
                message_type: MessageType::Peer,
                is_mine: false,
                is_read: true,
                has_attachment: false,
                attachment: None,
                created_at: unix_now(),
            })
            .await;
        assert!(!store.quota_exceeded(&trade_id, 5).await);
        assert!(store.quota_exceeded(&trade_id, 50).await);

        // An untouched trade has room.
        let other = uuid::Uuid::new_v4().to_string();
        assert!(!store.quota_exceeded(&other, 1024).await);
    }

    #[test]
    fn chat_still_relevant_selects_only_live_trades() {
        use crate::api::types::*;
        let base = TradeInfo {
            id: "t".into(),
            order: OrderInfo {
                id: "o".into(),
                kind: OrderKind::Sell,
                status: OrderStatus::Active,
                amount_sats: None,
                fiat_amount: None,
                fiat_amount_min: None,
                fiat_amount_max: None,
                fiat_code: "VES".into(),
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
            counterparty_pubkey: "peer".into(),
            current_step: TradeStep::Buyer(BuyerStep::FiatSent),
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
        };
        assert!(chat_still_relevant(&base));

        let mut done = base.clone();
        done.outcome = Some(TradeOutcome::Success);
        assert!(!chat_still_relevant(&done));

        let mut no_peer = base.clone();
        no_peer.counterparty_pubkey = String::new();
        assert!(!chat_still_relevant(&no_peer));

        let mut canceled = base;
        canceled.order.status = OrderStatus::Canceled;
        assert!(!chat_still_relevant(&canceled));
    }

    #[tokio::test]
    async fn is_known_finds_messages_already_in_memory() {
        let trade_id = uuid::Uuid::new_v4().to_string();
        let store = message_store();
        let id = uuid::Uuid::new_v4().to_string();
        store
            .add_message(ChatMessage {
                id: id.clone(),
                trade_id: trade_id.clone(),
                sender_pubkey: "peer".to_string(),
                content: "hello".to_string(),
                message_type: MessageType::Peer,
                is_mine: false,
                is_read: false,
                has_attachment: false,
                attachment: None,
                created_at: unix_now(),
            })
            .await;

        assert!(store.is_known(&trade_id, &id).await.unwrap());
        assert!(!store.is_known(&trade_id, "unknown-id").await.unwrap());
    }

    #[tokio::test]
    async fn on_new_message_stream_fires_for_correct_trade() {
        let trade_id = uuid::Uuid::new_v4().to_string();
        let other_trade = uuid::Uuid::new_v4().to_string();

        let mut stream = on_new_message(trade_id.clone()).await.unwrap();

        // Fire a message for a different trade — should not be delivered.
        let unrelated = ChatMessage {
            id: uuid::Uuid::new_v4().to_string(),
            trade_id: other_trade.clone(),
            sender_pubkey: "peer".to_string(),
            content: "noise".to_string(),
            message_type: MessageType::Peer,
            is_mine: false,
            is_read: false,
            has_attachment: false,
            attachment: None,
            created_at: unix_now(),
        };
        message_store().add_message(unrelated).await;

        // Now fire one for our trade.
        let target = ChatMessage {
            id: uuid::Uuid::new_v4().to_string(),
            trade_id: trade_id.clone(),
            sender_pubkey: "peer".to_string(),
            content: "hello".to_string(),
            message_type: MessageType::Peer,
            is_mine: false,
            is_read: false,
            has_attachment: false,
            attachment: None,
            created_at: unix_now(),
        };
        message_store().add_message(target.clone()).await;

        let received = stream.next().await.expect("should receive a message");
        assert_eq!(received.trade_id, trade_id);
        assert_eq!(received.content, "hello");
    }
}
