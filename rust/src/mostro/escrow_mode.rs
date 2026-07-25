//! Which settlement backend the active Mostro node runs — Lightning or Cashu.
//!
//! Phase C1 of `docs/cashu/README.md`. This is the gate every later Cashu phase
//! hangs off: nothing Cashu-shaped may run, and no Cashu UI may appear, unless
//! the active node has been *positively identified* as running Cashu escrow.
//!
//! Same shape as [`crate::mostro::pow`] — a process-global refreshed from the
//! daemon's Kind 38385 info event whenever the relay pool comes online or the
//! active node changes. Unlike PoW this one is tri-state, mirroring
//! `BondPolicy` on the Dart side (`lib/features/about/models/mostro_instance.dart`):
//! an old daemon that predates the tags is [`EscrowMode::Unknown`], which is
//! **not** the same as knowing it speaks Lightning.
//!
//! Fail-safe by construction: [`is_cashu_mode`] is the only way to ask whether
//! Cashu paths may run, and it answers `false` for `Unknown`, for `Lightning`,
//! and for a node that claims Cashu without publishing a usable mint. A node
//! that never answers therefore behaves exactly like today's Lightning-only
//! client.

use std::sync::{OnceLock, RwLock};
use tokio::sync::broadcast;

/// Settlement backend advertised by the active Mostro node.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum EscrowMode {
    /// Info event not fetched yet, unreachable, or a daemon old enough that it
    /// publishes no `escrow_mode` tag. Treated as Lightning everywhere.
    #[default]
    Unknown,
    /// Tag absent or explicitly `"lightning"`.
    Lightning,
    /// Tag `escrow_mode` == `"cashu"`.
    Cashu,
}

impl EscrowMode {
    /// What the node said, nothing more. `Unknown` answers `false`, so the
    /// Cashu paths stay closed unless the node positively said otherwise.
    ///
    /// This is the *mode* question, for the About screen — a node can say
    /// Cashu and still be unusable. To decide whether a Cashu path may run,
    /// ask [`is_cashu_mode`], which also requires a usable mint.
    pub fn is_cashu(self) -> bool {
        matches!(self, EscrowMode::Cashu)
    }

    /// Parse an `escrow_mode` tag value. Anything unrecognised is Lightning:
    /// a daemon advertising a backend we do not implement is one we cannot
    /// trade Cashu with either, and Lightning is the safe reading.
    pub fn from_tag_value(value: &str) -> Self {
        match value.trim().to_ascii_lowercase().as_str() {
            "cashu" => EscrowMode::Cashu,
            _ => EscrowMode::Lightning,
        }
    }

    /// Stable marker for the Dart layer. Rust never returns prose — Dart maps
    /// these to localized strings (repo translation rule).
    pub fn as_marker(self) -> &'static str {
        match self {
            EscrowMode::Unknown => "unknown",
            EscrowMode::Lightning => "lightning",
            EscrowMode::Cashu => "cashu",
        }
    }
}

/// The Cashu parameters a node publishes alongside `escrow_mode`.
///
/// Every field is optional because each tag is independently absent on an old
/// daemon. A `Cashu` mode with no `mint_url` is a misconfigured node, and
/// callers must treat it as unusable rather than guessing a mint — hence
/// [`CashuNodeConfig::is_usable`].
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CashuNodeConfig {
    /// Mint the node pins for every escrow. There is no per-order negotiation.
    pub mint_url: Option<String>,
    /// NUT-11 locktime the seller must set, in days (daemon default 15).
    pub escrow_locktime_days: Option<u32>,
    /// How close to expiry the daemon stops accepting `fiat-sent`, in days.
    pub settlement_margin_days: Option<u32>,
}

impl CashuNodeConfig {
    /// A Cashu node we can actually trade against needs, at minimum, a mint.
    pub fn is_usable(&self) -> bool {
        self.mint_url.as_deref().is_some_and(|u| !u.trim().is_empty())
    }
}

/// What the client resolved for the active node, override included.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ResolvedEscrowMode {
    pub mode: EscrowMode,
    pub config: CashuNodeConfig,
    /// True when the mode came from the developer override rather than the
    /// node's own tags. Surfaced in the UI so a tester is never fooled into
    /// thinking a Lightning node advertised Cashu.
    pub is_overridden: bool,
}

