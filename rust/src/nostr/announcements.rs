//! The announcement channel (kind 38387): what an announcement is, and who
//! may publish one.
//!
//! Announcements are signed events from a short list of project keys compiled
//! into the app. The signature is the whole trust model: a relay can withhold
//! an announcement or serve a stale one, but it cannot forge one. This module
//! is the pure half of the channel — the event contract
//! (`specs/006-announcement-channel/spec.md` §3) and the author allowlist
//! (§4.1). It touches no relay, no database and no clock: `now` and the app
//! version are always arguments.
//!
//! Wire contract: <https://github.com/MostroP2P/protocol/pull/56>.

use nostr_sdk::prelude::*;
use semver::Version;
use serde_json::{Map, Value};

/// Kind 38387 — an announcement, addressable by `(kind, pubkey, d)`.
pub const KIND_ANNOUNCEMENT: u16 = 38387;

/// The keys allowed to publish announcements, as `npub`s (§4.1).
///
/// **Empty on purpose.** An empty allowlist means no authors, and no authors
/// means no subscription: every step of the feature can merge without the
/// channel being live. Filling it is a one-line commit of its own, with each
/// `npub` checked against a source outside this repo.
///
/// Never a maintainer's personal key, a Mostro node key, or a key the app
/// derives (`m/44'/1237'/38383'/0/N`). `npub` rather than hex because it is
/// what a reviewer compares with the published value.
const ALLOWLIST: &[&str] = &[];

/// The locales every announcement carries, all of them and no others (§3.2).
/// They are the app's locales — `lib/l10n/app_*.arb` — and change with them.
pub const SUPPORTED_LOCALES: [&str; 6] = ["en", "es", "fr", "de", "it", "nl"];

/// The only content schema this build reads (`v`).
pub const CONTENT_VERSION: u64 = 1;

/// Longest title, in characters after trimming.
pub const MAX_TITLE_CHARS: usize = 80;

/// Longest body, in characters after trimming.
pub const MAX_BODY_CHARS: usize = 500;

/// The authors whose announcements are read: [`ALLOWLIST`], decoded.
pub fn allowed_authors() -> Vec<PublicKey> {
    decode_allowlist(ALLOWLIST)
}

/// Decode `npub` entries. One that fails is dropped with a warning and the
/// rest still work — a typo in one constant must not silence the channel.
/// Hex is refused: the list is checked by people, and they check `npub`s.
pub fn decode_allowlist(entries: &[&str]) -> Vec<PublicKey> {
    entries
        .iter()
        .filter_map(|entry| match PublicKey::from_bech32(entry) {
            Ok(key) => Some(key),
            Err(e) => {
                log::warn!(
                    "[announcements] allowlist entry {entry:?} is not an npub ({e}); skipped"
                );
                None
            }
        })
        .collect()
}

/// How loudly an announcement is painted (§3.4). The publisher picks a level,
/// never a colour; the app maps the level onto its own palette.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Severity {
    Info,
    Warning,
    Critical,
}

impl Severity {
    /// The level a wire token names, `None` for any other token.
    pub fn from_wire(token: &str) -> Option<Self> {
        match token {
            "info" => Some(Self::Info),
            "warning" => Some(Self::Warning),
            "critical" => Some(Self::Critical),
            _ => None,
        }
    }
}

/// One locale's copy, trimmed. Plain text: nothing in it is markup or a link.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LocalizedText {
    pub locale: String,
    pub title: String,
    pub body: String,
}

/// Something the reader tolerated that a publisher must not send. The
/// announcement still shows; the publisher tool (§8) refuses it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Leniency {
    /// A `severity` this build does not know, shown as [`Severity::Warning`].
    UnknownSeverity(String),
    /// A `url` that is not an `https` link, dropped.
    UrlDropped(String),
}

/// What an announcement says, from its tags and content (§3).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AnnouncementBody {
    /// The `d` tag: the announcement's id within its author's address space.
    pub identifier: String,
    pub expiration: Timestamp,
    /// Inclusive lower bound on the app version.
    pub min_version: Option<Version>,
    /// Exclusive upper bound on the app version.
    pub max_version: Option<Version>,
    pub severity: Severity,
    /// One entry per [`SUPPORTED_LOCALES`], in that order.
    pub texts: Vec<LocalizedText>,
    /// The single action link, `https` only.
    pub url: Option<String>,
    pub leniencies: Vec<Leniency>,
}

impl AnnouncementBody {
    /// Whether an app at `version` is inside `[min_version, max_version)`.
    pub fn reaches(&self, version: &Version) -> bool {
        self.min_version.as_ref().is_none_or(|min| version >= min)
            && self.max_version.as_ref().is_none_or(|max| version < max)
    }
}

