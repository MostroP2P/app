/// Messages API — encrypted P2P chat during trades.
///
/// P2P chat uses the ECDH-derived shared key (NIP-44 v2).
/// Admin/dispute chat uses the BIP-32 trade key.
/// All outbound messages are NIP-59 Gift Wrapped.
/// Messages persist locally (in-memory until DB layer is wired in Phase 10+).
///
/// Streams: `on_new_message(trade_id)`, `on_unread_count_changed()`,
/// `on_attachment_progress(message_id)`.
use anyhow::{anyhow, bail, Result};
use std::collections::HashMap;
use std::sync::{Arc, OnceLock};
use tokio::sync::{broadcast, RwLock};

use crate::api::types::{
    AttachmentInfo, ChatMessage, DownloadStatus, FileType, MessageType,
};
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
    /// Messages keyed by trade_id.
    messages: Arc<RwLock<HashMap<String, Vec<ChatMessage>>>>,
    /// Broadcast channel for new messages (payload = trade_id of new message).
    new_message_tx: broadcast::Sender<ChatMessage>,
    /// Broadcast channel for global unread count changes.
    unread_tx: broadcast::Sender<u32>,
    /// Broadcast channel for attachment progress (payload = (message_id, progress 0.0–1.0)).
    attachment_tx: broadcast::Sender<(String, f64)>,
}

impl MessageStore {
    fn new() -> Self {
        let (new_message_tx, _) = broadcast::channel(64);
        let (unread_tx, _) = broadcast::channel(16);
        let (attachment_tx, _) = broadcast::channel(64);
        Self {
            messages: Arc::new(RwLock::new(HashMap::new())),
            new_message_tx,
            unread_tx,
            attachment_tx,
        }
    }

    async fn add_message(&self, msg: ChatMessage) {
        {
            let mut store = self.messages.write().await;
            store
                .entry(msg.trade_id.clone())
                .or_default()
                .push(msg.clone());
        }
        let _ = self.new_message_tx.send(msg.clone());
        let unread = self.unread_count_inner().await;
        let _ = self.unread_tx.send(unread);
    }

    async fn get_messages(&self, trade_id: &str) -> Vec<ChatMessage> {
        let store = self.messages.read().await;
        store
            .get(trade_id)
            .cloned()
            .unwrap_or_default()
    }