impl ResolvedEscrowMode {
    /// May a Cashu path run against *this* resolution?
    ///
    /// The gate, expressed against a value the caller already holds — so a
    /// snapshot that reports `mode` and this flag together cannot have read
    /// them from two different states. [`is_cashu_mode`] is this applied to the
    /// current globals.
    pub fn is_cashu_usable(&self) -> bool {
        self.mode.is_cashu() && self.config.is_usable()
    }
}

/// Developer override, for testing against a daemon branch that implements
/// Cashu but does not publish the info tags yet (§4.3).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum EscrowModeOverride {
    /// Trust the node's tags.
    #[default]
    Auto,
    /// Pretend the node advertised Cashu.
    ForceCashu,
}

impl EscrowModeOverride {
    /// Parse the persisted settings value. Unrecognised → `Auto`, so a
    /// corrupted setting can never silently enable Cashu.
    pub fn from_stored(value: &str) -> Self {
        match value.trim().to_ascii_lowercase().as_str() {
            "force_cashu" => EscrowModeOverride::ForceCashu,
            _ => EscrowModeOverride::Auto,
        }
    }

    pub fn as_stored(self) -> &'static str {
        match self {
            EscrowModeOverride::Auto => "auto",
            EscrowModeOverride::ForceCashu => "force_cashu",
        }
    }
}

/// Everything the resolver needs, so resolution itself stays a pure function
/// and can be tested without touching globals or the network.
#[derive(Debug, Clone, Default)]
pub struct EscrowModeInputs {
    /// What the node's 38385 tags said.
    pub from_tags: EscrowMode,
    /// Cashu parameters from the same tags.
    pub tag_config: CashuNodeConfig,
    /// Developer override.
    pub override_mode: EscrowModeOverride,
    /// Mint URL override, used when the node publishes none.
    pub mint_url_override: Option<String>,
}

/// Resolution order from §4.3: `override > 38385 tag > Lightning`.
///
/// The mint URL resolves independently and with the same precedence, because
/// the two overrides serve different gaps: forcing the mode is for a daemon
/// that speaks Cashu without advertising it, while overriding the mint is for
/// pointing a tester at a local nutshell instead of the node's mint.
pub fn resolve(inputs: &EscrowModeInputs) -> ResolvedEscrowMode {
    let forcing = matches!(inputs.override_mode, EscrowModeOverride::ForceCashu);
    let mode = if forcing {
        EscrowMode::Cashu
    } else {
        inputs.from_tags
    };

    // `is_overridden` exists to warn a tester that the mode is not the node's
    // own. Forcing Cashu on a node that already advertises Cashu changes
    // nothing, so flagging it would cry wolf on the one configuration where the
    // override is irrelevant.
    let overridden = forcing && inputs.from_tags != EscrowMode::Cashu;

    let mut config = inputs.tag_config.clone();
    if let Some(url) = inputs
        .mint_url_override
        .as_deref()
        .map(str::trim)
        .filter(|u| !u.is_empty())
    {
        config.mint_url = Some(url.to_string());
    }

    ResolvedEscrowMode {
        mode,
        config,
        is_overridden: overridden,
    }
}

/// Read the `escrow_mode` / `cashu_*` tags out of a Kind 38385 event.
///
/// Tags are `["name", "value"]` pairs; anything malformed is skipped with a
/// warning rather than failing the whole fetch, matching how `fetch_and_set_pow`
/// already treats a bad `pow` value. A node is only reported as Cashu when it
/// says so explicitly.
pub fn parse_tags(tags: &[Vec<String>]) -> (EscrowMode, CashuNodeConfig) {
    let value_of = |name: &str| -> Option<&str> {
        tags.iter()
            .find(|t| t.first().map(String::as_str) == Some(name))
            .and_then(|t| t.get(1))
            .map(String::as_str)
    };

    let mode = match value_of("escrow_mode") {
        Some(v) => EscrowMode::from_tag_value(v),
        // No tag at all: an old daemon. Unknown, not Lightning — the
        // distinction is what lets the UI say "not advertised" honestly.
        None => EscrowMode::Unknown,
    };

    let days = |name: &str| -> Option<u32> {
        let raw = value_of(name)?;
        match raw.trim().parse::<u32>() {
            Ok(d) => Some(d),
            Err(_) => {
                log::warn!("[escrow-mode] malformed {name} tag value: {raw:?} — ignoring");
                None
            }
        }
    };

    let config = CashuNodeConfig {
        mint_url: value_of("cashu_mint_url")
            .map(str::trim)
            .filter(|u| !u.is_empty())
            .map(str::to_string),
        escrow_locktime_days: days("cashu_escrow_locktime_days"),
        settlement_margin_days: days("cashu_settlement_margin_days"),
    };

    (mode, config)
}

