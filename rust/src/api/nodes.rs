/// Mostro node registry API — trusted communities + user-added nodes.
///
/// The registry merges three sources into [`MostroNodeEntry`] rows for the
/// Settings → Mostro Node selector:
///
/// 1. the compiled-in trusted registry (`crate::config::TRUSTED_MOSTRO_NODES`),
/// 2. user-added nodes persisted in the settings KV store,
/// 3. cached kind 0 display metadata (name, picture, about, website) fetched
///    from the relay pool with [`refresh_mostro_node_metadata`].
///
/// Selecting a node stays where it always was —
/// `crate::api::settings::set_active_mostro_node` — this module only manages
/// the list the user picks from.
use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::OnceLock;
use tokio::sync::Mutex;

use crate::api::types::MostroNodeEntry;
use crate::db::{settings_keys, Storage};

/// Serializes every load-modify-save cycle on the registry's KV blobs
/// (`CUSTOM_MOSTRO_NODES`, `MOSTRO_NODE_METADATA`). The blobs are written as a
/// whole, so two concurrent cycles (e.g. a metadata refresh racing an
/// add-custom-node) would silently drop one side's update. Active-node
/// selection (`settings::set_active_mostro_node`) takes the same lock while
/// persisting the active key, so a removal cannot interleave with a selection
/// of the same pubkey (the auto-import would resurrect it nameless). Never
/// held across a relay round trip — only around the KV read/write itself.
static REGISTRY_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

pub(crate) fn registry_lock() -> &'static Mutex<()> {
    REGISTRY_LOCK.get_or_init(|| Mutex::new(()))
}

// ── Persisted shapes ─────────────────────────────────────────────────────────

/// A user-added node as persisted under [`settings_keys::CUSTOM_MOSTRO_NODES`].
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct CustomNode {
    /// 64-char lowercase hex.
    pub pubkey: String,
    /// Optional user-given display name (takes precedence over kind 0).
    pub name: Option<String>,
    /// Unix seconds when the user added the node.
    pub added_at: i64,
}

/// Cached kind 0 profile fields, persisted under
/// [`settings_keys::MOSTRO_NODE_METADATA`] as a pubkey → metadata map.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct NodeMetadata {
    pub name: Option<String>,
    pub picture: Option<String>,
    pub about: Option<String>,
    pub website: Option<String>,
}

// ── Pure helpers (unit-tested) ───────────────────────────────────────────────

/// Normalize `input` (64-char hex or `npub1…`) to lowercase hex.
///
/// **Errors** (stable markers, translated on the Dart side):
/// `PrivateKeyNotAllowed` for `nsec` input, `InvalidPubkey` otherwise.
fn parse_node_pubkey(input: &str) -> Result<String> {
    let trimmed = input.trim();
    if trimmed.to_ascii_lowercase().starts_with("nsec") {
        bail!("PrivateKeyNotAllowed: expected a public key, got an nsec");
    }
    let pk =
        nostr_sdk::prelude::PublicKey::parse(trimmed)
            .map_err(|e| anyhow::anyhow!("InvalidPubkey: {e}"))?;
    Ok(pk.to_hex())
}

/// Keep only https URLs — a kind 0 event is attacker-controlled input, and the
/// UI loads `picture` straight into an image widget.
fn sanitize_https_url(url: Option<String>) -> Option<String> {
    url.map(|u| u.trim().to_string())
        .filter(|u| u.starts_with("https://"))
}

/// Normalize a user-given name: trimmed, `None` when blank.
fn normalize_name(name: Option<String>) -> Option<String> {
    name.map(|n| n.trim().to_string()).filter(|n| !n.is_empty())
}

/// `true` when `pubkey` (lowercase hex) is in the compiled-in trusted registry.
fn is_trusted_pubkey(pubkey: &str) -> bool {
    crate::config::TRUSTED_MOSTRO_NODES
        .iter()
        .any(|n| n.pubkey == pubkey)
}

/// Drop custom entries whose pubkey has since joined the trusted registry.
/// Returns `true` when anything was removed.
///
/// Without this, a release that promotes a community into
/// `TRUSTED_MOSTRO_NODES` leaves users who had added it manually with a
/// duplicate row that can never be deleted (`remove_custom_mostro_node`
/// refuses trusted pubkeys). Mirrors v1's startup cleanup.
fn drop_promoted_customs(custom: &mut Vec<CustomNode>) -> bool {
    let before = custom.len();
    custom.retain(|n| !is_trusted_pubkey(&n.pubkey));
    custom.len() != before
}

