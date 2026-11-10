//! `announce` — validate an announcement draft and emit the unsigned event
//! (`specs/006-announcement-channel/spec.md` §8, `docs/ANNOUNCEMENTS.md`).
//!
//! The reader's failure mode is silence: publish a malformed announcement and
//! nothing tells you, on either end. This tool calls the app's own parser
//! (`nostr::announcements::parse_body`), so it cannot accept what the app
//! would drop, and it refuses what the app merely tolerates — an unknown
//! severity, a link that would be dropped. It does not sign and does not
//! publish: the key lives offline, and signing stays with `nak`.
//!
//! ```sh
//! cargo run --bin announce -- --template > draft.json
//! # edit draft.json — all seven locales, an expiry in the future
//! cargo run --bin announce -- draft.json --out event.json
//! nak event --sec <the offline key> wss://relay.mostro.network < event.json
//! ```
//!
//! Native only: on the web target the crate's library is the app, and this
//! binary is an empty `main` so `cargo check --target wasm32` stays green.

#[cfg(target_arch = "wasm32")]
fn main() {}

#[cfg(not(target_arch = "wasm32"))]
fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    std::process::exit(tool::run(&args));
}

#[cfg(not(target_arch = "wasm32"))]
mod tool {
    use std::io::Write;

    use nostr_sdk::prelude::*;
    use rust::nostr::announcements::{
        parse_body, AnnouncementBody, Leniency, Severity, KIND_ANNOUNCEMENT, SUPPORTED_LOCALES,
    };
    use serde::Deserialize;
    use serde_json::{json, Map, Value};

    /// The `y` tag: the platform and the publishing project (protocol
    /// `announcement_event.md`).
    const PLATFORM: &str = "mostro";
    const PROJECT: &str = "Mostro v2";

    const USAGE: &str = "usage:\n  \
        announce --template                 print a draft to fill in\n  \
        announce <draft.json> [--out FILE]  validate the draft and emit the unsigned event";

    /// What a human edits: the announcement without the event plumbing.
    /// Every field is checked by the app's parser once it is turned into
    /// tags and content; the few that are not (the expiry being in the
    /// future, the bounds making sense) are checked here.
    #[derive(Debug, Deserialize)]
    #[serde(deny_unknown_fields)]
    pub struct Draft {
        /// The `d` tag: never used before, unless deliberately correcting a
        /// live announcement from the same key.
        pub id: String,
        /// Unix seconds, NIP-40. One of this and `expires_in_days`.
        #[serde(default)]
        pub expiration: Option<u64>,
        /// Days from now; the usual way to say it.
        #[serde(default)]
        pub expires_in_days: Option<u64>,
        #[serde(default)]
        pub min_version: Option<String>,
        /// The version the announcement is *about*, exclusive.
        #[serde(default)]
        pub max_version: Option<String>,
        pub severity: String,
        #[serde(default)]
        pub url: Option<String>,
        /// `locale → { title, body }`, every supported locale and no other.
        pub locales: Map<String, Value>,
    }

    /// The event, unsigned: what `nak event` takes on stdin.
    pub struct Unsigned {
        pub tags: Vec<Tag>,
        pub content: String,
        pub created_at: Timestamp,
    }

    impl Unsigned {
        pub fn to_json(&self) -> Value {
            json!({
                "kind": KIND_ANNOUNCEMENT,
                "created_at": self.created_at.as_secs(),
                "tags": self.tags,
                "content": self.content,
            })
        }
    }

    pub fn run(args: &[String]) -> i32 {
        match args {
            [flag] if flag == "--template" => {
                println!("{}", serde_json::to_string_pretty(&template()).unwrap());
                0
            }
            [path] => emit(path, None),
            [path, flag, out] if flag == "--out" => emit(path, Some(out)),
            _ => {
                eprintln!("{USAGE}");
                2
            }
        }
    }

    fn emit(path: &str, out: Option<&String>) -> i32 {
        let raw = match std::fs::read_to_string(path) {
            Ok(raw) => raw,
            Err(e) => return fail(&format!("cannot read {path}: {e}")),
        };
        let draft: Draft = match serde_json::from_str(&raw) {
            Ok(draft) => draft,
            Err(e) => return fail(&format!("{path} is not a draft: {e}")),
        };
        let now = Timestamp::now();
        let (unsigned, body) = match build(&draft, now) {
            Ok(built) => built,
            Err(problems) => {
                for problem in &problems {
                    eprintln!("✗ {problem}");
                }
                return 1;
            }
        };
        describe(&body, now);
        let event = serde_json::to_string_pretty(&unsigned.to_json()).unwrap();
        match out {
            Some(out) => {
                if let Err(e) = std::fs::write(out, format!("{event}\n")) {
                    return fail(&format!("cannot write {out}: {e}"));
                }
                eprintln!("✓ unsigned event written to {out}");
            }
            None => println!("{event}"),
        }
        0
    }