/// The two developer overrides, as persisted and as applied.
///
/// Kept together because they are read together on every resolution and are
/// written by the same dev-only settings surface.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct EscrowOverrides {
    pub mode: EscrowModeOverride,
    /// Mint URL to use instead of the node's. `None` (or blank) leaves the
    /// node's own value in place — see [`resolve`].
    pub mint_url: Option<String>,
}

// ── Process-global state ────────────────────────────────────────────────────

/// What the active node's 38385 tags said, or `None` before the first
/// successful fetch. Node-scoped: cleared on every node switch.
static TAGS: RwLock<Option<(EscrowMode, CashuNodeConfig)>> = RwLock::new(None);

/// The developer overrides. **Not** node-scoped: forcing Cashu is a statement
/// about this build, not about a particular node, so it survives a node switch
/// exactly as the user left it. The surface that writes it is `kDebugMode`-only.
static OVERRIDES: RwLock<EscrowOverrides> = RwLock::new(EscrowOverrides {
    mode: EscrowModeOverride::Auto,
    mint_url: None,
});

/// Broadcast that *something* changed, so the UI re-reads without polling.
///
/// The event carries no payload on purpose. Subscribers rebuild the snapshot
/// from the globals anyway — that is what keeps a snapshot's mode and override
/// fields from ever disagreeing — so sending the resolution too would just
/// resolve it twice per change.
///
/// Every mutator below emits on it, and only when it actually changed
/// something; nothing else may write the globals.
static CHANGES: OnceLock<broadcast::Sender<()>> = OnceLock::new();

fn changes() -> &'static broadcast::Sender<()> {
    CHANGES.get_or_init(|| broadcast::channel(32).0)
}

/// Subscribe to escrow-mode changes.
pub fn subscribe() -> broadcast::Receiver<()> {
    changes().subscribe()
}

/// Wake subscribers. A send error means "no listeners", which is the normal
/// state before the UI attaches.
fn notify() {
    let _ = changes().send(());
}

/// Record what the active node advertised.
///
/// A poisoned lock is recovered from rather than propagated: this is a cache of
/// what the node said, and refusing to update it would leave the app pinned to
/// a stale node's mode after any unrelated panic.
pub fn set_from_tags(mode: EscrowMode, config: CashuNodeConfig) {
    let mint_url = config.mint_url.clone();
    let changed = {
        let mut guard = TAGS.write().unwrap_or_else(|e| e.into_inner());
        let next = Some((mode, config));
        let changed = *guard != next;
        *guard = next;
        changed
    };
    // A re-fetch that confirms what we already knew is the common case on a
    // reconnect: it wakes nobody, and it does not deserve a log line either.
    if changed {
        log::info!(
            "[escrow-mode] active node advertises {} (mint={mint_url:?})",
            mode.as_marker(),
        );
        notify();
    }
}

/// Current resolution, or the `Unknown` default before the first fetch.
///
/// Resolution happens on read rather than on write, so flipping an override
/// takes effect immediately instead of waiting for the next relay fetch — and
/// there is no second copy of the answer that could go stale.
pub fn get_resolved() -> ResolvedEscrowMode {
    let (from_tags, tag_config) = TAGS
        .read()
        .unwrap_or_else(|e| e.into_inner())
        .clone()
        .unwrap_or_default();
    let overrides = get_overrides();

    resolve(&EscrowModeInputs {
        from_tags,
        tag_config,
        override_mode: overrides.mode,
        mint_url_override: overrides.mint_url,
    })
}

/// The developer overrides currently in force.
pub fn get_overrides() -> EscrowOverrides {
    OVERRIDES.read().unwrap_or_else(|e| e.into_inner()).clone()
}

/// Replace the developer overrides wholesale. Persistence is the caller's job
/// (`crate::api::escrow`); this is the in-memory half.
///
/// Prefer [`update_overrides`] when changing one field: this one overwrites
/// both, so a caller that read-modify-writes races with any concurrent change
/// to the other field.
pub fn set_overrides(overrides: EscrowOverrides) {
    update_overrides(|current| *current = overrides);
}