/// An announcement from an allowlisted author, with a valid signature.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Announcement {
    pub author: PublicKey,
    pub event_id: EventId,
    pub created_at: Timestamp,
    pub body: AnnouncementBody,
}

/// Why a version bound cannot be read.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum BoundError {
    #[error("build metadata (`+…`) is not allowed: semver ignores it when comparing, so part of the bound would be silently dropped")]
    BuildMetadata,
    #[error("not a version: write MAJOR[.MINOR[.PATCH]], optionally with a pre-release such as `-beta.1`")]
    Unparseable,
}

/// Why an event is not an announcement. Every message names the fix, because
/// the publisher tool shows them to whoever is about to publish.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum AnnouncementError {
    #[error("kind {0} is not an announcement: use kind {KIND_ANNOUNCEMENT}")]
    WrongKind(u16),
    #[error("the author is not on the announcement allowlist")]
    AuthorNotAllowed,
    #[error("the signature does not match the event")]
    BadSignature,
    #[error(
        "the `d` tag is missing or empty: give the announcement an id that was never used before"
    )]
    MissingIdentifier,
    #[error(
        "the `expiration` tag is missing: every announcement needs one (unix seconds, NIP-40)"
    )]
    MissingExpiration,
    #[error("the `expiration` tag `{0}` is not a unix timestamp in seconds")]
    BadExpiration(String),
    #[error("the `{tag}` tag `{value}`: {problem}")]
    BadVersionBound {
        tag: &'static str,
        value: String,
        problem: BoundError,
    },
    #[error("the content is not JSON: {0}")]
    ContentNotJson(String),
    #[error("the content must be a JSON object")]
    ContentNotObject,
    #[error("content `v` is {0}: this app reads `\"v\": {CONTENT_VERSION}` only")]
    UnsupportedContentVersion(String),
    #[error("content field `{0}` is missing")]
    MissingField(&'static str),
    #[error("content `locales` must be an object keyed by locale")]
    LocalesNotObject,
    #[error("locale `{0}` is missing: every announcement carries all of en, es, fr, de, it, nl")]
    MissingLocale(String),
    #[error("locale `{0}` is not one the app has: send exactly en, es, fr, de, it, nl")]
    UnknownLocale(String),
    #[error("`locales.{locale}.{field}` is missing or not a string")]
    MissingText { locale: String, field: &'static str },
    #[error("`locales.{locale}.{field}` is empty")]
    EmptyText { locale: String, field: &'static str },
    #[error("`locales.{locale}.{field}` is {chars} characters, {} over the limit of {max}", chars - max)]
    TextTooLong {
        locale: String,
        field: &'static str,
        chars: usize,
        max: usize,
    },
}

/// Read a version bound (§3.1): one to three numeric components, missing ones
/// counting as `0`, and an optional pre-release. Build metadata is refused.
pub fn parse_version(raw: &str) -> Result<Version, BoundError> {
    if raw.contains('+') {
        return Err(BoundError::BuildMetadata);
    }
    let (release, pre_release) = match raw.split_once('-') {
        Some((release, pre)) => (release, Some(pre)),
        None => (raw, None),
    };
    let components: Vec<&str> = release.split('.').collect();
    let all_numeric = components
        .iter()
        .all(|c| !c.is_empty() && c.bytes().all(|b| b.is_ascii_digit()));
    if components.len() > 3 || !all_numeric {
        return Err(BoundError::Unparseable);
    }
    let mut full = components.join(".");
    for _ in components.len()..3 {
        full.push_str(".0");
    }
    if let Some(pre) = pre_release {
        full.push('-');
        full.push_str(pre);
    }
    // semver checks what is left: leading zeros and the pre-release grammar.
    Version::parse(&full).map_err(|_| BoundError::Unparseable)
}

/// The version bounds are compared against: the shipped release version, the
/// crate's (held equal to pubspec's by `api::tests`).
pub fn app_version() -> Version {
    parse_version(env!("CARGO_PKG_VERSION")).expect("CARGO_PKG_VERSION is a release version")
}

/// The first stage of the reader (§5.2 steps 1–3): the author is allowlisted,
/// the signature holds, and the event parses as §3 says. Freshness, expiry
/// and the version range depend on the clock and the build, and are applied
/// by the caller.
pub fn admit(event: &Event, allowlist: &[PublicKey]) -> Result<Announcement, AnnouncementError> {
    if event.kind.as_u16() != KIND_ANNOUNCEMENT {
        return Err(AnnouncementError::WrongKind(event.kind.as_u16()));
    }
    if !allowlist.contains(&event.pubkey) {
        return Err(AnnouncementError::AuthorNotAllowed);
    }
    // Explicit, whatever the relay pool verifies on its own: the pool's
    // settings are a transport detail, and this is what the channel rests on.
    event
        .verify()
        .map_err(|_| AnnouncementError::BadSignature)?;
    Ok(Announcement {
        author: event.pubkey,
        event_id: event.id,
        created_at: event.created_at,
        body: parse_body(&event.tags, &event.content)?,
    })
}

/// Parse an announcement's tags and content (§3). Shared by the reader and
/// the publisher tool, so the tool cannot accept what the app would drop.
pub fn parse_body(tags: &Tags, content: &str) -> Result<AnnouncementBody, AnnouncementError> {
    let identifier = tags
        .identifier()
        .filter(|d| !d.trim().is_empty())
        .ok_or(AnnouncementError::MissingIdentifier)?;
    let expiration = match tags.expiration() {
        Some(expiration) => expiration,
        None => {
            return Err(match tag_value(tags, "expiration") {
                Some(raw) => AnnouncementError::BadExpiration(raw.to_string()),
                None => AnnouncementError::MissingExpiration,
            })
        }
    };
    let min_version = version_bound(tags, "min_version")?;
    let max_version = version_bound(tags, "max_version")?;

    let json: Value = serde_json::from_str(content)
        .map_err(|e| AnnouncementError::ContentNotJson(e.to_string()))?;
    let fields = json
        .as_object()
        .ok_or(AnnouncementError::ContentNotObject)?;
    match fields.get("v") {
        Some(v) if v.as_u64() == Some(CONTENT_VERSION) => {}
        Some(v) => return Err(AnnouncementError::UnsupportedContentVersion(v.to_string())),
        None => {
            return Err(AnnouncementError::UnsupportedContentVersion(
                "missing".into(),
            ))
        }
    }

    let mut leniencies = Vec::new();
    let severity = parse_severity(fields, &mut leniencies)?;
    let texts = parse_locales(fields)?;
    let url = parse_url(fields, &mut leniencies);

    Ok(AnnouncementBody {
        identifier,
        expiration,
        min_version,
        max_version,
        severity,
        texts,
        url,
        leniencies,
    })
}

/// The first value of the first tag named `name`.
fn tag_value<'a>(tags: &'a Tags, name: &str) -> Option<&'a str> {
    tags.iter()
        .find(|t| t.kind() == name)
        .map(|t| t.content().unwrap_or_default())
}

