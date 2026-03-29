# Contract: Messages API

**Module**: `rust/src/api/messages.rs`

Encrypted peer-to-peer messaging during trades. P2P chat uses sharedKey
(ECDH-derived). Admin/dispute chat uses tradeKey (BIP-32 derived). All
messages are NIP-59 Gift Wrapped. Messages persist locally after decryption.
Supports encrypted file attachments via Blossom servers.

## Functions

### send_message(trade_id: String, content: String) → ChatMessage
Send an encrypted message to the trade counterparty.

**Validation**: `content` MUST not be empty. Trade MUST be active.

**Side effects**: Encrypts via NIP-59, publishes to relays. If offline,
queues in MessageQueue for delivery on reconnection.

**Errors**: `NoActiveTrade`, `TradeNotFound`, `MessageEmpty`.

---

### get_messages(trade_id: String) → Vec<ChatMessage>
Get all messages for a trade, ordered by creation time.

**Returns**: Locally persisted messages for the specified trade.

---

### mark_as_read(trade_id: String) → ()
Mark all messages in a trade as read.

**Side effects**: Updates `is_read` flag on all unread messages for
the trade. Emits on unread count stream.

---

### get_unread_count() → u32
Get total unread message count across all trades.

## Streams

### on_new_message(trade_id: String) → Stream<ChatMessage>
Emits when a new message is received for the specified trade.

### on_unread_count_changed() → Stream<u32>
Emits when the global unread message count changes.

---

## File Attachment Functions

### send_file(trade_id: String, file_bytes: Vec<u8>, file_name: String, mime_type: String) → ChatMessage
Encrypt and upload a file attachment, then send as a chat message.

**Validation**:
- File size MUST not exceed 25MB.
- `mime_type` MUST be a supported type (image/*, application/pdf,
  text/*, video/*).
- Trade MUST be active.

**Flow**:
1. Encrypt file with ChaCha20-Poly1305 (random nonce, key derived from
   sharedKey for P2P messages or tradeKey for admin/dispute messages).
2. Upload encrypted blob to Blossom server.
3. Send Blossom URL + encryption metadata as NIP-59 Gift Wrapped message.

**Returns**: ChatMessage with `has_attachment: true` and attachment metadata.

**Errors**: `FileTooLarge`, `UnsupportedFileType`, `UploadFailed`,
`NoActiveTrade`.

---

### download_attachment(message_id: String) → FileDownloadResult
Download and decrypt a file attachment.

**Returns**:
```text
FileDownloadResult {
  local_path: String    # Path to decrypted file on device
  file_name: String
  mime_type: String
  file_size: u64
}
```

**Errors**: `AttachmentNotFound`, `DownloadFailed`, `DecryptionFailed`.

---

### get_attachment_status(message_id: String) → AttachmentStatus?
Get download status of an attachment.

## Attachment Streams

### on_attachment_progress(message_id: String) → Stream<f64>
Emits download/upload progress (0.0 to 1.0).