/// Mutate the overrides under a single write lock.
///
/// The lock spans the read *and* the write, which is the point: the two
/// overrides are set from the same surface, and a read-modify-write of one
/// field would otherwise interleave with the other and silently discard it.
pub fn update_overrides(f: impl FnOnce(&mut EscrowOverrides)) {
    let changed = {
        let mut guard = OVERRIDES.write().unwrap_or_else(|e| e.into_inner());
        let before = guard.clone();
        f(&mut guard);
        if *guard != before {
            log::info!(
                "[escrow-mode] override set to {} (mint override={:?})",
                guard.mode.as_stored(),
                guard.mint_url,
            );
            true
        } else {
            false
        }
    };
    if changed {
        notify();
    }
}

/// Serializes tests that write the globals above, **across modules**.
///
/// `api::escrow` and `api::cashu` both drive this state; two private mutexes
/// would let one module's "force Cashu" leak into the other's "this is a
/// Lightning node" assertion, which fails only under parallel execution and
/// looks like flakiness. One global, one lock.
#[cfg(test)]
pub fn test_lock() -> std::sync::MutexGuard<'static, ()> {
    static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
    let guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    clear();
    set_overrides(EscrowOverrides::default());
    guard
}

/// Forget what the node advertised. Called when the active node changes, so a
/// stale Cashu resolution can never leak onto a different node between the
/// switch and the next successful fetch. The overrides are deliberately left
/// alone — see [`OVERRIDES`].
pub fn clear() {
    let changed = {
        let mut guard = TAGS.write().unwrap_or_else(|e| e.into_inner());
        let changed = guard.is_some();
        *guard = None;
        changed
    };
    // Clearing an already-clear cache is a no-op, and a node whose capability
    // fetch keeps failing would otherwise emit on every retry.
    if changed {
        notify();
    }
}

