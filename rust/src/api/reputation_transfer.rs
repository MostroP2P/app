//! Reputation portability (MostroP2P/mostro docs/REPUTATION_PORTABILITY.md,
//! phase 5b): export the reputation earned on the active node, import an
//! attestation earned elsewhere, and authorise moving an exported reputation
//! to a new identity.
//!
//! Both requests act on the identity key, so neither runs in privacy mode,
//! and each goes only to a node whose info event advertises it
//! (`mostro::reputation_support`): a node that predates the actions cannot
//! parse them and would never answer.
//!
//! **Errors** are `anyhow` markers Dart localizes (`core/daemon_errors.dart`):
//! `PrivacyModeEnabled`, `ReputationExportUnsupported`,
//! `ReputationImportUnsupported`, `NoDaemonResponse`, and the daemon's or the
//! local check's `CantDoReason` by name (`UntrustedReputationIssuer`,
//! `ReputationAlreadyImported`, `InvalidReputationAttestation`, …),
//! `InvalidPubkey` for a key that is not 64-char hex, and `NoIdentity` when
//! the identity that asked was deleted or replaced before the node answered.

use anyhow::{bail, Result};
use mostro_core::message::{Action, MessageKind, Payload, ReputationExportRequest};
use mostro_core::reputation::{
    AttestationError, ReputationAttestation, ReputationRebind, ATTESTATION_LIFETIME_SECS,
    REBIND_MAX_LIFETIME_SECS,
};
use nostr_sdk::prelude::{Keys, PublicKey, Timestamp};

use crate::api::identity::{identity_generation, while_identity_current};
use crate::api::orders::{ask_daemon_with, fresh_request_id, DaemonAnswer};
use crate::db::settings_keys::PENDING_REPUTATION_ATTESTATION;
use crate::db::Storage;
use crate::mostro::reputation_support;

/// How long to wait for the node's answer. The user is waiting and there is
/// no fallback, so the window is longer than the restore's.
const REPLY_WINDOW_SECS: u64 = 15;

/// What the active node offers for reputation portability.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReputationSupportInfo {
    /// The key the node signs attestations with; `None` when it does not
    /// export.
    pub issuer: Option<String>,
    /// The issuer keys it imports from; `None` when it does not import.
    pub import_issuers: Option<Vec<String>>,
}

/// A verified reputation attestation, for display and import.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReputationAttestationInfo {
    pub id: String,
    /// Key that signed it.
    pub issuer: String,
    /// Identity it is addressed to.
    pub destination: String,
    /// The source account, opaque.
    pub subject: String,
    /// Ratings received on the source.
    pub reviews: u32,
    /// Their average, with two decimals (`"4.87"`).
    pub rating: String,
    /// UTC day start of the first completed trade on the source.
    pub since: i64,
    pub created_at: i64,
    pub expiration: i64,
    /// The event JSON, as received, to import unchanged.
    pub json: String,
}

impl ReputationAttestationInfo {
    fn new(attestation: &ReputationAttestation, json: String) -> Self {
        Self {
            id: attestation.id.to_hex(),
            issuer: attestation.issuer.to_hex(),
            destination: attestation.destination.to_hex(),
            subject: attestation.subject.clone(),
            reviews: attestation.reviews,
            rating: attestation.rating_text(),
            since: attestation.since as i64,
            created_at: attestation.created_at as i64,
            expiration: attestation.expiration as i64,
            json,
        }
    }
}

/// What the active node advertises, as of its last capability fetch.
#[flutter_rust_bridge::frb(sync)]
pub fn get_reputation_support() -> ReputationSupportInfo {
    let support = reputation_support::get(&crate::config::active_mostro_pubkey());
    ReputationSupportInfo {
        issuer: support.issuer,
        import_issuers: support.import_issuers,
    }
}

/// Verify an attestation pasted or received, without sending anything: the
/// event's own rules (signature, kind, tags, clock). Whether the node trusts
/// its issuer is the node's to say on import.
#[flutter_rust_bridge::frb(sync)]
pub fn parse_reputation_attestation(json: String) -> Result<ReputationAttestationInfo> {
    let attestation = parse(&json)?;
    Ok(ReputationAttestationInfo::new(&attestation, json))
}

