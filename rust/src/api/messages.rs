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
/// Reactions (protocol chat.md, "Reactions") are inner kind 7 events. They are
/// stored on the message they answer, never as messages of their own, and
/// reach the screen through `on_message_updated`: they count as no unread,
/// raise no notification and wake nobody.
///
/// Streams: `on_new_message(trade_id)`, `on_message_updated(trade_id)`,
/// `on_unread_count_changed()`, `on_attachment_progress(message_id)`.
use anyhow::{anyhow, bail, Result};
use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, OnceLock};
use tokio::sync::{broadcast, RwLock};

use crate::api::types::{AttachmentInfo, ChatMessage, ChatReaction, DownloadStatus, MessageType};
use crate::db::Storage;
use crate::nostr::blossom;

// ── Types ────────────────────────────────────────────────────────────────────

/// A decrypted attachment, returned by [`download_attachment`].
///
/// Handed over in memory: the plaintext never touches the disk here. Dart
/// renders it, or writes a temporary file only for an explicit "open with…".
#[derive(Debug, Clone)]
pub struct AttachmentData {
    pub bytes: Vec<u8>,
    pub file_name: String,
    /// What the bytes are, sniffed after decrypting (JPEG, PNG, PDF); for any
    /// other type, the MIME the sender declared — or `application/octet-stream`
    /// when the sender declared JPEG, PNG or PDF and the bytes are not.
    pub mime_type: String,
}

// ── Message store ─────────────────────────────────────────────────────────────

/// Per trade, the reactions whose targets are not stored yet.
type HeldReactions = HashMap<String, VecDeque<HeldReaction>>;

/// A reaction waiting for its target.
#[derive(Debug, Clone)]
struct HeldReaction {
    target_id: String,
    reaction: ChatReaction,
    /// The peer chat's cursor when it arrived. The cursor stays there until
    /// the reaction is stored: its target is older than the reaction and
    /// not here yet, so a restart must fetch both again.
    floor: i64,
    /// When it was first held, by our clock: past [`HELD_FLOOR_SECS`] it no
    /// longer holds the cursor back.
    held_at: i64,
}

/// How long a held reaction keeps the peer cursor back. A target served in
/// the same catch-up arrives within seconds; one that has not come by then
/// (refused by the retention quota, or an id that names nothing) must not
/// pin the cursor for the life of the trade, refetching every later event on
/// each start. Past it the reaction stays held, and still lands if its
/// target comes.
const HELD_FLOOR_SECS: i64 = 600;

