# Contract: Messages API

**Module**: `rust/src/api/messages.rs`

Encrypted peer-to-peer messaging during trades, over the **chat envelope**
of the protocol spec (<https://mostro.network/protocol/chat.html>, issue
#246): a kind 14 outer event signed with `K_sign` and `p`-tagged to
`pub(K_conv)` — both HKDF-SHA256 derivations of the trade-key ECDH secret —
carrying a NIP-44 encrypted kind 1 inner event signed by the sender's trade
key. NIP-59 gift wrap (kind 1059) is **not spoken in either direction** on
this channel: its random ephemeral authors made third-party flooding
unattributable (#246), and the protocol spec now defines the envelope as
the only chat transport.

Admin/dispute chat uses the **same chat envelope**, keyed to the solver's
pubkey (from `admin-took-dispute`) instead of the counterparty's trade key
(<https://mostro.network/protocol/dispute_chat.html>, which states it
carries "no gift wrap and no ephemeral key").

> **Interop note.** An earlier revision of this contract mandated a
> gift-wrap dual read/write on the dispute channel until
> `LEGACY_CHAT_DEPRECATION_TS` (2026-12-31T00:00:00Z), because the solver
> client (mostrix) still writes kind 1059 — its migration is mostrix#102.
> That dual path, and the constant, were removed when this client dropped
> every protocol-v1 path: the cutoff is now "protocol v2 only, always"
> rather than a date. Until mostrix#102 ships, a solver replying in the
> legacy shape is not visible here and evidence sent from here does not
> reach a gift-wrap-only solver. This is a known, accepted interop gap,
> not an oversight.

Each channel keeps its **own** durable `since` cursor
(`chat_cursor:<order>` for peer, `chat_cursor:dispute-<order>` for
dispute) and its own subscription ids, so the two independent streams can
never suppress or tear down each other. Messages persist locally after
validation; the `since` cursor advances only past durably persisted
messages. Supports encrypted file attachments via Blossom servers.

**Security requirements implemented** (see the protocol spec for the
normative list):

- Subscription pinned to `authors = [pub(K_sign)]`, bounded by a persisted
  per-order `since` cursor (clamped to the local clock) plus a `limit`.
- Cheapest-check-first validation; no signature or decryption work before
  the outer-id LRU and the rate-limit budget (token bucket, 30 msg/min
  sustained, burst 60; sustained violation marks the conversation flooded
  and halts chat processing while the trade stays operational).
- Inner signature verified and its author checked against the two trade
  keys of the order — the only sender authentication.
- Durable replay dedup on the inner event id (`messages` table on native,
  IndexedDB on web), **fail-closed**: a dedup lookup error drops the event.
- The rate budget meters only the live stream (post-EOSE); stored catch-up
  is bounded by the filter `limit` instead, so history above the burst size
  is never dropped.
- The cursor advances only past durably stored messages.
- Per-trade retention quotas (message count and total bytes) bound durable
  growth even at a legitimate send rate.
- Send-side size validation: a message whose encrypted envelope no receiver
  would accept fails with a stable `MessageTooLarge` error; each inner event
  carries a signed uniqueness nonce so identical same-second sends keep
  distinct ids.
- Subscription lifecycle: one task per order (spawn guard), explicit
  subscription ids unsubscribed on every exit, no idle timeout, and
  automatic resubscription of persisted active trades when the relay pool
  comes online.
- Isolation: chat runs on its own task and bounded channels; it can never
  block the order state machine, the daemon transport, or a dispute.
- Push wake: once a peer message or attachment pointer reached the relays,
  the sender asks the push server to ring the counterparty's trade pubkey,
  debounced per peer and fire-and-forget (`contracts/push.md`, *Peer wake*).
  The dispute channel does not.

## Functions

### send_message(trade_id: String, content: String) → ChatMessage
Send an encrypted message to the trade counterparty.

**Validation**: `content` MUST not be empty. Trade MUST be active.

**Side effects**: Wraps in the chat envelope (inner kind 1 signed by the
trade key, outer kind 14 signed with `K_sign`), publishes to relays. The
stored message id is the inner event id, so both sides dedup on the same
identity. A missing session is first **rebuilt from the trade row** (the
durable peer record, #381): index + counterparty from the row, ECDH
re-derived, session re-cached — gated by the same liveness/poison guard
as the startup resubscription. Only when the row cannot serve it either
(no row, peer not yet revealed, terminal or poisoned row, web #233) does
the message degrade to local-only storage with a warning; a relay-pool
failure also degrades to local-only.

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

### on_any_new_message() → AnyMessageStream
Incoming unread peer and solver messages across all trades for in-app notification
cards. Delivery is **at least once**: the stream reconciles from persisted unread
messages at startup, after broadcast lag, and every 60 seconds, even when no new
relay message arrives. This recovers interrupted or failed Dart card writes without
bypassing the protocol's durable message deduplication. Recovery includes messages
whose trade no longer has a live subscription. Already-read messages and the user's
own messages are excluded; cached read state is checked again before delivery.

Dart atomically records the message id in its processed-event ledger with the card
update, including events deliberately suppressed by preferences, identity cutoff,
or an open chat. Repeated deliveries must preserve read/delete state. Card writes,
reads and deletes commit and publish in invocation order. Mark-read operates on the
latest persisted record even before UI hydration; a read during event processing
suppresses that pending event, even if the user has since left the chat.

### on_unread_count_changed() → Stream<u32>
Emits when the global unread message count changes.

---

## File Attachment Functions

### send_file(trade_id: String, file_bytes: Vec<u8>, file_name: String, upload_id: String) → ChatMessage
Encrypt and upload an image or PDF, then send it in the P2P chat (#589).

**Validation**:
- JPEG, PNG or PDF, recognised by content; ≤ 25MB.
- The counterpart must be known (the order was taken).

**Flow**:
1. Images are decoded and re-encoded (orientation applied, EXIF dropped).
2. Encrypt with ChaCha20-Poly1305: random nonce, key = raw ECDH x-coordinate
   between our trade key and the peer's (v1's key; not the SHA-256 NIP-04 form).
3. Upload the blob: `PUT {server}/upload`, `application/octet-stream`,
   kind 24242 auth signed by a throwaway key. First accepting server of
   v1's list wins; the URL is `{server}/{sha256}`. The blob is cached.
4. Send v1's JSON message through the chat envelope:
   `{"type":"image_encrypted","blossom_url","nonce","mime_type","original_size","width","height","filename","encrypted_size"}`
   for images, `{"type":"file_encrypted","file_type":"document",…}` for PDFs.

`on_attachment_progress(upload_id)` reports 0.1 prepared, 0.3 encrypted,
0.9 uploaded, 1.0 sent.

**Returns**: ChatMessage with `has_attachment: true`; `content` is the file name.

**Errors**: `FileTooLarge`, `UnsupportedFileType`, `InvalidImage`,
`PeerUnknown`, `UploadFailed`, `SendFailed`, `SessionNotFound` (only when
the session is absent AND the trade row cannot rebuild it — see
`send_message`; #381).

---

### download_attachment(message_id: String) → AttachmentData
Fetch and decrypt an attachment, in memory.

The encrypted blob comes from the cache or from Blossom — verified against
the hash in its URL, then cached (still encrypted). Decrypted with the key of
the conversation it arrived in: the peer's (P2P chat) or the solver's
(dispute chat) — for the solver's own messages, their authenticated sender,
so a resolved dispute's history stays openable. Nothing decrypted is written
to disk. The encrypted blob is cached only while the identity that started
the transfer is still active: one deleted mid-transfer is not written back. The key is read from
the trade row when no session is live, so a finished trade's attachments stay
openable after a restart. Any failure sets the attachment's status to `Failed`.

**Returns**:
```text
AttachmentData {
  bytes: Vec<u8>        # The decrypted file
  file_name: String     # Sanitized
  mime_type: String     # Sniffed (JPEG/PNG/PDF), else the declared one
}
```

**Errors**: `AttachmentNotFound`, `PeerUnknown`, `DownloadFailed`, `DecryptionFailed`,
`SessionNotFound` (only when no session is live AND no trade row exists —
the row is used whatever the trade's status, unlike `send_message`).

---

### get_attachment_status(message_id: String) → AttachmentStatus?
Get download status of an attachment.

## Attachment Streams

### on_attachment_progress(message_id: String) → Stream<f64>
Emits progress (0.0 to 1.0): the download of `message_id`, or the send of the
`upload_id` given to `send_file`.