/// Ask the active node to attest the user's reputation there for
/// `destination` (the user's own identity when `None`). The UI confirms the
/// destination with the user first: the request binds the node's account to
/// it. `rebind` is an authorisation from [`sign_reputation_rebind`], needed
/// when the account is bound to another identity. The attestation is
/// verified, kept until imported, and returned.
pub async fn export_reputation(
    destination: Option<String>,
    rebind: Option<String>,
) -> Result<ReputationAttestationInfo> {
    let node = crate::config::active_mostro_pubkey();
    let Some(issuer) = reputation_support::get(&node).issuer else {
        bail!("ReputationExportUnsupported: the node does not export reputation");
    };
    // Checked before the node binds the account: an attestation that cannot
    // be kept must not be reported as kept.
    let db = crate::db::app_db::db()
        .ok_or_else(|| anyhow::anyhow!("StorageUnavailable: the attestation could not be kept"))?;
    // Taken before the keys: an identity swapped in between reads as a
    // different generation, never as the one that asked.
    let generation = identity_generation().await;
    let identity = identity_keys().await?;
    let target = match destination {
        Some(hex) => pubkey(&hex)?,
        None => identity.public_key(),
    };
    let payload = Payload::ReputationExportRequest(ReputationExportRequest {
        destination: target.to_hex(),
        rebind,
    });
    let reply = ask(
        &node,
        &identity,
        generation,
        Action::ExportReputation,
        payload,
        is_export_reply,
    )
    .await?;
    let Some(Payload::ReputationAttestation(json)) = reply.payload else {
        bail!("InvalidPayload: the node answered without an attestation");
    };
    let attestation = parse(&json)?;
    check_exported(&attestation, &issuer, &target)?;
    // The wait above is long enough for the identity to be deleted or
    // replaced: a write after its wipe would hand this attestation to the
    // next identity.
    while_still_current(generation, async {
        let _slot = pending_slot().lock().await;
        db.set_setting(PENDING_REPUTATION_ATTESTATION, &json).await
    })
    .await?;
    Ok(ReputationAttestationInfo::new(&attestation, json))
}

/// Run, without sending anything, every check [`import_reputation`] makes
/// before it asks the node: the active node imports, the identity key is
/// usable (not in privacy mode), and the attestation verifies, names the
/// user's identity and comes from a key the node trusts. The screen calls it
/// on Check, so a refusal shows before the user commits to an import.
pub async fn check_reputation_import(
    attestation_json: String,
) -> Result<ReputationAttestationInfo> {
    let node = crate::config::active_mostro_pubkey();
    let (_, attestation) = importable(&node, &attestation_json).await?;
    Ok(ReputationAttestationInfo::new(
        &attestation,
        attestation_json,
    ))
}

/// Import `attestation_json` into the active node. It must name the user's
/// identity and be signed by a key the node advertises it trusts; the node
/// runs the full checks and answers `reputation-imported` or a refusal.
pub async fn import_reputation(attestation_json: String) -> Result<ReputationAttestationInfo> {
    let node = crate::config::active_mostro_pubkey();
    let generation = identity_generation().await;
    let (identity, attestation) = importable(&node, &attestation_json).await?;
    ask(
        &node,
        &identity,
        generation,
        Action::ImportReputation,
        Payload::ReputationAttestation(attestation_json.clone()),
        is_import_reply,
    )
    .await?;
    // Imported: it is no longer pending. Under the same guard as the export's
    // write, so a late answer never touches the next identity's slot.
    while_still_current(generation, async {
        let Some(db) = crate::db::app_db::db() else {
            return Ok(());
        };
        let _slot = pending_slot().lock().await;
        let pending = db.get_setting(PENDING_REPUTATION_ATTESTATION).await?;
        if pending.as_deref().and_then(event_id) == Some(attestation.id.to_hex()) {
            db.delete_setting(PENDING_REPUTATION_ATTESTATION).await?;
        }
        Ok(())
    })
    .await?;
    Ok(ReputationAttestationInfo::new(
        &attestation,
        attestation_json,
    ))
}