    async fn mark_as_read(&self, trade_id: &str) {
        let mut store = self.messages.write().await;
        if let Some(msgs) = store.get_mut(trade_id) {
            for m in msgs.iter_mut() {
                m.is_read = true;
            }
        }
        drop(store);
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

/// Send an encrypted text message to the trade counterparty.
///
/// Validates that `content` is non-empty. Encrypts via NIP-59 and publishes
/// to relays. If offline, the message is queued (queue wired in Phase 10+).
///
/// Returns the sent `ChatMessage` (with `is_mine: true`).
pub async fn send_message(trade_id: String, content: String) -> Result<ChatMessage> {
    if content.trim().is_empty() {
        bail!("MessageEmpty: content must not be empty");
    }
    if trade_id.trim().is_empty() {
        bail!("TradeNotFound: trade_id must not be empty");
    }

    let now = unix_now();

    // Look up session to get peer pubkey and trade key index.
    // If no session exists (e.g. order not yet active), fall back to local-only.
    let session = crate::mostro::session::session_manager()
        .get_session(&trade_id)
        .await;

    let (sender_pubkey, publish_result) = if let Some(ref s) = session {
        let sender_keys = crate::api::identity::get_active_trade_keys(s.trade_key_index).await;
        let sender_pubkey = sender_keys
            .as_ref()
            .map(|k| k.public_key().to_hex())
            .unwrap_or_default();

        let result = match (&sender_keys, &s.peer_pubkey) {
            (Err(e), _) => Err(anyhow!("key retrieval failed: {e}")),
            (Ok(_), None) => {
                log::warn!("[messages] session exists but peer not yet known — local-only");
                Ok(())
            }
            (Ok(keys), Some(peer_hex)) => match nostr_sdk::PublicKey::from_hex(peer_hex) {
                Err(e) => Err(anyhow!("invalid peer pubkey: {e}")),
                Ok(peer_pubkey) => {
                    let payload = serde_json::json!({ "text": content }).to_string();
                    match crate::nostr::gift_wrap::wrap(
                        keys,
                        &peer_pubkey,
                        &payload,
                        nostr_sdk::Kind::from(14u16),
                    )
                    .await
                    {
                        Err(e) => Err(anyhow!("gift wrap failed: {e}")),
                        Ok(event_json) => {
                            if let Ok(pool) = crate::api::nostr::get_pool() {
                                match serde_json::from_str::<nostr_sdk::Event>(&event_json) {
                                    Ok(event) => pool
                                        .client()
                                        .send_event(&event)
                                        .await
                                        .map(|_| ())
                                        .map_err(|e| anyhow!("publish failed: {e}")),
                                    Err(e) => Err(anyhow!("event parse failed: {e}")),
                                }
                            } else {
                                log::warn!("[messages] relay pool not ready — message stored locally");
                                Ok(())
                            }
                        }
                    }
                }
            },
        };

        (sender_pubkey, result)
    } else {
        log::warn!("[messages] no session for trade={trade_id} — local-only");
        (String::new(), Ok(()))
    };

    if let Err(e) = publish_result {
        log::warn!("[messages] send_message trade={trade_id}: {e}");
    }

    let msg = ChatMessage {
        id: uuid::Uuid::new_v4().to_string(),
        trade_id: trade_id.clone(),
        sender_pubkey,
        content,
        message_type: MessageType::Peer,
        is_mine: true,
        is_read: true,
        has_attachment: false,
        attachment: None,
        created_at: now,
    };

    message_store().add_message(msg.clone()).await;
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
        bail!("FileTooLarge: {} bytes exceeds 25 MB limit", file_bytes.len());
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
        let sender_keys =
            crate::api::identity::get_active_trade_keys(trade_key_index).await?;
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

    // 4. Build attachment metadata and publish via NIP-59 gift wrap.
    let payload = serde_json::json!({
        "url": blossom_url,
        "name": file_name,
        "mime_type": mime_type,
        "size": file_size,
        "type": "file",
    })
    .to_string();

    let sender_keys =
        crate::api::identity::get_active_trade_keys(trade_key_index).await?;
    let sender_pubkey = sender_keys.public_key().to_hex();

    if let Some(peer_hex) = &peer_pubkey_hex {
        match nostr_sdk::PublicKey::from_hex(peer_hex) {
            Err(e) => log::warn!("[messages] send_file invalid peer pubkey: {e}"),
            Ok(peer_pubkey) => match crate::nostr::gift_wrap::wrap(
                &sender_keys,
                &peer_pubkey,
                &payload,
                nostr_sdk::Kind::from(14u16),
            )
            .await
            {
                Err(e) => log::warn!("[messages] send_file gift wrap failed: {e}"),
                Ok(event_json) => match crate::api::nostr::get_pool() {
                    Err(_) => log::warn!("[messages] send_file relay pool not ready"),
                    Ok(pool) => match serde_json::from_str::<nostr_sdk::Event>(&event_json) {
                        Err(e) => log::warn!("[messages] send_file event parse failed: {e}"),
                        Ok(event) => {
                            if let Err(e) = pool.client().send_event(&event).await {
                                log::warn!("[messages] send_file publish failed: {e}");
                            }
                        }
                    },
                },
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

    let now = unix_now();
    let msg = ChatMessage {
        id: msg_id.clone(),
        trade_id: trade_id.clone(),
        sender_pubkey,
        content: blossom_url,
        message_type: MessageType::Peer,
        is_mine: true,
        is_read: true,
        has_attachment: true,
        attachment: Some(attachment),
        created_at: now,
    };

    message_store().add_message(msg.clone()).await;
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

    // 5. Write to temp dir with unique filename to avoid collisions.
    let safe_name = safe_filename(&attachment.file_name);
    let unique_name = format!("{message_id}_{safe_name}");
    let local_path = std::env::temp_dir()
        .join(&unique_name)
        .to_string_lossy()
        .into_owned();

    tokio::fs::write(&local_path, &plaintext)
        .await
        .map_err(|e| anyhow!("WriteFailed: {e}"))?;

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

fn unix_now() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

/// Strip directory components from a caller-supplied file name to prevent
/// path traversal (e.g. `../../../etc/passwd` → `passwd`).
/// Returns `"attachment"` for empty or path-only inputs.
fn safe_filename(name: &str) -> String {
    std::path::Path::new(name)
        .file_name()
        .and_then(|n| n.to_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("attachment")
        .to_string()
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

#[cfg(test)]
mod tests {
    use super::*;

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

        let count_before = get_unread_count().await.unwrap();
        mark_as_read(trade_id.clone()).await.unwrap();
        let count_after = get_unread_count().await.unwrap();
        assert!(count_after < count_before || count_after == 0);
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
}