/// `true` when the active pubkey is in neither the trusted registry nor the
/// custom list and must be surfaced as an auto-imported custom node.
fn needs_auto_import(custom: &[CustomNode], active: &str) -> bool {
    !is_trusted_pubkey(active) && !custom.iter().any(|n| n.pubkey == active)
}

fn entry_from(
    pubkey: &str,
    region: Option<&str>,
    is_trusted: bool,
    custom_name: Option<&str>,
    meta: Option<&NodeMetadata>,
    active_pubkey: &str,
) -> MostroNodeEntry {
    MostroNodeEntry {
        pubkey: pubkey.to_string(),
        region: region.map(str::to_string),
        is_trusted,
        is_active: pubkey == active_pubkey,
        name: custom_name
            .map(str::to_string)
            .or_else(|| meta.and_then(|m| m.name.clone())),
        picture: meta.and_then(|m| m.picture.clone()),
        about: meta.and_then(|m| m.about.clone()),
        website: meta.and_then(|m| m.website.clone()),
    }
}

// ── KV persistence ───────────────────────────────────────────────────────────

async fn load_custom_nodes(db: &impl Storage) -> Result<Vec<CustomNode>> {
    match db.get_setting(settings_keys::CUSTOM_MOSTRO_NODES).await? {
        // A corrupt blob loses the custom list, not the whole selector.
        Some(json) => Ok(serde_json::from_str(&json).unwrap_or_default()),
        None => Ok(Vec::new()),
    }
}

async fn save_custom_nodes(db: &impl Storage, nodes: &[CustomNode]) -> Result<()> {
    db.set_setting(
        settings_keys::CUSTOM_MOSTRO_NODES,
        &serde_json::to_string(nodes)?,
    )
    .await
}

async fn load_metadata_cache(db: &impl Storage) -> Result<HashMap<String, NodeMetadata>> {
    match db.get_setting(settings_keys::MOSTRO_NODE_METADATA).await? {
        Some(json) => Ok(serde_json::from_str(&json).unwrap_or_default()),
        None => Ok(HashMap::new()),
    }
}

async fn save_metadata_cache(
    db: &impl Storage,
    cache: &HashMap<String, NodeMetadata>,
) -> Result<()> {
    db.set_setting(
        settings_keys::MOSTRO_NODE_METADATA,
        &serde_json::to_string(cache)?,
    )
    .await
}

// ── Public API ───────────────────────────────────────────────────────────────

/// Return the full node registry: trusted nodes first (registry order), then
/// user-added nodes (insertion order), each merged with cached kind 0 metadata
/// and flagged with `is_active`.
///
/// If the active pubkey is not in the registry (selected before this feature
/// existed, or on another device), it is auto-imported as a custom node so the
/// selector always shows what the app is actually using.
pub async fn list_mostro_nodes() -> Result<Vec<MostroNodeEntry>> {
    let active = crate::config::active_mostro_pubkey();

    let mut custom: Vec<CustomNode>;
    let cache: HashMap<String, NodeMetadata>;
    if let Some(db) = crate::db::app_db::db() {
        let _guard = registry_lock().lock().await;
        custom = load_custom_nodes(db).await?;
        let mut changed = drop_promoted_customs(&mut custom);
        if needs_auto_import(&custom, &active) {
            custom.push(CustomNode {
                pubkey: active.clone(),
                name: None,
                added_at: crate::rt::unix_now(),
            });
            changed = true;
        }
        if changed {
            save_custom_nodes(db, &custom).await?;
        }
        cache = load_metadata_cache(db).await?;
    } else {
        // No storage yet — still surface the active node so the selector
        // never hides what the app is actually using.
        custom = Vec::new();
        if needs_auto_import(&custom, &active) {
            custom.push(CustomNode {
                pubkey: active.clone(),
                name: None,
                added_at: crate::rt::unix_now(),
            });
        }
        cache = HashMap::new();
    }

    let mut entries: Vec<MostroNodeEntry> = crate::config::TRUSTED_MOSTRO_NODES
        .iter()
        .map(|n| {
            entry_from(
                n.pubkey,
                Some(n.region),
                true,
                None,
                cache.get(n.pubkey),
                &active,
            )
        })
        .collect();
    entries.extend(custom.iter().map(|n| {
        entry_from(
            &n.pubkey,
            None,
            false,
            n.name.as_deref(),
            cache.get(&n.pubkey),
            &active,
        )
    }));
    Ok(entries)
}