/// How long a quiet chat waits before re-checking its cursor (an expired
/// held-reaction floor).
const CURSOR_RECHECK: crate::rt::time::Duration = crate::rt::time::Duration::from_secs(60);

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
    /// Broadcast channel for a stored message that changed: today, a reaction
    /// to it. Kept apart from `new_message_tx`, which feeds unread counts and
    /// notifications.
    updated_tx: broadcast::Sender<ChatMessage>,
    /// Reactions whose target has not arrived yet, per trade: catch-up does
    /// not keep order, and relays usually serve the newest event first.
    /// Memory only and bounded by [`MAX_HELD_REACTIONS_PER_TRADE`].
    held_reactions: Arc<RwLock<HeldReactions>>,
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
        let (updated_tx, _) = broadcast::channel(64);
        let (unread_tx, _) = broadcast::channel(16);
        let (attachment_tx, _) = broadcast::channel(64);
        Self {
            messages: Arc::new(RwLock::new(HashMap::new())),
            non_durable: Arc::new(RwLock::new(std::collections::HashSet::new())),
            hydrated: Arc::new(RwLock::new(std::collections::HashSet::new())),
            new_message_tx,
            updated_tx,
            held_reactions: Arc::new(RwLock::new(HashMap::new())),
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
    async fn add_message(&self, mut msg: ChatMessage) -> bool {
        // Hydrate first so the persisted history is not masked by a fresher
        // in-memory entry created before the first read.
        self.ensure_hydrated(&msg.trade_id).await;
        // Folding in the held reactions, storing and persisting happen under
        // one write lock, taken before the held reactions' (the order
        // `apply_reaction` uses too): a reaction arriving meanwhile is either
        // held before this drains it, or finds the message — never neither —
        // and no other write of this message reaches the database between.
        let stored = {
            let mut store = self.messages.write().await;
            let folded = self.fold_held_reactions(&mut msg).await;
            store
                .entry(msg.trade_id.clone())
                .or_default()
                .push(msg.clone());
            // Write-through: chat history and the durable replay dedup both
            // live in the `messages` table. Failure is logged, never
            // propagated — a full disk must not take the chat (let alone the
            // trade) down.
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
            // Not durable yet: the folded reactions keep holding the cursor
            // back, or a later event could carry it past them and their
            // target. They are folded again on the retry.
            if !stored && !folded.is_empty() {
                self.held_reactions
                    .write()
                    .await
                    .entry(msg.trade_id.clone())
                    .or_default()
                    .extend(folded);
            }
            // Recorded before the lock goes, with the write it describes:
            // another write of this row can't slip in between and be
            // undone by this one's outcome.
            self.note_durability(&msg.trade_id, &msg.id, stored).await;
            stored
        };
        let _ = self.new_message_tx.send(msg.clone());
        let unread = self.unread_count_inner().await;
        let _ = self.unread_tx.send(unread);
        stored
    }

    /// Keep memory-only ids distinct from durably committed ones — the
    /// receive path consults this before advancing the cursor.
    ///
    /// A stored row also carries every reaction held again when an earlier
    /// write of it failed (they were folded into it in memory): those stop
    /// holding the cursor back, whichever write stored it.
    async fn note_durability(&self, trade_id: &str, id: &str, durable: bool) {
        if durable {
            self.non_durable.write().await.remove(id);
            if let Some(list) = self.held_reactions.write().await.get_mut(trade_id) {
                list.retain(|h| h.target_id != id);
            }
        } else {
            self.non_durable.write().await.insert(id.to_string());
        }
    }

    /// Whether a message of `trade_id` is in memory only: its write failed and
    /// no retry has stored it yet.
    async fn has_unsaved(&self, trade_id: &str) -> bool {
        // Copied out, so `non_durable` is never held while waiting for
        // `messages`: writers take them the other way round.
        let unsaved = self.non_durable.read().await.clone();
        if unsaved.is_empty() {
            return false;
        }
        self.messages
            .read()
            .await
            .get(trade_id)
            .is_some_and(|msgs| msgs.iter().any(|m| unsaved.contains(&m.id)))
    }

    /// Fold a reaction into the message `target_id` of `trade_id`, persist the
    /// message and announce it on `updated_tx`. `floor` is the chat's cursor
    /// when it arrived, kept by [`Self::held_floor`] if the target is not
    /// here.
    async fn apply_reaction(
        &self,
        trade_id: &str,
        target_id: &str,
        reaction: ChatReaction,
        floor: i64,
    ) -> ReactionOutcome {
        self.ensure_hydrated(trade_id).await;
        let (updated, durable) = {
            let mut store = self.messages.write().await;
            let target = store
                .get_mut(trade_id)
                .and_then(|msgs| msgs.iter_mut().find(|m| m.id == target_id));
            let Some(target) = target else {
                // Still under the messages lock: `add_message` cannot store
                // the target between this miss and the hold.
                self.hold_reaction(trade_id, target_id, reaction, floor)
                    .await;
                return ReactionOutcome::Held;
            };
            if !reaction_allowed(target, &reaction) {
                return ReactionOutcome::Refused;
            }
            if !merge_reaction(&mut target.reactions, reaction) {
                return ReactionOutcome::Unchanged;
            }
            let updated = target.clone();
            // Saved under the lock, so the row written is the message as it
            // is now: a `mark_as_read` or another reaction waits for it
            // instead of being overwritten by an older copy.
            let durable = match crate::db::app_db::db() {
                Some(db) => match db.save_message(&updated).await {
                    Ok(()) => true,
                    Err(e) => {
                        log::warn!("[messages] persist reaction failed id={}: {e}", updated.id);
                        false
                    }
                },
                None => true,
            };
            // A failed write marks the message memory-only, so
            // `ensure_durable` retries it, reaction included, and the cursor
            // stays put meanwhile. Recorded under the lock, with the write.
            self.note_durability(trade_id, &updated.id, durable).await;
            (updated, durable)
        };
        let _ = self.updated_tx.send(updated.clone());
        ReactionOutcome::Applied {
            message: Box::new(updated),
            durable,
        }
    }

    /// Keep a reaction until its target arrives: one per party and target,
    /// the newest, so a re-wrapped copy takes no extra room. Past
    /// [`MAX_HELD_REACTIONS_PER_TRADE`] the oldest held goes: a target that
    /// never comes must not grow memory.
    async fn hold_reaction(
        &self,
        trade_id: &str,
        target_id: &str,
        reaction: ChatReaction,
        floor: i64,
    ) {
        let mut held = self.held_reactions.write().await;
        let list = held.entry(trade_id.to_string()).or_default();
        if let Some(kept) = list.iter_mut().find(|kept| {
            kept.target_id == target_id && kept.reaction.sender_pubkey == reaction.sender_pubkey
        }) {
            let mut one = vec![kept.reaction.clone()];
            if merge_reaction(&mut one, reaction) {
                kept.reaction = one.remove(0);
            }
            kept.floor = kept.floor.min(floor);
            return;
        }
        if list.len() >= MAX_HELD_REACTIONS_PER_TRADE {
            list.pop_front();
        }
        list.push_back(HeldReaction {
            target_id: target_id.to_string(),
            reaction,
            floor,
            held_at: unix_now(),
        });
    }

    /// The lowest cursor a reaction still held for `trade_id` arrived at: the
    /// peer chat's cursor must not pass it, or a restart before the target
    /// arrives loses the reaction, and the target too, which is older.
    async fn held_floor(&self, trade_id: &str) -> Option<i64> {
        self.held_floor_at(trade_id, unix_now()).await
    }

    /// [`Self::held_floor`] as of `now`: reactions held for longer than
    /// [`HELD_FLOOR_SECS`] no longer count.
    async fn held_floor_at(&self, trade_id: &str, now: i64) -> Option<i64> {
        let held = self.held_reactions.read().await;
        held.get(trade_id)?
            .iter()
            .filter(|h| now - h.held_at <= HELD_FLOOR_SECS)
            .map(|h| h.floor)
            .min()
    }

    /// Fold the reactions held for `msg` into it, and return them: they are
    /// held again if `msg` cannot be stored.
    async fn fold_held_reactions(&self, msg: &mut ChatMessage) -> Vec<HeldReaction> {
        let mine = {
            let mut held = self.held_reactions.write().await;
            let Some(list) = held.get_mut(&msg.trade_id) else {
                return Vec::new();
            };
            let (mine, rest): (VecDeque<_>, VecDeque<_>) =
                list.drain(..).partition(|h| h.target_id == msg.id);
            if rest.is_empty() {
                held.remove(&msg.trade_id);
            } else {
                *list = rest;
            }
            mine
        };
        for held in &mine {
            if reaction_allowed(msg, &held.reaction) {
                merge_reaction(&mut msg.reactions, held.reaction.clone());
            }
        }
        mine.into()
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
        // Under the write lock, like every other write of a message row: a
        // reaction or a read flag saved meanwhile is never put back by an
        // older copy, and the row written is the one the cursor relies on.
        let store = self.messages.write().await;
        let copy = store
            .get(trade_id)
            .and_then(|msgs| msgs.iter().find(|m| m.id == id).cloned());
        let (Some(db), Some(msg)) = (crate::db::app_db::db(), copy) else {
            return false;
        };
        // The outcome is recorded before the lock goes: a later write of
        // this row that fails cannot have its marker cleared by this success.
        let durable = match db.save_message(&msg).await {
            Ok(()) => {
                self.note_durability(trade_id, id, true).await;
                true
            }
            Err(e) => {
                log::warn!("[messages] persist retry failed id={id}: {e}");
                false
            }
        };
        drop(store);
        durable
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

    /// Reconcile notification delivery from storage, independently of relay
    /// dedup. Memory wins, including messages read since the DB query began.
    async fn notification_backlog(&self) -> Result<VecDeque<ChatMessage>> {
        let persisted = match crate::db::app_db::db() {
            Some(db) => db.list_unread_messages().await?,
            None => Vec::new(),
        };
        let mut by_id: HashMap<String, ChatMessage> =
            persisted.into_iter().map(|m| (m.id.clone(), m)).collect();
        for msg in self.messages.read().await.values().flatten() {
            if notification_candidate(msg) {
                by_id.insert(msg.id.clone(), msg.clone());
            } else {
                by_id.remove(&msg.id);
            }
        }
        let mut unread: Vec<_> = by_id.into_values().filter(notification_candidate).collect();
        unread.sort_by(|a, b| (a.created_at, &a.id).cmp(&(b.created_at, &b.id)));
        Ok(unread.into())
    }

    /// A queued clone may have been read while Dart processed an earlier
    /// event. Use the cache's fresh read flag before delivering it.
    async fn notification_candidate_now(&self, mut msg: ChatMessage) -> Option<ChatMessage> {
        if let Some(current) = self
            .messages
            .read()
            .await
            .get(&msg.trade_id)
            .and_then(|messages| messages.iter().find(|m| m.id == msg.id))
        {
            msg = current.clone();
        }
        notification_candidate(&msg).then_some(msg)
    }

    async fn mark_as_read(&self, trade_id: &str) {
        self.ensure_hydrated(trade_id).await;
        let mut store = self.messages.write().await;
        if let Some(msgs) = store.get_mut(trade_id) {
            for m in msgs.iter_mut() {
                m.is_read = true;
            }
        }
        // Written under the lock, like every other write of a message row:
        // on web the read flag is set by rewriting whole rows, which would
        // otherwise put back a copy taken before a reaction was saved.
        if let Some(db) = crate::db::app_db::db() {
            if let Err(e) = db.mark_messages_read(trade_id).await {
                log::warn!("[messages] mark_messages_read failed trade={trade_id}: {e}");
            }
        }
        drop(store);
        let unread = self.unread_count_inner().await;
        let _ = self.unread_tx.send(unread);
    }

    /// Drop every conversation held in memory and publish an unread count
    /// of zero. `hydrated` goes too, so a later read of the same trade id
    /// goes back to the database instead of trusting an emptied cache.
    async fn clear(&self) {
        self.messages.write().await.clear();
        self.hydrated.write().await.clear();
        self.non_durable.write().await.clear();
        self.held_reactions.write().await.clear();
        let _ = self.unread_tx.send(0);
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

/// Reactions held per trade while their targets have not arrived.
const MAX_HELD_REACTIONS_PER_TRADE: usize = 256;

/// What became of a reaction handed to [`MessageStore::apply_reaction`].
#[derive(Debug)]
enum ReactionOutcome {
    /// The target now carries it; `durable` as for `add_message`.
    Applied {
        message: Box<ChatMessage>,
        durable: bool,
    },
    /// Not newer than what the target holds from that party: a re-delivery,
    /// or a re-wrapped older reaction (chat.md, step 12).
    Unchanged,
    /// The target is not here yet: held until it arrives.
    Held,
    /// Not a reaction this chat shows: on the reactor's own message, or on a
    /// message that is not of the peer chat.
    Refused,
}

/// Whether `target` can show `reaction`: only the other party's messages of
/// the peer chat take one (chat.md, "Reactions").
fn reaction_allowed(target: &ChatMessage, reaction: &ChatReaction) -> bool {
    target.message_type == MessageType::Peer && target.sender_pubkey != reaction.sender_pubkey
}

/// Fold `reaction` into `reactions`: one per party, the newest holding and a
/// tie going to the lowest event id, so both sides settle on the same one
/// whatever order they received them in. `true` when `reactions` changed.
fn merge_reaction(reactions: &mut Vec<ChatReaction>, reaction: ChatReaction) -> bool {
    match reactions
        .iter_mut()
        .find(|held| held.sender_pubkey == reaction.sender_pubkey)
    {
        None => {
            reactions.push(reaction);
            true
        }
        Some(held) => {
            let newer = reaction.created_at > held.created_at
                || (reaction.created_at == held.created_at && reaction.event_id < held.event_id);
            if newer {
                *held = reaction;
            }
            newer
        }
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
    trade_keys: nostr_sdk::prelude::Keys,
    /// `K_conv` — NIP-44 encryption; `pub(K_conv)` is the `p` tag.
    conv: nostr_sdk::prelude::Keys,
    /// `K_sign` — outer-event author; what relays and clients filter on.
    sign: nostr_sdk::prelude::Keys,
}

/// Derive the conversation keys for a session's trade-key index and peer.
///
/// Cheap enough to derive on demand (one ECDH + two HKDF expands), which
/// keeps the secrets out of long-lived session state.
async fn chat_context(trade_key_index: u32, peer_hex: &str) -> Result<ChatContext> {
    let trade_keys = crate::api::identity::get_active_trade_keys(trade_key_index)
        .await
        .map_err(|e| anyhow!("key retrieval failed: {e}"))?;
    let peer_pubkey = nostr_sdk::prelude::PublicKey::from_hex(peer_hex)
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
    admin_pubkey: &nostr_sdk::prelude::PublicKey,
) -> Result<ChatContext> {
    chat_context(trade_key_index, &admin_pubkey.to_hex()).await
}

/// Publish over an already-built context. Exposed for the dispute channel,
/// which owns its own send path but must not reimplement the envelope.
pub(crate) async fn publish_chat_payload_for(
    ctx: &ChatContext,
    payload: &str,
) -> Result<nostr_sdk::prelude::Event> {
    publish_chat_payload(ctx, payload).await.map(|p| p.inner)
}

/// [`publish_chat_payload_for`] for a message that only counts once a relay
/// holds it, such as the chat key sent to a solver (#415): when none takes
/// it, it fails with `SendFailed` instead of being kept as sent.
pub(crate) async fn publish_delivered_chat_payload_for(
    ctx: &ChatContext,
    payload: &str,
) -> Result<nostr_sdk::prelude::Event> {
    let published = publish_chat_payload(ctx, payload)
        .await
        .map_err(|e| anyhow!("SendFailed: {e}"))?;
    if !published.delivered {
        bail!("SendFailed: no relay accepted the message");
    }
    Ok(published.inner)
}

/// A chat envelope handed to the pool.
struct PublishedChat {
    /// The signed inner event: the message's durable identity.
    inner: nostr_sdk::prelude::Event,
    /// Whether at least one relay accepted the envelope.
    delivered: bool,
}

/// The peer to wake after a publish, if any: only an envelope some relay
/// accepted is worth a wake. Waking for one that reached nobody rings the
/// peer for nothing and debounces the wake of the retry that does land.
fn peer_to_wake(delivered: bool, peer_hex: &str) -> Option<&str> {
    delivered.then_some(peer_hex)
}

/// Record a message we just sent to the solver, mirroring what `send_message`
/// stores for the peer chat: identified by the inner event id so the relay
/// echo dedups against it, and never unread (we wrote it). Returns it.
pub(crate) async fn store_outgoing_admin_message(
    trade_id: &str,
    ctx: &ChatContext,
    content: &str,
    inner: &nostr_sdk::prelude::Event,
) -> ChatMessage {
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
        reactions: Vec::new(),
    };
    let _ = message_store().add_message(msg.clone()).await;
    msg
}

async fn publish_chat_payload(ctx: &ChatContext, payload: &str) -> Result<PublishedChat> {
    let (outer, inner) =
        crate::nostr::transport::mostro_wrap(&ctx.trade_keys, &ctx.conv, &ctx.sign, payload)
            .await?;
    publish_wrapped(outer, inner).await
}

async fn publish_wrapped(
    outer: nostr_sdk::prelude::Event,
    inner: nostr_sdk::prelude::Event,
) -> Result<PublishedChat> {
    let pool = crate::api::nostr::get_pool().map_err(|_| anyhow!("relay pool not ready"))?;
    // Back on the first relay that accepts it: the message is in the
    // conversation from then on, and a relay that never answers no longer
    // holds it back for its 10 s timeout. The rest keep sending and logging.
    let delivered = match crate::nostr::publish::publish_event(&pool.client(), &outer).await {
        Ok(()) => true,
        // Nobody took it: kept, as before, under the id it would have had.
        Err(e) if e.to_string() == "NoRelayAccepted" => false,
        Err(e) => return Err(anyhow!("publish failed: {e}")),
    };
    Ok(PublishedChat { inner, delivered })
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

    // Look up session to get peer pubkey and trade key index — rebuilding it
    // from the trade row when absent (#381). Local-only remains the fallback
    // for trades the row cannot serve either (peer not yet revealed, web).
    let session = session_or_rebuild(&trade_id).await;

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
                        Ok(published) => {
                            id = published.inner.id.to_hex();
                            created_at = published.inner.created_at.as_secs() as i64;
                            // The envelope's `p` tag is `pub(K_conv)`, which
                            // the push server cannot match: ask it to ring the
                            // peer's trade key (docs/PUSH_NOTIFICATIONS.md §7.3).
                            if let Some(peer) = peer_to_wake(published.delivered, peer_hex) {
                                crate::api::push::wake_peer(peer);
                            }
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
        reactions: Vec::new(),
    };

    let _ = message_store().add_message(msg.clone()).await;
    Ok(msg)
}

/// React to the counterparty's message `message_id` with `emoji`, or withdraw
/// the reaction with an empty `emoji` (protocol chat.md, "Reactions").
///
/// Only a peer-chat message the counterparty wrote takes one. Unlike a
/// message, a reaction is not kept when no relay takes it — the counterparty
/// would never see it — and it wakes nobody.
///
/// Returns the message with the reaction applied; the same value reaches
/// `on_message_updated`. Errors carry a stable marker: `ReactionTooLarge`,
/// `MessageNotFound`, `ReactionNotAllowed` or `SendFailed`.
pub async fn send_reaction(
    trade_id: String,
    message_id: String,
    emoji: String,
) -> Result<ChatMessage> {
    if emoji.len() > crate::nostr::transport::MAX_REACTION_BYTES {
        bail!("ReactionTooLarge: {} bytes", emoji.len());
    }
    // One send at a time: each is dated after the reaction it replaces,
    // which only holds if the next one reads that reaction once applied.
    // Two taps in one second would otherwise share a date and be settled by
    // their ids, not their order.
    static SENDING: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
    let _sending = SENDING.lock().await;
    let target = message_store()
        .get_messages(&trade_id)
        .await
        .into_iter()
        .find(|m| m.id == message_id)
        .ok_or_else(|| anyhow!("MessageNotFound: {message_id}"))?;
    if target.message_type != MessageType::Peer || target.is_mine {
        bail!("ReactionNotAllowed: only the counterparty's messages take a reaction");
    }
    // A message that reached us has its inner id as id; nothing else can be
    // named by the counterparty.
    let target_id = nostr_sdk::prelude::EventId::from_hex(&message_id)
        .map_err(|_| anyhow!("ReactionNotAllowed: {message_id} is not an event id"))?;

    let session = session_or_rebuild(&trade_id)
        .await
        .ok_or_else(|| anyhow!("SendFailed: no session for trade {trade_id}"))?;
    let peer_hex = session
        .peer_pubkey
        .as_deref()
        .ok_or_else(|| anyhow!("SendFailed: counterparty not known yet"))?;
    let ctx = chat_context(session.trade_key_index, peer_hex)
        .await
        .map_err(|e| anyhow!("SendFailed: {e}"))?;
    let me = ctx.trade_keys.public_key().to_hex();

    // Strictly after our previous reaction to this message: two changes in
    // one second would otherwise be settled by their ids, not their order.
    let previous = target
        .reactions
        .iter()
        .find(|r| r.sender_pubkey == me)
        .map(|r| r.created_at);
    let created_at = reaction_time(unix_now(), previous)
        .ok_or_else(|| anyhow!("SendFailed: the previous reaction is dated too far ahead"))?;

    let (outer, inner) = crate::nostr::transport::mostro_wrap_reaction(
        &ctx.trade_keys,
        &ctx.conv,
        &ctx.sign,
        &target_id,
        &emoji,
        nostr_sdk::prelude::Timestamp::from_secs(created_at as u64),
    )
    .await?;
    let published = publish_wrapped(outer, inner)
        .await
        .map_err(|e| anyhow!("SendFailed: {e}"))?;
    if !published.delivered {
        bail!("SendFailed: no relay accepted the reaction");
    }

    let reaction = ChatReaction {
        sender_pubkey: me,
        emoji,
        created_at: published.inner.created_at.as_secs() as i64,
        event_id: published.inner.id.to_hex(),
    };
    match message_store()
        .apply_reaction(&trade_id, &message_id, reaction, created_at)
        .await
    {
        ReactionOutcome::Applied { message, .. } => Ok(*message),
        // Our own echo got here first, which already applied it.
        ReactionOutcome::Unchanged => message_store()
            .get_messages(&trade_id)
            .await
            .into_iter()
            .find(|m| m.id == message_id)
            .ok_or_else(|| anyhow!("MessageNotFound: {message_id}")),
        // Published, yet not shown: the message changed under us. Report it
        // as it stands rather than a failure that did not happen.
        ReactionOutcome::Held | ReactionOutcome::Refused => message_store()
            .get_messages(&trade_id)
            .await
            .into_iter()
            .find(|m| m.id == message_id)
            .ok_or_else(|| anyhow!("MessageNotFound: {message_id}")),
    }
}

/// When a new reaction is dated: now, or one second after the sender's
/// previous reaction to that message when that is later. `None` when that
/// would be further ahead of our clock than receivers accept
/// (`MAX_CLOCK_SKEW_SECS`): the previous one came from a device whose clock
/// runs ahead, or quick changes piled up. Publishing it anyway would show
/// here and be dropped by the counterparty.
fn reaction_time(now: i64, previous: Option<i64>) -> Option<i64> {
    let at = match previous {
        Some(previous) if previous >= now => previous + 1,
        _ => now,
    };
    let limit = now.saturating_add(crate::nostr::transport::MAX_CLOCK_SKEW_SECS as i64);
    (at <= limit).then_some(at)
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

/// Encrypt, upload and send an image or PDF in the P2P chat (#589).
///
/// 1. Check and clean it ([`crate::attachments::media::prepare_for_send`]):
///    JPEG, PNG or PDF by content, ≤ 25 MB; images re-encoded without EXIF.
/// 2. Encrypt with the attachment key — the raw ECDH with the peer, as v1.
/// 3. Upload the blob to Blossom and keep it, still encrypted, in the cache.
/// 4. Send the v1 JSON message (`image_encrypted` / `file_encrypted`).
///
/// `upload_id` is chosen by the caller: `on_attachment_progress(upload_id)`
/// reports 0.1 prepared, 0.3 encrypted, 0.9 uploaded, 1.0 sent.
///
/// Errors are markers: `FileTooLarge`, `UnsupportedFileType`, `InvalidImage`,
/// `SessionNotFound`, `PeerUnknown`, `UploadFailed`, `SendFailed`.
pub async fn send_file(
    trade_id: String,
    file_bytes: Vec<u8>,
    file_name: String,
    upload_id: String,
) -> Result<ChatMessage> {
    if trade_id.trim().is_empty() {
        bail!("TradeNotFound: trade_id must not be empty");
    }
    // The session — rebuilt from the trade row when absent (#381).
    let target = async {
        let session = session_or_rebuild(&trade_id)
            .await
            .ok_or_else(|| anyhow!("SessionNotFound: {trade_id}"))?;
        let counterpart_hex = session
            .peer_pubkey
            .clone()
            .ok_or_else(|| anyhow!("PeerUnknown: the counterpart has not taken the order yet"))?;
        Ok(AttachmentTarget {
            trade_key_index: session.trade_key_index,
            counterpart_hex,
            channel: ChatChannel::Peer,
        })
    };
    send_attachment(&trade_id, file_bytes, file_name, &upload_id, target).await
}

/// Who an attachment goes to: the counterpart its key and envelope are
/// shared with — the peer, or the solver in the dispute chat — and the
/// conversation it is filed under.
pub(crate) struct AttachmentTarget {
    pub(crate) trade_key_index: u32,
    pub(crate) counterpart_hex: String,
    pub(crate) channel: ChatChannel,
}

/// The send path shared by [`send_file`] and the dispute chat's
/// `send_dispute_file` (#589 phase 3); see [`send_file`] for the steps.
///
/// `target` is awaited only once the file passed its checks, so a file that
/// could never be sent is refused as such whatever the conversation's state.
pub(crate) async fn send_attachment(
    trade_id: &str,
    file_bytes: Vec<u8>,
    file_name: String,
    upload_id: &str,
    target: impl std::future::Future<Output = Result<AttachmentTarget>>,
) -> Result<ChatMessage> {
    use crate::attachments::payload::{AttachmentPayload, FilePayload, ImagePayload};

    let progress = |p: f64| {
        let _ = message_store()
            .attachment_tx
            .send((upload_id.to_string(), p));
    };
    let generation = crate::api::identity::identity_generation().await;

    // 1. What it is, decided by the bytes; images leave without metadata.
    let prepared = crate::attachments::media::prepare_for_send(file_bytes)?;
    progress(0.1);

    // 2. The conversation, and the key shared with whoever is on the other
    //    side of it.
    let target = target.await?;
    let counterpart = nostr_sdk::prelude::PublicKey::from_hex(&target.counterpart_hex)
        .map_err(|e| anyhow!("PeerUnknown: invalid counterpart pubkey: {e}"))?;
    let trade_keys = crate::api::identity::get_active_trade_keys(target.trade_key_index).await?;
    let key = crate::crypto::file_enc::attachment_key(&trade_keys, &counterpart)?;
    let encrypted = crate::crypto::file_enc::encrypt_file(&prepared.bytes, &key)
        .map_err(|e| anyhow!("FileEncryptionFailed: {e}"))?;
    progress(0.3);

    // 3. Upload, and keep our own copy so our bubble never downloads it.
    let encrypted_size = encrypted.len() as u64;
    let nonce_hex = hex::encode(&encrypted[..12]);
    let uploaded = blossom::upload_blob(encrypted.clone()).await?;
    let db = crate::db::app_db::db();
    cache_attachment_blob(db, generation, &uploaded.sha256, &encrypted).await;
    progress(0.9);

    // 4. The v1 message: JPEG/PNG as `image_encrypted`, the rest as
    //    `file_encrypted` (v1's `ChatFileUploadHelper` splits them the same way).
    let file_name = crate::attachments::media::sanitize_filename(&file_name);
    let mime_type = prepared.kind.mime().to_string();
    let original_size = prepared.bytes.len() as u64;
    let payload = match (prepared.width, prepared.height) {
        (Some(width), Some(height)) => AttachmentPayload::Image(ImagePayload {
            blossom_url: uploaded.url.clone(),
            nonce: nonce_hex,
            mime_type: mime_type.clone(),
            original_size,
            width,
            height,
            filename: file_name.clone(),
            encrypted_size,
        }),
        _ => AttachmentPayload::File(FilePayload {
            file_type: "document".to_string(),
            blossom_url: uploaded.url.clone(),
            nonce: nonce_hex,
            mime_type: mime_type.clone(),
            original_size,
            filename: file_name.clone(),
            encrypted_size,
        }),
    };

    let ctx = chat_context(target.trade_key_index, &target.counterpart_hex).await?;
    let published = publish_chat_payload(&ctx, &payload.to_json())
        .await
        .map_err(|e| anyhow!("SendFailed: {e}"))?;
    // Only the peer is a push client: the solver is never rung (see
    // CLAUDE.md, "Dispute chat must wake").
    if target.channel == ChatChannel::Peer {
        if let Some(peer) = peer_to_wake(published.delivered, &target.counterpart_hex) {
            crate::api::push::wake_peer(peer);
        }
    }
    progress(1.0);

    let attachment = AttachmentInfo {
        file_name: file_name.clone(),
        mime_type,
        file_size: original_size,
        file_type: prepared.kind.file_type(),
        // The encrypted blob is already in the cache.
        download_status: DownloadStatus::Downloaded,
        blossom_url: uploaded.url,
        sha256: uploaded.sha256,
        encrypted_size,
        width: prepared.width,
        height: prepared.height,
        counterpart_pubkey: Some(target.counterpart_hex.clone()),
    };
    // Identified by the inner event id, like `send_message`: the relay echo
    // and the recipient's replay dedup on it.
    let msg = ChatMessage {
        id: published.inner.id.to_hex(),
        trade_id: trade_id.to_string(),
        sender_pubkey: trade_keys.public_key().to_hex(),
        content: file_name,
        message_type: target.channel.message_type(),
        is_mine: true,
        is_read: true,
        has_attachment: true,
        attachment: Some(attachment),
        created_at: published.inner.created_at.as_secs() as i64,
        reactions: Vec::new(),
    };
    let _ = message_store().add_message(msg.clone()).await;
    Ok(msg)
}

/// Fetch and decrypt the attachment of `message_id` (#589).
///
/// The blob comes from the local cache, or from Blossom — verified against
/// the hash in its URL, then cached still encrypted. Decrypted in memory
/// with the key of the conversation it arrived in: the peer's for the P2P
/// chat, the solver's for the dispute chat. `on_attachment_progress(message_id)`
/// reports the download.
///
/// Errors are markers: `AttachmentNotFound`, `SessionNotFound`, `PeerUnknown`,
/// `DownloadFailed`, `DecryptionFailed`.
pub async fn download_attachment(message_id: String) -> Result<AttachmentData> {
    let msg = {
        let store = message_store().messages.read().await;
        store
            .values()
            .flat_map(|msgs| msgs.iter())
            .find(|m| m.id == message_id)
            .cloned()
            .ok_or_else(|| anyhow!("AttachmentNotFound: message {message_id}"))?
    };
    let attachment = msg
        .attachment
        .clone()
        .ok_or_else(|| anyhow!("AttachmentNotFound: message has no attachment"))?;

    let generation = crate::api::identity::identity_generation().await;
    let opened = async {
        let key = attachment_key_for(&msg).await?;
        let blob = attachment_blob(&message_id, &attachment, generation).await?;
        crate::crypto::file_enc::decrypt_file(&blob, &key)
            .map_err(|e| anyhow!("DecryptionFailed: {e}"))
    }
    .await;
    // Any failure — key, transfer or decryption — must leave a state the UI
    // can offer a retry on, never a stale Pending / Downloading.
    let bytes = match opened {
        Ok(bytes) => bytes,
        Err(e) => {
            set_download_status(&message_id, DownloadStatus::Failed).await;
            return Err(e);
        }
    };

    set_download_status(&message_id, DownloadStatus::Downloaded).await;
    let mime_type = crate::attachments::media::reported_mime(&bytes, &attachment.mime_type);
    Ok(AttachmentData { bytes, file_name: attachment.file_name, mime_type })
}

/// The encrypted blob of an attachment: cached, or downloaded and verified.
/// `generation` is the identity the download started under.
async fn attachment_blob(
    message_id: &str,
    attachment: &AttachmentInfo,
    generation: Option<u64>,
) -> Result<Vec<u8>> {
    let db = crate::db::app_db::db();
    if let Some(db) = db {
        match db.get_attachment_blob(&attachment.sha256).await {
            Ok(Some(blob)) => return Ok(blob),
            Ok(None) => {}
            Err(e) => log::warn!("[messages] attachment cache read failed: {e}"),
        }
    }
    set_download_status(message_id, DownloadStatus::Downloading).await;
    let progress_id = message_id.to_string();
    let blob = match blossom::download_blob(&attachment.blossom_url, |p| {
        let _ = message_store().attachment_tx.send((progress_id.clone(), p));
    })
    .await
    {
        Ok(blob) => blob,
        Err(e) => return Err(e),
    };
    cache_attachment_blob(db, generation, &attachment.sha256, &blob).await;
    Ok(blob)
}

/// Cache an encrypted blob — only while the identity a transfer started
/// under (`generation`) is still the active one (PR #590 review).
///
/// The transfer awaits the network, and the identity can be deleted
/// meanwhile: an unguarded write would put the old identity's blob back into
/// the cache `clear_identity_data` just emptied. Returns whether it wrote.
async fn cache_attachment_blob<S: crate::db::Storage>(
    db: Option<&S>,
    generation: Option<u64>,
    sha256: &str,
    blob: &[u8],
) -> bool {
    let (Some(db), Some(generation)) = (db, generation) else {
        return false;
    };
    let written = crate::api::identity::while_identity_current(generation, async {
        if let Err(e) = db.save_attachment_blob(sha256, blob).await {
            log::warn!("[messages] attachment cache write failed: {e}");
            return false;
        }
        true
    })
    .await;
    if written.is_none() {
        log::info!("[messages] attachment not cached: its identity was deleted mid-transfer");
    }
    written.unwrap_or(false)
}

/// The key an attachment was encrypted with: the raw ECDH between our trade
/// key and whoever is on the other side of the conversation it arrived in.
///
/// Read from the live session, else straight from the trade row — not
/// through [`session_or_rebuild`], whose [`chat_still_relevant`] gate refuses
/// finished trades: their history must stay openable after a restart. A row
/// whose counterparty is wrong only yields a key the AEAD rejects.
async fn attachment_key_for(msg: &ChatMessage) -> Result<zeroize::Zeroizing<[u8; 32]>> {
    let session = crate::mostro::session::session_manager().get_session(&msg.trade_id).await;
    let row = match (&session, crate::db::app_db::db()) {
        (None, Some(db)) => db.get_trade_by_order_id(&msg.trade_id).await?,
        _ => None,
    };
    let (trade_key_index, peer_hex) = conversation_of(session.as_ref(), row.as_ref())
        .ok_or_else(|| anyhow!("SessionNotFound: cannot decrypt without the trade's session"))?;
    let live_solver = match msg.message_type {
        MessageType::Admin => crate::api::disputes::solver_pubkey(&msg.trade_id).await,
        _ => None,
    };
    let counterpart_hex = counterpart_of(msg, peer_hex, live_solver)
        .ok_or_else(|| anyhow!("PeerUnknown: no counterpart key for this conversation"))?;
    let counterpart = nostr_sdk::prelude::PublicKey::from_hex(&counterpart_hex)
        .map_err(|e| anyhow!("PeerUnknown: invalid counterpart pubkey: {e}"))?;
    let trade_keys = crate::api::identity::get_active_trade_keys(trade_key_index).await?;
    crate::crypto::file_enc::attachment_key(&trade_keys, &counterpart)
}

/// Who is on the other side of the conversation `msg` arrived in.
///
/// For the solver's own messages that is their sender: `mostro_unwrap`
/// admitted the inner event only as signed by the solver, and the stored
/// message keeps it after the dispute is resolved and its solver key cleared
/// — so the history stays openable after a restart (PR #590 review). Our
/// own files to the solver name the solver they were encrypted to, for the
/// same reason (PR #596 review); the live dispute is the last fallback, for
/// a copy that does not (an echo of a send from another device).
fn counterpart_of(
    msg: &ChatMessage,
    peer_hex: Option<String>,
    live_solver: Option<String>,
) -> Option<String> {
    match msg.message_type {
        MessageType::Peer => peer_hex,
        MessageType::Admin if !msg.is_mine => Some(msg.sender_pubkey.clone()),
        MessageType::Admin => msg
            .attachment
            .as_ref()
            .and_then(|a| a.counterpart_pubkey.clone())
            .or(live_solver),
        MessageType::System => None,
    }
}

/// Our trade key index and the peer's pubkey for a conversation: from the
/// live session, else from the trade row whatever its status.
fn conversation_of(
    session: Option<&crate::mostro::session::Session>,
    row: Option<&crate::api::types::TradeInfo>,
) -> Option<(u32, Option<String>)> {
    match (session, row) {
        (Some(s), _) => Some((s.trade_key_index, s.peer_pubkey.clone())),
        (None, Some(t)) => Some((
            t.trade_key_index,
            Some(t.counterparty_pubkey.clone()).filter(|pk| !pk.is_empty()),
        )),
        (None, None) => None,
    }
}

/// Record an attachment's download state on its message (memory only: the
/// cache, not this flag, is what survives a restart).
async fn set_download_status(message_id: &str, status: DownloadStatus) {
    let mut store = message_store().messages.write().await;
    for m in store.values_mut().flat_map(|msgs| msgs.iter_mut()) {
        if m.id == message_id {
            if let Some(att) = m.attachment.as_mut() {
                att.download_status = status.clone();
            }
        }
    }
}

/// The web smoke test's attachment round trip (#589 phase 4): encrypt random
/// bytes, upload them to `server`, download them back, cache and decrypt
/// them. Only `test/web/smoke` calls it, against its own Blossom endpoint —
/// the app's uploads always go to the fixed server list.
///
/// Errors: `StorageUnavailable` before `init_db`, else the first step's.
pub async fn attachment_web_probe(server: String) -> Result<()> {
    let db = crate::db::app_db::db()
        .ok_or_else(|| anyhow!("StorageUnavailable: the store is not open"))?;
    crate::attachments::probe::roundtrip(db, &server).await
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

/// Incoming unread messages for notification cards, with at-least-once
/// delivery. Replays durable unread history on startup, channel lag and
/// every minute (including after resume), so a failed Dart persistence write
/// or a crash between the Rust and Dart commits is retried without a relay.
/// Consumers must deduplicate by message id, including deliberately suppressed
/// messages. Per-screen consumers want [`on_new_message`] instead.
pub async fn on_any_new_message() -> Result<AnyMessageStream> {
    Ok(AnyMessageStream::new(message_store()))
}

/// Stream that emits the updated global unread count after any read/write.
pub async fn on_unread_count_changed() -> Result<UnreadCountStream> {
    let rx = message_store().unread_tx.subscribe();
    Ok(UnreadCountStream { rx })
}

/// Stream that emits a trade's messages again when they change after being
/// stored: a reaction to one of them, received or sent. Never a new message.
///
/// It opens with the trade's messages that carry reactions, read once it is
/// subscribed: a reaction applied between the caller's history read and the
/// subscription still arrives. A receiver that lags behind gets the same
/// snapshot again instead of a gap.
pub async fn on_message_updated(trade_id: String) -> Result<MessageUpdateStream> {
    let rx = message_store().updated_tx.subscribe();
    let pending = reacted_messages(&trade_id).await;
    Ok(MessageUpdateStream {
        rx,
        trade_id,
        pending,
    })
}

/// The trade's messages carrying a reaction, withdrawn ones included.
async fn reacted_messages(trade_id: &str) -> VecDeque<ChatMessage> {
    message_store()
        .get_messages(trade_id)
        .await
        .into_iter()
        .filter(|m| !m.reactions.is_empty())
        .collect()
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

/// See [`on_message_updated`].
pub struct MessageUpdateStream {
    rx: broadcast::Receiver<ChatMessage>,
    trade_id: String,
    /// A snapshot still to hand out: at the start, and after a lag.
    pending: VecDeque<ChatMessage>,
}

impl MessageUpdateStream {
    pub async fn next(&mut self) -> Option<ChatMessage> {
        loop {
            if let Some(msg) = self.pending.pop_front() {
                return Some(msg);
            }
            match self.rx.recv().await {
                Ok(msg) if msg.trade_id == self.trade_id => return Some(msg),
                Ok(_) => continue, // different trade
                // Updates were dropped: hand out the current state instead.
                Err(broadcast::error::RecvError::Lagged(_)) => {
                    self.pending = reacted_messages(&self.trade_id).await;
                }
                Err(broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

fn notification_candidate(msg: &ChatMessage) -> bool {
    !msg.is_mine && !msg.is_read && msg.message_type != MessageType::System
}

pub struct AnyMessageStream {
    rx: broadcast::Receiver<ChatMessage>,
    pending: VecDeque<ChatMessage>,
    replay_at: crate::rt::time::Instant,
}

impl AnyMessageStream {
    fn new(store: &MessageStore) -> Self {
        Self {
            rx: store.new_message_tx.subscribe(),
            pending: VecDeque::new(),
            replay_at: crate::rt::time::Instant::now(),
        }
    }

    pub async fn next(&mut self) -> Option<ChatMessage> {
        self.next_from(message_store()).await
    }

    async fn next_from(&mut self, store: &MessageStore) -> Option<ChatMessage> {
        use crate::rt::time::{timeout, Duration, Instant};
        loop {
            if let Some(msg) = self.pending.pop_front() {
                if let Some(msg) = store.notification_candidate_now(msg).await {
                    return Some(msg);
                }
                continue;
            }
            if Instant::now() >= self.replay_at {
                match store.notification_backlog().await {
                    Ok(backlog) => self.pending = backlog,
                    Err(e) => {
                        log::warn!("[messages] notification recovery failed, will retry: {e}")
                    }
                }
                self.replay_at = Instant::now() + Duration::from_secs(60);
                if !self.pending.is_empty() {
                    continue;
                }
            }
            match timeout(
                self.replay_at.saturating_duration_since(Instant::now()),
                self.rx.recv(),
            )
            .await
            {
                Ok(Ok(msg)) => {
                    if let Some(msg) = store.notification_candidate_now(msg).await {
                        return Some(msg);
                    }
                }
                Ok(Err(broadcast::error::RecvError::Lagged(n))) => {
                    log::warn!(
                        "[messages] notification stream lagged by {n}; recovering stored messages"
                    );
                    self.replay_at = Instant::now();
                }
                Ok(Err(broadcast::error::RecvError::Closed)) => return None,
                Err(_) => {} // Retry durable unread messages, even without new traffic.
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
fn chat_subscription_id(
    channel: ChatChannel,
    order_id: &str,
) -> nostr_sdk::prelude::SubscriptionId {
    nostr_sdk::prelude::SubscriptionId::new(format!(
        "mostro-chat-{}{order_id}",
        channel.id_prefix()
    ))
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

/// Orders with a live chat task. Single-owner guard: the peer-reveal capture
/// fires again on daemon replays and reconnect backfills, and a second task
/// for the same order would double-process events and race on the cursor.
static ACTIVE_CHATS: OnceLock<tokio::sync::Mutex<std::collections::HashMap<String, u64>>> =
    OnceLock::new();

/// Live chat tasks, by guard key: the generation of the task that owns the
/// chat's subscription. Presence alone is not ownership: after a stop, a
/// replacement task can claim the same chat before the old one wakes, and the
/// old one's cleanup must not release — or close the REQ of — its successor
/// (PR #527 review). Same scheme as `single_order_tasks` in `orders.rs`.
fn active_chats() -> &'static tokio::sync::Mutex<std::collections::HashMap<String, u64>> {
    ACTIVE_CHATS.get_or_init(Default::default)
}

/// Source of chat task generations; strictly increasing.
static CHAT_GENERATION: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// Claim the chat for a new task: its generation, or `None` while another
/// task owns it.
pub(crate) async fn claim_chat(channel: ChatChannel, order_id: &str) -> Option<u64> {
    let mut active = active_chats().lock().await;
    claim_chat_locked(&mut active, channel, order_id)
}

/// Claim the dispute chat for a task bound to `solver_hex`: `None` while
/// another task owns it, or when the dispute's solver is no longer
/// `solver_hex`. A listener armed for the previous solver (rehydration on
/// reconnect) can reach this after a takeover already stopped the chat; it
/// must not take the chat from the new solver's task. The solver is read
/// under the guard's lock, so a takeover either happens before this check
/// or finds the claimed task to stop.
pub(crate) async fn claim_dispute_chat(order_id: &str, solver_hex: &str) -> Option<u64> {
    let mut active = active_chats().lock().await;
    if let Some(current) = crate::api::disputes::solver_pubkey(order_id).await {
        if current != solver_hex {
            log::debug!("[messages] dispute chat for a replaced solver order={order_id}");
            return None;
        }
    }
    claim_chat_locked(&mut active, ChatChannel::Dispute, order_id)
}

fn claim_chat_locked(
    active: &mut std::collections::HashMap<String, u64>,
    channel: ChatChannel,
    order_id: &str,
) -> Option<u64> {
    let key = channel.guard_key(order_id);
    if active.contains_key(&key) {
        return None;
    }
    let generation = CHAT_GENERATION.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
    active.insert(key, generation);
    Some(generation)
}

/// Whether `generation` still owns the chat.
pub(crate) async fn chat_is_current(
    channel: ChatChannel,
    order_id: &str,
    generation: u64,
) -> bool {
    active_chats().lock().await.get(&channel.guard_key(order_id)) == Some(&generation)
}

/// Release `generation`'s claim, returning whether it still held it — only
/// then does the task own the subscription it is about to close.
#[cfg(test)]
async fn release_chat(channel: ChatChannel, order_id: &str, generation: u64) -> bool {
    let mut active = active_chats().lock().await;
    let key = channel.guard_key(order_id);
    if active.get(&key) == Some(&generation) {
        active.remove(&key);
        true
    } else {
        false
    }
}

/// Stop the chat subscriptions of a trade that is over (#523): release both
/// channels' ownership and close their REQs, which otherwise stayed open for
/// the rest of the session and counted against the relays' caps. A running
/// task sees its ownership gone and exits at its next wake. Returns the
/// channels that were running.
pub(crate) async fn stop_chat_subscriptions(order_id: &str) -> Vec<ChatChannel> {
    let mut stopped = Vec::new();
    for channel in [ChatChannel::Peer, ChatChannel::Dispute] {
        if stop_chat_subscription(channel, order_id).await {
            stopped.push(channel);
        }
    }
    stopped
}

/// Stop one channel's chat task of an order: release its ownership and close
/// its REQ, so a replacement task can claim it. Used when the counterpart of a
/// live conversation changes — a solver taking over a dispute — since the
/// running task is bound to the old counterpart's keys. Returns whether a task
/// was running.
pub(crate) async fn stop_chat_subscription(channel: ChatChannel, order_id: &str) -> bool {
    let mut active = active_chats().lock().await;
    stop_chat_locked(&mut active, channel, order_id).await
}

/// A task's own cleanup: release its claim and close the chat's REQ, only
/// while `generation` still owns the chat, all under the guard's lock (through
/// the registry, or a reconnect repair would resurrect the REQ of a chat
/// nobody listens to). Releasing first and closing after would let a
/// replacement task (a takeover's) claim the chat and install its filter in
/// between, and the late close would then remove it. Returns whether it
/// still owned the chat.
async fn release_and_close_chat(channel: ChatChannel, order_id: &str, generation: u64) -> bool {
    let mut active = active_chats().lock().await;
    if active.get(&channel.guard_key(order_id)) != Some(&generation) {
        return false;
    }
    stop_chat_locked(&mut active, channel, order_id).await
}

/// Hand an order's dispute chat over to a new solver: stop the running task,
/// close its REQ and forget the cursor, all under the guard's lock. A new
/// task (the new solver's, or a reconnect's resubscribe) can only claim the
/// chat once this is complete, so it neither loads the previous
/// conversation's cursor nor has its subscription removed by a late close of
/// the old one. Returns whether a task was running.
pub(crate) async fn hand_over_dispute_chat(order_id: &str) -> bool {
    let mut active = active_chats().lock().await;
    let stopped = stop_chat_locked(&mut active, ChatChannel::Dispute, order_id).await;
    reset_chat_cursor(ChatChannel::Dispute, order_id).await;
    stopped
}

/// Release the chat's claim and close its REQ, with the guard's lock held
/// throughout, so no new task claims the chat before its old REQ is gone.
async fn stop_chat_locked(
    active: &mut std::collections::HashMap<String, u64>,
    channel: ChatChannel,
    order_id: &str,
) -> bool {
    let was_running = active.remove(&channel.guard_key(order_id)).is_some();
    if was_running {
        if let Ok(pool) = crate::api::nostr::get_pool() {
            crate::nostr::live_subs::live_subs()
                .close(&pool.client(), &chat_subscription_id(channel, order_id))
                .await;
        }
    }
    was_running
}

/// Forget every conversation of the identity being deleted (issue #533):
/// release each live chat task's claim, close its REQ, and empty the
/// in-memory store, so the next user starts with no chats and an unread
/// count of zero. The persisted rows go with `clear_identity_data`; a task
/// still running sees its claim gone at its next wake and exits.
pub(crate) async fn forget_identity_chats() {
    let guard_keys: Vec<String> = active_chats()
        .lock()
        .await
        .drain()
        .map(|(key, _)| key)
        .collect();
    if let Ok(pool) = crate::api::nostr::get_pool() {
        let client = pool.client();
        for key in &guard_keys {
            // Same shape as `chat_subscription_id`, whose suffix is the guard key.
            let id = nostr_sdk::prelude::SubscriptionId::new(format!("mostro-chat-{key}"));
            crate::nostr::live_subs::live_subs()
                .close(&client, &id)
                .await;
        }
    }
    message_store().clear().await;
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

/// Forget the `since` cursor of one channel of `order_id`. When the dispute
/// changes solver, the cursor dates the previous solver's conversation, and
/// the new solver's clock may be behind it: their first messages would fall
/// before `since` and never be fetched. The new filter only matches the new
/// conversation, so starting without a cursor refetches nothing else.
/// Best-effort, like the cursor itself.
async fn reset_chat_cursor(channel: ChatChannel, order_id: &str) {
    if let Some(db) = crate::db::app_db::db() {
        let key = channel.cursor_key(order_id);
        if let Err(e) = db.delete_setting(&key).await {
            log::warn!("[messages] cursor reset failed order={order_id}: {e}");
        }
    }
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

/// Persist the cursor only while `generation` still owns the chat, checked
/// and written under the guard's lock. A task stopped by a solver takeover
/// can still be handling an event; without this its write could land after
/// the takeover reset the cursor and restore the previous conversation's
/// `since`. A stop takes the same lock, so it happens either before the
/// check (no write) or after the write (the reset follows it).
async fn store_chat_cursor_if_current(
    channel: ChatChannel,
    order_id: &str,
    generation: u64,
    ts: i64,
) {
    let active = active_chats().lock().await;
    if active.get(&channel.guard_key(order_id)) != Some(&generation) {
        return;
    }
    store_chat_cursor(channel, order_id, ts).await;
}

/// Interpret a validated inner-event payload.
///
/// An attachment travels as v1's JSON message (`image_encrypted` /
/// `file_encrypted`, see [`crate::attachments::payload`]); everything else is
/// plaintext. Returns `(content, attachment)`: for an attachment the content
/// is its file name — what a list preview or a notification shows.
fn parse_chat_payload(payload: &str) -> (String, Option<AttachmentInfo>) {
    match crate::attachments::payload::parse(payload) {
        Some(a) => (
            a.file_name.clone(),
            Some(AttachmentInfo {
                file_name: a.file_name,
                mime_type: a.mime_type,
                file_size: a.original_size,
                file_type: a.file_type,
                download_status: DownloadStatus::Pending,
                blossom_url: a.blossom_url,
                sha256: a.sha256,
                encrypted_size: a.encrypted_size,
                width: a.width,
                height: a.height,
                // Only our own sends record it; a peer cannot supply it.
                counterpart_pubkey: None,
            }),
        ),
        None => (payload.to_string(), None),
    }
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
/// replays re-invoke the peer-reveal capture and must be no-ops), explicit
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
    trade_keys: nostr_sdk::prelude::Keys,
    peer_pubkey: nostr_sdk::prelude::PublicKey,
    conv: nostr_sdk::prelude::Keys,
    sign: nostr_sdk::prelude::Keys,
) {
    // Single-owner guard: a second spawn for the same order is a no-op, and
    // so is a dispute chat for a solver that was replaced.
    let claimed = match channel {
        ChatChannel::Dispute => claim_dispute_chat(&order_id, &peer_pubkey.to_hex()).await,
        ChatChannel::Peer => claim_chat(channel, &order_id).await,
    };
    let Some(generation) = claimed else {
        log::debug!("[messages] chat task already active order={order_id}");
        return;
    };
    // A peer chat starts only while its row keeps it open (#642). Its grace
    // window can run out between the decision to start this listener and
    // this claim (key derivation, the spawn), and the timer that ends the
    // window finds no task to stop then. Asked after the claim, so a close
    // that comes later still finds the task.
    if channel == ChatChannel::Peer && persisted_chat_closed(&order_id).await {
        log::info!("[messages] chat over before its listener started order={order_id}");
        release_and_close_chat(channel, &order_id, generation).await;
        return;
    }

    run_chat_subscription(
        channel,
        &order_id,
        generation,
        &trade_keys,
        &peer_pubkey,
        &conv,
        &sign,
    )
    .await;

    // Cleanup on every exit path: release ownership and drop the relay
    // subscription so it never outlives the task — but only while this task
    // still owns the chat. After a stop the REQ is already closed, and a
    // replacement task may have re-opened it under the same id.
    if !release_and_close_chat(channel, &order_id, generation).await {
        log::debug!("[messages] chat task superseded order={order_id}");
        return;
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
    /// The newest event passed so far. The cursor follows it, except that
    /// the peer chat's stops at a reaction still held (`held_floor`) and
    /// catches up once that is stored.
    wanted: i64,
    /// The cursor this subscription started from. Catch-up serves the
    /// newest events first, so by the time a reaction arrives the cursor may
    /// already be past its older target; this is where both are safe.
    start_cursor: i64,
    flooded: bool,
    /// Every relay that held the subscription has sent EOSE: stored
    /// catch-up is over and the cursor may move. `live` turns on at the first
    /// one, for the token bucket; this waits for the slowest, which may
    /// still be serving older events newest first.
    caught_up: bool,
    /// The relays whose EOSE is still to come. Empty in tests, which call
    /// [`Self::caught_up`] themselves.
    awaiting_eose: std::collections::HashSet<String>,
    /// Relays that have sent EOSE, each with the connection it came on (the
    /// relay's count of connections, see `connection_of`). An event from a relay with no EOSE on its
    /// current connection — it joined late, or reconnected and got the
    /// subscription again from `live_subs` — is a replay of stored events,
    /// newest first: catch-up starts over for that relay.
    eose_seen: HashMap<String, u64>,
    /// The event being handled comes from a relay still in catch-up: like
    /// any stored backlog, the token bucket lets it through (`budget_ok`).
    from_catch_up: bool,
    /// The chat claim this state belongs to: cursor writes are gated on it
    /// still owning the chat. `None` only in tests that run no task.
    generation: Option<u64>,
}

impl ChatRxState {
    fn new(channel: ChatChannel, cursor: i64, generation: Option<u64>) -> Self {
        Self {
            channel,
            outer_seen: BoundedIdSet::new(OUTER_LRU_CAP),
            bucket: TokenBucket::new(crate::rt::time::Instant::now()),
            consecutive_rejected: 0,
            live: false,
            cursor,
            wanted: cursor,
            start_cursor: cursor,
            flooded: false,
            caught_up: false,
            awaiting_eose: std::collections::HashSet::new(),
            eose_seen: HashMap::new(),
            from_catch_up: false,
            generation,
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
        // Stored backlog is bounded by the filter's `limit`; metering it
        // would reject older events for good, the cursor passing them.
        if !self.live || self.from_catch_up {
            return true;
        }
        if self.bucket.try_take(crate::rt::time::Instant::now()) {
            true
        } else {
            self.reject(order_id);
            false
        }
    }

    async fn persist_cursor(&self, order_id: &str) {
        match self.generation {
            Some(generation) => {
                store_chat_cursor_if_current(self.channel, order_id, generation, self.cursor).await
            }
            None => store_chat_cursor(self.channel, order_id, self.cursor).await,
        }
    }

    /// Advance the persisted cursor to `event_ts` clamped to our own clock,
    /// so a counterparty dating events at the skew-tolerance edge can never
    /// push it into the future and silence the conversation. Callers only
    /// invoke this once the corresponding message is durably stored (or was
    /// already known/durable).
    ///
    /// Stored catch-up comes newest first, so until it is over (EOSE) the
    /// cursor stays where this subscription started: passing a newer event
    /// before an older one arrives would lose the older one on a restart.
    /// [`Self::caught_up`] moves it then. On the peer chat it also stops at
    /// the floor of a reaction still held for a target that has not arrived
    /// (`held_floor`).
    async fn advance_cursor(&mut self, order_id: &str, event_ts: i64) {
        self.wanted = self.wanted.max(event_ts.min(unix_now()));
        self.settle_cursor(order_id).await;
    }

    /// Stored catch-up is over: the cursor may now pass what it delivered.
    async fn caught_up(&mut self, order_id: &str) {
        self.live = true;
        self.caught_up = true;
        self.settle_cursor(order_id).await;
    }

    /// One relay's EOSE: from the first the token bucket meters arrivals;
    /// once every relay that held the subscription has sent one, catch-up
    /// is over.
    async fn eose_from(&mut self, order_id: &str, relay: &str, connection: u64) {
        self.live = true;
        self.eose_seen.insert(relay.to_string(), connection);
        self.awaiting_eose.remove(relay);
        if self.awaiting_eose.is_empty() {
            self.caught_up(order_id).await;
        }
    }

    /// `relay` closed the subscription (CLOSED). It sends no EOSE, so it is
    /// no longer awaited; nor is its connection marked done: `live_subs`
    /// issues the REQ again on that same connection, and the replay that
    /// follows must reopen catch-up (and take the cursor back) like any
    /// other.
    async fn closed_by(&mut self, order_id: &str, relay: &str) {
        self.eose_seen.remove(relay);
        self.awaiting_eose.remove(relay);
        if self.awaiting_eose.is_empty() {
            self.caught_up(order_id).await;
        }
    }

    /// An event from `relay`, on its connection `connection`. A relay with
    /// no EOSE on that connection is replaying stored events newest first —
    /// it joined late or reconnected — so the cursor waits for its EOSE as
    /// for the others', and its backlog skips the token bucket.
    ///
    /// Its REQ is the recorded one, `since` the subscription's start, so it
    /// may replay events older than a cursor already persisted: the cursor
    /// goes back to that start, or a restart halfway through would skip
    /// them.
    async fn event_from(&mut self, order_id: &str, relay: &str, connection: u64) {
        if self.eose_seen.get(relay) != Some(&connection) {
            self.eose_seen.remove(relay);
            if self.awaiting_eose.insert(relay.to_string()) {
                self.caught_up = false;
                if self.cursor > self.start_cursor {
                    self.cursor = self.start_cursor;
                    self.persist_cursor(order_id).await;
                }
            }
        }
        self.from_catch_up = self.awaiting_eose.contains(relay);
    }

    /// Stop waiting for relays that dropped the connection: their catch-up
    /// starts over on a reconnect and cannot hold this one back for good.
    async fn forget_gone_relays(&mut self, order_id: &str, client: &nostr_sdk::prelude::Client) {
        if self.caught_up || self.awaiting_eose.is_empty() {
            return;
        }
        let connected: std::collections::HashSet<String> = client
            .relays()
            .await
            .into_iter()
            .filter(|(_, relay)| relay.status() == nostr_sdk::prelude::RelayStatus::Connected)
            .map(|(url, _)| url.to_string())
            .collect();
        self.awaiting_eose.retain(|url| connected.contains(url));
        if self.awaiting_eose.is_empty() && self.live {
            self.caught_up(order_id).await;
        }
    }

    /// Move the cursor as far as [`Self::wanted`], short of a held
    /// reaction's floor. Also run on a quiet chat, so a floor that expired
    /// with no event after it still lets the cursor go.
    async fn settle_cursor(&mut self, order_id: &str) {
        // A message of this trade whose write failed — received, or a
        // reaction this device sent — keeps the cursor where it is until a
        // retry stores it: a later event passing it would leave it behind,
        // never fetched again.
        if !self.caught_up || message_store().has_unsaved(order_id).await {
            return;
        }
        let floor = match self.channel {
            ChatChannel::Peer => message_store().held_floor(order_id).await,
            ChatChannel::Dispute => None,
        };
        let accepted = floor.map_or(self.wanted, |floor| self.wanted.min(floor));
        if accepted > self.cursor {
            self.cursor = accepted;
            self.persist_cursor(order_id).await;
        }
    }
}

/// Install the chat's relay subscription only while `generation` still owns
/// the chat, checked and replaced under the guard's lock. All tasks of a chat
/// share one subscription id, so a task stopped by a solver takeover between
/// its claim and this point would otherwise overwrite the new solver's filter
/// with the previous one and leave the current task deaf. A stop takes the
/// same lock: it lands either before the check (`None`, nothing installed)
/// or after the replace (it closes the REQ, and the new task replaces it).
async fn replace_chat_subscription_if_current(
    channel: ChatChannel,
    order_id: &str,
    generation: u64,
    client: &nostr_sdk::prelude::Client,
    sub_id: nostr_sdk::prelude::SubscriptionId,
    filter: nostr_sdk::prelude::Filter,
) -> Option<Result<crate::nostr::live_subs::Issued>> {
    let active = active_chats().lock().await;
    if active.get(&channel.guard_key(order_id)) != Some(&generation) {
        return None;
    }
    Some(
        crate::nostr::live_subs::live_subs()
            .replace(client, sub_id, filter)
            .await,
    )
}

async fn run_chat_subscription(
    channel: ChatChannel,
    order_id: &str,
    generation: u64,
    trade_keys: &nostr_sdk::prelude::Keys,
    peer_pubkey: &nostr_sdk::prelude::PublicKey,
    conv: &nostr_sdk::prelude::Keys,
    sign: &nostr_sdk::prelude::Keys,
) {
    use nostr_sdk::prelude::{ClientNotification, StreamExt};

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

    let mut filter = nostr_sdk::prelude::Filter::new()
        .kind(nostr_sdk::prelude::Kind::PrivateDirectMessage)
        .author(sign_pubkey)
        .limit(CHAT_BACKLOG_LIMIT);
    if cursor > 0 {
        filter = filter.since(nostr_sdk::prelude::Timestamp::from_secs(cursor as u64));
    }

    // Obtain the receiver BEFORE subscribing — same pattern as subscribe_daemon_messages.
    // This avoids a race where an event arrives between subscribe() and notifications()
    // and would otherwise be missed.
    let mut rx = client.notifications();

    // `replace`, not a bare subscribe: issued while relays are still coming
    // back (a resume), it must reach each of them as it connects.
    let issued = match replace_chat_subscription_if_current(
        channel,
        order_id,
        generation,
        &client,
        sub_id.clone(),
        filter,
    )
    .await
    {
        Some(Ok(issued)) => issued,
        Some(Err(e)) => {
            log::warn!("[messages] subscribe_incoming_chat subscribe failed: {e}");
            return;
        }
        None => {
            log::debug!("[messages] chat task stopped before subscribing order={order_id}");
            return;
        }
    };

    log::info!(
        "[messages] incoming-chat subscription {issued:?} order={order_id} author={} since={cursor}",
        sign_pubkey.to_hex(),
    );

    let mut state = ChatRxState::new(channel, cursor, Some(generation));
    state.awaiting_eose = relays_holding(&client, &sub_id).await;
    // On its own clock: the notification stream is the whole client's, so
    // waiting for a quiet stream would hardly ever reach the re-check.
    let mut last_recheck = crate::rt::time::Instant::now();

    loop {
        // The trade ended and `stop_chat_subscriptions` took the chat back.
        if !chat_is_current(channel, order_id, generation).await {
            return;
        }
        // Every minute, whatever else arrives, the cursor is re-checked: a
        // held reaction's floor can expire with no event after it, and a
        // relay awaited for its EOSE can have gone.
        let wait = CURSOR_RECHECK.saturating_sub(last_recheck.elapsed());
        let next = crate::rt::time::timeout(wait, rx.next()).await;
        if last_recheck.elapsed() >= CURSOR_RECHECK {
            last_recheck = crate::rt::time::Instant::now();
            state.forget_gone_relays(order_id, &client).await;
            state.settle_cursor(order_id).await;
        }
        let Ok(notification) = next else {
            continue;
        };
        match notification {
            Some(ClientNotification::Event {
                relay_url,
                subscription_id,
                event,
            }) => {
                if subscription_id == sub_id {
                    let connection = connection_of(&client, &relay_url).await;
                    state
                        .event_from(order_id, &relay_url.to_string(), connection)
                        .await;
                    handle_chat_event(
                        channel,
                        order_id,
                        &allowed_signers,
                        conv,
                        &sign_pubkey,
                        &my_trade_pubkey,
                        &event,
                        &mut state,
                    )
                    .await;
                }
                if state.flooded {
                    return;
                }
            }
            Some(ClientNotification::Message {
                relay_url, message, ..
            }) => {
                // EOSE for one of our subscriptions: that relay's stored
                // catch-up is over. A CLOSED (auth-required, a rate limit)
                // never comes with one: that relay is no longer awaited, but
                // its connection is not marked done either, since `live_subs`
                // issues the REQ again on it and that replay is a catch-up.
                //
                // The connection is read now, not when the relay sent it: an
                // EOSE still queued while the relay reconnects is taken for
                // the new connection's. The SDK says neither which
                // connection a message came on nor when a relay reconnects,
                // and the window is the queue's latency.
                match &*message {
                    nostr_sdk::prelude::RelayMessage::EndOfStoredEvents(sid) if **sid == sub_id => {
                        let connection = connection_of(&client, &relay_url).await;
                        state
                            .eose_from(order_id, &relay_url.to_string(), connection)
                            .await;
                    }
                    nostr_sdk::prelude::RelayMessage::Closed {
                        subscription_id, ..
                    } if **subscription_id == sub_id => {
                        state.closed_by(order_id, &relay_url.to_string()).await;
                    }
                    _ => {}
                }
            }
            // The SDK's notification stream ends on shutdown; lag under
            // pressure is absorbed inside the SDK since 0.45 and no longer
            // surfaces here.
            Some(ClientNotification::Shutdown) | None => break,
        }
    }
}

/// Which connection of `relay` this is: how many times it has connected. A
/// reconnect counts one more, which is how a replayed catch-up is told from
/// live traffic — even two connections within the same second, which the
/// relay's `connected_at` (whole seconds) would not tell apart.
async fn connection_of(
    client: &nostr_sdk::prelude::Client,
    relay: &nostr_sdk::prelude::RelayUrl,
) -> u64 {
    match client.relay(relay).await {
        Ok(Some(relay)) => relay.stats().success() as u64,
        _ => 0,
    }
}

/// The connected relays that hold subscription `id`: the ones whose stored
/// catch-up the chat cursor waits for.
async fn relays_holding(
    client: &nostr_sdk::prelude::Client,
    id: &nostr_sdk::prelude::SubscriptionId,
) -> std::collections::HashSet<String> {
    let mut holding = std::collections::HashSet::new();
    for (url, relay) in client.relays().await {
        if relay.status() == nostr_sdk::prelude::RelayStatus::Connected
            && relay.subscription(id).await.is_some()
        {
            holding.insert(url.to_string());
        }
    }
    holding
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
    allowed_signers: &[nostr_sdk::prelude::PublicKey],
    conv: &nostr_sdk::prelude::Keys,
    sign_pubkey: &nostr_sdk::prelude::PublicKey,
    my_trade_pubkey: &nostr_sdk::prelude::PublicKey,
    event: &nostr_sdk::prelude::Event,
    state: &mut ChatRxState,
) {
    if event.kind != nostr_sdk::prelude::Kind::PrivateDirectMessage {
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
        nostr_sdk::prelude::Timestamp::now(),
    ) {
        Ok(inner) => inner,
        // A kind this client does not implement is an extension of the
        // protocol, not abuse: dropped without feeding the flood breaker, and
        // passed, since fetching it again would change nothing.
        Err(e)
            if e.downcast_ref::<crate::nostr::transport::UnsupportedInnerKind>()
                .is_some() =>
        {
            log::debug!("[messages] incoming-chat skipped order={order_id}: {e}");
            state
                .advance_cursor(order_id, event.created_at.as_secs() as i64)
                .await;
            return;
        }
        Err(e) => {
            // Only the counterparty can author a validly-signed outer event,
            // so failures here are attributable.
            log::warn!("[messages] incoming-chat rejected order={order_id}: {e}");
            state.reject(order_id);
            return;
        }
    };
    state.consecutive_rejected = 0;

    if inner.kind == nostr_sdk::prelude::Kind::Reaction {
        handle_reaction(channel, order_id, &inner, event, state).await;
        return;
    }

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
    // Another device of ours sent the solver the chat key (#415): this one
    // must stop offering it too.
    if channel == ChatChannel::Dispute && is_echo && attachment.is_none() {
        if let Some(solver) = allowed_signers.iter().find(|k| *k != my_trade_pubkey) {
            crate::api::disputes::note_chat_key_share_echo(order_id, solver, &content).await;
        }
    }

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
        reactions: Vec::new(),
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

/// An accepted reaction (`mostro_unwrap` checked its shape). It is never a
/// message: stored on its target, the newest per party holding, which is
/// also what makes a re-wrapped one harmless (chat.md, step 12).
async fn handle_reaction(
    channel: ChatChannel,
    order_id: &str,
    inner: &nostr_sdk::prelude::Event,
    event: &nostr_sdk::prelude::Event,
    state: &mut ChatRxState,
) {
    let at = event.created_at.as_secs() as i64;
    // Reactions are defined for the peer chat only: here a kind like any
    // other this channel does not implement.
    if channel != ChatChannel::Peer {
        state.advance_cursor(order_id, at).await;
        return;
    }
    let Some(target) = crate::nostr::transport::reaction_target(inner) else {
        return;
    };
    let target = target.to_hex();
    let reaction = ChatReaction {
        sender_pubkey: inner.pubkey.to_hex(),
        emoji: inner.content.clone(),
        created_at: inner.created_at.as_secs() as i64,
        event_id: inner.id.to_hex(),
    };
    // Live events come in order, so a missing target is older than the
    // cursor only in catch-up, where it is still on its way.
    let floor = if state.caught_up {
        state.cursor
    } else {
        state.start_cursor
    };
    let outcome = message_store()
        .apply_reaction(order_id, &target, reaction, floor)
        .await;
    log::debug!("[messages] incoming-chat reaction order={order_id} → {outcome:?}");
    // The cursor passes only what is durably stored, as for a message.
    let passed = match outcome {
        ReactionOutcome::Applied { durable, .. } => durable,
        // Already shown: as durable as the message holding it, whose write
        // gets one retry here if it failed.
        ReactionOutcome::Unchanged => message_store().ensure_durable(order_id, &target).await,
        // In memory only until its target arrives: the cursor's floor
        // (`held_floor`) keeps it where it was meanwhile, so a restart
        // fetches the reaction and its older target again.
        ReactionOutcome::Held => true,
        ReactionOutcome::Refused => true,
    };
    if passed {
        state.advance_cursor(order_id, at).await;
    }
}

/// Rebuild the chat listeners for every persisted trade that can still chat.
///
/// Called once the relay pool is up (`api::nostr::initialize`): sessions are
/// in-memory, so after a process restart nothing else would resubscribe and
/// the next peer message would be lost until the daemon happened to resend a
/// peer-pubkey notification.
///
/// Also runs on every resume (`run_resync`), ahead of the subscription
/// repair: a completed trade's peer chat whose grace window ended while the
/// device slept is closed here (#642), before a reconnect re-issues its REQ.
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
    let total = trades.len();
    let now = unix_now();
    let (relevant, ended): (Vec<_>, Vec<_>) = trades
        .into_iter()
        .partition(|trade| chat_still_relevant_at(trade, now));
    for trade in ended {
        let order_id = &trade.order.id;
        if chat_grace_ends_at(&trade).is_some() && chat_running(ChatChannel::Peer, order_id).await {
            crate::api::orders::close_grace_chat_if_over(order_id).await;
        }
    }
    // Each of these is a REQ, and relays cap them per connection (#560): the
    // count and each trade's age say whether a stale row is holding one.
    crate::api::logging::blog_info(
        "messages",
        format!(
            "resubscribing {} chats of {total} persisted trades",
            relevant.len()
        ),
    );
    for trade in relevant {
        let order_id = trade.order.id.clone();
        crate::api::logging::blog_debug(
            "messages",
            format!(
                "chat resubscribe order={} status={:?} age={}s",
                crate::api::logging::short_id(&order_id),
                trade.order.status,
                crate::rt::unix_now().saturating_sub(trade.started_at),
            ),
        );
        spawn_peer_chat(&trade).await;
        // A completed trade within its window (#642): the chat closes at its
        // end, which no status change will announce in this process.
        if let Some(until) = chat_grace_ends_at(&trade) {
            crate::api::orders::schedule_chat_grace_end(&order_id, until);
        }
    }
}

/// Start the peer chat listener of `trade` from its row: the trade key and
/// the counterparty it persists derive the chat keys, as the reveal did.
/// A no-op while one runs (the single-owner guard in
/// [`subscribe_incoming_chat`]), and for a row they cannot derive from.
pub(crate) async fn spawn_peer_chat(trade: &crate::api::types::TradeInfo) {
    let Ok(trade_keys) = crate::api::identity::get_active_trade_keys(trade.trade_key_index).await
    else {
        return;
    };
    let Ok(peer) = nostr_sdk::prelude::PublicKey::from_hex(&trade.counterparty_pubkey) else {
        return;
    };
    let Ok((conv, sign)) = crate::crypto::chat_keys::derive_chat_keys(&trade_keys, &peer) else {
        return;
    };
    let order_id = trade.order.id.clone();
    log::info!("[messages] resubscribing chat order={order_id}");
    crate::rt::spawn(subscribe_incoming_chat(
        ChatChannel::Peer,
        order_id,
        trade_keys,
        peer,
        conv,
        sign,
    ));
}

/// Whether a task owns `order_id`'s chat on `channel`.
pub(crate) async fn chat_running(channel: ChatChannel, order_id: &str) -> bool {
    active_chats()
        .lock()
        .await
        .contains_key(&channel.guard_key(order_id))
}

/// How long the peer chat of a successfully completed trade stays open
/// (issue #642): the parties tend to thank each other and announce their
/// ratings right after the trade ends. Canceled, expired and admin-resolved
/// trades get no such window.
pub(crate) const PEER_CHAT_GRACE_SECS: i64 = 3600;

/// When the peer chat of a completed trade closes: `completed_at` plus
/// [`PEER_CHAT_GRACE_SECS`], for a `success` row that has a completion time.
/// `None` for any other row — a row completed before the time was recorded
/// included, so an old trade's chat never reopens.
pub(crate) fn chat_grace_ends_at(trade: &crate::api::types::TradeInfo) -> Option<i64> {
    use crate::api::types::{OrderStatus, TradeOutcome};
    if trade.order.status != OrderStatus::Success
        || !matches!(trade.outcome, None | Some(TradeOutcome::Success))
    {
        return None;
    }
    trade
        .completed_at
        .map(|at| at.saturating_add(PEER_CHAT_GRACE_SECS))
}

/// A persisted trade still needs a live chat listener: it has a known peer
/// and has not reached a terminal outcome, or it completed less than
/// [`PEER_CHAT_GRACE_SECS`] ago.
///
/// The pubkey checks are an invariant guard (#334): a row whose
/// "counterparty" is the Mostro node itself (rows written before the fix
/// seeded `creator_pubkey` = the 38383 event author) would derive garbage
/// chat keys AND claim the single-owner subscription guard with them,
/// silently blocking the correct subscription when a replayed reveal
/// arrives. The `creator_pubkey` comparison is the load-bearing one: it is
/// the exact field the pre-fix seed copied from, on the same row, so it
/// catches the poison whichever node published the event — the trades table
/// is not scoped per node, and this iterates rows from every node the user
/// has pointed at. The active-pubkey check stays as defense in depth.
pub(crate) fn chat_still_relevant(trade: &crate::api::types::TradeInfo) -> bool {
    chat_still_relevant_at(trade, unix_now())
}

/// Whether `peer` can be `trade`'s counterparty: known, and not the Mostro
/// node a pre-#334 row seeded it with (see [`chat_still_relevant`]). Keys
/// derived with the node would open no conversation of this trade.
pub(crate) fn plausible_counterparty(trade: &crate::api::types::TradeInfo, peer: &str) -> bool {
    !peer.is_empty()
        && peer != trade.order.creator_pubkey
        && peer != crate::config::active_mostro_pubkey()
}

/// [`chat_still_relevant`] at `now` (Unix seconds).
pub(crate) fn chat_still_relevant_at(trade: &crate::api::types::TradeInfo, now: i64) -> bool {
    use crate::api::types::OrderStatus::*;
    let peer_known = plausible_counterparty(trade, &trade.counterparty_pubkey);
    let live = trade.outcome.is_none()
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
        );
    peer_known && (live || chat_grace_ends_at(trade).is_some_and(|end| now < end))
}

/// Whether `trade`'s peer chat is over at `now`: the trade ended, and not
/// with a `success` whose grace window (#642) still runs — the line
/// `ChatRowState` draws for the composer, on the same row. Positive evidence
/// only: unlike [`chat_still_relevant_at`] it leaves the peer checks out, as
/// it judges a cached session that already holds the peer, and the row's
/// counterparty write is best-effort.
pub(crate) fn chat_closed_at(trade: &crate::api::types::TradeInfo, now: i64) -> bool {
    crate::mostro::status::is_hard_terminal(&trade.order.status)
        && !chat_grace_ends_at(trade).is_some_and(|end| now < end)
}

/// Session lookup with a durable fallback (#381): a missing session is
/// rebuilt from the persisted trade row before any chat function degrades
/// (local-only send, `SessionNotFound`). Sessions are memory-only, so after
/// a restart the send path would otherwise stay broken until a relay
/// replays the peer reveal — and permanently, if every relay has pruned the
/// trade's daemon messages. The row already carries everything needed:
/// trade key index and counterparty pubkey.
///
/// Gated by [`chat_still_relevant`], the same invariant guard the startup
/// resubscription uses: without it, a poisoned pre-#334 row (counterparty =
/// the Mostro node) would be resurrected into a session with garbage keys.
///
/// A cached session answers only while the row has not closed the chat
/// ([`persisted_chat_closed`]): nothing removes a session when its trade ends or
/// a completed trade's grace window runs out (#642), so a send after either —
/// a late UI timer, a clock jump, a direct bridge call — would still publish.
async fn session_or_rebuild(trade_id: &str) -> Option<crate::mostro::session::Session> {
    let mgr = crate::mostro::session::session_manager();
    if let Some(s) = mgr.get_session(trade_id).await {
        if persisted_chat_closed(trade_id).await {
            log::info!("[messages] trade={trade_id}: its chat is over — local-only");
            return None;
        }
        return Some(s);
    }
    let db = crate::db::app_db::db()?;
    let trade = match db.get_trade_by_order_id(trade_id).await {
        Ok(row) => row?,
        Err(e) => {
            // A corrupt DB surfacing as a bare SessionNotFound would be
            // undiagnosable; the reveal path logs its lookup failures too.
            log::warn!("[messages] session rebuild trade={trade_id}: row lookup failed: {e}");
            return None;
        }
    };
    if !chat_still_relevant(&trade) {
        return None;
    }
    let trade_keys = match crate::api::identity::get_active_trade_keys(trade.trade_key_index).await
    {
        Ok(k) => k,
        Err(e) => {
            log::warn!("[messages] session rebuild trade={trade_id}: key load failed: {e}");
            return None;
        }
    };
    rebuild_session(&trade, &trade_keys).await
}

/// [`chat_closed_at`] on `trade_id`'s persisted row, now: asked by a cached
/// session before it sends, and by a peer listener right after its claim.
/// No store, no row (a take's first reply caches its session and starts its
/// chat before the row exists) or a read error close nothing, as the dispute
/// chat's `persisted_order_is_finished` reads them.
async fn persisted_chat_closed(trade_id: &str) -> bool {
    let Some(db) = crate::db::app_db::db() else {
        return false;
    };
    match db.get_trade_by_order_id(trade_id).await {
        Ok(Some(trade)) => chat_closed_at(&trade, unix_now()),
        Ok(None) => false,
        Err(e) => {
            log::warn!("[messages] chat gate trade={trade_id}: row lookup failed: {e}");
            false
        }
    }
}

/// The derivation half of [`session_or_rebuild`], split so tests can inject
/// generated keys instead of mutating the process-global identity (the same
/// seam as `apply_peer_reveal` in `orders.rs`). Derives the ECDH shared key
/// from `(our_trade_key, row.counterparty_pubkey)` and inserts the session
/// **already populated** — the session stays a pure cache of the row.
async fn rebuild_session(
    trade: &crate::api::types::TradeInfo,
    trade_keys: &nostr_sdk::prelude::Keys,
) -> Option<crate::mostro::session::Session> {
    let order_id = &trade.order.id;
    let peer_pk = match nostr_sdk::prelude::PublicKey::from_hex(&trade.counterparty_pubkey) {
        Ok(pk) => pk,
        Err(e) => {
            log::warn!("[messages] session rebuild order={order_id}: invalid peer pubkey: {e}");
            return None;
        }
    };
    let shared_key = match crate::crypto::ecdh::derive_nip04_shared_key(trade_keys, &peer_pk) {
        Ok(k) => k,
        Err(e) => {
            log::warn!("[messages] session rebuild order={order_id}: ECDH failed: {e}");
            return None;
        }
    };
    let mgr = crate::mostro::session::session_manager();
    // Atomic insert: the session enters the manager already carrying peer +
    // shared key. A create-then-update pair exposes a keyless intermediate
    // between the two locks, and a concurrent send_message reading it would
    // silently degrade to local-only — the exact failure this fallback
    // exists to eliminate.
    match mgr
        .create_session_with_peer(
            order_id.clone(),
            trade.role.clone(),
            trade.trade_key_index,
            trade.order.clone(),
            trade.counterparty_pubkey.clone(),
            shared_key,
        )
        .await
    {
        Ok(session) => {
            log::info!("[messages] session rebuilt from trade row order={order_id} (#381)");
            Some(session)
        }
        // Benign race: a concurrent rebuild or a live peer reveal created it
        // between our lookup and here — theirs is at least as complete.
        Err(_) => mgr.get_session(order_id).await,
    }
}

#[cfg(test)]
mod tests {
    fn notification_test_message(trade_id: &str, index: i64) -> ChatMessage {
        ChatMessage {
            id: format!("{trade_id}-{index}"),
            trade_id: trade_id.into(),
            sender_pubkey: "peer".into(),
            content: "hello".into(),
            message_type: MessageType::Peer,
            is_mine: false,
            is_read: false,
            has_attachment: false,
            attachment: None,
            created_at: index,
            reactions: Vec::new(),
        }
    }

    /// Issue #533: a new user starts with no conversations and no unread
    /// badge, whatever the previous one left in memory.
    #[tokio::test]
    async fn clearing_the_store_leaves_no_chats_and_no_unread_count() {
        let store = MessageStore::new();
        let trade_id = uuid::Uuid::new_v4().to_string();
        let mut unread = store.unread_tx.subscribe();
        store
            .add_message(notification_test_message(&trade_id, 1))
            .await;
        assert_eq!(store.messages.read().await.len(), 1);
        assert!(store.hydrated.read().await.contains(&trade_id));
        assert_eq!(store.unread_count_inner().await, 1);

        store.clear().await;

        // Asserted on the maps `clear` owns, not through `get_messages`: that
        // read re-hydrates from the process-wide database, where a parallel
        // test may have had this message persisted. In the app the rows are
        // wiped first, so the re-hydration `clear` allows finds nothing.
        assert!(store.messages.read().await.is_empty());
        assert!(store.hydrated.read().await.is_empty());
        assert!(store.non_durable.read().await.is_empty());
        assert_eq!(store.unread_count_inner().await, 0);
        // The badge is pushed, not polled: the last value published is zero.
        let mut last = None;
        while let Ok(count) = unread.try_recv() {
            last = Some(count);
        }
        assert_eq!(last, Some(0));
    }

    #[tokio::test]
    async fn notification_stream_recovers_every_message_after_lag() {
        let store = MessageStore::new();
        let trade_id = uuid::Uuid::new_v4().to_string();
        let mut stream = AnyMessageStream::new(&store);
        // Exhaust startup reconciliation first, so this tests actual lag recovery.
        stream.replay_at = crate::rt::time::Instant::now() + std::time::Duration::from_secs(60);
        for i in 0..70 {
            store
                .add_message(notification_test_message(&trade_id, i))
                .await;
        }
        let mut received = Vec::new();
        while received.len() < 70 {
            let msg =
                tokio::time::timeout(std::time::Duration::from_secs(5), stream.next_from(&store))
                    .await
                    .unwrap()
                    .unwrap();
            if msg.trade_id == trade_id {
                received.push(msg.created_at);
            }
        }
        assert_eq!(received, (0..70).collect::<Vec<_>>());
    }

    #[tokio::test]
    async fn notification_stream_retries_without_another_relay_message() {
        let store = MessageStore::new();
        let trade_id = uuid::Uuid::new_v4().to_string();
        store
            .add_message(notification_test_message(&trade_id, 1))
            .await;
        // No receiver existed at send time. Startup still recovers the message.
        let mut stream = AnyMessageStream::new(&store);
        for _ in 0..2 {
            loop {
                let msg = tokio::time::timeout(
                    std::time::Duration::from_secs(5),
                    stream.next_from(&store),
                )
                .await
                .unwrap()
                .unwrap();
                if msg.trade_id == trade_id {
                    break;
                }
            }
            // Simulate the recovery deadline after a failed Dart write.
            stream.pending.clear();
            stream.replay_at = crate::rt::time::Instant::now();
        }
    }

    #[tokio::test]
    async fn notification_stream_drops_queued_messages_read_since_snapshot() {
        let store = MessageStore::new();
        let trade_id = uuid::Uuid::new_v4().to_string();
        let msg = notification_test_message(&trade_id, 1);
        store.add_message(msg.clone()).await;
        store.mark_as_read(&trade_id).await;
        assert!(store.notification_candidate_now(msg).await.is_none());
        assert!(!store
            .notification_backlog()
            .await
            .unwrap()
            .iter()
            .any(|m| m.trade_id == trade_id));
    }

    use super::*;
    use crate::api::types::FileType;

    const PEER: &str = "aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11";

    #[test]
    fn a_message_no_relay_accepted_wakes_nobody() {
        // `send_message` and `send_file` both gate `wake_peer` on this: an
        // empty `output.success` still comes back as `Ok` from the pool.
        assert_eq!(peer_to_wake(false, PEER), None);
    }

    #[test]
    fn a_message_some_relay_accepted_wakes_the_peer() {
        assert_eq!(peer_to_wake(true, PEER), Some(PEER));
    }

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

    /// Issue #474: the Notifications cards read one stream for every trade's
    /// chat, where the per-trade stream drops all but one.
    #[tokio::test]
    async fn the_any_message_stream_carries_every_trade() {
        let mut stream = on_any_new_message().await.unwrap();
        let first = uuid::Uuid::new_v4().to_string();
        let second = uuid::Uuid::new_v4().to_string();
        for (index, trade_id) in [&first, &second].into_iter().enumerate() {
            message_store()
                .add_message(ChatMessage {
                    id: uuid::Uuid::new_v4().to_string(),
                    trade_id: trade_id.clone(),
                    sender_pubkey: "peer".into(),
                    content: "hi".into(),
                    message_type: MessageType::Peer,
                    is_mine: false,
                    is_read: false,
                    has_attachment: false,
                    attachment: None,
                    created_at: index as i64 + 1,
                    reactions: Vec::new(),
                })
                .await;
        }

        // Parallel tests share the store, so only our two trades count.
        let mut seen = Vec::new();
        while seen.len() < 2 {
            let msg = tokio::time::timeout(std::time::Duration::from_secs(5), stream.next())
                .await
                .expect("a message within 5s")
                .expect("stream open");
            if msg.trade_id == first || msg.trade_id == second {
                seen.push(msg.trade_id);
            }
        }
        assert_eq!(seen, vec![first, second]);
    }

    #[test]
    fn the_peer_channel_keeps_its_wire_identity() {
        // The peer subscription id is unchanged by the channel refactor: a
        // different string would orphan subscriptions across an app upgrade.
        assert_eq!(
            chat_subscription_id(ChatChannel::Peer, "order-1"),
            nostr_sdk::prelude::SubscriptionId::new("mostro-chat-order-1")
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
            .finalize(&sign)
            .unwrap();

        let mut state = ChatRxState::new(ChatChannel::Peer, 0, None);
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
        let mut big = b"%PDF-".to_vec();
        big.resize(crate::attachments::MAX_ATTACHMENT_BYTES + 1, 0);
        let err = send_file(trade_id, big, "test.pdf".into(), "u1".into()).await.unwrap_err();
        assert!(err.to_string().starts_with("FileTooLarge"), "got: {err}");
    }

    #[tokio::test]
    async fn only_jpeg_png_and_pdf_are_sent_whatever_the_name_says() {
        let trade_id = uuid::Uuid::new_v4().to_string();
        let err = send_file(trade_id, b"MZ\x90\x00".to_vec(), "receipt.pdf".into(), "u2".into())
            .await
            .unwrap_err();
        assert!(err.to_string().starts_with("UnsupportedFileType"), "got: {err}");
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
            reactions: Vec::new(),
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

    #[tokio::test]
    async fn send_file_fails_without_session() {
        let trade_id = uuid::Uuid::new_v4().to_string();
        let result = send_file(
            trade_id,
            b"%PDF-1.4\n%%EOF".to_vec(),
            "receipt.pdf".to_string(),
            "u3".to_string(),
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
            blossom_url: format!("https://blossom.example.com/{}", "a".repeat(64)),
            sha256: "a".repeat(64),
            encrypted_size: 128,
            width: Some(10),
            height: Some(10),
            counterpart_pubkey: None,
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
            reactions: Vec::new(),
        };
        store.add_message(msg).await;

        let result = download_attachment(msg_id.clone()).await;
        assert!(result.is_err());
        let err = result.unwrap_err().to_string();
        assert!(err.contains("SessionNotFound"), "got: {err}");
        // A failure leaves a retryable state, not a stale Pending.
        assert_eq!(get_attachment_status(msg_id).await.unwrap(), Some(DownloadStatus::Failed));
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
            reactions: Vec::new(),
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
    fn chat_payload_parses_v1_attachments_and_plaintext() {
        // A v1 image message → content is the file name, attachment populated.
        let hash = "b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553";
        let file = serde_json::json!({
            "type": "image_encrypted",
            "blossom_url": format!("https://cdn.hzrd149.com/{hash}"),
            "nonce": "0102030405060708090a0b0c",
            "mime_type": "image/jpeg",
            "original_size": 12345,
            "width": 800,
            "height": 600,
            "filename": "receipt.jpg",
            "encrypted_size": 12373,
        })
        .to_string();
        let (content, att) = parse_chat_payload(&file);
        assert_eq!(content, "receipt.jpg");
        let att = att.expect("attachment expected");
        assert_eq!(att.file_name, "receipt.jpg");
        assert_eq!(att.file_size, 12345);
        assert_eq!(att.sha256, hash);
        assert_eq!((att.width, att.height), (Some(800), Some(600)));
        assert!(matches!(att.file_type, FileType::Image));
        assert!(matches!(att.download_status, DownloadStatus::Pending));

        // Plaintext stays as-is.
        let (content, att) = parse_chat_payload("hola, ¿pagaste?");
        assert_eq!(content, "hola, ¿pagaste?");
        assert!(att.is_none());

        // JSON that is not a v1 attachment (here, v2's old never-sent
        // shape) is displayed verbatim, not misinterpreted.
        let (content, att) = parse_chat_payload(r#"{"type":"file","url":"x"}"#);
        assert_eq!(content, r#"{"type":"file","url":"x"}"#);
        assert!(
            att.is_none(),
            "incomplete pointer must not become an attachment"
        );
    }

    #[test]
    fn bucket_is_bypassed_during_stored_catchup() {
        use crate::rt::time::Instant;

        // Pre-EOSE (catch-up): a backlog far above the burst size is all
        // accepted — dropping stored history would lose it permanently
        // because the cursor advances past it.
        let mut state = ChatRxState::new(ChatChannel::Peer, 0, None);
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
                reactions: Vec::new(),
            })
            .await;
        assert!(!store.quota_exceeded(&trade_id, 5).await);
        assert!(store.quota_exceeded(&trade_id, 50).await);

        // An untouched trade has room.
        let other = uuid::Uuid::new_v4().to_string();
        assert!(!store.quota_exceeded(&other, 1024).await);
    }

    /// #523: a finished trade gives its chat REQs back. Stopping releases
    /// both channels' ownership — the running tasks exit at their next wake —
    /// and reports which were running; an order with no chat is a no-op.
    #[tokio::test]
    async fn stopping_a_finished_trades_chats_releases_both_channels() {
        let order = format!("stop-{}", uuid::Uuid::new_v4());
        let peer = claim_chat(ChatChannel::Peer, &order).await.expect("claim");
        let dispute = claim_chat(ChatChannel::Dispute, &order).await.expect("claim");

        let stopped = stop_chat_subscriptions(&order).await;

        assert_eq!(stopped, vec![ChatChannel::Peer, ChatChannel::Dispute]);
        assert!(!chat_is_current(ChatChannel::Peer, &order, peer).await);
        assert!(!chat_is_current(ChatChannel::Dispute, &order, dispute).await);
        assert!(stop_chat_subscriptions(&order).await.is_empty());
    }

    /// Codex review of #638: a dispute chat task stopped by a solver
    /// takeover can still be handling an event. Its cursor write must not
    /// land once it no longer owns the chat, or it would restore the previous
    /// conversation's `since` after the takeover reset it.
    #[tokio::test]
    async fn a_stopped_chat_task_does_not_write_the_cursor() {
        let path = std::env::temp_dir()
            .join(format!("mostro_dispute_takeover_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let Some(db) = crate::db::app_db::db() else {
            panic!("no store: the cursor gate cannot be exercised");
        };
        let order = format!("stopped-cursor-{}", uuid::Uuid::new_v4());
        let key = ChatChannel::Dispute.cursor_key(&order);
        let now = unix_now();

        let generation = claim_chat(ChatChannel::Dispute, &order).await.expect("claim");
        let mut state = ChatRxState::new(ChatChannel::Dispute, 0, Some(generation));
        state.live = true;
        state.caught_up = true;
        state.advance_cursor(&order, now - 20).await;
        assert_eq!(
            db.get_setting(&key).await.unwrap(),
            Some((now - 20).to_string()),
            "the owning task writes its cursor"
        );

        stop_chat_subscription(ChatChannel::Dispute, &order).await;
        reset_chat_cursor(ChatChannel::Dispute, &order).await;
        state.advance_cursor(&order, now - 10).await;
        assert_eq!(
            db.get_setting(&key).await.unwrap(),
            None,
            "a stopped task must not restore the cursor"
        );
    }

    /// Codex and CodeRabbit review of #638: a dispute chat task can be
    /// stopped by a takeover after its claim but before it installs its relay
    /// subscription. It must not install it then: the id is shared with the
    /// new solver's task, whose filter it would overwrite.
    #[tokio::test]
    async fn a_chat_task_stopped_before_subscribing_installs_nothing() {
        let order = format!("claimed-before-req-{}", uuid::Uuid::new_v4());
        let client = nostr_sdk::prelude::Client::default();
        let filter = || {
            nostr_sdk::prelude::Filter::new().kind(nostr_sdk::prelude::Kind::PrivateDirectMessage)
        };

        let old = claim_chat(ChatChannel::Dispute, &order).await.expect("claim");
        stop_chat_subscription(ChatChannel::Dispute, &order).await;
        let new = claim_chat(ChatChannel::Dispute, &order).await.expect("claim");

        let sub_id = chat_subscription_id(ChatChannel::Dispute, &order);
        assert!(
            replace_chat_subscription_if_current(
                ChatChannel::Dispute,
                &order,
                old,
                &client,
                sub_id.clone(),
                filter(),
            )
            .await
            .is_none(),
            "the stopped task must not install its subscription"
        );
        assert!(
            replace_chat_subscription_if_current(
                ChatChannel::Dispute,
                &order,
                new,
                &client,
                sub_id.clone(),
                filter(),
            )
            .await
            .is_some(),
            "the owning task installs it"
        );

        crate::nostr::live_subs::live_subs().close(&client, &sub_id).await;
        release_chat(ChatChannel::Dispute, &order, new).await;
    }

    /// Codex review of #638: a new dispute chat task (a reconnect's
    /// resubscribe for the new solver) can try to claim the chat while the
    /// takeover is still handing it over. It must only get the chat once the
    /// handover is complete, or it loads the previous conversation's `since`.
    /// The old REQ's close sits under the same lock, but needs a relay pool,
    /// which unit tests do not have, so only the cursor is observed here.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn a_claim_during_the_handover_sees_it_complete() {
        let path = std::env::temp_dir()
            .join(format!("mostro_dispute_takeover_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let Some(db) = crate::db::app_db::db() else {
            panic!("no store: the cursor reset cannot be exercised");
        };
        let client = std::sync::Arc::new(nostr_sdk::prelude::Client::default());
        let filter = || {
            nostr_sdk::prelude::Filter::new().kind(nostr_sdk::prelude::Kind::PrivateDirectMessage)
        };

        for _ in 0..30 {
            let order = format!("handover-{}", uuid::Uuid::new_v4());
            let sub_id = chat_subscription_id(ChatChannel::Dispute, &order);
            db.set_setting(&ChatChannel::Dispute.cursor_key(&order), "500")
                .await
                .unwrap();
            let old = claim_chat(ChatChannel::Dispute, &order).await.expect("claim");
            let _ = replace_chat_subscription_if_current(
                ChatChannel::Dispute,
                &order,
                old,
                &client,
                sub_id.clone(),
                filter(),
            )
            .await;

            let new_task = {
                let order = order.clone();
                let client = client.clone();
                let sub_id = sub_id.clone();
                tokio::spawn(async move {
                    let generation = loop {
                        if let Some(g) = claim_chat(ChatChannel::Dispute, &order).await {
                            break g;
                        }
                        tokio::task::yield_now().await;
                    };
                    let cursor = load_chat_cursor(ChatChannel::Dispute, &order).await;
                    let _ = replace_chat_subscription_if_current(
                        ChatChannel::Dispute,
                        &order,
                        generation,
                        &client,
                        sub_id,
                        filter(),
                    )
                    .await;
                    (generation, cursor)
                })
            };
            hand_over_dispute_chat(&order).await;
            let (generation, cursor) = new_task.await.unwrap();

            assert_eq!(cursor, None, "the new task must not load the old cursor");

            crate::nostr::live_subs::live_subs().close(&client, &sub_id).await;
            release_chat(ChatChannel::Dispute, &order, generation).await;
        }
    }

    /// Codex review of #638: a task's own cleanup releases and closes only
    /// while it owns the chat. After a takeover handed the chat to a new task,
    /// the old task's cleanup leaves the new claim (and so its REQ) alone. The
    /// close runs under the same lock as the release; unit tests have no relay
    /// pool, so only the claim is observed here.
    #[tokio::test]
    async fn a_chat_tasks_cleanup_leaves_its_replacement_alone() {
        let order = format!("cleanup-{}", uuid::Uuid::new_v4());
        let old = claim_chat(ChatChannel::Dispute, &order).await.expect("claim");
        stop_chat_subscription(ChatChannel::Dispute, &order).await;
        let new = claim_chat(ChatChannel::Dispute, &order).await.expect("claim");

        assert!(!release_and_close_chat(ChatChannel::Dispute, &order, old).await);
        assert!(chat_is_current(ChatChannel::Dispute, &order, new).await);

        assert!(release_and_close_chat(ChatChannel::Dispute, &order, new).await);
        assert!(!chat_is_current(ChatChannel::Dispute, &order, new).await);
    }

    /// PR #527 review: stop, then a replacement task claims the same chat,
    /// then the old task finally exits. The old task's cleanup must not take
    /// the replacement's ownership (nor, therefore, close its REQ).
    #[tokio::test]
    async fn an_old_chat_task_cannot_release_its_replacement() {
        let order = format!("swap-{}", uuid::Uuid::new_v4());
        let old = claim_chat(ChatChannel::Peer, &order).await.expect("first claim");
        // One owner at a time.
        assert!(claim_chat(ChatChannel::Peer, &order).await.is_none());

        stop_chat_subscriptions(&order).await;
        let new = claim_chat(ChatChannel::Peer, &order).await.expect("replacement");
        assert_ne!(old, new);

        // The old task wakes: it is no longer current, and releasing reports
        // that it owned nothing — so its cleanup leaves the REQ alone.
        assert!(!chat_is_current(ChatChannel::Peer, &order, old).await);
        assert!(!release_chat(ChatChannel::Peer, &order, old).await);
        assert!(chat_is_current(ChatChannel::Peer, &order, new).await);

        assert!(release_chat(ChatChannel::Peer, &order, new).await);
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
                maker_since: None,
                cashu_mint_url: None,
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
            peer_since: None,
            rated_at: None,
            bond: None,
            buyer_trade_pubkey: None,
            seller_trade_pubkey: None,
            cashu_mint_url: None,
            cashu_escrow_token: None,
            cashu_locked_at: None,
            cashu_rejected_escrow_tokens: Vec::new(),
        };
        assert!(chat_still_relevant(&base));

        let mut done = base.clone();
        done.outcome = Some(TradeOutcome::Success);
        assert!(!chat_still_relevant(&done));

        let mut no_peer = base.clone();
        no_peer.counterparty_pubkey = String::new();
        assert!(!chat_still_relevant(&no_peer));

        // A pre-#334 row seeded with `creator_pubkey` holds the Mostro node
        // itself as "counterparty" — deriving chat keys from it would claim
        // the subscription guard with garbage and block the real reveal.
        let mut daemon_peer = base.clone();
        daemon_peer.counterparty_pubkey = crate::config::active_mostro_pubkey();
        assert!(!chat_still_relevant(&daemon_peer));

        // Same poison, different node: the trades table is not scoped per
        // node, so a row seeded while ANOTHER node was active carries that
        // node's pubkey — which never equals the currently-active one. The
        // row-local `creator_pubkey` comparison is what catches it.
        let mut other_node_peer = base.clone();
        other_node_peer.counterparty_pubkey = "maker".into(); // == creator_pubkey
        assert!(!chat_still_relevant(&other_node_peer));

        let mut canceled = base;
        canceled.order.status = OrderStatus::Canceled;
        assert!(!chat_still_relevant(&canceled));
    }

    /// #642: a completed trade's chat stays relevant for the grace window
    /// after its recorded completion, and only a `success` gets one.
    #[test]
    fn a_completed_trade_keeps_its_chat_for_the_grace_window() {
        use crate::api::types::*;
        let done_at = 1_700_000_000;
        let mut done = live_trade("order-grace", "peer", 1);
        done.order.status = OrderStatus::Success;
        done.completed_at = Some(done_at);

        assert_eq!(
            chat_grace_ends_at(&done),
            Some(done_at + PEER_CHAT_GRACE_SECS)
        );
        assert!(chat_still_relevant_at(&done, done_at));
        assert!(chat_still_relevant_at(
            &done,
            done_at + PEER_CHAT_GRACE_SECS - 1
        ));
        assert!(!chat_still_relevant_at(
            &done,
            done_at + PEER_CHAT_GRACE_SECS
        ));

        // Completed before the time was recorded: closed, as before.
        let mut legacy = done.clone();
        legacy.completed_at = None;
        assert_eq!(chat_grace_ends_at(&legacy), None);
        assert!(!chat_still_relevant_at(&legacy, done_at));

        // No window for any other ending.
        for status in [
            OrderStatus::Canceled,
            OrderStatus::CooperativelyCanceled,
            OrderStatus::Expired,
            OrderStatus::CanceledByAdmin,
            OrderStatus::SettledByAdmin,
            OrderStatus::CompletedByAdmin,
        ] {
            let mut ended = done.clone();
            ended.order.status = status.clone();
            assert!(!chat_still_relevant_at(&ended, done_at), "{status:?}");
        }

        // Still no chat without a usable peer.
        let mut no_peer = done;
        no_peer.counterparty_pubkey = String::new();
        assert!(!chat_still_relevant_at(&no_peer, done_at));
    }

    /// #642 review: a chat is over once its trade ended — a `success` only
    /// once its grace window ran out — whatever the row says of the peer.
    #[test]
    fn a_chat_is_over_once_its_trade_ended_outside_the_window() {
        use crate::api::types::*;
        let done_at = 1_700_000_000;
        let mut done = live_trade("order-closed", "peer", 1);
        done.order.status = OrderStatus::Success;
        done.completed_at = Some(done_at);
        assert!(!chat_closed_at(&done, done_at + PEER_CHAT_GRACE_SECS - 1));
        assert!(chat_closed_at(&done, done_at + PEER_CHAT_GRACE_SECS));

        let mut unknown = done.clone();
        unknown.completed_at = None;
        assert!(chat_closed_at(&unknown, done_at), "completed at an unknown time");

        for status in [
            OrderStatus::Canceled,
            OrderStatus::CooperativelyCanceled,
            OrderStatus::Expired,
            OrderStatus::CanceledByAdmin,
            OrderStatus::SettledByAdmin,
            OrderStatus::CompletedByAdmin,
        ] {
            let mut ended = done.clone();
            ended.order.status = status.clone();
            assert!(chat_closed_at(&ended, done_at), "{status:?}");
        }
        for status in [
            OrderStatus::Active,
            OrderStatus::FiatSent,
            OrderStatus::SettledHoldInvoice,
            OrderStatus::Dispute,
            OrderStatus::WaitingTakerBond,
            OrderStatus::WaitingMakerBond,
        ] {
            let mut live = done.clone();
            live.order.status = status.clone();
            live.counterparty_pubkey = String::new();
            assert!(!chat_closed_at(&live, done_at), "{status:?}");
        }
    }

    /// #642 review: a grace window can run out between the decision to start
    /// a peer listener and its claim. The listener asks the row right after
    /// the claim, so the window's timer either finds the task or the task
    /// finds the chat closed — never a listener left with no timer.
    #[test]
    fn a_peer_listener_asks_its_row_right_after_its_claim() {
        let source = include_str!("messages.rs");
        let start = source
            .find("pub(crate) async fn subscribe_incoming_chat(")
            .expect("the listener exists");
        let body = &source[start..start + source[start..].find("\n}\n").expect("it ends")];
        let claim = body.find("let Some(generation) = claimed").expect("the claim");
        let gate = body.find("persisted_chat_closed(&order_id)").expect("the row is asked");
        let run = body.find("run_chat_subscription(").expect("the subscription");
        assert!(claim < gate && gate < run, "claim, then the row, then the REQ");
    }

    /// #642 review: a cached session does not outlive the chat. Past the
    /// window, after any other ending, or completed at an unknown time, the
    /// send paths get no session; inside the window, on a live trade, or
    /// before the row exists, the cached one still serves.
    #[tokio::test]
    async fn a_cached_session_does_not_outlive_the_chat() {
        use crate::api::types::OrderStatus;
        let path = std::env::temp_dir().join(format!("mostro_chat_gate_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");
        let now = unix_now();
        let peer = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let cached = |status: OrderStatus, completed_at: Option<i64>, saved: bool| {
            let mut row = live_trade(&format!("gate-{}", uuid::Uuid::new_v4()), &peer, 3);
            row.order.status = status;
            row.completed_at = completed_at;
            async move {
                crate::mostro::session::session_manager()
                    .create_session_with_peer(
                        row.order.id.clone(),
                        row.role.clone(),
                        row.trade_key_index,
                        row.order.clone(),
                        row.counterparty_pubkey.clone(),
                        [7; 32],
                    )
                    .await
                    .expect("session cached");
                if saved {
                    db.save_trade(&row).await.expect("row saved");
                }
                row.order.id
            }
        };

        let past = Some(now - PEER_CHAT_GRACE_SECS - 10);
        for (status, at) in [
            (OrderStatus::Success, past),
            (OrderStatus::Success, None),
            (OrderStatus::Canceled, None),
            (OrderStatus::Expired, None),
            (OrderStatus::SettledByAdmin, None),
        ] {
            let id = cached(status.clone(), at, true).await;
            assert!(session_or_rebuild(&id).await.is_none(), "{status:?} {at:?}");
        }
        for (status, at, saved) in [
            (OrderStatus::Success, Some(now - 60), true),
            (OrderStatus::FiatSent, None, true),
            (OrderStatus::Active, None, false),
        ] {
            let id = cached(status.clone(), at, saved).await;
            assert!(session_or_rebuild(&id).await.is_some(), "{status:?} saved={saved}");
        }
    }

    /// A live trade row shaped like the ones `take_order` persists after the
    /// peer reveal: known counterparty, non-terminal status.
    fn live_trade(order_id: &str, counterparty: &str, index: u32) -> crate::api::types::TradeInfo {
        use crate::api::types::*;
        TradeInfo {
            id: order_id.into(),
            order: OrderInfo {
                id: order_id.into(),
                kind: OrderKind::Sell,
                status: OrderStatus::Active,
                amount_sats: None,
                fiat_amount: Some(100.0),
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
                maker_since: None,
                cashu_mint_url: None,
            },
            role: TradeRole::Buyer,
            counterparty_pubkey: counterparty.into(),
            current_step: TradeStep::Buyer(BuyerStep::FiatSent),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: index,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            peer_since: None,
            rated_at: None,
            bond: None,
            buyer_trade_pubkey: None,
            seller_trade_pubkey: None,
            cashu_mint_url: None,
            cashu_escrow_token: None,
            cashu_locked_at: None,
            cashu_rejected_escrow_tokens: Vec::new(),
        }
    }

    /// The derivation half of the #381 fallback: a live row plus our trade
    /// keys yields a session carrying the row's role/index/peer and the real
    /// ECDH shared key. Exercised with generated keys — loading a real
    /// identity would mutate process-global state (same seam as the
    /// `apply_peer_reveal` tests in orders.rs).
    #[tokio::test]
    async fn rebuild_session_derives_from_trade_row() {
        let order_id = uuid::Uuid::new_v4().to_string();
        let trade_keys = nostr_sdk::prelude::Keys::generate();
        let peer_keys = nostr_sdk::prelude::Keys::generate();
        let trade = live_trade(&order_id, &peer_keys.public_key().to_hex(), 9);

        let session = rebuild_session(&trade, &trade_keys)
            .await
            .expect("live row must rebuild a session");
        assert!(matches!(session.role, crate::api::types::TradeRole::Buyer));
        assert_eq!(session.trade_key_index, 9);
        assert_eq!(
            session.peer_pubkey.as_deref(),
            Some(trade.counterparty_pubkey.as_str())
        );
        let expected =
            crate::crypto::ecdh::derive_nip04_shared_key(&trade_keys, &peer_keys.public_key())
                .expect("ECDH derivation");
        assert_eq!(session.shared_key, Some(expected));

        // Benign race arm: a second rebuild finds the session already created
        // and returns the EXISTING one — even when called with other keys, it
        // must not overwrite the first derivation.
        let other_keys = nostr_sdk::prelude::Keys::generate();
        let again = rebuild_session(&trade, &other_keys)
            .await
            .expect("existing session is returned, not rebuilt");
        assert_eq!(again.shared_key, Some(expected));
    }

    /// A garbage counterparty on the row degrades to `None` — no session, no
    /// panic. (Poisoned/terminal/empty rows never reach the derivation at
    /// all: `session_or_rebuild` filters them with `chat_still_relevant`,
    /// covered above.)
    /// A finished trade's history stays openable after a restart (#590
    /// review): with no session, the attachment key comes from the row even
    /// though `chat_still_relevant` refuses to rebuild a chat for it.
    #[test]
    fn attachment_conversation_comes_from_a_finished_trade_row() {
        let peer = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let mut trade = live_trade("o", &peer, 7);
        trade.order.status = crate::api::types::OrderStatus::Success;
        assert!(!chat_still_relevant(&trade));
        assert_eq!(conversation_of(None, Some(&trade)), Some((7, Some(peer))));

        trade.counterparty_pubkey.clear();
        assert_eq!(conversation_of(None, Some(&trade)), Some((7, None)));
        assert_eq!(conversation_of(None, None), None);
    }

    /// PR #590 review: once a dispute is resolved its solver key is cleared
    /// and a restart does not rehydrate it — the solver's attachments are
    /// still decrypted with the authenticated sender kept on the message.
    #[test]
    fn solver_attachment_counterpart_survives_the_resolved_dispute() {
        let solver = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let peer = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let mut msg = notification_test_message("o", 1);
        msg.message_type = MessageType::Admin;
        msg.sender_pubkey = solver.clone();

        // No live dispute (resolved, then restarted): the sender answers.
        assert_eq!(
            counterpart_of(&msg, Some(peer.clone()), None),
            Some(solver.clone())
        );

        // Our own message to the solver names us as sender: only the live
        // dispute knows who it went to.
        msg.is_mine = true;
        assert_eq!(counterpart_of(&msg, Some(peer.clone()), None), None);
        assert_eq!(
            counterpart_of(&msg, Some(peer.clone()), Some(solver.clone())),
            Some(solver)
        );

        msg.message_type = MessageType::Peer;
        assert_eq!(counterpart_of(&msg, Some(peer.clone()), None), Some(peer));
        msg.message_type = MessageType::System;
        assert_eq!(counterpart_of(&msg, None, None), None);
    }

    /// PR #596 review: a file we sent to the solver names the solver it was
    /// encrypted to, so it still opens once the resolved dispute is gone —
    /// and that record wins over whoever the live dispute names.
    #[test]
    fn own_solver_attachment_keeps_its_recipient() {
        let solver = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let other = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let mut msg = notification_test_message("o", 1);
        msg.message_type = MessageType::Admin;
        msg.is_mine = true;
        msg.sender_pubkey = "me".into();
        let (_, attachment) = parse_chat_payload(
            &crate::attachments::payload::AttachmentPayload::File(
                crate::attachments::payload::FilePayload {
                    file_type: "document".into(),
                    blossom_url: format!("https://blossom.example/{}", "a".repeat(64)),
                    nonce: "00".repeat(12),
                    mime_type: "application/pdf".into(),
                    original_size: 10,
                    filename: "r.pdf".into(),
                    encrypted_size: 38,
                },
            )
            .to_json(),
        );
        let mut attachment = attachment.expect("a v1 file parses");
        // Nothing read from the wire names a recipient.
        assert_eq!(attachment.counterpart_pubkey, None);
        attachment.counterpart_pubkey = Some(solver.clone());
        msg.attachment = Some(attachment);

        assert_eq!(counterpart_of(&msg, None, None), Some(solver.clone()));
        assert_eq!(counterpart_of(&msg, None, Some(other)), Some(solver));
    }

    /// PR #590 review: a transfer that resumes after its identity was
    /// deleted must not put the blob back into the wiped cache. A generation
    /// no identity holds stands for the deleted one — the global identity is
    /// driven only by the identity lifecycle test, which covers the fence.
    #[tokio::test]
    async fn a_transfer_of_a_deleted_identity_does_not_refill_the_cache() {
        let path = std::env::temp_dir().join(format!(
            "mostro-attachment-fence-{}.db",
            uuid::Uuid::new_v4()
        ));
        let db = crate::db::sqlite::SqliteStorage::open(path.to_str().unwrap())
            .await
            .unwrap();
        let sha = "b".repeat(64);

        assert!(!cache_attachment_blob(Some(&db), Some(u64::MAX), &sha, b"blob").await);
        assert!(!cache_attachment_blob(Some(&db), None, &sha, b"blob").await);
        assert_eq!(db.get_attachment_blob(&sha).await.unwrap(), None);

        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn rebuild_session_rejects_unparseable_peer() {
        let order_id = uuid::Uuid::new_v4().to_string();
        let trade_keys = nostr_sdk::prelude::Keys::generate();
        let trade = live_trade(&order_id, "not-a-pubkey", 1);
        assert!(rebuild_session(&trade, &trade_keys).await.is_none());
        assert!(crate::mostro::session::session_manager()
            .get_session(&order_id)
            .await
            .is_none());
    }

    /// The seam test for #381: `session_or_rebuild` is only useful if the
    /// three chat functions actually call it — this drives `send_message`
    /// end to end from a persisted row with NO session and asserts it takes
    /// the publishable path (sender = our trade key, not the local-only
    /// empty marker) and leaves the rebuilt session in the manager. Deleting
    /// the fallback from `send_message` fails this test.
    ///
    /// `#[ignore]`d because it claims the process-global `app_db` OnceCell
    /// and identity (same pattern and same mnemonic as
    /// `peer_reveal_capture_is_wired_into_dispatch` in orders.rs, so the two
    /// coexist under `--ignored`). Run with:
    ///   cargo test --lib send_message_rebuilds_session -- --ignored
    #[tokio::test]
    #[ignore = "claims the process-global app_db and identity — run with --ignored"]
    async fn send_message_rebuilds_session_from_trade_row() {
        let db_path =
            std::env::temp_dir().join(format!("mostro-381-seam-test-{}.db", uuid::Uuid::new_v4()));
        crate::db::app_db::init_db(db_path.to_str().unwrap())
            .await
            .expect("init app db");
        crate::api::identity::import_from_mnemonic(
            "abandon abandon abandon abandon abandon abandon abandon abandon \
             abandon abandon abandon about"
                .split_whitespace()
                .map(String::from)
                .collect(),
            false,
        )
        .await
        .expect("import identity");

        let trade_index = 5u32;
        let trade_keys = crate::api::identity::get_active_trade_keys(trade_index)
            .await
            .expect("derive trade key");
        let peer_keys = nostr_sdk::prelude::Keys::generate();
        let peer_hex = peer_keys.public_key().to_hex();

        let order_id = uuid::Uuid::new_v4().to_string();
        crate::db::app_db::db()
            .expect("db just initialized")
            .save_trade(&live_trade(&order_id, &peer_hex, trade_index))
            .await
            .expect("save the post-reveal row");
        assert!(
            crate::mostro::session::session_manager()
                .get_session(&order_id)
                .await
                .is_none(),
            "the restart shape: row persisted, session gone"
        );

        let msg = send_message(order_id.clone(), "hola".into())
            .await
            .expect("send returns the stored message");

        // Publishable path, not local-only: the sender is our trade key.
        // (Publish itself fails harmlessly here — no relay pool in tests —
        // but local-only would have left sender_pubkey empty.)
        assert_eq!(msg.sender_pubkey, trade_keys.public_key().to_hex());

        // And the rebuilt session is now cached for every later call.
        let session = crate::mostro::session::session_manager()
            .get_session(&order_id)
            .await
            .expect("fallback must leave the session in the manager");
        assert_eq!(session.peer_pubkey.as_deref(), Some(peer_hex.as_str()));
        let expected =
            crate::crypto::ecdh::derive_nip04_shared_key(&trade_keys, &peer_keys.public_key())
                .expect("ECDH derivation");
        assert_eq!(session.shared_key, Some(expected));

        // The safety-gate leg: a poisoned pre-#334 row names the node that
        // authored the book order as "counterparty". That pubkey is VALID,
        // so without the `chat_still_relevant` gate the rebuild succeeds and
        // this send encrypts chat to the node — deleting the gate from
        // `session_or_rebuild` fails these assertions (before this leg, the
        // gate survived every mutation).
        let node_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let poisoned_id = uuid::Uuid::new_v4().to_string();
        let mut poisoned = live_trade(&poisoned_id, &node_hex, trade_index);
        poisoned.order.creator_pubkey = node_hex.clone();
        crate::db::app_db::db()
            .expect("db still initialized")
            .save_trade(&poisoned)
            .await
            .expect("save the poisoned row");

        let msg = send_message(poisoned_id.clone(), "hola".into())
            .await
            .expect("poisoned row still returns Ok — but local-only");
        assert_eq!(
            msg.sender_pubkey, "",
            "poisoned row must stay on the local-only path, never publish"
        );
        assert!(
            crate::mostro::session::session_manager()
                .get_session(&poisoned_id)
                .await
                .is_none(),
            "no session may be rebuilt toward the node's pubkey"
        );

        let _ = std::fs::remove_file(&db_path);
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
                reactions: Vec::new(),
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
            reactions: Vec::new(),
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
            reactions: Vec::new(),
        };
        message_store().add_message(target.clone()).await;

        let received = stream.next().await.expect("should receive a message");
        assert_eq!(received.trade_id, trade_id);
        assert_eq!(received.content, "hello");
    }

    // ── Reactions (protocol chat.md, "Reactions") ────────────────────────────

    fn reaction(sender: &str, emoji: &str, created_at: i64, event_id: &str) -> ChatReaction {
        ChatReaction {
            sender_pubkey: sender.to_string(),
            emoji: emoji.to_string(),
            created_at,
            event_id: event_id.to_string(),
        }
    }

    #[test]
    fn a_message_stored_before_reactions_still_loads() {
        let stored = r#"{"id":"m","trade_id":"t","sender_pubkey":"p","content":"hi",
            "message_type":"Peer","is_mine":false,"is_read":true,"has_attachment":false,
            "attachment":null,"created_at":1}"#;

        let msg: ChatMessage = serde_json::from_str(stored).unwrap();

        assert!(msg.reactions.is_empty());
    }

    #[test]
    fn the_newest_reaction_of_a_party_holds() {
        let mut held = Vec::new();

        assert!(merge_reaction(&mut held, reaction("bob", "👍", 10, "b")));
        assert!(merge_reaction(&mut held, reaction("bob", "❤️", 11, "c")));
        assert!(
            !merge_reaction(&mut held, reaction("bob", "👍", 10, "b")),
            "a re-wrapped older reaction changes nothing"
        );

        assert_eq!(held, vec![reaction("bob", "❤️", 11, "c")]);
    }

    #[test]
    fn a_tie_goes_to_the_lowest_event_id_whatever_the_order() {
        let low = reaction("bob", "👍", 10, "aa");
        let high = reaction("bob", "😂", 10, "bb");
        let mut one = Vec::new();
        let mut other = Vec::new();

        merge_reaction(&mut one, low.clone());
        merge_reaction(&mut one, high.clone());
        merge_reaction(&mut other, high);
        merge_reaction(&mut other, low.clone());

        assert_eq!(one, vec![low.clone()]);
        assert_eq!(other, vec![low]);
    }

    #[test]
    fn a_withdrawal_is_kept_so_an_older_reaction_stays_out() {
        let mut held = Vec::new();
        merge_reaction(&mut held, reaction("bob", "👍", 10, "b"));
        merge_reaction(&mut held, reaction("bob", "", 12, "d"));

        assert!(!merge_reaction(&mut held, reaction("bob", "👍", 10, "b")));
        assert_eq!(held, vec![reaction("bob", "", 12, "d")]);
    }

    #[test]
    fn a_change_within_a_second_is_dated_after_the_one_it_replaces() {
        assert_eq!(reaction_time(100, None), Some(100));
        assert_eq!(reaction_time(100, Some(99)), Some(100));
        assert_eq!(reaction_time(100, Some(100)), Some(101));
        assert_eq!(reaction_time(100, Some(101)), Some(102));
    }

    #[test]
    fn a_change_is_never_dated_past_what_receivers_accept() {
        let skew = crate::nostr::transport::MAX_CLOCK_SKEW_SECS as i64;

        assert_eq!(reaction_time(100, Some(100 + skew - 1)), Some(100 + skew));
        assert_eq!(reaction_time(100, Some(100 + skew)), None);
    }

    #[test]
    fn only_the_other_partys_peer_messages_take_a_reaction() {
        let mut msg = notification_test_message("t", 1);
        msg.sender_pubkey = "alice".to_string();

        assert!(reaction_allowed(&msg, &reaction("bob", "👍", 1, "a")));
        assert!(!reaction_allowed(&msg, &reaction("alice", "👍", 1, "a")));
        msg.message_type = MessageType::Admin;
        assert!(!reaction_allowed(&msg, &reaction("bob", "👍", 1, "a")));
    }

    #[tokio::test]
    async fn clearing_the_store_drops_held_reactions() {
        let store = MessageStore::new();
        let msg = ChatMessage {
            sender_pubkey: "alice".to_string(),
            ..notification_test_message("held-trade", 1)
        };
        let outcome = store
            .apply_reaction("held-trade", &msg.id, reaction("bob", "👍", 1, "a"), 1)
            .await;
        assert!(matches!(outcome, ReactionOutcome::Held));

        store.clear().await;
        store.add_message(msg).await;

        assert!(store.get_messages("held-trade").await[0]
            .reactions
            .is_empty());
    }

    /// Alice's side of a peer chat with Bob, fed through `handle_chat_event`.
    struct AliceChat {
        alice: nostr_sdk::prelude::Keys,
        bob: nostr_sdk::prelude::Keys,
        conv: nostr_sdk::prelude::Keys,
        sign: nostr_sdk::prelude::Keys,
        order_id: String,
        state: ChatRxState,
    }

    impl AliceChat {
        fn new() -> Self {
            use nostr_sdk::prelude::Keys;
            let alice = Keys::generate();
            let bob = Keys::generate();
            let (conv, sign) =
                crate::crypto::chat_keys::derive_chat_keys(&alice, &bob.public_key()).unwrap();
            Self {
                alice,
                bob,
                conv,
                sign,
                order_id: uuid::Uuid::new_v4().to_string(),
                state: ChatRxState::new(ChatChannel::Peer, 0, None),
            }
        }

        async fn receive(&mut self, outer: &nostr_sdk::prelude::Event) {
            handle_chat_event(
                ChatChannel::Peer,
                &self.order_id,
                &[self.alice.public_key(), self.bob.public_key()],
                &self.conv,
                &self.sign.public_key(),
                &self.alice.public_key(),
                outer,
                &mut self.state,
            )
            .await;
        }

        /// A message by `author`, wrapped but not received yet.
        async fn message(
            &self,
            author: &nostr_sdk::prelude::Keys,
            text: &str,
        ) -> (nostr_sdk::prelude::Event, nostr_sdk::prelude::Event) {
            crate::nostr::transport::mostro_wrap(author, &self.conv, &self.sign, text)
                .await
                .unwrap()
        }

        /// Bob's reaction to `target`, wrapped but not received yet.
        async fn bob_reacts(
            &self,
            target: &nostr_sdk::prelude::EventId,
            emoji: &str,
        ) -> nostr_sdk::prelude::Event {
            self.bob_reacts_at(target, emoji, unix_now()).await
        }

        async fn bob_reacts_at(
            &self,
            target: &nostr_sdk::prelude::EventId,
            emoji: &str,
            at: i64,
        ) -> nostr_sdk::prelude::Event {
            crate::nostr::transport::mostro_wrap_reaction(
                &self.bob,
                &self.conv,
                &self.sign,
                target,
                emoji,
                nostr_sdk::prelude::Timestamp::from_secs(at as u64),
            )
            .await
            .unwrap()
            .0
        }

        /// The relay's EOSE: stored catch-up is over.
        async fn caught_up(&mut self) {
            let order = self.order_id.clone();
            self.state.caught_up(&order).await;
        }

        async fn messages(&self) -> Vec<ChatMessage> {
            get_messages(self.order_id.clone()).await.unwrap()
        }
    }

    #[tokio::test]
    async fn a_reaction_lands_on_its_message_and_is_never_a_message() {
        let mut chat = AliceChat::new();
        let (outer, inner) = chat.message(&chat.alice.clone(), "fiat sent").await;
        chat.receive(&outer).await; // her own echo
        let mut updates = on_message_updated(chat.order_id.clone()).await.unwrap();
        let mut news = message_store().new_message_tx.subscribe();

        let reaction = chat.bob_reacts(&inner.id, "👍").await;
        chat.receive(&reaction).await;

        let msgs = chat.messages().await;
        assert_eq!(msgs.len(), 1, "a reaction is not a message");
        assert_eq!(msgs[0].reactions.len(), 1);
        assert_eq!(msgs[0].reactions[0].emoji, "👍");
        assert_eq!(
            msgs[0].reactions[0].sender_pubkey,
            chat.bob.public_key().to_hex()
        );
        assert!(msgs.iter().all(|m| m.is_read), "nothing new to read");
        let updated = tokio::time::timeout(std::time::Duration::from_secs(1), updates.next())
            .await
            .expect("the screen hears about the change")
            .unwrap();
        assert_eq!(updated.id, inner.id.to_hex());
        while let Ok(msg) = news.try_recv() {
            assert_ne!(
                msg.trade_id, chat.order_id,
                "no new-message event, so no notification"
            );
        }
    }

    #[tokio::test]
    async fn a_reaction_before_its_message_waits_for_it() {
        let mut chat = AliceChat::new();
        let (outer, inner) = chat
            .message(&chat.alice.clone(), "sent from her laptop")
            .await;

        let reaction = chat.bob_reacts(&inner.id, "😂").await;
        chat.receive(&reaction).await;
        assert!(chat.messages().await.is_empty());
        chat.receive(&outer).await;

        let msgs = chat.messages().await;
        assert_eq!(msgs[0].reactions.len(), 1);
        assert_eq!(msgs[0].reactions[0].emoji, "😂");
    }

    #[tokio::test]
    async fn a_reaction_to_ones_own_message_is_not_shown() {
        let mut chat = AliceChat::new();
        let (outer, inner) = chat.message(&chat.bob.clone(), "hello").await;
        chat.receive(&outer).await;

        let reaction = chat.bob_reacts(&inner.id, "❤️").await;
        chat.receive(&reaction).await;

        assert!(chat.messages().await[0].reactions.is_empty());
    }

    #[tokio::test]
    async fn an_unsupported_inner_kind_never_trips_the_flood_breaker() {
        let mut chat = AliceChat::new();

        for _ in 0..FLOOD_TRIP_REJECTIONS + 5 {
            let (outer, _) = crate::nostr::transport::wrap_inner(
                &chat.bob,
                &chat.conv,
                &chat.sign,
                nostr_sdk::prelude::EventBuilder::new(
                    nostr_sdk::prelude::Kind::Custom(30023),
                    "an article",
                ),
                nostr_sdk::prelude::Timestamp::now(),
            )
            .unwrap();
            chat.receive(&outer).await;
        }
        chat.caught_up().await;

        assert!(!chat.state.flooded);
        assert_eq!(chat.state.consecutive_rejected, 0);
        assert!(chat.messages().await.is_empty());
        assert!(
            chat.state.cursor > 0,
            "fetching them again would change nothing"
        );
    }

    #[tokio::test]
    async fn catch_up_keeps_the_cursor_until_it_is_over() {
        let mut chat = AliceChat::new();
        let now = unix_now();
        let (older, _) = crate::nostr::transport::wrap_inner(
            &chat.bob,
            &chat.conv,
            &chat.sign,
            nostr_sdk::prelude::EventBuilder::new(nostr_sdk::prelude::Kind::TextNote, "older"),
            nostr_sdk::prelude::Timestamp::from_secs((now - 20) as u64),
        )
        .unwrap();
        let (newest, _) = chat.message(&chat.bob.clone(), "newest").await;

        // Newest first, as relays serve stored events.
        chat.receive(&newest).await;
        assert_eq!(
            chat.state.cursor, 0,
            "a restart now would still fetch the older one"
        );
        chat.receive(&older).await;
        chat.caught_up().await;

        assert!(chat.state.cursor >= newest.created_at.as_secs() as i64 - 1);
    }

    #[tokio::test]
    async fn a_held_reaction_keeps_the_cursor_until_its_message_arrives() {
        let mut chat = AliceChat::new();
        chat.caught_up().await;
        let (outer, inner) = chat.message(&chat.alice.clone(), "laptop").await;

        let reaction = chat.bob_reacts(&inner.id, "👍").await;
        chat.receive(&reaction).await;
        assert_eq!(chat.state.cursor, 0, "only memory holds it");
        chat.receive(&outer).await;

        assert!(chat.state.cursor > 0);
        assert_eq!(chat.messages().await[0].reactions[0].emoji, "👍");
    }

    #[tokio::test]
    async fn a_held_reaction_keeps_the_cursor_before_its_older_target() {
        let mut chat = AliceChat::new();
        let now = unix_now();
        let (target_outer, target) = crate::nostr::transport::wrap_inner(
            &chat.alice,
            &chat.conv,
            &chat.sign,
            nostr_sdk::prelude::EventBuilder::new(nostr_sdk::prelude::Kind::TextNote, "paid"),
            nostr_sdk::prelude::Timestamp::from_secs((now - 20) as u64),
        )
        .unwrap();
        let reaction = chat.bob_reacts_at(&target.id, "👍", now - 10).await;
        let (newest, _) = chat.message(&chat.bob.clone(), "anyone there?").await;

        // Catch-up, newest first, ends before the target arrives.
        chat.receive(&newest).await;
        chat.receive(&reaction).await;
        chat.caught_up().await;
        assert_eq!(
            chat.state.cursor, 0,
            "a restart must fetch the reaction and its older target again"
        );
        chat.receive(&target_outer).await;

        assert!(chat.state.cursor >= newest.created_at.as_secs() as i64 - 1);
        assert_eq!(chat.messages().await.len(), 2);
        let paid = chat
            .messages()
            .await
            .into_iter()
            .find(|m| m.content == "paid");
        assert_eq!(paid.unwrap().reactions[0].emoji, "👍");
    }

    #[tokio::test]
    async fn an_expired_floor_lets_a_quiet_chat_cursor_go() {
        let mut chat = AliceChat::new();
        chat.caught_up().await;
        let reaction = chat
            .bob_reacts(&nostr_sdk::prelude::EventId::from_byte_array([9; 32]), "👍")
            .await;
        let (later, _) = chat.message(&chat.bob.clone(), "hello?").await;
        chat.receive(&reaction).await;
        chat.receive(&later).await;
        assert_eq!(chat.state.cursor, 0, "the target that never comes holds it");

        // Ten minutes on, with nothing else arriving.
        for held in message_store()
            .held_reactions
            .write()
            .await
            .get_mut(&chat.order_id)
            .unwrap()
            .iter_mut()
        {
            held.held_at -= HELD_FLOOR_SECS + 1;
        }
        let order = chat.order_id.clone();
        chat.state.settle_cursor(&order).await;

        assert!(chat.state.cursor >= later.created_at.as_secs() as i64 - 1);
    }

    #[tokio::test]
    async fn the_cursor_waits_for_every_relays_eose() {
        let mut chat = AliceChat::new();
        let (newest, _) = chat.message(&chat.bob.clone(), "newest").await;
        chat.state.awaiting_eose = ["wss://fast".to_string(), "wss://slow".to_string()].into();
        chat.receive(&newest).await;
        let order = chat.order_id.clone();

        chat.state.eose_from(&order, "wss://fast", 1).await;
        assert!(chat.state.live, "the token bucket meters from the first");
        assert_eq!(
            chat.state.cursor, 0,
            "the slow relay may still serve older ones"
        );
        chat.state.eose_from(&order, "wss://slow", 1).await;

        assert!(chat.state.cursor >= newest.created_at.as_secs() as i64 - 1);
    }

    #[tokio::test]
    async fn an_unsaved_message_keeps_the_cursor_until_a_retry_stores_it() {
        let mut chat = AliceChat::new();
        chat.caught_up().await;
        // A reaction this device sent whose write failed leaves its target
        // in memory only, as a failed incoming write does.
        let (outer, inner) = chat.message(&chat.alice.clone(), "target").await;
        chat.receive(&outer).await;
        let cursor = chat.state.cursor;
        message_store()
            .non_durable
            .write()
            .await
            .insert(inner.id.to_hex());
        let (later, _) = chat.message(&chat.bob.clone(), "after the failure").await;

        chat.receive(&later).await;
        assert_eq!(
            chat.state.cursor, cursor,
            "a restart fetches the unsaved one again"
        );
        message_store()
            .non_durable
            .write()
            .await
            .remove(&inner.id.to_hex());
        let order = chat.order_id.clone();
        chat.state.settle_cursor(&order).await;

        assert!(chat.state.cursor >= later.created_at.as_secs() as i64 - 1);
    }

    #[tokio::test]
    async fn a_relay_that_joins_late_reopens_catch_up() {
        let mut state = ChatRxState::new(ChatChannel::Peer, 0, None);
        state.caught_up = true;
        state.eose_seen.insert("wss://early".to_string(), 1);

        state.event_from("o", "wss://early", 1).await;
        assert!(state.caught_up, "a relay past its EOSE is live");
        assert!(!state.from_catch_up);
        state.event_from("o", "wss://late", 1).await;

        assert!(!state.caught_up);
        assert!(state.awaiting_eose.contains("wss://late"));
        assert!(state.from_catch_up, "its backlog skips the token bucket");
    }

    #[tokio::test]
    async fn a_relay_that_reconnects_reopens_catch_up_from_the_start() {
        let mut state = ChatRxState::new(ChatChannel::Peer, 100, None);
        state.caught_up = true;
        state.cursor = 150; // persisted after the first catch-up
        state.eose_seen.insert("wss://relay".to_string(), 1);

        // Same relay, a later connection: the subscription was repaired,
        // with the recorded since = 100.
        state.event_from("o", "wss://relay", 2).await;

        assert!(!state.caught_up);
        assert!(state.awaiting_eose.contains("wss://relay"));
        assert_eq!(state.cursor, 100, "back to what the replay starts from");
    }

    #[tokio::test]
    async fn a_closed_subscription_replayed_on_the_same_connection_is_a_catch_up() {
        let mut state = ChatRxState::new(ChatChannel::Peer, 100, None);
        state.awaiting_eose.insert("wss://relay".to_string());

        state.closed_by("o", "wss://relay").await;
        assert!(state.caught_up, "a refused REQ holds nothing back");
        state.cursor = 150;
        // `live_subs` issues the REQ again on the same connection.
        state.event_from("o", "wss://relay", 1).await;

        assert!(!state.caught_up);
        assert!(state.from_catch_up);
        assert_eq!(state.cursor, 100, "back to what the replay starts from");
    }

    #[tokio::test]
    async fn a_relay_still_in_catch_up_skips_the_token_bucket() {
        let mut state = ChatRxState::new(ChatChannel::Peer, 0, None);
        state.live = true; // another relay already sent EOSE
        state.awaiting_eose.insert("wss://slow".to_string());

        state.event_from("o", "wss://slow", 1).await;
        let accepted = (0..RATE_CAPACITY as u32 * 3)
            .filter(|_| state.budget_ok("order-x"))
            .count();

        assert_eq!(accepted, RATE_CAPACITY as usize * 3);
        assert_eq!(state.consecutive_rejected, 0);
    }

    #[tokio::test]
    async fn the_update_stream_opens_with_the_reacted_messages() {
        let mut chat = AliceChat::new();
        let (outer, inner) = chat.message(&chat.alice.clone(), "reacted").await;
        let (plain, _) = chat.message(&chat.alice.clone(), "plain").await;
        chat.receive(&outer).await;
        chat.receive(&plain).await;
        chat.receive(&chat.bob_reacts(&inner.id, "👍").await).await;

        let mut updates = on_message_updated(chat.order_id.clone()).await.unwrap();
        let first = updates.next().await.unwrap();

        assert_eq!(first.content, "reacted");
        assert!(updates.pending.is_empty(), "the plain one is not resent");
    }

    #[tokio::test]
    async fn a_lagging_update_stream_gets_the_snapshot_again() {
        let mut chat = AliceChat::new();
        let (outer, inner) = chat.message(&chat.alice.clone(), "reacted").await;
        chat.receive(&outer).await;
        chat.receive(&chat.bob_reacts(&inner.id, "👍").await).await;
        let mut updates = on_message_updated(chat.order_id.clone()).await.unwrap();
        updates.next().await.unwrap();

        // More updates than the channel holds, none read.
        let other = notification_test_message("another-trade", 1);
        for _ in 0..100 {
            let _ = message_store().updated_tx.send(other.clone());
        }
        let next = tokio::time::timeout(std::time::Duration::from_secs(1), updates.next())
            .await
            .unwrap()
            .unwrap();

        assert_eq!(next.content, "reacted");
    }

    #[tokio::test]
    async fn an_older_reaction_received_again_changes_nothing() {
        let mut chat = AliceChat::new();
        chat.caught_up().await;
        let (outer, inner) = chat.message(&chat.alice.clone(), "paid").await;
        chat.receive(&outer).await;
        let now = unix_now();
        let first = chat.bob_reacts_at(&inner.id, "👍", now - 2).await;
        let second = chat.bob_reacts_at(&inner.id, "", now - 1).await;
        chat.receive(&first).await;
        chat.receive(&second).await;

        // After a restart: the outer-id LRU is empty again.
        chat.state = ChatRxState::new(ChatChannel::Peer, 0, None);
        chat.receive(&first).await;
        chat.caught_up().await;

        let reactions = &chat.messages().await[0].reactions;
        assert_eq!(reactions.len(), 1);
        assert_eq!(reactions[0].emoji, "", "the withdrawal holds");
        assert!(chat.state.cursor > 0, "nothing left to fetch again");
    }

    #[tokio::test]
    async fn a_re_wrapped_reaction_takes_one_held_place() {
        let store = MessageStore::new();
        for _ in 0..3 {
            store
                .apply_reaction("t", "target", reaction("bob", "👍", 1, "a"), 1)
                .await;
        }
        store
            .apply_reaction("t", "target", reaction("bob", "😂", 2, "b"), 2)
            .await;

        let held = store.held_reactions.read().await;
        assert_eq!(held["t"].len(), 1);
        assert_eq!(held["t"][0].reaction.emoji, "😂", "the newest is kept");
    }

    #[tokio::test]
    async fn a_reaction_held_too_long_stops_holding_the_cursor() {
        let store = MessageStore::new();
        store
            .apply_reaction("t", "never-comes", reaction("bob", "👍", 1, "a"), 42)
            .await;
        let now = unix_now();

        assert_eq!(store.held_floor_at("t", now).await, Some(42));
        assert_eq!(
            store.held_floor_at("t", now + HELD_FLOOR_SECS + 1).await,
            None
        );
        assert_eq!(
            store.held_reactions.read().await["t"].len(),
            1,
            "still held"
        );
    }

    #[tokio::test]
    async fn a_stored_row_releases_the_reactions_held_again_for_it() {
        let store = MessageStore::new();
        let msg = ChatMessage {
            sender_pubkey: "alice".to_string(),
            ..notification_test_message("re-held", 1)
        };
        store.add_message(msg.clone()).await;
        // As after a failed write of the target: its reaction held again.
        store
            .hold_reaction("re-held", &msg.id, reaction("bob", "👍", 1, "a"), 0)
            .await;
        assert!(store.held_floor("re-held").await.is_some());

        // Another reaction stores the row.
        store
            .apply_reaction("re-held", &msg.id, reaction("bob", "😂", 2, "b"), 0)
            .await;

        assert_eq!(store.held_floor("re-held").await, None);
    }

    #[tokio::test]
    async fn held_reactions_are_bounded_oldest_first() {
        let store = MessageStore::new();
        for i in 0..=MAX_HELD_REACTIONS_PER_TRADE {
            store
                .apply_reaction(
                    "t",
                    &format!("target-{i}"),
                    reaction("bob", "👍", 1, "a"),
                    1,
                )
                .await;
        }

        let held = store.held_reactions.read().await;
        assert_eq!(held["t"].len(), MAX_HELD_REACTIONS_PER_TRADE);
        assert_eq!(held["t"][0].target_id, "target-1");
    }

    #[tokio::test]
    async fn send_reaction_refuses_what_the_protocol_does_not_allow() {
        let mut chat = AliceChat::new();
        let (outer, inner) = chat.message(&chat.alice.clone(), "mine").await;
        chat.receive(&outer).await;
        let id = inner.id.to_hex();

        let own = send_reaction(chat.order_id.clone(), id.clone(), "👍".into()).await;
        let unknown = send_reaction(chat.order_id.clone(), "nope".into(), "👍".into()).await;
        let too_long = send_reaction(chat.order_id.clone(), id, "😀".repeat(17)).await;

        assert!(own
            .unwrap_err()
            .to_string()
            .starts_with("ReactionNotAllowed"));
        assert!(unknown
            .unwrap_err()
            .to_string()
            .starts_with("MessageNotFound"));
        assert!(too_long
            .unwrap_err()
            .to_string()
            .starts_with("ReactionTooLarge"));
    }
}