/// The attestation exported last and not imported yet, while still valid.
/// One slot for all nodes: a later export replaces it. An expired one is
/// dropped; one refused for another reason (a clock behind the issuer's)
/// is kept, as it may verify later.
pub async fn get_pending_reputation_attestation() -> Result<Option<ReputationAttestationInfo>> {
    let Some(db) = crate::db::app_db::db() else {
        return Ok(None);
    };
    let Some(generation) = identity_generation().await else {
        return Ok(None);
    };
    // Read under the identity guard: a wipe that starts meanwhile waits for
    // it, so the slot read is always the active identity's.
    let read = while_identity_current(generation, async {
        // Held from the read to the drop, so the attestation dropped is the
        // one read, never one an export wrote since.
        let _slot = pending_slot().lock().await;
        let Some(json) = db.get_setting(PENDING_REPUTATION_ATTESTATION).await? else {
            return Ok(None);
        };
        match ReputationAttestation::parse_json(&json, Timestamp::now(), ATTESTATION_LIFETIME_SECS)
        {
            Ok((attestation, _)) => Ok(Some(ReputationAttestationInfo::new(&attestation, json))),
            Err(AttestationError::Expired) => {
                log::info!("[reputation] the pending attestation expired; dropping it");
                db.delete_setting(PENDING_REPUTATION_ATTESTATION).await?;
                Ok(None)
            }
            Err(_) => Ok(None),
        }
    })
    .await;
    read.unwrap_or(Ok(None))
}

/// Sign, with the identity the reputation at `issuer` is bound to now, the
/// authorisation to move that binding to `new_identity` (hex). Pass it as
/// `rebind` to [`export_reputation`] from the new identity, or paste it into
/// lnp2pBot. Valid for an hour.
pub async fn sign_reputation_rebind(issuer: String, new_identity: String) -> Result<String> {
    let bound = identity_keys().await?;
    let issuer = pubkey(&issuer)?;
    let new_identity = pubkey(&new_identity)?;
    let event = ReputationRebind::build(
        &bound,
        &issuer,
        &new_identity,
        Timestamp::now(),
        REBIND_MAX_LIFETIME_SECS,
    )
    .map_err(|e| anyhow::anyhow!("InvalidReputationRebind: {e}"))?;
    Ok(event.as_json())
}

/// The identity keys, refusing in privacy mode: there is no identity-bound
/// reputation to export or import into.
async fn identity_keys() -> Result<Keys> {
    if crate::api::reputation::get_privacy_mode() {
        bail!("PrivacyModeEnabled: reputation portability needs the identity key");
    }
    crate::api::identity::get_active_keys().await
}

/// Held around every read-and-write of the pending slot. The identity guard
/// is a shared lock, so without it an export's write could land between a
/// cleanup's comparison and its delete, and be the one deleted. Always taken
/// inside the identity guard, never around it.
fn pending_slot() -> &'static tokio::sync::Mutex<()> {
    static SLOT: std::sync::OnceLock<tokio::sync::Mutex<()>> = std::sync::OnceLock::new();
    SLOT.get_or_init(|| tokio::sync::Mutex::new(()))
}

/// Run `write` only while the identity of `generation` is still active;
/// `NoIdentity` when it was deleted or replaced meanwhile.
async fn while_still_current(
    generation: Option<u64>,
    write: impl std::future::Future<Output = Result<()>>,
) -> Result<()> {
    let Some(generation) = generation else {
        bail!("NoIdentity");
    };
    while_identity_current(generation, write)
        .await
        .unwrap_or_else(|| bail!("NoIdentity: the identity changed before the node answered"))
}

/// A hex public key from user input, or the `InvalidPubkey` marker.
fn pubkey(hex: &str) -> Result<PublicKey> {
    PublicKey::from_hex(hex.trim()).map_err(|_| anyhow::anyhow!("InvalidPubkey: {}", hex.trim()))
}

/// The id of the event in `json`, whatever its formatting.
fn event_id(json: &str) -> Option<String> {
    nostr_sdk::prelude::Event::from_json(json)
        .ok()
        .map(|event| event.id.to_hex())
}

/// The node's answer to an export is signed by the key it advertises and
/// names the identity the export was asked for.
fn check_exported(
    attestation: &ReputationAttestation,
    issuer: &str,
    destination: &PublicKey,
) -> Result<()> {
    if attestation.issuer.to_hex() != issuer || attestation.destination != *destination {
        bail!("InvalidReputationAttestation: not the node's issuer key, or another identity");
    }
    Ok(())
}