    fn fail(message: &str) -> i32 {
        eprintln!("✗ {message}");
        1
    }

    /// A draft with every locale to fill in and the usual defaults.
    pub fn template() -> Value {
        let locales: Map<String, Value> = SUPPORTED_LOCALES
            .iter()
            .map(|l| (l.to_string(), json!({ "title": "", "body": "" })))
            .collect();
        json!({
            "id": "2026-10-release-2-2",
            "expires_in_days": 14,
            "min_version": null,
            "max_version": null,
            "severity": "info",
            "url": "https://mostro.network/",
            "locales": locales,
        })
    }

    /// Turn the draft into tags and content, run them through the app's
    /// parser, and refuse what a publisher must not send (§8). Every problem
    /// found is reported, not just the first.
    pub fn build(
        draft: &Draft,
        now: Timestamp,
    ) -> Result<(Unsigned, AnnouncementBody), Vec<String>> {
        let mut problems = Vec::new();
        let expiration = match (draft.expiration, draft.expires_in_days) {
            (Some(at), None) => at,
            (None, Some(days)) => now.as_secs() + days * 24 * 3600,
            (Some(_), Some(_)) => {
                problems.push("give `expiration` or `expires_in_days`, not both".to_string());
                0
            }
            (None, None) => {
                problems.push(
                    "the announcement needs an expiry: `expires_in_days` (or `expiration` in unix seconds)"
                        .to_string(),
                );
                0
            }
        };
        if expiration <= now.as_secs() {
            problems.push("the expiry is in the past: nothing would ever show it".to_string());
        }

        let mut tags = vec![
            Tag::identifier(draft.id.trim()),
            Tag::expiration(Timestamp::from_secs(expiration)),
        ];
        if let Some(min) = &draft.min_version {
            tags.push(Tag::custom("min_version", [min.as_str()]));
        }
        if let Some(max) = &draft.max_version {
            tags.push(Tag::custom("max_version", [max.as_str()]));
        }
        tags.push(Tag::custom("z", ["announcement"]));
        tags.push(Tag::custom("y", [PLATFORM, PROJECT]));

        let mut content = Map::new();
        content.insert("v".into(), json!(1));
        content.insert("severity".into(), json!(draft.severity));
        content.insert("locales".into(), Value::Object(draft.locales.clone()));
        if let Some(url) = &draft.url {
            content.insert("url".into(), json!(url));
        }
        let content = Value::Object(content).to_string();

        let body = match parse_body(&Tags::from_list(tags.clone()), &content) {
            Ok(body) => body,
            Err(e) => {
                problems.push(e.to_string());
                return Err(problems);
            }
        };
        // What the app tolerates and a publisher must not send.
        for leniency in &body.leniencies {
            problems.push(match leniency {
                Leniency::UnknownSeverity(token) => format!(
                    "severity `{token}` is not one of info, warning, critical: the app would show it as a warning"
                ),
                Leniency::UrlDropped(url) => format!(
                    "url `{url}` is not an https link the app accepts: it would be dropped"
                ),
            });
        }
        if let (Some(min), Some(max)) = (&body.min_version, &body.max_version) {
            if max <= min {
                problems.push(format!(
                    "max_version {max} is not above min_version {min}: the bound is exclusive, so this reaches nobody"
                ));
            }
        }
        if body.severity == Severity::Critical {
            eprintln!(
                "! severity is critical: for a security issue the user must act on now, nothing else (§3.4)"
            );
        }
        if !problems.is_empty() {
            return Err(problems);
        }
        Ok((
            Unsigned {
                tags,
                content,
                created_at: now,
            },
            body,
        ))
    }