/// A bound that is present must parse: a targeting instruction nobody can
/// read has failed, and showing the message to everyone is the wrong way to
/// fail it.
fn version_bound(tags: &Tags, tag: &'static str) -> Result<Option<Version>, AnnouncementError> {
    tag_value(tags, tag)
        .map(|value| {
            parse_version(value).map_err(|problem| AnnouncementError::BadVersionBound {
                tag,
                value: value.to_string(),
                problem,
            })
        })
        .transpose()
}

/// Missing is invalid; unknown paints as a warning (§3.4). `v` and the
/// locales decide whether a message is intelligible, severity only how it is
/// painted — and dropping a security notice because a later release added a
/// level is the worst outcome available. Not `critical`: an unknown token
/// must not be a way to paint the app red.
fn parse_severity(
    fields: &Map<String, Value>,
    leniencies: &mut Vec<Leniency>,
) -> Result<Severity, AnnouncementError> {
    let token = match fields.get("severity") {
        None | Some(Value::Null) => return Err(AnnouncementError::MissingField("severity")),
        Some(Value::String(token)) => token.clone(),
        Some(other) => other.to_string(),
    };
    Ok(Severity::from_wire(&token).unwrap_or_else(|| {
        leniencies.push(Leniency::UnknownSeverity(token));
        Severity::Warning
    }))
}

/// Exactly [`SUPPORTED_LOCALES`], each with a title and a body. No fallback
/// to English: it is a bug that ships quietly. An extra locale is refused
/// too — it is the shape a new locale takes, and ignoring it would leave the
/// sender believing they reached readers this build cannot serve.
fn parse_locales(fields: &Map<String, Value>) -> Result<Vec<LocalizedText>, AnnouncementError> {
    let locales = match fields.get("locales") {
        None | Some(Value::Null) => return Err(AnnouncementError::MissingField("locales")),
        Some(locales) => locales
            .as_object()
            .ok_or(AnnouncementError::LocalesNotObject)?,
    };
    if let Some(missing) = SUPPORTED_LOCALES
        .iter()
        .find(|l| !locales.contains_key(**l))
    {
        return Err(AnnouncementError::MissingLocale(missing.to_string()));
    }
    if let Some(extra) = locales
        .keys()
        .find(|l| !SUPPORTED_LOCALES.contains(&l.as_str()))
    {
        return Err(AnnouncementError::UnknownLocale(extra.clone()));
    }
    SUPPORTED_LOCALES
        .iter()
        .map(|locale| {
            let entry = &locales[*locale];
            Ok(LocalizedText {
                locale: locale.to_string(),
                title: text_field(entry, locale, "title", MAX_TITLE_CHARS)?,
                body: text_field(entry, locale, "body", MAX_BODY_CHARS)?,
            })
        })
        .collect()
}