/// Add a user-defined node by pubkey (64-char hex or `npub1…`) with an
/// optional display name, persist it, and return its registry entry.
///
/// **Errors**: `PrivateKeyNotAllowed`, `InvalidPubkey`, `NodeAlreadyExists`
/// (already trusted or already added), `NotInitialized` (no storage yet).
pub async fn add_custom_mostro_node(
    input: String,
    name: Option<String>,
) -> Result<MostroNodeEntry> {
    let pubkey = parse_node_pubkey(&input)?;
    let name = normalize_name(name);

    let Some(db) = crate::db::app_db::db() else {
        bail!("NotInitialized: storage is not ready");
    };

    if is_trusted_pubkey(&pubkey) {
        bail!("NodeAlreadyExists: {pubkey} is a trusted node");
    }
    {
        let _guard = registry_lock().lock().await;
        let mut custom = load_custom_nodes(db).await?;
        if custom.iter().any(|n| n.pubkey == pubkey) {
            bail!("NodeAlreadyExists: {pubkey} was already added");
        }
        custom.push(CustomNode {
            pubkey: pubkey.clone(),
            name: name.clone(),
            added_at: crate::rt::unix_now(),
        });
        save_custom_nodes(db, &custom).await?;
    }

    let cache = load_metadata_cache(db).await?;
    let active = crate::config::active_mostro_pubkey();
    Ok(entry_from(
        &pubkey,
        None,
        false,
        name.as_deref(),
        cache.get(&pubkey),
        &active,
    ))
}

/// Remove a user-added node. Removing an absent node is a no-op.
///
/// **Errors**: `CannotRemoveActiveNode` (switch away first),
/// `NodeIsTrusted` (compiled-in entries cannot be removed),
/// `NotInitialized` (no storage yet).
pub async fn remove_custom_mostro_node(pubkey: String) -> Result<()> {
    let pubkey = pubkey.to_lowercase();
    if is_trusted_pubkey(&pubkey) {
        bail!("NodeIsTrusted: compiled-in nodes cannot be removed");
    }
    let Some(db) = crate::db::app_db::db() else {
        bail!("NotInitialized: storage is not ready");
    };
    let _guard = registry_lock().lock().await;
    // Active check under the lock: selection holds the same lock, so the key
    // cannot become active between this check and the save below.
    if pubkey == crate::config::active_mostro_pubkey() {
        bail!("CannotRemoveActiveNode: select another node first");
    }
    let mut custom = load_custom_nodes(db).await?;
    custom.retain(|n| n.pubkey != pubkey);
    save_custom_nodes(db, &custom).await
}

