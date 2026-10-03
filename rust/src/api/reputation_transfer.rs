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
//! `ReputationAlreadyImported`, `InvalidReputationAttestation`, …).

use anyhow::{bail, Result};
use mostro_core::message::{Action, MessageKind, Payload, ReputationExportRequest};
use mostro_core::reputation::{
    AttestationError, ReputationAttestation, ReputationRebind, ATTESTATION_LIFETIME_SECS,
    REBIND_MAX_LIFETIME_SECS,
};
use nostr_sdk::prelude::{Keys, PublicKey, Timestamp};

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
    let identity = identity_keys().await?;
    let target = match destination {
        Some(hex) => PublicKey::from_hex(hex.trim())?.to_hex(),
        None => identity.public_key().to_hex(),
    };
    let payload = Payload::ReputationExportRequest(ReputationExportRequest {
        destination: target.clone(),
        rebind,
    });
    let reply = ask(
        &node,
        &identity,
        Action::ExportReputation,
        payload,
        is_export_reply,
    )
    .await?;
    let Some(Payload::ReputationAttestation(json)) = reply.payload else {
        bail!("InvalidPayload: the node answered without an attestation");
    };
    let attestation = parse(&json)?;
    if attestation.issuer.to_hex() != issuer || attestation.destination.to_hex() != target {
        bail!("InvalidReputationAttestation: not the node's issuer key, or another identity");
    }
    if let Some(db) = crate::db::app_db::db() {
        db.set_setting(PENDING_REPUTATION_ATTESTATION, &json)
            .await?;
    }
    Ok(ReputationAttestationInfo::new(&attestation, json))
}

/// Import `attestation_json` into the active node. It must name the user's
/// identity and be signed by a key the node advertises it trusts; the node
/// runs the full checks and answers `reputation-imported` or a refusal.
pub async fn import_reputation(attestation_json: String) -> Result<ReputationAttestationInfo> {
    let node = crate::config::active_mostro_pubkey();
    let Some(trusted) = reputation_support::get(&node).import_issuers else {
        bail!("ReputationImportUnsupported: the node does not import reputation");
    };
    let identity = identity_keys().await?;
    let attestation = parse(&attestation_json)?;
    if attestation.destination != identity.public_key() {
        bail!("ReputationIdentityMismatch: it names another identity");
    }
    if !trusted.contains(&attestation.issuer.to_hex()) {
        bail!("UntrustedReputationIssuer: the node does not trust its issuer");
    }
    ask(
        &node,
        &identity,
        Action::ImportReputation,
        Payload::ReputationAttestation(attestation_json.clone()),
        is_import_reply,
    )
    .await?;
    if let Some(db) = crate::db::app_db::db() {
        if db
            .get_setting(PENDING_REPUTATION_ATTESTATION)
            .await?
            .as_deref()
            == Some(attestation_json.as_str())
        {
            db.delete_setting(PENDING_REPUTATION_ATTESTATION).await?;
        }
    }
    Ok(ReputationAttestationInfo::new(
        &attestation,
        attestation_json,
    ))
}

/// The attestation exported last and not imported yet, while still valid.
pub async fn get_pending_reputation_attestation() -> Result<Option<ReputationAttestationInfo>> {
    let Some(db) = crate::db::app_db::db() else {
        return Ok(None);
    };
    let Some(json) = db.get_setting(PENDING_REPUTATION_ATTESTATION).await? else {
        return Ok(None);
    };
    Ok(parse(&json)
        .ok()
        .map(|attestation| ReputationAttestationInfo::new(&attestation, json)))
}

/// Sign, with the identity the reputation at `issuer` is bound to now, the
/// authorisation to move that binding to `new_identity` (hex). Pass it as
/// `rebind` to [`export_reputation`] from the new identity, or paste it into
/// lnp2pBot. Valid for an hour.
pub async fn sign_reputation_rebind(issuer: String, new_identity: String) -> Result<String> {
    let bound = identity_keys().await?;
    let issuer = PublicKey::from_hex(issuer.trim())?;
    let new_identity = PublicKey::parse(new_identity.trim())?;
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

/// Send one reputation request from a fresh trade key with the identity
/// proof, and wait for the node's answer to it.
async fn ask(
    node: &str,
    identity: &Keys,
    action: Action,
    payload: Payload,
    is_reply: fn(&MessageKind, u64) -> bool,
) -> Result<MessageKind> {
    let mostro_pubkey = PublicKey::from_hex(node)?;
    let trade_key_info = crate::api::identity::derive_trade_key().await?;
    let trade_keys = crate::api::identity::get_active_trade_keys(trade_key_info.index).await?;
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
}