/// The one question the rest of the app asks: may a Cashu path run against the
/// active node?
///
/// Deliberately stricter than [`EscrowMode::is_cashu`]. A node that advertises
/// `escrow_mode=cashu` but publishes no mint URL is misconfigured, and there is
/// nothing to connect to — enabling Cashu routing or UI for it would only fail
/// later and further from the cause. The gate therefore also requires
/// [`CashuNodeConfig::is_usable`], and the mint override (§4.3) is what makes a
/// forced Cashu mode usable against a daemon that publishes no mint of its own.
///
/// The About screen must *not* use this: it reads [`get_resolved`], so it can
/// say "cashu, but no mint advertised" instead of silently reading Lightning.
pub fn is_cashu_mode() -> bool {
    get_resolved().is_cashu_usable()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tag(name: &str, value: &str) -> Vec<String> {
        vec![name.to_string(), value.to_string()]
    }

    /// Tests that touch the globals run in the same process and would otherwise
    /// race each other. A poisoned lock is recovered from so one failing test
    /// does not cascade into the others.
    static GLOBAL: std::sync::Mutex<()> = std::sync::Mutex::new(());

    /// Take the globals and reset them, so each test starts from the state a
    /// freshly-launched app has: nothing fetched, no override.
    fn own_the_global() -> std::sync::MutexGuard<'static, ()> {
        let guard = GLOBAL.lock().unwrap_or_else(|e| e.into_inner());
        clear();
        set_overrides(EscrowOverrides::default());
        guard
    }

    #[test]
    fn a_daemon_without_the_tag_is_unknown_not_lightning() {
        // Arrange — today's daemons: pow and bond tags, nothing about escrow.
        let tags = vec![tag("pow", "8"), tag("bond", "enabled")];

        // Act
        let (mode, config) = parse_tags(&tags);

        // Assert — Unknown is what lets the About screen say "not advertised"
        // instead of claiming the node confirmed Lightning.
        assert_eq!(mode, EscrowMode::Unknown);
        assert!(!mode.is_cashu());
        assert_eq!(config, CashuNodeConfig::default());
    }

    #[test]
    fn unknown_and_lightning_both_keep_cashu_closed() {
        // Assert — the fail-safe the whole feature rests on.
        assert!(!EscrowMode::Unknown.is_cashu());
        assert!(!EscrowMode::Lightning.is_cashu());
        assert!(EscrowMode::Cashu.is_cashu());
    }

    #[test]
    fn a_cashu_node_is_parsed_with_its_parameters() {
        // Arrange
        let tags = vec![
            tag("escrow_mode", "cashu"),
            tag("cashu_mint_url", "https://mint.example.com"),
            tag("cashu_escrow_locktime_days", "15"),
            tag("cashu_settlement_margin_days", "3"),
        ];

        // Act
        let (mode, config) = parse_tags(&tags);

        // Assert
        assert_eq!(mode, EscrowMode::Cashu);
        assert_eq!(config.mint_url.as_deref(), Some("https://mint.example.com"));
        assert_eq!(config.escrow_locktime_days, Some(15));
        assert_eq!(config.settlement_margin_days, Some(3));
        assert!(config.is_usable());
    }

    #[test]
    fn an_explicit_lightning_tag_is_lightning() {
        // Arrange / Act
        let (mode, _) = parse_tags(&[tag("escrow_mode", "lightning")]);

        // Assert
        assert_eq!(mode, EscrowMode::Lightning);
    }

    #[test]
    fn an_unrecognised_backend_reads_as_lightning() {
        // Arrange — a future backend this client does not implement.
        let (mode, _) = parse_tags(&[tag("escrow_mode", "fedimint")]);

        // Assert — we cannot trade Cashu with it, so the safe reading is the
        // one that leaves every Cashu path shut.
        assert_eq!(mode, EscrowMode::Lightning);
        assert!(!mode.is_cashu());
    }

    #[test]
    fn tag_values_are_matched_case_insensitively_and_trimmed() {
        // Arrange / Act
        let (mode, _) = parse_tags(&[tag("escrow_mode", "  Cashu ")]);

        // Assert
        assert_eq!(mode, EscrowMode::Cashu);
    }

    #[test]
    fn malformed_day_counts_are_dropped_not_fatal() {
        // Arrange — a garbage locktime must not cost us the mint URL.
        let tags = vec![
            tag("escrow_mode", "cashu"),
            tag("cashu_mint_url", "https://mint.example.com"),
            tag("cashu_escrow_locktime_days", "fifteen"),
        ];

        // Act
        let (mode, config) = parse_tags(&tags);

        // Assert
        assert_eq!(mode, EscrowMode::Cashu);
        assert_eq!(config.escrow_locktime_days, None);
        assert_eq!(config.mint_url.as_deref(), Some("https://mint.example.com"));
    }

    #[test]
    fn an_empty_mint_url_is_not_a_mint_url() {
        // Arrange — a node that publishes the tag but leaves it blank.
        let tags = vec![tag("escrow_mode", "cashu"), tag("cashu_mint_url", "   ")];

        // Act
        let (_, config) = parse_tags(&tags);

        // Assert — is_usable() is what stops us from trying to reach "".
        assert_eq!(config.mint_url, None);
        assert!(!config.is_usable());
    }

    #[test]
    fn resolution_prefers_the_override_over_the_tags() {
        // Arrange — a Lightning node plus a tester forcing Cashu (§4.3).
        let inputs = EscrowModeInputs {
            from_tags: EscrowMode::Lightning,
            override_mode: EscrowModeOverride::ForceCashu,
            mint_url_override: Some("http://localhost:3338".to_string()),
            ..Default::default()
        };

        // Act
        let resolved = resolve(&inputs);

        // Assert
        assert_eq!(resolved.mode, EscrowMode::Cashu);
        assert!(resolved.is_overridden);
        assert_eq!(
            resolved.config.mint_url.as_deref(),
            Some("http://localhost:3338")
        );
    }

    #[test]
    fn without_an_override_the_tags_decide_and_nothing_is_flagged() {
        // Arrange
        let inputs = EscrowModeInputs {
            from_tags: EscrowMode::Cashu,
            tag_config: CashuNodeConfig {
                mint_url: Some("https://mint.example.com".to_string()),
                escrow_locktime_days: Some(15),
                settlement_margin_days: Some(3),
            },
            ..Default::default()
        };

        // Act
        let resolved = resolve(&inputs);

        // Assert — is_overridden drives the "this is forced" UI hint.
        assert_eq!(resolved.mode, EscrowMode::Cashu);
        assert!(!resolved.is_overridden);
        assert_eq!(
            resolved.config.mint_url.as_deref(),
            Some("https://mint.example.com")
        );
    }

    #[test]
    fn the_mint_override_wins_even_when_the_node_published_one() {
        // Arrange — pointing a tester at a local nutshell.
        let inputs = EscrowModeInputs {
            from_tags: EscrowMode::Cashu,
            tag_config: CashuNodeConfig {
                mint_url: Some("https://mint.example.com".to_string()),
                ..Default::default()
            },
            mint_url_override: Some("http://localhost:3338".to_string()),
            ..Default::default()
        };

        // Act
        let resolved = resolve(&inputs);

        // Assert
        assert_eq!(
            resolved.config.mint_url.as_deref(),
            Some("http://localhost:3338")
        );
    }

    #[test]
    fn a_blank_mint_override_is_ignored_rather_than_erasing_the_node_value() {
        // Arrange — an override field the user cleared.
        let inputs = EscrowModeInputs {
            from_tags: EscrowMode::Cashu,
            tag_config: CashuNodeConfig {
                mint_url: Some("https://mint.example.com".to_string()),
                ..Default::default()
            },
            mint_url_override: Some("   ".to_string()),
            ..Default::default()
        };

        // Act
        let resolved = resolve(&inputs);

        // Assert
        assert_eq!(
            resolved.config.mint_url.as_deref(),
            Some("https://mint.example.com")
        );
    }

    #[test]
    fn an_unrecognised_stored_override_falls_back_to_auto() {
        // Assert — a corrupted setting must never switch Cashu on.
        assert_eq!(
            EscrowModeOverride::from_stored("auto"),
            EscrowModeOverride::Auto
        );
        assert_eq!(EscrowModeOverride::from_stored(""), EscrowModeOverride::Auto);
        assert_eq!(
            EscrowModeOverride::from_stored("garbage"),
            EscrowModeOverride::Auto
        );
        assert_eq!(
            EscrowModeOverride::from_stored("force_cashu"),
            EscrowModeOverride::ForceCashu
        );
        // Round-trips through persistence.
        assert_eq!(
            EscrowModeOverride::from_stored(EscrowModeOverride::ForceCashu.as_stored()),
            EscrowModeOverride::ForceCashu
        );
    }

    fn cashu_tags() -> (EscrowMode, CashuNodeConfig) {
        parse_tags(&[
            tag("escrow_mode", "cashu"),
            tag("cashu_mint_url", "https://mint.example.com"),
        ])
    }

    #[test]
    fn the_global_defaults_to_unknown_and_clears_on_node_switch() {
        // Arrange — this test owns the global; keep it self-contained.
        let _guard = own_the_global();
        assert_eq!(get_resolved().mode, EscrowMode::Unknown);
        assert!(!is_cashu_mode());

        // Act — a Cashu node is detected, then the user switches nodes.
        let (mode, config) = cashu_tags();
        set_from_tags(mode, config);
        assert!(is_cashu_mode());
        clear();

        // Assert — a stale Cashu resolution must not leak onto the new node.
        assert_eq!(get_resolved().mode, EscrowMode::Unknown);
        assert!(!is_cashu_mode());
    }

    #[test]
    fn a_cashu_node_without_a_usable_mint_keeps_the_gate_shut() {
        // Arrange — a node that says cashu but published no mint URL.
        let _guard = own_the_global();
        let (mode, config) = parse_tags(&[tag("escrow_mode", "cashu"), tag("cashu_mint_url", "  ")]);
        set_from_tags(mode, config);

        // Assert — the mode is reported honestly for the About screen, but
        // there is no mint to connect to, so no Cashu path may run.
        assert_eq!(get_resolved().mode, EscrowMode::Cashu);
        assert!(!get_resolved().config.is_usable());
        assert!(!is_cashu_mode());

        // Act — the tester points it at a local mint (§4.3).
        set_overrides(EscrowOverrides {
            mint_url: Some("http://localhost:3338".to_string()),
            ..Default::default()
        });

        // Assert — now there is something to connect to.
        assert!(is_cashu_mode());
    }

    #[test]
    fn flipping_the_override_re_resolves_without_another_fetch() {
        // Arrange — a plain Lightning node, already fetched.
        let _guard = own_the_global();
        set_from_tags(EscrowMode::Lightning, CashuNodeConfig::default());
        assert!(!is_cashu_mode());

        // Act — the developer forces Cashu at a local mint. No fetch happens.
        set_overrides(EscrowOverrides {
            mode: EscrowModeOverride::ForceCashu,
            mint_url: Some("http://localhost:3338".to_string()),
        });

        // Assert — resolution is computed on read, so the change is immediate.
        let resolved = get_resolved();
        assert_eq!(resolved.mode, EscrowMode::Cashu);
        assert!(resolved.is_overridden);
        assert!(is_cashu_mode());

        // Act — and turning it off restores what the node actually said.
        set_overrides(EscrowOverrides::default());

        // Assert
        assert_eq!(get_resolved().mode, EscrowMode::Lightning);
        assert!(!is_cashu_mode());
    }

    #[test]
    fn a_node_switch_clears_the_tags_but_keeps_the_override() {
        // Arrange — override on, against some node.
        let _guard = own_the_global();
        let (mode, config) = cashu_tags();
        set_from_tags(mode, config);
        set_overrides(EscrowOverrides {
            mode: EscrowModeOverride::ForceCashu,
            mint_url: Some("http://localhost:3338".to_string()),
        });

        // Act — the user switches nodes.
        clear();

        // Assert — the override is a statement about this build, not about the
        // node, so it survives; the node's own tags do not.
        assert_eq!(
            get_overrides().mode,
            EscrowModeOverride::ForceCashu,
            "the override must not be reset by a node switch"
        );
        assert_eq!(get_resolved().mode, EscrowMode::Cashu);
        assert!(get_resolved().is_overridden);
    }

    #[tokio::test]
    async fn every_mutator_notifies_subscribers() {
        // Arrange — a Lightning node, so each step below is a real change.
        let _guard = own_the_global();
        set_from_tags(EscrowMode::Lightning, CashuNodeConfig::default());
        let mut rx = subscribe();

        // Act / Assert — tags in. The event is a bare wake-up; the state is
        // read from the globals, which is what subscribers do.
        let (mode, config) = cashu_tags();
        set_from_tags(mode, config);
        rx.recv().await.unwrap();
        assert_eq!(get_resolved().mode, EscrowMode::Cashu);

        // Act / Assert — override changed.
        set_overrides(EscrowOverrides {
            mode: EscrowModeOverride::ForceCashu,
            mint_url: Some("http://localhost:3338".to_string()),
        });
        rx.recv().await.unwrap();
        assert_eq!(
            get_resolved().config.mint_url.as_deref(),
            Some("http://localhost:3338")
        );

        // Act / Assert — node switch. The override still forces Cashu, but the
        // tags changed, so subscribers must be woken.
        clear();
        rx.recv().await.unwrap();
        assert!(get_resolved().is_overridden);
    }

    #[tokio::test]
    async fn a_change_that_changes_nothing_does_not_wake_subscribers() {
        // Arrange — a node that has already been fetched.
        let _guard = own_the_global();
        let (mode, config) = cashu_tags();
        set_from_tags(mode, config.clone());
        let mut rx = subscribe();

        // Act — a reconnect re-fetches the same event, and a settings screen
        // re-writes the override it already had. Neither changed anything.
        set_from_tags(mode, config);
        set_overrides(EscrowOverrides::default());
        clear();
        clear();

        // Assert — exactly one wake-up, from the `clear()` that emptied the
        // cache. On a flaky relay the alternative is a stream of identical
        // events that every listener has to re-render.
        rx.recv().await.unwrap();
        assert!(
            rx.try_recv().is_err(),
            "only a real change may wake subscribers"
        );
    }

    #[test]
    fn forcing_cashu_on_a_cashu_node_is_not_flagged_as_an_override() {
        // Arrange — the node genuinely advertises Cashu and the developer has
        // the override on anyway.
        let inputs = EscrowModeInputs {
            from_tags: EscrowMode::Cashu,
            tag_config: CashuNodeConfig {
                mint_url: Some("https://mint.example.com".to_string()),
                ..Default::default()
            },
            override_mode: EscrowModeOverride::ForceCashu,
            ..Default::default()
        };

        // Act
        let resolved = resolve(&inputs);

        // Assert — the flag warns "this is not what the node said". Here it is
        // exactly what the node said, so raising it would cry wolf on the one
        // configuration where the override changes nothing.
        assert_eq!(resolved.mode, EscrowMode::Cashu);
        assert!(!resolved.is_overridden);
    }
}
