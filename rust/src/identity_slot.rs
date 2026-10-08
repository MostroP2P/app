//! The identity slot and the hooks a deletion calls on the rest of the
//! process: crate-internal, so they live outside `crate::api`, where the
//! bridge codegen would scan them (review of #573). The transitions that use
//! them are in `api::identity`.

use nostr_sdk::prelude::Keys;
use tokio::sync::RwLock;

use crate::api::types::IdentityInfo;

/// The identity loaded into the core: its words, its keys and what the UI
/// reads of it.
pub(crate) struct IdentityState {
    pub(crate) mnemonic_words: Vec<String>,
    pub(crate) keys: Keys,
    pub(crate) identity_info: IdentityInfo,
}

/// The loaded identity and the generation that tells it from the next one.
///
/// The process has one (`api::identity::identity_slot`); the lifecycle seams (`create_in`,
/// `load_in`, `import_in`, `import_nsec_in`, `delete_in`) take it as a
/// parameter so a test can drive them on a slot of its own, without racing
/// the tests that share the global one.
pub(crate) struct IdentitySlot {
    pub(crate) state: RwLock<Option<IdentityState>>,
    /// Bumped by every identity deletion, under the write lock: it tells work
    /// that started under one identity apart from the next — even when the
    /// same mnemonic is imported again, which a pubkey comparison would not.
    pub(crate) generation: std::sync::atomic::AtomicU64,
    /// Held by every transition of the slot — creation, load, import,
    /// deletion — from its first read to its last write, so none interleaves
    /// with another (review round 4 of #573). A deletion awaits the relays,
    /// the push server and the store between reading its owner and wiping
    /// that owner's rows; without this, a second deletion could clear the
    /// marker it recorded, a reload release it, or a replacement land before
    /// the wipe and lose its rows to it. Readers of the identity take only
    /// `state`, so none of them waits on a transition's I/O.
    pub(crate) lifecycle: tokio::sync::Mutex<()>,
}

impl IdentitySlot {
    pub(crate) const fn new() -> Self {
        Self {
            state: RwLock::const_new(None),
            generation: std::sync::atomic::AtomicU64::new(0),
            lifecycle: tokio::sync::Mutex::const_new(()),
        }
    }
}

/// What a deletion does to the rest of the process, outside the slot and the
/// store: injectable so a test can stand in for the process-wide stores and
/// pause the deletion at each of these points.
pub(crate) trait DeletionHooks {
    /// Give back the identity's relay subscriptions.
    fn release_subscriptions(&self) -> impl std::future::Future<Output = ()>;
    /// Stop the push server waking this device for the identity's keys.
    fn unregister_push(&self) -> impl std::future::Future<Output = ()>;
    /// Empty the in-memory stores of the deleted identity.
    fn forget_state(&self) -> impl std::future::Future<Output = ()>;
}

/// The process's own [`DeletionHooks`].
pub(crate) struct AppDeletionHooks;

impl DeletionHooks for AppDeletionHooks {
    async fn release_subscriptions(&self) {
        crate::api::orders::release_identity_subscriptions().await;
    }
    async fn unregister_push(&self) {
        crate::api::push::unregister_all().await;
    }
    async fn forget_state(&self) {
        crate::api::identity::forget_identity_state().await;
    }
}