    /// What is about to be published, for the person holding the key.
    fn describe(body: &AnnouncementBody, now: Timestamp) {
        let stderr = std::io::stderr();
        let mut out = stderr.lock();
        let _ = writeln!(out, "id         {}", body.identifier);
        let _ = writeln!(
            out,
            "severity   {}",
            match body.severity {
                Severity::Info => "info",
                Severity::Warning => "warning",
                Severity::Critical => "critical",
            }
        );
        let hours = body.expiration.as_secs().saturating_sub(now.as_secs()) / 3600;
        let _ = writeln!(
            out,
            "expires    {} (in {} day(s), {} hour(s))",
            body.expiration.as_secs(),
            hours / 24,
            hours % 24
        );
        let bounds = match (&body.min_version, &body.max_version) {
            (None, None) => "every version".to_string(),
            (Some(min), None) => format!(">= {min}"),
            (None, Some(max)) => format!("< {max}"),
            (Some(min), Some(max)) => format!(">= {min} and < {max}"),
        };
        let _ = writeln!(out, "reaches    {bounds}");
        let _ = writeln!(out, "url        {}", body.url.as_deref().unwrap_or("none"));
        for text in &body.texts {
            let _ = writeln!(out, "{:<10} {}", text.locale, text.title);
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        const NOW: u64 = 1_800_000_000;

        fn draft(edit: impl FnOnce(&mut Value)) -> Draft {
            let mut raw = template();
            for locale in SUPPORTED_LOCALES {
                raw["locales"][locale] = json!({
                    "title": format!("Title {locale}"),
                    "body": format!("Body {locale}"),
                });
            }
            edit(&mut raw);
            serde_json::from_value(raw).unwrap()
        }

        fn problems(edit: impl FnOnce(&mut Value)) -> Vec<String> {
            build(&draft(edit), Timestamp::from_secs(NOW))
                .err()
                .unwrap_or_default()
        }

        #[test]
        fn a_filled_template_clears_the_apps_parser_and_carries_z_and_y() {
            // Arrange
            let draft = draft(|_| {});

            // Act
            let (unsigned, body) = build(&draft, Timestamp::from_secs(NOW)).unwrap();

            // Assert: the emitted event is what the app reads.
            let event = unsigned.to_json();
            assert_eq!(event["kind"], json!(KIND_ANNOUNCEMENT));
            assert_eq!(event["created_at"], json!(NOW));
            let tags: Vec<Vec<String>> = serde_json::from_value(event["tags"].clone()).unwrap();
            assert!(tags.contains(&vec!["z".to_string(), "announcement".to_string()]));
            assert!(tags.contains(&vec![
                "y".to_string(),
                PLATFORM.to_string(),
                PROJECT.to_string()
            ]));
            assert!(parse_body(&Tags::from_list(unsigned.tags.clone()), &unsigned.content).is_ok());
            assert_eq!(body.expiration.as_secs(), NOW + 14 * 24 * 3600);
            assert_eq!(body.texts.len(), SUPPORTED_LOCALES.len());
        }

        #[test]
        fn a_missing_locale_is_named() {
            let problems = problems(|raw| {
                raw["locales"].as_object_mut().unwrap().remove("nl");
            });

            assert_eq!(problems.len(), 1);
            assert!(
                problems[0].contains("locale `nl` is missing"),
                "{problems:?}"
            );
        }

        #[test]
        fn what_the_app_tolerates_the_tool_refuses() {
            // An unknown severity shows as a warning in the app; a non-https
            // url loses only its button. The publisher gets neither.
            let problems = problems(|raw| {
                raw["severity"] = json!("emergency");
                raw["url"] = json!("http://mostro.network/");
            });

            assert_eq!(problems.len(), 2, "{problems:?}");
            assert!(problems[0].contains("severity `emergency`"));
            assert!(problems[1].contains("url `http://mostro.network/`"));
        }

        #[test]
        fn an_expiry_in_the_past_is_refused() {
            let problems = problems(|raw| {
                raw.as_object_mut().unwrap().remove("expires_in_days");
                raw["expiration"] = json!(NOW - 1);
            });

            assert!(
                problems.iter().any(|p| p.contains("in the past")),
                "{problems:?}"
            );
        }

        #[test]
        fn both_expiry_forms_at_once_are_refused() {
            let problems = problems(|raw| raw["expiration"] = json!(NOW + 60));

            assert!(
                problems.iter().any(|p| p.contains("not both")),
                "{problems:?}"
            );
        }

        #[test]
        fn an_empty_version_range_is_refused() {
            let problems = problems(|raw| {
                raw["min_version"] = json!("2.2");
                raw["max_version"] = json!("2.2");
            });

            assert!(
                problems.iter().any(|p| p.contains("reaches nobody")),
                "{problems:?}"
            );
        }

        #[test]
        fn a_bound_with_build_metadata_is_refused_by_the_parser() {
            let problems = problems(|raw| raw["max_version"] = json!("2.2.0+7"));

            assert!(
                problems.iter().any(|p| p.contains("build metadata")),
                "{problems:?}"
            );
        }

        #[test]
        fn the_template_names_every_locale() {
            let raw = template();
            let locales = raw["locales"].as_object().unwrap();

            assert_eq!(locales.len(), SUPPORTED_LOCALES.len());
            for locale in SUPPORTED_LOCALES {
                assert!(locales.contains_key(locale));
            }
        }

        #[test]
        fn an_unknown_draft_field_is_refused() {
            let mut raw = template();
            raw["colour"] = json!("red");

            assert!(serde_json::from_value::<Draft>(raw).is_err());
        }
    }
}