/// The local checks of an import into `node`, in order: the node imports,
/// the identity key is usable, the attestation verifies and passes
/// [`check_importable`]. Returns the identity keys and the attestation.
async fn importable(node: &str, json: &str) -> Result<(Keys, ReputationAttestation)> {
    let Some(trusted) = reputation_support::get(node).import_issuers else {
        bail!("ReputationImportUnsupported: the node does not import reputation");
    };
    let identity = identity_keys().await?;
    let attestation = parse(json)?;
    check_importable(&attestation, &identity.public_key(), &trusted)?;
    Ok((identity, attestation))
}

/// What can be checked before an import is sent: the attestation names
/// `identity` and comes from a key the node advertises it trusts.
fn check_importable(
    attestation: &ReputationAttestation,
    identity: &PublicKey,
    trusted: &[String],
) -> Result<()> {
    if attestation.destination != *identity {
        bail!("ReputationIdentityMismatch: it names another identity");
    }
    if !trusted.contains(&attestation.issuer.to_hex()) {
        bail!("UntrustedReputationIssuer: the node does not trust its issuer");
    }
    Ok(())
}

fn parse(json: &str) -> Result<ReputationAttestation> {
    ReputationAttestation::parse_json(json, Timestamp::now(), ATTESTATION_LIFETIME_SECS)
        .map(|(attestation, _)| attestation)
        .map_err(refusal)
}

/// An attestation the local check refuses, named by the `cant-do` reason a
/// destination would answer with.
fn refusal(error: AttestationError) -> anyhow::Error {
    anyhow::anyhow!("{:?}: {error}", error.cant_do_reason())
}

fn is_export_reply(kind: &MessageKind, request_id: u64) -> bool {
    kind.action == Action::ReputationExported && kind.request_id == Some(request_id)
}

fn is_import_reply(kind: &MessageKind, request_id: u64) -> bool {
    kind.action == Action::ReputationImported && kind.request_id == Some(request_id)
}

/// `NoIdentity` unless the identity of generation `asked` is still the active
/// one `now`. Deletion bumps the generation under the identity write lock, so
/// an unchanged one means no identity was swapped in between.
fn same_identity(asked: Option<u64>, now: Option<u64>) -> Result<()> {
    match (asked, now) {
        (Some(asked), Some(now)) if asked == now => Ok(()),
        _ => bail!("NoIdentity: the identity changed before the request was sent"),
    }
}