fn text_field(
    entry: &Value,
    locale: &str,
    field: &'static str,
    max: usize,
) -> Result<String, AnnouncementError> {
    let text = entry
        .get(field)
        .and_then(Value::as_str)
        .ok_or_else(|| AnnouncementError::MissingText {
            locale: locale.into(),
            field,
        })?
        .trim();
    if text.is_empty() {
        return Err(AnnouncementError::EmptyText {
            locale: locale.into(),
            field,
        });
    }
    let chars = text.chars().count();
    if chars > max {
        return Err(AnnouncementError::TextTooLong {
            locale: locale.into(),
            field,
            chars,
            max,
        });
    }
    Ok(text.to_string())
}

/// The one action link: an `https` URL with a host and no credentials, or
/// nothing. A bad link costs the announcement its button, not the
/// announcement itself. What is kept is the URL as parsed, not as sent: the
/// parser drops whitespace and reads `\` as `/`, so the raw string could name
/// another host to whatever opens it. Credentials are refused because
/// `https://mostro.network@evil.example` is a link to `evil.example`.
fn parse_url(fields: &Map<String, Value>, leniencies: &mut Vec<Leniency>) -> Option<String> {
    let raw = match fields.get("url") {
        None | Some(Value::Null) => return None,
        Some(Value::String(raw)) => raw.clone(),
        Some(other) => other.to_string(),
    };
    match Url::parse(&raw) {
        Ok(url)
            if url.scheme() == "https"
                && url.host_str().is_some_and(|h| !h.is_empty())
                && url.username().is_empty()
                && url.password().is_none() =>
        {
            Some(url.to_string())
        }
        _ => {
            leniencies.push(Leniency::UrlDropped(raw));
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn valid_content() -> Value {
        let locale =
            |l: &str| json!({ "title": format!("Title {l}"), "body": format!("Body {l}") });
        json!({
            "v": 1,
            "severity": "info",
            "locales": {
                "en": locale("en"), "es": locale("es"), "fr": locale("fr"),
                "de": locale("de"), "it": locale("it"), "nl": locale("nl"),
            },
            "url": "https://mostro.network/blog/2-1",
        })
    }

    fn valid_tags() -> Vec<Tag> {
        vec![
            Tag::identifier("release-2.1"),
            Tag::expiration(Timestamp::from_secs(2_000_000_000)),
            Tag::custom("z", ["announcement"]),
        ]
    }

    fn sign(keys: &Keys, tags: Vec<Tag>, content: &Value) -> Event {
        EventBuilder::new(Kind::from(KIND_ANNOUNCEMENT), content.to_string())
            .tags(tags)
            .finalize(keys)
            .unwrap()
    }

    fn parse(tags: Vec<Tag>, content: &Value) -> Result<AnnouncementBody, AnnouncementError> {
        parse_body(&Tags::from_list(tags), &content.to_string())
    }

    fn parse_content(content: &Value) -> Result<AnnouncementBody, AnnouncementError> {
        parse(valid_tags(), content)
    }

    fn with_tag(name: &str, value: &str) -> Vec<Tag> {
        let mut tags = valid_tags();
        tags.push(Tag::custom(name, [value]));
        tags
    }

    fn v(raw: &str) -> Version {
        parse_version(raw).unwrap()
    }

    // ── Allowlist (§4.1) ────────────────────────────────────────────────

    #[test]
    fn allowlisted_author_is_admitted() {
        let keys = Keys::generate();
        let event = sign(&keys, valid_tags(), &valid_content());

        let announcement = admit(&event, &[keys.public_key()]).unwrap();

        assert_eq!(announcement.author, keys.public_key());
        assert_eq!(announcement.event_id, event.id);
        assert_eq!(announcement.created_at, event.created_at);
        assert_eq!(announcement.body.identifier, "release-2.1");
    }

    #[test]
    fn any_other_author_is_refused() {
        let project = Keys::generate();
        let stranger = Keys::generate();
        let event = sign(&stranger, valid_tags(), &valid_content());

        assert_eq!(
            admit(&event, &[project.public_key()]),
            Err(AnnouncementError::AuthorNotAllowed)
        );
    }

    #[test]
    fn an_empty_allowlist_admits_nobody() {
        let keys = Keys::generate();
        let event = sign(&keys, valid_tags(), &valid_content());

        assert!(decode_allowlist(&[]).is_empty());
        assert_eq!(admit(&event, &[]), Err(AnnouncementError::AuthorNotAllowed));
    }

    #[test]
    fn an_undecodable_entry_does_not_disable_the_rest() {
        let a = Keys::generate().public_key();
        let b = Keys::generate().public_key();
        let a_npub = a.to_bech32().unwrap();
        let b_npub = b.to_bech32().unwrap();
        // Swap the last character for a different one: bech32 catches any
        // single substitution. Always writing 'x' turned the "typo" back into
        // `a_npub` whenever that already ended in 'x' (one key in 32).
        let (head, last) = a_npub.split_at(a_npub.len() - 1);
        let typo = format!("{head}{}", if last == "x" { 'q' } else { 'x' });

        let decoded = decode_allowlist(&[&a_npub, &typo, "", &b_npub]);

        assert_eq!(decoded, vec![a, b]);
    }

    #[test]
    fn a_hex_entry_is_refused() {
        let key = Keys::generate().public_key();

        assert!(decode_allowlist(&[&key.to_hex()]).is_empty());
    }

    #[test]
    fn the_shipped_allowlist_decodes_in_full() {
        assert_eq!(allowed_authors().len(), ALLOWLIST.len());
    }

    #[test]
    fn another_kind_is_refused() {
        let keys = Keys::generate();
        let event = EventBuilder::new(Kind::from(38383), valid_content().to_string())
            .tags(valid_tags())
            .finalize(&keys)
            .unwrap();

        assert_eq!(
            admit(&event, &[keys.public_key()]),
            Err(AnnouncementError::WrongKind(38383))
        );
    }

    // ── Verification (§4.2) ─────────────────────────────────────────────

    fn tampered(event: &Event, edit: impl FnOnce(&mut Value)) -> Event {
        let mut json: Value = serde_json::from_str(&event.as_json()).unwrap();
        edit(&mut json);
        Event::from_json(json.to_string()).unwrap()
    }

    #[test]
    fn tampered_content_is_refused() {
        let keys = Keys::generate();
        let event = sign(&keys, valid_tags(), &valid_content());
        let mut forged_content = valid_content();
        forged_content["url"] = json!("https://evil.example/");
        let forged = tampered(&event, |e| e["content"] = json!(forged_content.to_string()));

        assert_eq!(
            admit(&forged, &[keys.public_key()]),
            Err(AnnouncementError::BadSignature)
        );
    }

    #[test]
    fn a_tampered_tag_is_refused() {
        let keys = Keys::generate();
        let event = sign(&keys, valid_tags(), &valid_content());
        let forged = tampered(&event, |e| e["tags"][1][1] = json!("4000000000"));

        assert_eq!(
            admit(&forged, &[keys.public_key()]),
            Err(AnnouncementError::BadSignature)
        );
    }

    #[test]
    fn a_signature_by_another_key_is_refused() {
        let project = Keys::generate();
        let stranger = Keys::generate();
        let by_stranger = sign(&stranger, valid_tags(), &valid_content());
        // Claim the project's key, keep the stranger's signature.
        let forged = tampered(&by_stranger, |e| {
            e["pubkey"] = json!(project.public_key().to_hex())
        });

        assert_eq!(
            admit(&forged, &[project.public_key()]),
            Err(AnnouncementError::BadSignature)
        );
    }

    // ── Tags (§3, §3.1) ─────────────────────────────────────────────────

    #[test]
    fn a_valid_announcement_parses_in_full() {
        let body = parse_content(&valid_content()).unwrap();

        assert_eq!(body.identifier, "release-2.1");
        assert_eq!(body.expiration, Timestamp::from_secs(2_000_000_000));
        assert_eq!(body.severity, Severity::Info);
        assert_eq!(body.url.as_deref(), Some("https://mostro.network/blog/2-1"));
        assert_eq!(body.min_version, None);
        assert_eq!(body.max_version, None);
        assert!(body.leniencies.is_empty());
        let locales: Vec<&str> = body.texts.iter().map(|t| t.locale.as_str()).collect();
        assert_eq!(locales, SUPPORTED_LOCALES);
        assert_eq!(body.texts[4].title, "Title it");
        assert_eq!(body.texts[4].body, "Body it");
    }

    #[test]
    fn a_missing_or_empty_d_is_refused() {
        let no_d: Vec<Tag> = valid_tags().into_iter().skip(1).collect();
        let mut empty_d = valid_tags();
        empty_d[0] = Tag::identifier("");
        let mut blank_d = valid_tags();
        blank_d[0] = Tag::identifier("  ");

        assert_eq!(
            parse(no_d, &valid_content()),
            Err(AnnouncementError::MissingIdentifier)
        );
        assert_eq!(
            parse(empty_d, &valid_content()),
            Err(AnnouncementError::MissingIdentifier)
        );
        assert_eq!(
            parse(blank_d, &valid_content()),
            Err(AnnouncementError::MissingIdentifier)
        );
    }

    #[test]
    fn a_missing_expiration_is_refused() {
        let tags: Vec<Tag> = valid_tags()
            .into_iter()
            .filter(|t| t.kind() != "expiration")
            .collect();

        assert_eq!(
            parse(tags, &valid_content()),
            Err(AnnouncementError::MissingExpiration)
        );
    }

    #[test]
    fn an_unreadable_expiration_is_refused() {
        let mut tags = valid_tags();
        tags[1] = Tag::custom("expiration", ["tomorrow"]);

        assert_eq!(
            parse(tags, &valid_content()),
            Err(AnnouncementError::BadExpiration("tomorrow".into()))
        );
    }

    #[test]
    fn the_z_tag_is_not_required_of_the_reader() {
        let tags: Vec<Tag> = valid_tags()
            .into_iter()
            .filter(|t| t.kind() != "z")
            .collect();

        assert!(parse(tags, &valid_content()).is_ok());
    }

    #[test]
    fn version_bounds_are_read() {
        let mut tags = with_tag("min_version", "2");
        tags.push(Tag::custom("max_version", ["2.1.0-beta.1"]));

        let body = parse(tags, &valid_content()).unwrap();

        assert_eq!(body.min_version, Some(v("2.0.0")));
        assert_eq!(body.max_version, Some(v("2.1.0-beta.1")));
    }

    #[test]
    fn a_bound_with_build_metadata_is_refused() {
        assert_eq!(
            parse(with_tag("max_version", "2.1.0+1"), &valid_content()),
            Err(AnnouncementError::BadVersionBound {
                tag: "max_version",
                value: "2.1.0+1".into(),
                problem: BoundError::BuildMetadata,
            })
        );
    }

    #[test]
    fn an_unparseable_bound_is_refused_not_ignored() {
        for raw in ["next", "", "2.1.0.4", "v2.1", "2..1", "2.1-", " 2.1"] {
            assert_eq!(
                parse(with_tag("min_version", raw), &valid_content()),
                Err(AnnouncementError::BadVersionBound {
                    tag: "min_version",
                    value: raw.into(),
                    problem: BoundError::Unparseable,
                }),
                "{raw:?}"
            );
        }
    }

    // ── Version bounds (§3.1) ───────────────────────────────────────────

    #[test]
    fn short_versions_fill_with_zeros() {
        assert_eq!(v("2"), Version::new(2, 0, 0));
        assert_eq!(v("2.1"), Version::new(2, 1, 0));
        assert_eq!(v("2.1.3"), Version::new(2, 1, 3));
        assert_eq!(v("2.1-rc.1"), Version::parse("2.1.0-rc.1").unwrap());
    }

    #[test]
    fn a_pre_release_orders_before_its_release() {
        assert!(v("2.1.0-beta.1") < v("2.1.0"));
        assert!(v("2.1.0-beta.1") > v("2.0.9"));
    }

    fn bounded(min: Option<&str>, max: Option<&str>) -> AnnouncementBody {
        let mut tags = valid_tags();
        if let Some(min) = min {
            tags.push(Tag::custom("min_version", [min]));
        }
        if let Some(max) = max {
            tags.push(Tag::custom("max_version", [max]));
        }
        parse(tags, &valid_content()).unwrap()
    }

    #[test]
    fn an_unbounded_announcement_reaches_every_version() {
        assert!(bounded(None, None).reaches(&v("0.0.1")));
        assert!(bounded(None, None).reaches(&v("99")));
    }

    #[test]
    fn max_version_is_exclusive() {
        let about_2_1 = bounded(None, Some("2.1"));

        assert!(about_2_1.reaches(&v("2.0.0")));
        assert!(about_2_1.reaches(&v("2.1.0-beta.1")));
        assert!(!about_2_1.reaches(&v("2.1.0")));
        assert!(!about_2_1.reaches(&v("2.2.0")));
    }

    #[test]
    fn min_version_is_inclusive() {
        let since_2_1 = bounded(Some("2.1"), None);

        assert!(!since_2_1.reaches(&v("2.0.10")));
        assert!(since_2_1.reaches(&v("2.1.0")));
        assert!(since_2_1.reaches(&v("3.0.0")));
    }

    #[test]
    fn an_empty_range_reaches_nobody() {
        let empty = bounded(Some("2.1"), Some("2.1"));

        assert!(!empty.reaches(&v("2.1.0")));
        assert!(!empty.reaches(&v("2.0.0")));
    }

    #[test]
    fn the_app_version_is_a_release_version() {
        let version = app_version();

        assert!(version.pre.is_empty());
        assert!(version.build.is_empty());
        assert_eq!(version.to_string(), env!("CARGO_PKG_VERSION"));
    }

    // ── Content (§3.2) ──────────────────────────────────────────────────

    #[test]
    fn content_that_is_not_json_is_refused() {
        let result = parse_body(&Tags::from_list(valid_tags()), "not json");

        assert!(matches!(result, Err(AnnouncementError::ContentNotJson(_))));
    }

    #[test]
    fn content_that_is_not_an_object_is_refused() {
        assert_eq!(
            parse_content(&json!([1, 2])),
            Err(AnnouncementError::ContentNotObject)
        );
    }

    #[test]
    fn an_unknown_content_version_is_refused() {
        let mut v2 = valid_content();
        v2["v"] = json!(2);
        let mut no_v = valid_content();
        no_v.as_object_mut().unwrap().remove("v");
        let mut text_v = valid_content();
        text_v["v"] = json!("1");

        assert_eq!(
            parse_content(&v2),
            Err(AnnouncementError::UnsupportedContentVersion("2".into()))
        );
        assert_eq!(
            parse_content(&no_v),
            Err(AnnouncementError::UnsupportedContentVersion(
                "missing".into()
            ))
        );
        assert_eq!(
            parse_content(&text_v),
            Err(AnnouncementError::UnsupportedContentVersion("\"1\"".into()))
        );
    }

    #[test]
    fn a_missing_locale_is_refused() {
        let mut content = valid_content();
        content["locales"].as_object_mut().unwrap().remove("it");

        assert_eq!(
            parse_content(&content),
            Err(AnnouncementError::MissingLocale("it".into()))
        );
    }

    #[test]
    fn an_unknown_extra_locale_is_refused() {
        let mut content = valid_content();
        content["locales"]["pt"] = json!({ "title": "Olá", "body": "Corpo" });

        assert_eq!(
            parse_content(&content),
            Err(AnnouncementError::UnknownLocale("pt".into()))
        );
    }

    #[test]
    fn missing_locales_are_refused() {
        let mut content = valid_content();
        content.as_object_mut().unwrap().remove("locales");
        let mut not_object = valid_content();
        not_object["locales"] = json!(["en"]);

        assert_eq!(
            parse_content(&content),
            Err(AnnouncementError::MissingField("locales"))
        );
        assert_eq!(
            parse_content(&not_object),
            Err(AnnouncementError::LocalesNotObject)
        );
    }

    #[test]
    fn a_locale_without_a_title_or_body_is_refused() {
        let mut no_title = valid_content();
        no_title["locales"]["de"]
            .as_object_mut()
            .unwrap()
            .remove("title");
        let mut numeric_body = valid_content();
        numeric_body["locales"]["fr"]["body"] = json!(5);

        assert_eq!(
            parse_content(&no_title),
            Err(AnnouncementError::MissingText {
                locale: "de".into(),
                field: "title"
            })
        );
        assert_eq!(
            parse_content(&numeric_body),
            Err(AnnouncementError::MissingText {
                locale: "fr".into(),
                field: "body"
            })
        );
    }

    #[test]
    fn a_blank_title_or_body_is_refused() {
        let mut blank = valid_content();
        blank["locales"]["nl"]["body"] = json!("   ");

        assert_eq!(
            parse_content(&blank),
            Err(AnnouncementError::EmptyText {
                locale: "nl".into(),
                field: "body"
            })
        );
    }

    #[test]
    fn text_is_trimmed_and_measured_in_characters() {
        let mut content = valid_content();
        // 80 two-byte characters, padded: at the limit once trimmed.
        content["locales"]["es"]["title"] = json!(format!("  {}\n", "ñ".repeat(80)));
        content["locales"]["es"]["body"] = json!("é".repeat(500));

        let body = parse_content(&content).unwrap();

        assert_eq!(body.texts[1].title, "ñ".repeat(80));
    }

    #[test]
    fn an_over_length_title_or_body_is_refused() {
        let mut long_title = valid_content();
        long_title["locales"]["en"]["title"] = json!("x".repeat(83));
        let mut long_body = valid_content();
        long_body["locales"]["it"]["body"] = json!("x".repeat(501));

        let err = parse_content(&long_title).unwrap_err();
        assert_eq!(
            err,
            AnnouncementError::TextTooLong {
                locale: "en".into(),
                field: "title",
                chars: 83,
                max: MAX_TITLE_CHARS,
            }
        );
        assert!(err.to_string().contains("3 over the limit of 80"), "{err}");
        assert_eq!(
            parse_content(&long_body),
            Err(AnnouncementError::TextTooLong {
                locale: "it".into(),
                field: "body",
                chars: 501,
                max: MAX_BODY_CHARS,
            })
        );
    }

    #[test]
    fn a_url_is_optional() {
        let mut content = valid_content();
        content.as_object_mut().unwrap().remove("url");

        let body = parse_content(&content).unwrap();

        assert_eq!(body.url, None);
        assert!(body.leniencies.is_empty());
    }

    #[test]
    fn a_url_that_is_not_https_is_dropped_and_the_announcement_kept() {
        for raw in [
            json!("http://mostro.network/"),
            json!("javascript:alert(1)"),
            json!("mostro.network"),
            json!("https://"),
            json!(42),
        ] {
            let mut content = valid_content();
            content["url"] = raw.clone();

            let body = parse_content(&content).unwrap();

            assert_eq!(body.url, None, "{raw}");
            let shown = raw
                .as_str()
                .map(str::to_string)
                .unwrap_or_else(|| raw.to_string());
            assert_eq!(body.leniencies, vec![Leniency::UrlDropped(shown)], "{raw}");
        }
    }

    #[test]
    fn the_url_kept_is_the_one_that_was_checked() {
        for (raw, kept) in [
            // A browser reads `\` as `/`; another parser may read a host.
            (
                "https://mostro.network\\@evil.example/",
                "https://mostro.network/@evil.example/",
            ),
            (" https://mostro.network/a\nb ", "https://mostro.network/ab"),
            ("https://mostro.network", "https://mostro.network/"),
        ] {
            let mut content = valid_content();
            content["url"] = json!(raw);

            assert_eq!(
                parse_content(&content).unwrap().url.as_deref(),
                Some(kept),
                "{raw:?}"
            );
        }
    }

    #[test]
    fn a_url_with_credentials_is_dropped() {
        for raw in [
            "https://mostro.network@evil.example/",
            "https://user:pw@mostro.network/",
        ] {
            let mut content = valid_content();
            content["url"] = json!(raw);

            let body = parse_content(&content).unwrap();

            assert_eq!(body.url, None, "{raw}");
            assert_eq!(body.leniencies, vec![Leniency::UrlDropped(raw.into())]);
        }
    }

    // ── Severity (§3.4) ─────────────────────────────────────────────────

    #[test]
    fn each_severity_is_read() {
        for (token, level) in [
            ("info", Severity::Info),
            ("warning", Severity::Warning),
            ("critical", Severity::Critical),
        ] {
            let mut content = valid_content();
            content["severity"] = json!(token);

            assert_eq!(parse_content(&content).unwrap().severity, level);
        }
    }

    #[test]
    fn a_missing_severity_is_refused() {
        let mut content = valid_content();
        content.as_object_mut().unwrap().remove("severity");
        let mut null = valid_content();
        null["severity"] = Value::Null;

        assert_eq!(
            parse_content(&content),
            Err(AnnouncementError::MissingField("severity"))
        );
        assert_eq!(
            parse_content(&null),
            Err(AnnouncementError::MissingField("severity"))
        );
    }

    #[test]
    fn an_unknown_severity_shows_as_a_warning() {
        let mut content = valid_content();
        content["severity"] = json!("emergency");

        let body = parse_content(&content).unwrap();

        assert_eq!(body.severity, Severity::Warning);
        assert_eq!(
            body.leniencies,
            vec![Leniency::UnknownSeverity("emergency".into())]
        );
    }

    #[test]
    fn severity_tokens_are_exact() {
        assert_eq!(Severity::from_wire("Critical"), None);
        assert_eq!(Severity::from_wire(" info"), None);
    }

    // ── Locales follow the app ──────────────────────────────────────────

    /// When the app gains a locale, announcements must carry it too (§3.2):
    /// the two lists change in the same release.
    #[test]
    fn supported_locales_are_the_apps_locales() {
        let l10n = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../lib/l10n");
        let mut app: Vec<String> = std::fs::read_dir(&l10n)
            .unwrap()
            .filter_map(|entry| {
                let name = entry.unwrap().file_name().into_string().unwrap();
                name.strip_prefix("app_")?
                    .strip_suffix(".arb")
                    .map(str::to_string)
            })
            .collect();
        app.sort();
        let mut ours: Vec<String> = SUPPORTED_LOCALES.iter().map(|l| l.to_string()).collect();
        ours.sort();

        assert_eq!(ours, app);
    }
}
