//! The announcement channel's bridge surface
//! (`specs/006-announcement-channel/spec.md` §6.1, §7): what Dart reads, the
//! stream it follows, the Announcements toggle, and the read / dismissed
//! flags it reports back.
//!
//! Dart renders what this hands it and decides nothing: every announcement
//! here already passed the reader's door (`nostr::announcement_reader`), and
//! it carries all seven locales because Rust does not translate.

use anyhow::{anyhow, bail, Result};
use nostr_sdk::prelude::*;
use tokio::sync::broadcast;
use tokio::sync::broadcast::error::RecvError;

use crate::api::types::{AnnouncementInfo, AnnouncementSeverity, AnnouncementText};
use crate::db::{settings_keys, Storage};
use crate::nostr::announcement_reader::{self, CurrentAnnouncement};
use crate::nostr::announcements::{self, Severity};

/// Every announcement the cache holds right now: `critical` first, then
/// newest first (§3.4), dismissed ones included — a dismissed `critical`
/// stays listed and Dart is the one that knows (§3.4). Empty before the
/// database is up.
pub async fn get_announcements() -> Result<Vec<AnnouncementInfo>> {
    let Some(db) = crate::db::app_db::db() else {
        return Ok(Vec::new());
    };
    let current = announcement_reader::restore(
        db,
        &announcements::allowed_authors(),
        Timestamp::now(),
        &announcements::app_version(),
    )
    .await?;
    Ok(current.iter().map(to_info).collect())
}

/// The Announcements toggle (§7): on unless the user turned it off.
pub async fn get_announcements_enabled() -> Result<bool> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow!("StorageUnavailable"))?;
    Ok(announcement_reader::enabled_from_setting(
        db.get_setting(settings_keys::ANNOUNCEMENTS_ENABLED)
            .await?
            .as_deref(),
    ))
}

/// Flip the toggle. Off closes the relay subscription at the tap and
/// discards anything queued behind it; on reopens it, with the same 30-day
/// window a fresh install gets (§7). Persisted first: the subscription
/// follows the setting, never the other way round.
pub async fn set_announcements_enabled(enabled: bool) -> Result<()> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow!("StorageUnavailable"))?;
    db.set_setting(
        settings_keys::ANNOUNCEMENTS_ENABLED,
        if enabled { "true" } else { "false" },
    )
    .await?;
    announcement_reader::set_enabled(enabled).await;
    Ok(())
}

/// The user saw the announcement at `address`. Rust holds the flag because
/// it is Rust that decides whether a later revision re-announces (§5.3).
pub async fn mark_announcement_read(address: String) -> Result<()> {
    set_flags(&address, Some(true), None).await
}

/// The user swiped the announcement at `address` away. Read as well: a
/// dismissed notice never counts as unread, whichever level keeps it listed.
pub async fn dismiss_announcement(address: String) -> Result<()> {
    set_flags(&address, Some(true), Some(true)).await
}

async fn set_flags(address: &str, read: Option<bool>, dismissed: Option<bool>) -> Result<()> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow!("StorageUnavailable"))?;
    if !announcement_reader::set_flags(db, address, read, dismissed).await? {
        // Expired or swept since the card was drawn: nothing to record, and
        // the next emit takes the card with it.
        log::debug!("[announcements] {address} is no longer cached; flag dropped");
    }
    publish_current().await;
    Ok(())
}

/// The bridge's view of a cached announcement.
pub(crate) fn to_info(current: &CurrentAnnouncement) -> AnnouncementInfo {
    let announcement = &current.announcement;
    let body = &announcement.body;
    AnnouncementInfo {
        address: current.address.clone(),
        revision: announcement_reader::revision_of(announcement),
        created_at: announcement.created_at.as_secs() as i64,
        expiration: body.expiration.as_secs() as i64,
        severity: match body.severity {
            Severity::Info => AnnouncementSeverity::Info,
            Severity::Warning => AnnouncementSeverity::Warning,
            Severity::Critical => AnnouncementSeverity::Critical,
        },
        texts: body
            .texts
            .iter()
            .map(|text| AnnouncementText {
                locale: text.locale.clone(),
                title: text.title.clone(),
                body: text.body.clone(),
            })
            .collect(),
        url: body.url.clone(),
        read: current.read,
        dismissed: current.dismissed,
    }
}

// ── Stream ────────────────────────────────────────────────────────────────────

/// A few snapshots at most sit unread: each is the whole list, so a lagging
/// subscriber loses nothing by skipping to the newest.
const CHANNEL_CAPACITY: usize = 8;

fn tx() -> &'static broadcast::Sender<Vec<AnnouncementInfo>> {
    static TX: std::sync::OnceLock<broadcast::Sender<Vec<AnnouncementInfo>>> =
        std::sync::OnceLock::new();
    TX.get_or_init(|| broadcast::channel(CHANNEL_CAPACITY).0)
}