/// Fetch kind 0 profile events for every known node in one relay query,
/// update the persisted metadata cache, and return the refreshed registry.
///
/// Best-effort by design: partial updates are allowed. Whatever events arrive
/// within the 10s window are cached — including when the window closes before
/// every author answered — and nodes without a kind 0 event keep their cached
/// (or empty) metadata. Only an outright query failure returns an error, and
/// then the cache is untouched.
pub async fn refresh_mostro_node_metadata() -> Result<Vec<MostroNodeEntry>> {
    use nostr_sdk::prelude::*;
    use std::time::Duration;

    let client = crate::api::nostr::get_pool()?.client();

    let mut pubkeys: Vec<String> = crate::config::TRUSTED_MOSTRO_NODES
        .iter()
        .map(|n| n.pubkey.to_string())
        .collect();
    if let Some(db) = crate::db::app_db::db() {
        pubkeys.extend(load_custom_nodes(db).await?.into_iter().map(|n| n.pubkey));
    }
    let authors: Vec<PublicKey> = pubkeys
        .iter()
        .filter_map(|p| PublicKey::from_hex(p).ok())
        .collect();

    let filter = Filter::new().kind(Kind::Metadata).authors(authors);
    let events = client
        .fetch_events(filter)
        .timeout(Duration::from_secs(10))
        .await
        .map_err(|e| anyhow::anyhow!("fetch_events failed: {e}"))?;

    if let Some(db) = crate::db::app_db::db() {
        // Locked only for the KV cycle — the relay fetch above runs unlocked.
        let _guard = registry_lock().lock().await;
        let mut cache = load_metadata_cache(db).await?;
        // Events are ordered newest-first; take the first (newest) per author
        // and overwrite the cache so profile edits propagate.
        let mut seen = std::collections::HashSet::new();
        for event in events.into_iter() {
            let author = event.pubkey.to_hex();
            if !pubkeys.contains(&author) || !seen.insert(author.clone()) {
                continue;
            }
            let Ok(meta) = Metadata::from_json(&event.content) else {
                continue;
            };
            cache.insert(
                author,
                NodeMetadata {
                    name: normalize_name(meta.name.or(meta.display_name)),
                    picture: sanitize_https_url(meta.picture),
                    about: meta
                        .about
                        .map(|a| a.trim().to_string())
                        .filter(|a| !a.is_empty()),
                    website: sanitize_https_url(meta.website),
                },
            );
        }
        save_metadata_cache(db, &cache).await?;
    }

    list_mostro_nodes().await
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    const HEX: &str = "82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390";

    #[test]
    fn parse_accepts_hex_and_normalizes_case() {
        let upper = HEX.to_uppercase();
        assert_eq!(parse_node_pubkey(&upper).unwrap(), HEX);
    }

    #[test]
    fn parse_accepts_npub() {
        use nostr_sdk::prelude::ToBech32;
        let npub = nostr_sdk::prelude::PublicKey::from_hex(HEX)
            .unwrap()
            .to_bech32()
            .unwrap();
        assert_eq!(parse_node_pubkey(&npub).unwrap(), HEX);
    }

    #[test]
    fn parse_rejects_nsec_with_marker() {
        // Any nsec-shaped input must yield the dedicated marker, never a
        // generic parse error — Dart maps markers to localized strings.
        let err = parse_node_pubkey("nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq").unwrap_err();
        assert!(err.to_string().contains("PrivateKeyNotAllowed"));
    }

    #[test]
    fn parse_rejects_garbage_with_marker() {
        let err = parse_node_pubkey("not-a-key").unwrap_err();
        assert!(err.to_string().contains("InvalidPubkey"));
    }

    #[test]
    fn sanitize_drops_non_https_urls() {
        assert_eq!(
            sanitize_https_url(Some("https://x.com/a.png".into())).as_deref(),
            Some("https://x.com/a.png")
        );
        assert_eq!(sanitize_https_url(Some("http://x.com/a.png".into())), None);
        assert_eq!(sanitize_https_url(Some("javascript:alert(1)".into())), None);
        assert_eq!(sanitize_https_url(None), None);
    }

    #[test]
    fn custom_name_takes_precedence_over_kind0() {
        let meta = NodeMetadata {
            name: Some("Kind0 Name".into()),
            ..Default::default()
        };
        let e = entry_from(HEX, None, false, Some("My Node"), Some(&meta), "");
        assert_eq!(e.name.as_deref(), Some("My Node"));
        let e = entry_from(HEX, None, false, None, Some(&meta), "");
        assert_eq!(e.name.as_deref(), Some("Kind0 Name"));
    }

    /// Syntactically valid hex that is deliberately not any real node.
    const OTHER: &str = "0000000000000000000000000000000000000000000000000000000000000001";

    #[test]
    fn promoted_custom_nodes_are_dropped() {
        // HEX is in the trusted registry (it is the default node), so a custom
        // row carrying it is a leftover from before a promotion and must go.
        let mut custom = vec![
            CustomNode {
                pubkey: HEX.into(),
                name: None,
                added_at: 0,
            },
            CustomNode {
                pubkey: OTHER.into(),
                name: None,
                added_at: 0,
            },
        ];
        assert!(drop_promoted_customs(&mut custom));
        assert_eq!(custom.len(), 1);
        assert_eq!(custom[0].pubkey, OTHER);
        // Idempotent: a clean list reports no change.
        assert!(!drop_promoted_customs(&mut custom));
    }

    #[test]
    fn auto_import_only_for_unknown_active() {
        // Trusted active → no import.
        assert!(!needs_auto_import(&[], HEX));
        // Unknown active → import.
        assert!(needs_auto_import(&[], OTHER));
        // Already custom → no import.
        let custom = vec![CustomNode {
            pubkey: OTHER.into(),
            name: None,
            added_at: 0,
        }];
        assert!(!needs_auto_import(&custom, OTHER));
    }

    #[test]
    fn trusted_registry_is_valid_and_unique() {
        let nodes = crate::config::TRUSTED_MOSTRO_NODES;
        let mut seen = std::collections::HashSet::new();
        for n in nodes {
            assert!(
                nostr_sdk::prelude::PublicKey::from_hex(n.pubkey).is_ok(),
                "invalid pubkey in trusted registry: {}",
                n.pubkey
            );
            assert_eq!(n.pubkey, n.pubkey.to_lowercase());
            assert!(seen.insert(n.pubkey), "duplicate pubkey: {}", n.pubkey);
        }
        assert!(
            nodes
                .iter()
                .any(|n| n.pubkey == crate::config::DEFAULT_MOSTRO_PUBKEY),
            "default node must be part of the trusted registry"
        );
    }
}
