//! Chat attachments (#589): images and files sent in the trade chat,
//! encrypted on the device and stored on Blossom.
//!
//! Wire-compatible with v1 (`MostroP2P/mobile`): the same file key
//! (`crypto::file_enc::attachment_key`), the same blob layout
//! (`crypto::file_enc`), the same JSON message ([`payload`]) and the same
//! Blossom upload (`nostr::blossom`). Either app opens the other's files.
pub mod media;
pub mod payload;
pub(crate) mod probe;

/// Largest file a user may attach, before encryption. v1's limit.
pub const MAX_ATTACHMENT_BYTES: usize = 25 * 1024 * 1024;

/// Largest encrypted blob: the file plus the 12-byte nonce and 16-byte tag.
pub const MAX_BLOB_BYTES: usize = MAX_ATTACHMENT_BYTES + 12 + 16;