/// Send one reputation request from a fresh trade key with the identity
/// proof, and wait for the node's answer to it. `generation` is the one taken
/// before `identity` was read.
async fn ask(
    node: &str,
    identity: &Keys,
    generation: Option<u64>,
    action: Action,
    payload: Payload,
    is_reply: fn(&MessageKind, u64) -> bool,
) -> Result<MessageKind> {
    let mostro_pubkey = PublicKey::from_hex(node)?;
    let trade_key_info = crate::api::identity::derive_trade_key().await?;
    let trade_keys = crate::api::identity::get_active_trade_keys(trade_key_info.index).await?;
    // The proof and the trade key must come from one identity: a swap since
    // `identity` was read would sign the request with both. The derivation
    // takes the identity write lock, so it cannot run under
    // `while_identity_current`; the generation is checked after it instead.
    same_identity(generation, identity_generation().await)?;
    let request_id = fresh_request_id();
    let label = format!("{action:?}");
    let event_json = crate::mostro::actions::reputation_request(
        identity,
        &trade_keys,
        &mostro_pubkey,
        request_id,
        action,
        payload,
    )
    .await?;
    let answer = ask_daemon_with(
        &trade_keys,
        &mostro_pubkey,
        request_id,
        &event_json,
        &label,
        is_reply,
        crate::rt::time::Duration::from_secs(REPLY_WINDOW_SECS),
        "reputation",
    )
    .await?;
    match answer {
        DaemonAnswer::Reply(kind, _) => Ok(*kind),
        DaemonAnswer::Refused(reason) => bail!("{reason}: refused by the node"),
        DaemonAnswer::Silent => bail!(crate::mostro::pending::NO_DAEMON_RESPONSE),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const VECTORS: &str = include_str!("../../tests/fixtures/reputation_v1.json");

    fn vectors() -> serde_json::Value {
        serde_json::from_str(VECTORS).unwrap()
    }

    #[test]
    fn a_refused_attestation_is_named_by_its_cant_do_reason() {
        let v = vectors();
        for case in v["attestation"]["invalid"].as_array().unwrap() {
            let name = case["name"].as_str().unwrap();
            if ["identity_mismatch", "untrusted_issuer", "own_issuer_key"].contains(&name) {
                continue;
            }
            let event = nostr_sdk::prelude::Event::from_json(case["event"].to_string()).unwrap();
            let now = Timestamp::from(v["context"]["now"].as_u64().unwrap());
            let error = ReputationAttestation::parse(&event, now, ATTESTATION_LIFETIME_SECS)
                .map_err(refusal)
                .unwrap_err()
                .to_string();
            let expected = match case["reason"].as_str().unwrap() {
                "expired_reputation_attestation" => "ExpiredReputationAttestation",
                _ => "InvalidReputationAttestation",
            };
            assert!(error.starts_with(expected), "{name}: {error}");
        }
    }

    #[test]
    fn a_request_goes_out_only_from_the_identity_that_asked() {
        assert!(same_identity(Some(3), Some(3)).is_ok());
        for (asked, now) in [
            (Some(3), Some(4)),
            (Some(3), None),
            (None, Some(3)),
            (None, None),
        ] {
            let error = same_identity(asked, now).unwrap_err().to_string();
            assert!(
                error.starts_with("NoIdentity"),
                "{asked:?} → {now:?}: {error}"
            );
        }
    }

    #[test]
    fn the_replies_are_matched_by_action_and_nonce() {
        let exported = MessageKind::new(None, Some(9), None, Action::ReputationExported, None);
        assert!(is_export_reply(&exported, 9));
        assert!(!is_export_reply(&exported, 8));
        assert!(!is_import_reply(&exported, 9));
        let imported = MessageKind::new(None, Some(9), None, Action::ReputationImported, None);
        assert!(is_import_reply(&imported, 9));
    }

    #[test]
    fn the_info_keeps_the_figures_and_the_json() {
        let v = vectors();
        let json = v["attestation"]["valid"]["json"]
            .as_str()
            .unwrap()
            .to_string();
        let now = Timestamp::from(v["context"]["now"].as_u64().unwrap());
        let (attestation, _) =
            ReputationAttestation::parse_json(&json, now, ATTESTATION_LIFETIME_SECS).unwrap();
        let info = ReputationAttestationInfo::new(&attestation, json.clone());
        assert_eq!(info.reviews, 214);
        assert_eq!(info.rating, "4.87");
        assert_eq!(info.since, 1_696_204_800);
        assert_eq!(info.json, json);
        assert_eq!(info.id, v["attestation"]["valid"]["id"].as_str().unwrap());
    }

    /// A vector event that verifies on its own: the valid one, or a named
    /// `invalid` case whose refusal is the destination's to make.
    fn attestation(v: &serde_json::Value, name: &str) -> ReputationAttestation {
        let event = match name {
            "valid" => v["attestation"]["valid"]["event"].clone(),
            _ => v["attestation"]["invalid"]
                .as_array()
                .unwrap()
                .iter()
                .find(|case| case["name"] == name)
                .unwrap()["event"]
                .clone(),
        };
        let event = nostr_sdk::prelude::Event::from_json(event.to_string()).unwrap();
        let now = Timestamp::from(v["context"]["now"].as_u64().unwrap());
        ReputationAttestation::parse(&event, now, ATTESTATION_LIFETIME_SECS).unwrap()
    }

    fn proven_identity(v: &serde_json::Value) -> PublicKey {
        PublicKey::from_hex(v["context"]["proven_identity"].as_str().unwrap()).unwrap()
    }

    fn trust_list(v: &serde_json::Value) -> Vec<String> {
        v["context"]["trust_list"]
            .as_array()
            .unwrap()
            .iter()
            .flat_map(|entry| entry["keys"].as_array().unwrap().clone())
            .map(|key| key.as_str().unwrap().to_string())
            .collect()
    }

    #[test]
    fn an_export_answer_must_come_from_the_advertised_issuer_for_the_asked_identity() {
        // Arrange
        let v = vectors();
        let valid = attestation(&v, "valid");
        let issuer = valid.issuer.to_hex();
        let identity = proven_identity(&v);
        let someone_else = Keys::generate().public_key();

        // Act + Assert
        assert!(check_exported(&valid, &issuer, &identity).is_ok());
        let wrong_issuer = check_exported(&valid, &someone_else.to_hex(), &identity);
        assert!(wrong_issuer
            .unwrap_err()
            .to_string()
            .starts_with("InvalidReputationAttestation"));
        let wrong_identity = check_exported(&valid, &issuer, &someone_else);
        assert!(wrong_identity
            .unwrap_err()
            .to_string()
            .starts_with("InvalidReputationAttestation"));
    }

    #[test]
    fn an_import_is_refused_locally_for_another_identity_or_an_untrusted_issuer() {
        // Arrange
        let v = vectors();
        let identity = proven_identity(&v);
        let trusted = trust_list(&v);

        // Act + Assert
        assert!(check_importable(&attestation(&v, "valid"), &identity, &trusted).is_ok());
        let foreign = check_importable(&attestation(&v, "identity_mismatch"), &identity, &trusted);
        assert!(foreign
            .unwrap_err()
            .to_string()
            .starts_with("ReputationIdentityMismatch"));
        let untrusted = check_importable(&attestation(&v, "untrusted_issuer"), &identity, &trusted);
        assert!(untrusted
            .unwrap_err()
            .to_string()
            .starts_with("UntrustedReputationIssuer"));
        // A node that imports from nobody yet trusts no issuer.
        let nobody = check_importable(&attestation(&v, "valid"), &identity, &[]);
        assert!(nobody
            .unwrap_err()
            .to_string()
            .starts_with("UntrustedReputationIssuer"));
    }

    #[test]
    fn a_reformatted_attestation_has_the_same_event_id() {
        // Arrange: the same event, pretty-printed.
        let v = vectors();
        let json = v["attestation"]["valid"]["json"].as_str().unwrap();
        let reformatted =
            serde_json::to_string_pretty(&serde_json::from_str::<serde_json::Value>(json).unwrap())
                .unwrap();
        assert_ne!(reformatted, json);

        // Act + Assert
        assert_eq!(event_id(&reformatted), event_id(json));
        assert_eq!(
            event_id(json).as_deref(),
            v["attestation"]["valid"]["id"].as_str()
        );
        assert_eq!(event_id("not an event"), None);
    }

    #[test]
    fn a_key_that_is_not_hex_is_named_by_the_invalid_pubkey_marker() {
        let error = pubkey("npub-ish").unwrap_err().to_string();
        assert!(error.starts_with("InvalidPubkey"), "{error}");
        let key = Keys::generate().public_key();
        assert_eq!(pubkey(&format!("  {}\n", key.to_hex())).unwrap(), key);
    }

    #[tokio::test]
    async fn a_write_for_an_identity_no_longer_active_is_refused_without_running() {
        // Arrange: a generation no identity ever reaches, as if the one that
        // asked had been deleted while the node answered.
        let mut wrote = false;

        // Act
        let result = while_still_current(Some(u64::MAX), async {
            wrote = true;
            Ok(())
        })
        .await;

        // Assert
        assert!(result.unwrap_err().to_string().starts_with("NoIdentity"));
        assert!(!wrote);
        let no_identity = while_still_current(None, async { Ok(()) }).await;
        assert!(no_identity
            .unwrap_err()
            .to_string()
            .starts_with("NoIdentity"));
    }

    #[tokio::test]
    async fn checking_an_import_on_a_node_that_does_not_import_is_refused_up_front() {
        // Arrange: a valid attestation; the active node never advertised
        // `reputation_import_issuers` (no test records support for it).
        let v = vectors();
        let json = v["attestation"]["valid"]["json"]
            .as_str()
            .unwrap()
            .to_string();

        // Act
        let result = check_reputation_import(json).await;

        // Assert: refused by the capability gate, before the identity or the
        // attestation is looked at.
        let error = result.unwrap_err().to_string();
        assert!(error.starts_with("ReputationImportUnsupported"), "{error}");
    }
}