/// Hand Dart the cache as it stands. Called with the result of every pass
/// that may have changed it: a sweep, an arrival, a flag.
pub(crate) fn emit(current: &[CurrentAnnouncement]) {
    // An error only means nobody is listening yet.
    let _ = tx().send(current.iter().map(to_info).collect());
}

/// Re-read the cache and [`emit`] it. For the paths that changed one row
/// and do not hold the whole list.
pub(crate) async fn publish_current() {
    match get_announcements().await {
        Ok(list) => {
            let _ = tx().send(list);
        }
        Err(e) => log::warn!("[announcements] re-reading the cache failed: {e}"),
    }
}

/// The cache, whole, every time it changes (§6.1).
pub struct AnnouncementsStream {
    rx: broadcast::Receiver<Vec<AnnouncementInfo>>,
}

impl AnnouncementsStream {
    /// The next snapshot; a lag skips to the newest rather than ending the
    /// stream, since every snapshot is the whole list.
    pub async fn next(&mut self) -> Result<Vec<AnnouncementInfo>> {
        loop {
            match self.rx.recv().await {
                Ok(list) => return Ok(list),
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => bail!("AnnouncementsStream closed: sender dropped"),
            }
        }
    }
}

/// Subscribe before the first [`get_announcements`], so a snapshot landing
/// in between is not missed.
pub fn on_announcements_changed() -> AnnouncementsStream {
    AnnouncementsStream {
        rx: tx().subscribe(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::nostr::announcements::{parse_body, Announcement};
    use serde_json::json;

    fn current(severity: &str, read: bool, dismissed: bool) -> CurrentAnnouncement {
        let keys = Keys::generate();
        let locale = |l: &str| json!({ "title": format!("T {l}"), "body": "B" });
        let content = json!({
            "v": 1,
            "severity": severity,
            "locales": {
                "en": locale("en"), "es": locale("es"), "fr": locale("fr"),
                "de": locale("de"), "it": locale("it"), "nl": locale("nl"),
                "pt": locale("pt"),
            },
            "url": "https://mostro.network/blog",
        })
        .to_string();
        let tags = vec![
            Tag::identifier("release-2.1"),
            Tag::expiration(Timestamp::from_secs(1_900_000_000)),
        ];
        let event = EventBuilder::new(Kind::from(38387u16), &content)
            .tags(tags.clone())
            .custom_created_at(Timestamp::from_secs(1_800_000_000))
            .finalize(&keys)
            .unwrap();
        CurrentAnnouncement {
            address: announcement_reader::address_of(&keys.public_key(), "release-2.1"),
            announcement: Announcement {
                author: keys.public_key(),
                event_id: event.id,
                created_at: event.created_at,
                body: parse_body(&Tags::from_list(tags), &content).unwrap(),
            },
            read,
            dismissed,
        }
    }

    #[test]
    fn the_bridge_view_carries_every_locale_and_the_flags() {
        // Arrange
        let current = current("critical", true, false);

        // Act
        let info = to_info(&current);

        // Assert
        assert_eq!(info.address, current.address);
        assert_eq!(
            info.revision,
            format!("1800000000:{}", current.announcement.event_id.to_hex())
        );
        assert_eq!(info.created_at, 1_800_000_000);
        assert_eq!(info.expiration, 1_900_000_000);
        assert_eq!(info.severity, AnnouncementSeverity::Critical);
        assert_eq!(info.url.as_deref(), Some("https://mostro.network/blog"));
        assert!(info.read);
        assert!(!info.dismissed);
        let locales: Vec<&str> = info.texts.iter().map(|t| t.locale.as_str()).collect();
        assert_eq!(locales, announcements::SUPPORTED_LOCALES);
        assert_eq!(info.texts[1].title, "T es");
    }

    #[test]
    fn each_severity_maps_to_its_own_level() {
        for (token, level) in [
            ("info", AnnouncementSeverity::Info),
            ("warning", AnnouncementSeverity::Warning),
            ("critical", AnnouncementSeverity::Critical),
        ] {
            assert_eq!(to_info(&current(token, false, false)).severity, level);
        }
    }

    #[tokio::test]
    async fn an_emit_reaches_a_subscriber_whole() {
        // Arrange: subscribed before the emit, as Dart must be.
        let mut stream = on_announcements_changed();
        let list = vec![current("info", false, true)];

        // Act
        emit(&list);

        // Assert: other tests emit too, so read until this list arrives.
        loop {
            let got = stream.next().await.unwrap();
            if got.len() == 1 && got[0].address == list[0].address {
                assert!(got[0].dismissed);
                break;
            }
        }
    }

    #[test]
    fn the_toggle_defaults_to_on() {
        assert!(announcement_reader::enabled_from_setting(None));
        assert!(announcement_reader::enabled_from_setting(Some("true")));
        assert!(!announcement_reader::enabled_from_setting(Some("false")));
    }
}
