//! Cashu wallet surface for the UI — phase C2 of `docs/cashu/README.md`.
//!
//! Holds the single process-wide wallet and broadcasts changes so the UI never
//! polls.
//!
//! **The wallet is always available** (docs/cashu/README.md §1.2): it runs on
//! every node, Lightning ones included, and its mint is the user's — persisted
//! as a device preference, never changed by a node switch. A Cashu node that
//! pins one mint only offers that mint as the default.
//!
//! **The escrow is not.** [`cashu_escrow_quote`] and [`lock_escrow`] decide how
//! a trade settles, which is the node's call: they return `CashuNotEnabled`
//! unless [`crate::mostro::escrow_mode::is_cashu_mode`] is true, and lock only
//! from a wallet bound to the node's mint.
//!
//! Errors are stable markers (`CashuNoMint`, `CashuNotConnected`,
//! `CashuMintUnreachable`, …); Dart maps them to localized strings.

use anyhow::{bail, Result};
use std::sync::{Arc, OnceLock};
use tokio::sync::broadcast::error::RecvError;
use tokio::sync::{broadcast, RwLock};

use crate::api::types::CashuWalletStatus;
use crate::cashu::CashuWallet;
use crate::db::{settings_keys, Storage};
use crate::mostro::escrow_mode;

// ── Global wallet ─────────────────────────────────────────────────────────────

/// The wallet is held behind an `Arc` so callers can take a handle and drop the
/// lock before talking to the mint. Holding the read guard across a round trip
/// would park a waiting `cashu_disconnect` in tokio's write-preferring queue,
/// and every `cashu_status` behind it — a frozen screen for as long as the mint
/// takes to answer.
fn wallet_lock() -> &'static RwLock<Option<BoundWallet>> {
    static WALLET: OnceLock<RwLock<Option<BoundWallet>>> = OnceLock::new();
    WALLET.get_or_init(|| RwLock::new(None))
}

/// The bound wallet, with the identity whose seed it was built from.
#[derive(Clone)]
struct BoundWallet {
    wallet: Arc<CashuWallet>,
    identity: String,
}

/// The public key of the identity loaded now, or `None` before one is.
async fn current_identity() -> Option<String> {
    crate::api::identity::get_identity()
        .await
        .ok()
        .flatten()
        .map(|identity| identity.public_key)
}

/// May a wallet built for `bound_to` serve the identity loaded now?
///
/// Only that same identity. The wallet derives its ecash from one identity's
/// seed, and it outlives node switches on purpose; after an identity is
/// deleted, created or imported, the previous one's wallet must not serve the
/// next user.
fn serves(bound_to: &str, current: Option<&str>) -> bool {
    current == Some(bound_to)
}

/// The bound wallet, if it was built for the identity loaded now.
async fn live_wallet() -> Option<Arc<CashuWallet>> {
    let bound = wallet_lock().read().await.clone()?;
    serves(&bound.identity, current_identity().await.as_deref()).then_some(bound.wallet)
}

/// Build a wallet at `target` for the identity loaded now, without installing
/// it. The caller holds [`lifecycle_lock`].
async fn open_wallet(target: &str) -> Result<BoundWallet> {
    let identity = current_identity()
        .await
        .ok_or_else(|| anyhow::anyhow!("NoIdentity"))?;
    let seed = crate::api::identity::current_bip39_seed().await?;
    // The seed must be this identity's: one swapped in between would build a
    // wallet labelled with the wrong owner.
    if current_identity().await.as_deref() != Some(identity.as_str()) {
        bail!("NoIdentity");
    }
    let db_path = proof_store_path(&identity)?;
    // Finishes a move the identity load could not, for its recorded owner only.
    #[cfg(not(target_arch = "wasm32"))]
    settle_legacy_store(&identity, false).await?;
    let wallet = CashuWallet::connect(target, seed, &db_path).await?;
    Ok(BoundWallet {
        wallet: Arc::new(wallet),
        identity,
    })
}

async fn install(bound: BoundWallet) {
    *wallet_lock().write().await = Some(bound);
}

fn changes() -> &'static broadcast::Sender<CashuWalletStatus> {
    static CHANGES: OnceLock<broadcast::Sender<CashuWalletStatus>> = OnceLock::new();
    CHANGES.get_or_init(|| broadcast::channel(32).0)
}

/// Where `identity`'s proof store lives: a sibling of the app database, never
/// inside it, and one file per identity.
///
/// `cdk` owns that file's schema and migrations; mixing it into the app's would
/// put two migration systems on one file. And it keys proofs by mint, not by
/// seed: a store shared between identities would hand one user's bearer proofs
/// to the next one at the same mint. Deleting an identity keeps its file, so
/// importing its words again brings the balance back.
fn proof_store_path(identity: &str) -> Result<String> {
    sibling_store_path(
        crate::db::app_db::app_db_path(),
        &identity_store_name(identity),
    )
}

/// The store every identity shared before stores were per identity.
#[cfg(not(target_arch = "wasm32"))]
const LEGACY_STORE_NAME: &str = "cashu.sqlite";

fn identity_store_name(identity: &str) -> String {
    format!("cashu-{identity}.sqlite")
}

/// Settle an older install's shared proof store on the identity `identity`
/// was loaded as, at an identity load (`may_record`) or a wallet open.
///
/// Called on every identity load (`api::identity`); never fails the load —
/// a store that cannot move yet is logged and retried at the next one.
#[cfg(not(target_arch = "wasm32"))]
pub(crate) async fn claim_legacy_store(identity: &str) {
    if let Err(e) = settle_legacy_store(identity, true).await {
        log::error!("[cashu] the shared proof store could not move yet: {e}");
    }
}

#[cfg(target_arch = "wasm32")]
pub(crate) async fn claim_legacy_store(_identity: &str) {}

/// Whose an older install's shared store is, and whether `identity` takes it
/// now. The first identity loaded after the upgrade — the one the app starts
/// with, before any screen can replace it — is recorded as its owner; only
/// that identity ever adopts it, so switching identities first cannot hand
/// one user's bearer proofs to another. Returns `(record, adopt)`.
#[cfg(not(target_arch = "wasm32"))]
fn legacy_store_decision(owner: Option<&str>, identity: &str, may_record: bool) -> (bool, bool) {
    match owner {
        Some(owner) => (false, owner == identity),
        None => (may_record, may_record),
    }
}

#[cfg(not(target_arch = "wasm32"))]
async fn settle_legacy_store(identity: &str, may_record: bool) -> Result<()> {
    let legacy = sibling_store_path(crate::db::app_db::app_db_path(), LEGACY_STORE_NAME)?;
    if !["", "-wal", "-shm"]
        .iter()
        .any(|suffix| std::path::Path::new(&format!("{legacy}{suffix}")).exists())
    {
        return Ok(());
    }
    let db = crate::db::app_db::db().ok_or_else(|| anyhow::anyhow!("CashuStoreUnavailable"))?;
    let owner = db
        .get_setting(settings_keys::CASHU_LEGACY_STORE_OWNER)
        .await?;
    let (record, adopt) = legacy_store_decision(owner.as_deref(), identity, may_record);
    if record {
        db.set_setting(settings_keys::CASHU_LEGACY_STORE_OWNER, identity)
            .await?;
    }
    if adopt {
        move_legacy_store(&legacy, &proof_store_path(identity)?)?;
    }
    Ok(())
}

/// Move the shared store to `own`, restart-safe. The `-wal` and `-shm`
/// companions go first and the main file last: until the main file has moved,
/// the next attempt still finds it under the shared name and completes the
/// move, and once it has, every companion is already beside it — SQLite never
/// opens the main file without the WAL holding its latest commits. A store
/// the identity already has is never merged with the shared one.
#[cfg(not(target_arch = "wasm32"))]
fn move_legacy_store(legacy: &str, own: &str) -> Result<()> {
    let exists = |path: &str| std::path::Path::new(path).exists();
    if exists(own) && exists(legacy) {
        log::warn!("[cashu] the identity already has a proof store; the shared one stays");
        return Ok(());
    }
    for suffix in ["-wal", "-shm", ""] {
        let from = format!("{legacy}{suffix}");
        let to = format!("{own}{suffix}");
        if exists(&from) && !exists(&to) {
            std::fs::rename(&from, &to)
                .map_err(|e| anyhow::anyhow!("CashuStoreUnavailable: {e}"))?;
        }
    }
    log::info!("[cashu] the shared proof store now belongs to its owner identity");
    Ok(())
}

/// The Cashu sats the loaded identity would leave behind if it were replaced,
/// or `None` when there are none.
///
/// Read from its proof store without contacting a mint; an older install's
/// shared store has already moved to its owner at that identity's load. Each
/// identity's store opens only under its own key, so these sats come back only
/// by importing that identity's words again.
///
/// **Errors**: `CashuStoreUnavailable`.
pub(crate) async fn identity_balance_at_risk() -> Result<Option<u64>> {
    let Some(identity) = current_identity().await else {
        return Ok(None);
    };
    let sats = crate::cashu::stored_balance(&proof_store_path(&identity)?, None).await?;
    Ok((sats > 0).then_some(sats))
}

/// The file `name` next to `app_db`, or `CashuStoreUnavailable` when the app
/// database was never opened.
///
/// Split from [`proof_store_path`] so it can be tested on its argument instead
/// of on a process-wide `OnceLock` that any other test in this binary may have
/// set — two of them in `api::escrow` and `api::reputation` call `init_db`.
fn sibling_store_path(app_db: Option<&str>, name: &str) -> Result<String> {
    let app_db = app_db.ok_or_else(|| anyhow::anyhow!("CashuStoreUnavailable"))?;

    // `init_db`'s argument is a filesystem path on native and an IndexedDB
    // *database name* on web. A name has no parent, and joining onto `""` would
    // silently produce a relative file next to the process's cwd — so the two
    // cases are separated rather than left to `Path` semantics.
    let parent = std::path::Path::new(app_db)
        .parent()
        .filter(|p| !p.as_os_str().is_empty());

    Ok(match parent {
        Some(dir) => dir.join(name).to_string_lossy().into_owned(),
        None => name.to_string(),
    })
}

/// Serializes wallet lifecycle changes: connect, a change of mint, disconnect.
///
/// Without it two connects both open the proof store and both hit the mint, and
/// — worse — a disconnect issued during a connect clears an empty slot which the
/// connect then fills, rebinding a wallet the caller just dropped.
fn lifecycle_lock() -> &'static tokio::sync::Mutex<()> {
    static LIFECYCLE: OnceLock<tokio::sync::Mutex<()>> = OnceLock::new();
    LIFECYCLE.get_or_init(|| tokio::sync::Mutex::new(()))
}

/// Is the wallet bound to `bound_to` at the mint `resolved_now` names?
///
/// Asked of the mint a connect requests, of the node's mint before an escrow,
/// and of an order's own mint. All compare in the daemon's canonical form
/// ([`canonical_mint`]): the node lists its mints as configured but publishes
/// an order's mint canonicalised, so the same mint can arrive spelled two ways.
fn same_mint(bound_to: &str, resolved_now: Option<&str>) -> bool {
    resolved_now
        .map(|current| canonical_mint(current) == canonical_mint(bound_to))
        .unwrap_or(false)
}

/// A mint URL as mostrod stores an order's mint (`normalize_mint_url`,
/// MostroP2P/mostro#1047): parsed, so scheme and host are lower-cased and a
/// default port dropped, without a trailing slash. A value that does not
/// parse is compared as written, minus that slash.
fn canonical_mint(url: &str) -> String {
    let trimmed = url.trim();
    match nostr_sdk::prelude::Url::parse(trimmed) {
        Ok(parsed) => parsed.as_str().trim_end_matches('/').to_string(),
        Err(_) => trimmed.trim_end_matches('/').to_string(),
    }
}

/// A handle to the bound wallet.
///
/// The `Arc` is cloned out and the guard dropped, so the mint round trip that
/// follows holds no lock. Not gated on the node: the wallet works on every
/// node (docs/cashu/README.md §1.2).
///
/// **Errors**: `CashuNotConnected`.
async fn active_wallet() -> Result<Arc<CashuWallet>> {
    live_wallet()
        .await
        .ok_or_else(|| anyhow::anyhow!("CashuNotConnected"))
}

/// The marker [`cashu_connect`] returns when it has no mint to bind to.
const NO_MINT: &str = "CashuNoMint";

/// Which mint [`cashu_connect`] binds the wallet to: the one the user asks for,
/// else the one they set before, else the node's default. The wallet's mint
/// belongs to the user; a node only offers a default and never changes it.
///
/// **Errors**: `InvalidMintUrl` for a request that is not an `http(s)` URL with
/// a host, `CashuNoMint` when there is nothing to go on.
fn wallet_mint_target(
    requested: Option<&str>,
    stored: Option<&str>,
    node_default: Option<&str>,
) -> Result<String> {
    fn given(value: Option<&str>) -> Option<&str> {
        value.map(str::trim).filter(|v| !v.is_empty())
    }
    if let Some(url) = given(requested) {
        validate_wallet_mint_url(url)?;
        return Ok(url.to_string());
    }
    given(stored)
        .or(given(node_default))
        .map(str::to_string)
        .ok_or_else(|| anyhow::anyhow!(NO_MINT))
}

/// A mint the wallet may bind to on the user's say-so: an `http(s)` URL with a
/// host, over HTTPS unless it is this device. Proofs are bearer money, and
/// cleartext HTTP to a remote mint hands them to anyone on the path; a local
/// test mint (`http://localhost:3338`) is the one exception.
///
/// **Errors**: `InvalidMintUrl`.
fn validate_wallet_mint_url(url: &str) -> Result<()> {
    crate::api::escrow::validate_mint_url(url)?;
    let parsed = nostr_sdk::prelude::Url::parse(url)?;
    let loopback = match parsed.host() {
        Some(nostr_sdk::prelude::url::Host::Domain(host)) => host.eq_ignore_ascii_case("localhost"),
        Some(nostr_sdk::prelude::url::Host::Ipv4(ip)) => ip.is_loopback(),
        Some(nostr_sdk::prelude::url::Host::Ipv6(ip)) => ip.is_loopback(),
        None => false,
    };
    if parsed.scheme() == "http" && !loopback {
        bail!("InvalidMintUrl: '{url}' must use https");
    }
    Ok(())
}

/// The mint a Cashu node that pins exactly one offers as the wallet's default.
///
/// Held to the same rule as a mint the user types: a node that names a remote
/// `http://` mint offers no default, and the user is asked for a mint instead.
fn node_default_mint() -> Option<String> {
    if !escrow_mode::is_cashu_mode() {
        return None;
    }
    let mint_url = escrow_mode::get_resolved()
        .config
        .single_mint()
        .map(str::to_string)?;
    validate_wallet_mint_url(&mint_url).ok()?;
    Some(mint_url)
}

/// The wallet's mint as the user last set it, or `None` on a fresh install.
///
/// An unreadable store is an error, never "unset": read as unset, the next
/// connect would bind elsewhere and overwrite the mint the user chose.
///
/// **Errors**: `CashuStoreUnavailable`.
async fn stored_wallet_mint() -> Result<Option<String>> {
    let Some(db) = crate::db::app_db::db() else {
        return Ok(None);
    };
    db.get_setting(settings_keys::CASHU_WALLET_MINT_URL)
        .await
        .map_err(|e| anyhow::anyhow!("CashuStoreUnavailable: {e}"))
}

async fn store_wallet_mint(mint_url: &str) -> Result<()> {
    let Some(db) = crate::db::app_db::db() else {
        log::warn!("[cashu] no DB — the wallet's mint applies to this session only");
        return Ok(());
    };
    db.set_setting(settings_keys::CASHU_WALLET_MINT_URL, mint_url)
        .await
}

/// The escrow gate: fail closed unless the active node was positively
/// identified as Cashu. Wallet operations never pass through here.
fn ensure_enabled() -> Result<()> {
    if escrow_mode::is_cashu_mode() {
        return Ok(());
    }
    // A Cashu node that pins no single mint (it accepts several, or any):
    // the seller is routed to the escrow screen on the mode alone (there is no
    // hold invoice on such a node), so it must say why it cannot lock rather
    // than "not Cashu".
    if escrow_mode::get_resolved().mode.is_cashu() {
        bail!("CashuMintNotSupported");
    }
    bail!("CashuNotEnabled")
}

async fn snapshot() -> CashuWalletStatus {
    // Cloned out so the balance read below — which can reach the store — runs
    // with no lock held.
    let wallet = live_wallet().await;
    match wallet.as_ref() {
        Some(wallet) => CashuWalletStatus {
            connected: true,
            mint_url: Some(wallet.mint_url().to_string()),
            // A failed read reports `None`, never zero. The wallet is still
            // connected and the next event will carry the real figure, but in
            // the meantime the UI must say "unknown" rather than name a number
            // that would read as "your money is gone".
            balance_sats: match wallet.balance().await {
                Ok(balance) => Some(balance),
                Err(e) => {
                    log::warn!("[cashu] balance read failed: {e}");
                    None
                }
            },
            missing_capabilities: wallet
                .capabilities()
                .missing()
                .into_iter()
                .map(str::to_string)
                .collect(),
        },
        None => {
            // Not bound, but a mint may be set that is not answering right
            // now: it is named, with what it holds read from disk, so a user
            // about to replace it sees what stays behind there. With no mint
            // set, a wallet genuinely holds nothing — a known zero.
            let mint_url = stored_wallet_mint().await.ok().flatten();
            let balance_sats = match &mint_url {
                Some(mint_url) => offline_balance(mint_url).await,
                None => Some(0),
            };
            CashuWalletStatus {
                connected: false,
                mint_url,
                balance_sats,
                missing_capabilities: Vec::new(),
            }
        }
    }
}

/// What the loaded identity's proof store holds at `mint_url`, without
/// contacting it; `None` when that cannot be read — unknown, never zero.
async fn offline_balance(mint_url: &str) -> Option<u64> {
    let identity = current_identity().await?;
    let path = proof_store_path(&identity).ok()?;
    crate::cashu::stored_balance(&path, Some(mint_url))
        .await
        .map_err(|e| log::warn!("[cashu] offline balance unreadable: {e}"))
        .ok()
}

async fn notify() {
    let _ = changes().send(snapshot().await);
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Bind the wallet to a mint, unless it is already bound to it.
///
/// `mint_url` is the mint the user chose; it becomes the wallet's mint once the
/// mint has proven usable, and stays it across node switches and restarts.
/// `None` keeps the mint set before, or — on a fresh install — takes the
/// default of a Cashu node that pins exactly one ([`wallet_mint_target`]).
/// Binding another mint never deletes the proofs of the previous one: they stay
/// in the proof store and come back when the wallet is bound to it again.
///
/// Lazy by design: nothing connects at startup, so a user who never opens the
/// wallet never opens a proof store or contacts a mint.
///
/// **Errors**: `CashuNoMint` when no mint was given, set or offered,
/// `InvalidMintUrl`, `NoIdentity` before an identity is loaded,
/// `CashuNoMnemonic` for an nsec-imported identity (there is no seed to
/// derive), plus the markers from [`CashuWallet::connect`].
pub async fn cashu_connect(mint_url: Option<String>) -> Result<CashuWalletStatus> {
    // One lifecycle change at a time — see [`lifecycle_lock`].
    let _lifecycle = lifecycle_lock().lock().await;

    let stored = stored_wallet_mint().await?;
    let target = wallet_mint_target(
        mint_url.as_deref(),
        stored.as_deref(),
        node_default_mint().as_deref(),
    )?;

    // A wallet already bound to that mint is reused as is.
    let live = live_wallet().await;
    if live.is_some_and(|wallet| same_mint(wallet.mint_url(), Some(&target))) {
        return Ok(snapshot().await);
    }

    let bound = open_wallet(&target).await?;

    // Remembered only once the mint has answered and proven usable, so a typo
    // never becomes the wallet's mint — and before installing, so a store that
    // refuses leaves the previous wallet and its mint as they were.
    if !stored
        .as_deref()
        .is_some_and(|stored| same_mint(stored, Some(&target)))
    {
        store_wallet_mint(&target).await?;
    }
    install(bound).await;

    notify().await;
    Ok(snapshot().await)
}

/// Current wallet status: "not connected" until the wallet is bound to a mint.
pub async fn cashu_status() -> Result<CashuWalletStatus> {
    Ok(snapshot().await)
}

/// Spendable balance in satoshis.
///
/// **Errors**: `CashuNotConnected`.
pub async fn cashu_get_balance() -> Result<u64> {
    active_wallet().await?.balance().await
}

/// Redeem an encoded Cashu token into the wallet, returning the amount received.
///
/// An unbound wallet binds first, to the mint set before (or the node's
/// default) — and with no mint set at all, to the mint the token names. A mint
/// is adopted only by a receive that succeeds: a token that turns out spent or
/// worthless leaves the wallet unbound and nothing remembered.
///
/// **Errors**: `CashuReceiveFailed` (wrong mint, already spent, malformed),
/// `CashuTokenUnverified`, plus the markers from [`cashu_connect`].
pub async fn cashu_receive_token(encoded: String) -> Result<u64> {
    let amount = match live_wallet().await {
        Some(wallet) => wallet.receive_token(&encoded).await?,
        None => receive_unbound(&encoded).await?,
    };
    notify().await;
    Ok(amount)
}

/// Receive into a wallet that is not bound yet, binding it only if the receive
/// succeeds.
async fn receive_unbound(encoded: &str) -> Result<u64> {
    let _lifecycle = lifecycle_lock().lock().await;

    let stored = stored_wallet_mint().await?;
    let target = match wallet_mint_target(None, stored.as_deref(), node_default_mint().as_deref()) {
        Ok(target) => target,
        Err(e) if e.to_string() == NO_MINT => {
            // The token names its mint; it is held to the same rule as one the
            // user types, before anything contacts it.
            let mint_url = crate::cashu::token_mint_url(encoded)?;
            validate_wallet_mint_url(&mint_url)?;
            mint_url
        }
        Err(e) => return Err(e),
    };

    // Bound by another call while this one waited for the lock.
    if let Some(wallet) = live_wallet().await {
        if same_mint(wallet.mint_url(), Some(&target)) {
            return wallet.receive_token(encoded).await;
        }
    }

    let bound = open_wallet(&target).await?;
    let amount = bound.wallet.receive_token(encoded).await?;

    // The sats are in the proof store now, keyed by this mint, so a store that
    // refuses costs only the binding across a restart — not the funds.
    if stored.is_none() {
        if let Err(e) = store_wallet_mint(&target).await {
            log::warn!("[cashu] received at {target}, but the mint was not remembered: {e}");
        }
    }
    install(bound).await;
    Ok(amount)
}

/// Export `amount_sats` from the wallet as an encoded token.
///
/// **Errors**: `CashuNotConnected`, `CashuAmountZero`, `CashuSendFailed`
/// (insufficient funds included).
pub async fn cashu_create_token(amount_sats: u64) -> Result<String> {
    let token = active_wallet().await?.create_token(amount_sats).await?;
    notify().await;
    Ok(token)
}

/// Reconcile the proof store with the mint: proofs the mint reports spent are
/// forgotten, and the new balance is broadcast.
///
/// **Returns nothing on purpose.** It reclaims neither an unredeemed token of
/// ours nor the proofs of a half-finished send — cdk's state check cannot see
/// either — so there is no "reclaimed N sat" to report and C2 does not pretend
/// otherwise; see [`CashuWallet::sweep_spent_proofs`]. Getting an abandoned
/// token back is phase C10.
///
/// **Errors**: `CashuNotConnected`.
pub async fn cashu_sweep_spent_proofs() -> Result<()> {
    active_wallet().await?.sweep_spent_proofs().await?;
    notify().await;
    Ok(())
}

/// Drop the in-memory wallet. Proofs stay on disk and the wallet's mint stays
/// set — this is a disconnect, not a wipe. A node switch does **not** call it:
/// the wallet's mint is the user's, not the node's.
pub async fn cashu_disconnect() -> Result<()> {
    // Shares the lifecycle lock with `cashu_connect`, so a disconnect issued
    // during a connect waits for it and then clears the slot, instead of
    // clearing an empty slot and having the connect fill it back in.
    let _lifecycle = lifecycle_lock().lock().await;
    *wallet_lock().write().await = None;
    notify().await;
    Ok(())
}

// ── Escrow lock (phase C5) ────────────────────────────────────────────────────

/// What the seller is about to lock, so the UI can show it before they commit.
///
/// Computed rather than taken from the daemon: the escrow request states the
/// amount but neither the mint nor the locktime, and in Cashu mode the node
/// publishes no info event that would (mostro `scheduler.rs`, "a Cashu-aware
/// info event is future work"). So the mint must be known — advertised or set
/// through the developer override — and the locktime falls back to the
/// protocol default, never to a guess.
///
/// **Errors**: `CashuNotEnabled`, `CashuOrderAmountUnknown`, `CashuMintNotSupported`,
/// `CashuWalletOnOtherMint`, `CashuNotConnected`, `CashuBalanceUnknown`, plus the
/// markers from [`cashu_connect`].
pub async fn cashu_escrow_quote(order_id: String) -> Result<crate::api::types::CashuEscrowQuote> {
    ensure_enabled()?;

    let trade = load_trade(&order_id).await?;
    let amount_sats = trade
        .order
        .amount_sats
        .ok_or_else(|| anyhow::anyhow!("CashuOrderAmountUnknown"))?;

    // No fee token until the daemon collects one (TA-1f): today its handler
    // ignores `fee_token`, so building one would move the seller's sats to a
    // 1-of-1 lock nobody accounts for. `node_fee` keeps the daemon's formula
    // for the day it does.
    let fee_sats = 0;

    let resolved = escrow_mode::get_resolved();
    // An escrow locked at the wrong mint is rejected only after the swap, so a
    // node that pins no single mint fails here instead of guessing one.
    let mint_url = resolved
        .config
        .single_mint()
        .map(str::to_string)
        .ok_or_else(|| anyhow::anyhow!("CashuMintNotSupported"))?;
    // The order names its own mint (mostro#1047), and the node refuses a
    // token locked anywhere else only after the swap: an order on a mint
    // other than the node's stops here. The wallet's own mint is checked
    // against the node's below, by `ensure_wallet_at`.
    if let Some(order_mint) = trade.order.cashu_mint_url.as_deref() {
        if !same_mint(&mint_url, Some(order_mint)) {
            log::warn!(
                "[cashu] order {order_id} escrows at {order_mint}, the node's mint is {mint_url}"
            );
            bail!("CashuMintNotSupported");
        }
    }

    let locktime_days = resolved
        .config
        .escrow_locktime_days
        .unwrap_or(PROTOCOL_DEFAULT_LOCKTIME_DAYS);
    let quote = |balance_sats: u64, mint_url: String, pending_submission: bool| {
        crate::api::types::CashuEscrowQuote {
            order_id: order_id.clone(),
            amount_sats,
            fee_sats,
            total_sats: amount_sats.saturating_add(fee_sats),
            balance_sats,
            mint_url,
            locktime_days,
            pending_submission,
        }
    };

    // An escrow already swapped — on the row, or held because the row could
    // not be written — is re-sent as is by `lock_escrow`, at the mint it was
    // locked at, without the wallet. So the wallet's mint must not stand in
    // the way of that retry: a user who changed it since still gets a quote.
    let recorded = trade
        .cashu_escrow_token
        .as_deref()
        .map(|token| (trade.cashu_mint_url.as_deref().unwrap_or(&mint_url), token));
    if let Some((locked_at, _)) = recorded_or_held_escrow(&order_id, recorded) {
        let balance = match live_wallet().await {
            Some(wallet) => wallet.balance().await.unwrap_or(0),
            None => 0,
        };
        return Ok(quote(balance, locked_at, true));
    }

    // Connect before reading the balance. An unconnected wallet reports zero,
    // and a quote that reports zero turns into "insufficient funds" on a wallet
    // that is fully funded — the screen connects first, but a retry from
    // anywhere else would not.
    cashu_connect(None).await?;
    let wallet = active_wallet().await?;
    // The wallet's mint is the user's and may not be this node's: the escrow
    // is locked from the wallet's proofs, so the two must match.
    ensure_wallet_at(wallet.mint_url(), &mint_url)?;

    let balance = wallet
        .balance()
        .await
        .map_err(|e| anyhow::anyhow!("CashuBalanceUnknown: {e}"))?;

    Ok(quote(balance, mint_url, false))
}

/// Refuse an escrow from a wallet bound to another mint than `mint_url`, before
/// any swap: the node rejects a token locked elsewhere only after it.
///
/// **Errors**: `CashuWalletOnOtherMint`.
fn ensure_wallet_at(wallet_mint: &str, mint_url: &str) -> Result<()> {
    if same_mint(wallet_mint, Some(mint_url)) {
        return Ok(());
    }
    log::warn!("[cashu] the wallet is bound to {wallet_mint}, the escrow needs {mint_url}");
    bail!("CashuWalletOnOtherMint")
}

/// The escrow locktime a node that states none is held to: the daemon's own
/// default for `[cashu] escrow_locktime_days` (mostro `src/config/types.rs`,
/// `settings.tpl.toml`), which is also the floor it validates against. A node
/// configured higher rejects the token (`invalid_cashu_token`); the token is
/// then retired, not lost — it refunds to the seller at its locktime.
const PROTOCOL_DEFAULT_LOCKTIME_DAYS: u32 = 15;

/// How long the seller waits for the daemon to answer a submission.
const ESCROW_REPLY_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);

/// One escrow operation per order at a time. Two taps, or a tap racing the
/// reconnect resubmission, would otherwise both see "no token recorded" and
/// both swap.
fn escrow_op_lock(order_id: &str) -> std::sync::Arc<tokio::sync::Mutex<()>> {
    static LOCKS: std::sync::OnceLock<
        std::sync::Mutex<std::collections::HashMap<String, std::sync::Arc<tokio::sync::Mutex<()>>>>,
    > = std::sync::OnceLock::new();
    let mut map = LOCKS
        .get_or_init(Default::default)
        .lock()
        .unwrap_or_else(|e| e.into_inner());
    map.entry(order_id.to_string()).or_default().clone()
}

/// Escrows swapped but not written to their trade row (the store refused the
/// write), held for the life of the process. The swap already happened: a
/// retry must find this token instead of swapping again.
/// `(mint_url, token)` per order: a re-send must name the mint the token
/// lives at, not whatever the node resolves to now.
type HeldEscrows = std::sync::Mutex<std::collections::HashMap<String, (String, String)>>;

fn held_escrows() -> &'static HeldEscrows {
    static HELD: std::sync::OnceLock<HeldEscrows> = std::sync::OnceLock::new();
    HELD.get_or_init(Default::default)
}

fn hold_unrecorded_escrow(order_id: &str, mint_url: &str, token: &str) {
    held_escrows()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .insert(
            order_id.to_string(),
            (mint_url.to_string(), token.to_string()),
        );
}

fn forget_held_escrow(order_id: &str) {
    held_escrows()
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .remove(order_id);
}

/// The escrow already swapped for `order_id`, as `(mint_url, token)`: the one
/// on its row, else one held because the row could not be written. `None`
/// means none exists yet.
fn recorded_or_held_escrow(
    order_id: &str,
    recorded: Option<(&str, &str)>,
) -> Option<(String, String)> {
    recorded
        .map(|(mint, token)| (mint.to_string(), token.to_string()))
        .or_else(|| {
            held_escrows()
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .get(order_id)
                .cloned()
        })
}

/// How many times a freshly swapped escrow is written before it is held in
/// memory instead: the write is what keeps it across a restart.
const RECORD_ATTEMPTS: usize = 3;

/// Seller: fund the 2-of-3 escrow for `order_id` and submit it to the daemon.
///
/// The Cashu analogue of paying the hold invoice, built so no call can lose or
/// double-spend the seller's funds:
///
/// 1. one operation per order at a time ([`escrow_op_lock`]);
/// 2. an escrow already recorded for the trade is **re-sent as is** — the
///    daemon answers the same token with `cashu-escrow-locked` again, and a
///    different one with `invalid_cashu_token`, so a retry must never swap
///    anew;
/// 3. otherwise the balance is checked, the escrow built, and the token
///    **recorded before anything else can fail** — from the swap on, the
///    funds exist only in that token;
/// 4. the submission is correlated by `request_id` and answered by the
///    daemon: `cashu-escrow-locked`, or a `cant-do` that
///    [`settle_escrow_rejection`] turns into the next step.
///
/// **Errors** (stable markers): `CashuNotEnabled`, `CashuNotConnected`,
/// `CashuMintNotSupported`, `CashuWalletOnOtherMint`, `CashuInsufficientFunds`,
/// `NotTheSeller`,
/// `CashuEscrowOrderMovedOn`,
/// `CashuEscrowRequestMissing`, `CashuWrongTradeKey`, `DeviceClockInvalid`,
/// `CashuEscrowNotPersisted`, `CashuEscrowRejected: <reason>`,
/// `NoDaemonResponse`, plus the `CashuLockFailed` markers from construction.
pub async fn lock_escrow(order_id: String) -> Result<()> {
    ensure_enabled()?;
    let op = escrow_op_lock(&order_id);
    let _op = op.lock().await;

    let trade = load_trade(&order_id).await?;

    // Only the seller funds an escrow. A buyer reaching this is a bug, but it
    // would burn the buyer's own ecash, so it is checked rather than assumed.
    if !matches!(trade.role, crate::api::types::TradeRole::Seller) {
        bail!("NotTheSeller");
    }

    let trade_index = crate::api::orders::trade_key_for_order(&order_id)
        .await
        .ok_or_else(|| anyhow::anyhow!("no persisted trade key for order {order_id}"))?;
    let seller_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let identity_keys = crate::api::identity::get_transport_identity_keys(&seller_keys).await?;
    let mostro_hex = crate::config::active_mostro_pubkey();
    let mostro_pubkey = nostr_sdk::prelude::PublicKey::from_hex(&mostro_hex)?;

    let seller_hex = seller_keys.public_key().to_hex();

    // The daemon re-derives {P_B, P_S, P_M} from the order and rejects a proof
    // that names any others, so these must be the per-order **trade** keys it
    // stated in the escrow request. `counterparty_pubkey` is not that: it holds
    // the maker's order-book key for a taker, and nothing at all for a maker.
    let buyer_hex = trade
        .buyer_trade_pubkey
        .clone()
        .ok_or_else(|| anyhow::anyhow!("CashuEscrowRequestMissing"))?;

    // The daemon also checks the seller key against the order. If the trade key
    // this device would sign with is not the one it recorded, the escrow would
    // be locked to a key nobody here holds — worse than a rejection, because
    // the swap happens first.
    if let Some(expected) = trade.seller_trade_pubkey.as_deref() {
        if expected != seller_hex {
            bail!("CashuWrongTradeKey: order expects {expected}, this device holds {seller_hex}");
        }
    }

    let parties =
        crate::cashu::escrow::EscrowParties::from_xonly_hex(&buyer_hex, &seller_hex, &mostro_hex)?;

    // A token already swapped — on the row, or held because the row could
    // not be written — is re-sent as is, at the mint it was locked at: never
    // a second swap, and no quote, connection or balance needed for it.
    // A recorded token is never built again, even on a row that lost its mint
    // (every write sets both): it goes to the node's resolved mint, and a
    // mismatch comes back as `invalid_mint_url`, which retires it.
    let fallback_mint = escrow_mode::get_resolved()
        .config
        .single_mint()
        .unwrap_or_default()
        .to_string();
    let recorded = trade.cashu_escrow_token.as_deref().map(|token| {
        (
            trade
                .cashu_mint_url
                .as_deref()
                .unwrap_or(fallback_mint.as_str()),
            token,
        )
    });
    let existing = recorded_or_held_escrow(&order_id, recorded);
    let resubmission = existing.is_some();
    let (mint_url, escrow_token) = match existing {
        Some(pair) => pair,
        None => {
            let quote = cashu_escrow_quote(order_id.clone()).await?;
            let token = build_and_record_escrow(&order_id, &quote, &parties).await?;
            (quote.mint_url, token)
        }
    };

    let submitted = submit_escrow(
        &order_id,
        trade_index,
        &identity_keys,
        &seller_keys,
        &mostro_pubkey,
        &escrow_token,
        &mint_url,
        &buyer_hex,
        &seller_hex,
    )
    .await;
    notify().await;
    match submitted {
        Ok(()) => {}
        Err(SubmitError::Rejected(reason)) => {
            settle_escrow_rejection(&order_id, &reason, resubmission).await?
        }
        Err(SubmitError::Other(e)) => return Err(e),
    }
    // A held token gets one more chance at the row now that it is live; if
    // the store still refuses, say so rather than let the seller believe this
    // device keeps a copy it can reclaim after a restart.
    if recorded_or_held_escrow(&order_id, None).is_some() {
        record_escrow_token(&order_id, &mint_url, &escrow_token)
            .await
            .map_err(|e| anyhow::anyhow!("CashuEscrowNotPersisted: {e}"))?;
        forget_held_escrow(&order_id);
    }
    log::info!("[cashu] escrow locked for order={order_id}");
    Ok(())
}

/// Build the escrow and record it against the trade. From the swap on, the
/// token is never dropped: written to the row, or — if the store refuses
/// [`RECORD_ATTEMPTS`] times — held in memory, where the next attempt finds
/// it before it could swap again.
async fn build_and_record_escrow(
    order_id: &str,
    quote: &crate::api::types::CashuEscrowQuote,
    parties: &crate::cashu::escrow::EscrowParties,
) -> Result<String> {
    if quote.balance_sats < quote.total_sats {
        bail!(
            "CashuInsufficientFunds: need {} sat, have {}",
            quote.total_sats,
            quote.balance_sats
        );
    }

    // The daemon's floor is `now + escrow_locktime_days` evaluated when it
    // *validates* the submission, which is strictly later than our `now` by the
    // publish and propagation delay. Matching the floor exactly would make every
    // lock a race against the network, with the funds already swapped by the
    // time it is lost.
    let locktime = now_secs()?
        .saturating_add(u64::from(quote.locktime_days).saturating_mul(SECONDS_PER_DAY))
        .saturating_add(LOCKTIME_SUBMISSION_MARGIN_SECS);

    // The mint can change between the quote and here; the escrow is built
    // from the wallet's proofs, so it is checked again.
    let wallet = active_wallet().await?;
    ensure_wallet_at(wallet.mint_url(), &quote.mint_url)?;
    let escrow = wallet
        .build_escrow_token(quote.amount_sats, parties, locktime)
        .await?;

    // From here the funds exist only in `escrow`: record it before anything
    // else can fail.
    let mut recorded = Err(anyhow::anyhow!("not attempted"));
    for _ in 0..RECORD_ATTEMPTS {
        recorded = record_escrow_token(order_id, &quote.mint_url, &escrow).await;
        if recorded.is_ok() {
            break;
        }
    }
    if let Err(e) = &recorded {
        log::error!("[cashu] escrow built but not recorded for order={order_id}, held: {e}");
        hold_unrecorded_escrow(order_id, &quote.mint_url, &escrow);
    }

    // Verify what we just built before handing it over. The daemon runs the
    // same check; a token that fails it is retired rather than sent, and the
    // next attempt builds a new one. Retiring needs the store: if that fails
    // too, the token stays held — a re-send is rejected and retired then.
    if let Err(e) = wallet
        .verify_escrow_token(&escrow, parties, quote.amount_sats, locktime)
        .await
    {
        if recorded.is_ok() {
            retire_escrow_token(order_id).await?;
        }
        return Err(e);
    }
    Ok(escrow)
}

/// Record a freshly built escrow on the trade row.
async fn record_escrow_token(order_id: &str, mint_url: &str, token: &str) -> Result<()> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow::anyhow!("CashuStoreUnavailable"))?;
    let mut trade = load_trade(order_id).await?;
    trade.cashu_mint_url = Some(mint_url.to_string());
    trade.cashu_escrow_token = Some(token.to_string());
    trade.cashu_locked_at = now_secs().ok().map(|t| t as i64);
    db.save_trade(&trade).await?;
    crate::api::trade_touch::touch_trade(order_id);
    Ok(())
}

/// Move the recorded escrow to `cashu_rejected_escrow_tokens`: the daemon will
/// never accept it, so the next attempt must build anew — but the token is the
/// seller's money until its locktime refunds it, so it is kept.
async fn retire_escrow_token(order_id: &str) -> Result<()> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow::anyhow!("CashuStoreUnavailable"))?;
    let mut trade = load_trade(order_id).await?;
    let held = recorded_or_held_escrow(order_id, None).map(|(_, token)| token);
    let retired: Vec<String> = trade
        .cashu_escrow_token
        .take()
        .into_iter()
        .chain(held)
        .collect();
    if retired.is_empty() {
        return Ok(());
    }
    for token in retired {
        if !trade.cashu_rejected_escrow_tokens.contains(&token) {
            trade.cashu_rejected_escrow_tokens.push(token);
        }
    }
    db.save_trade(&trade).await?;
    forget_held_escrow(order_id);
    crate::api::trade_touch::touch_trade(order_id);
    Ok(())
}

enum SubmitError {
    /// The daemon answered `cant-do` with this reason.
    Rejected(String),
    Other(anyhow::Error),
}

/// Publish `add-cashu-escrow` and wait for the daemon's answer.
#[allow(clippy::too_many_arguments)]
async fn submit_escrow(
    order_id: &str,
    trade_index: u32,
    identity_keys: &nostr_sdk::prelude::Keys,
    seller_keys: &nostr_sdk::prelude::Keys,
    mostro_pubkey: &nostr_sdk::prelude::PublicKey,
    escrow_token: &str,
    mint_url: &str,
    buyer_hex: &str,
    seller_hex: &str,
) -> std::result::Result<(), SubmitError> {
    use crate::mostro::pending::{forget_cashu_lock, register_cashu_lock, CashuLockReply};
    // Correlation nonce: 0 is indistinguishable from "unset" on the wire.
    let request_id: u64 = {
        use rand::RngCore;
        rand::rngs::OsRng.next_u64().max(1)
    };
    let event_json = crate::mostro::actions::add_cashu_escrow(
        identity_keys,
        seller_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        escrow_token,
        mint_url,
        buyer_hex,
        seller_hex,
        None,
        request_id,
    )
    .await
    .map_err(SubmitError::Other)?;

    let seller_pk = seller_keys.public_key().to_hex();
    // Registered before the publish so the answer cannot beat it.
    let reply_rx = register_cashu_lock(&seller_pk, request_id);
    if let Err(e) = crate::api::orders::publish_event_json(&event_json).await {
        forget_cashu_lock(&seller_pk, request_id);
        return Err(SubmitError::Other(e));
    }
    match crate::rt::time::timeout(ESCROW_REPLY_TIMEOUT, reply_rx).await {
        Ok(Ok(CashuLockReply::Locked)) => Ok(()),
        Ok(Ok(CashuLockReply::Rejected { reason })) => Err(SubmitError::Rejected(reason)),
        // A late `cashu-escrow-locked` still activates the trade through the
        // status arm; the recorded token is re-sent on the next attempt.
        _ => {
            forget_cashu_lock(&seller_pk, request_id);
            Err(SubmitError::Other(anyhow::anyhow!(
                crate::mostro::pending::NO_DAEMON_RESPONSE
            )))
        }
    }
}

/// What a `cant-do` on an escrow submission means for the recorded token.
///
/// - `InvalidOrderStatus` on a **re-submission**: the order is no longer
///   waiting for the escrow — past `active` (a same-token replay while active
///   is answered with `cashu-escrow-locked`), or closed while this device was
///   offline. The wire does not say which, so it is never reported as a lock:
///   `CashuEscrowOrderMovedOn`, and the token stays recorded.
/// - `InvalidCashuToken`, `InvalidMintUrl`: the daemon did not store this
///   token and never will; it is retired so the next attempt builds anew.
/// - anything else (`CashuMintUnavailable`, `InvalidPeer`, `InvalidAmount`,
///   a first-time `InvalidOrderStatus`): the token stays recorded and the
///   reason is reported.
async fn settle_escrow_rejection(order_id: &str, reason: &str, resubmission: bool) -> Result<()> {
    match reason {
        "InvalidOrderStatus" if resubmission => {
            log::info!(
                "[cashu] escrow re-submission for order={order_id} refused by status: \
                 the order is no longer waiting for it"
            );
            bail!("CashuEscrowOrderMovedOn")
        }
        "InvalidCashuToken" | "InvalidMintUrl" => {
            retire_escrow_token(order_id).await?;
            bail!("CashuEscrowRejected: {reason}")
        }
        other => bail!("CashuEscrowRejected: {other}"),
    }
}

/// Re-send every escrow this device recorded but the node never confirmed —
/// the seller's app died or lost the relay between the swap and the answer.
/// Called when the relay pool comes online; best effort, one order at a time,
/// and each goes through [`lock_escrow`], so it swaps nothing and serializes
/// with a seller tapping the same button.
pub(crate) async fn resubmit_pending_escrows() {
    if !escrow_mode::is_cashu_mode() {
        return;
    }
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    let trades = match db.list_trades().await {
        Ok(trades) => trades,
        Err(e) => {
            log::warn!("[cashu] escrow resubmission skipped, trades unreadable: {e}");
            return;
        }
    };
    for trade in trades.into_iter().filter(|t| {
        matches!(t.role, crate::api::types::TradeRole::Seller)
            && t.order.status == crate::api::types::OrderStatus::WaitingPayment
            && t.cashu_escrow_token.is_some()
    }) {
        let order_id = trade.order.id.clone();
        match lock_escrow(order_id.clone()).await {
            Ok(_) => log::info!("[cashu] recorded escrow re-sent for order={order_id}"),
            Err(e) => log::warn!("[cashu] recorded escrow not re-sent for order={order_id}: {e}"),
        }
    }
}

const SECONDS_PER_DAY: u64 = 86_400;

/// Added on top of the daemon's locktime floor to absorb the delay between
/// building the token and the daemon validating it. An hour is invisible to a
/// seller and orders of magnitude larger than relay propagation.
const LOCKTIME_SUBMISSION_MARGIN_SECS: u64 = 3_600;

/// Seconds since the unix epoch.
///
/// A clock before the epoch is an error rather than `0`: substituting zero
/// would build a locktime in 1970 and surface much later as an unexplained
/// `InvalidEscrowConditions`.
fn now_secs() -> Result<u64> {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .map_err(|_| anyhow::anyhow!("DeviceClockInvalid: system time is before 1970"))
}

async fn load_trade(order_id: &str) -> Result<crate::api::types::TradeInfo> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow::anyhow!("CashuStoreUnavailable"))?;
    db.get_trade_by_order_id(order_id)
        .await?
        .ok_or_else(|| anyhow::anyhow!("TradeNotFound: {order_id}"))
}

// ── Stream ────────────────────────────────────────────────────────────────────

/// Emits the wallet status whenever it changes: connect, receive, send, reclaim
/// or disconnect.
pub struct CashuWalletStream {
    rx: broadcast::Receiver<CashuWalletStatus>,
}

impl CashuWalletStream {
    /// Poll for the next wallet-changed event.
    ///
    /// A lagged receiver skips dropped snapshots: the value is current state,
    /// so only the newest one matters.
    pub async fn next(&mut self) -> Result<CashuWalletStatus> {
        loop {
            match self.rx.recv().await {
                Ok(status) => return Ok(status),
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => bail!("CashuWalletStreamClosed"),
            }
        }
    }
}

/// Subscribe to wallet changes.
pub fn on_cashu_wallet_changed() -> CashuWalletStream {
    CashuWalletStream {
        rx: changes().subscribe(),
    }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    /// The escrow globals are process-wide, and so is the lock that guards
    /// them: a private mutex here would serialize this module against itself
    /// while racing `api::escrow` and `mostro::escrow_mode`, whose `clear()`
    /// would land mid-test — issue #309, which is why the lock lives with the
    /// state. It also resets to a node that has advertised nothing.
    fn escrow_lock() -> std::sync::MutexGuard<'static, ()> {
        escrow_mode::lock_globals_for_test()
    }

    /// No wallet bound and no mint remembered: a fresh install.
    async fn forget_wallet_mint() {
        cashu_disconnect().await.unwrap();
        if let Some(db) = crate::db::app_db::db() {
            db.delete_setting(crate::db::settings_keys::CASHU_WALLET_MINT_URL)
                .await
                .unwrap();
        }
    }

    #[tokio::test]
    // The globals lock must span the calls it guards.
    #[allow(clippy::await_holding_lock)]
    async fn the_escrow_entry_points_stay_shut_on_a_lightning_node() {
        // Arrange — the default state: nothing fetched, so not Cashu.
        let _g = escrow_lock();

        // Act / Assert — these move real money into a Cashu escrow, which only
        // a Cashu node takes. The node decides how a trade settles.
        for err in [
            cashu_escrow_quote("any-order".to_string())
                .await
                .unwrap_err(),
            lock_escrow("any-order".to_string()).await.unwrap_err(),
        ] {
            assert!(
                err.to_string().contains("CashuNotEnabled"),
                "expected the escrow gate to close, got {err}"
            );
        }
    }

    #[tokio::test]
    // The globals lock must span the calls it guards.
    #[allow(clippy::await_holding_lock)]
    async fn the_wallet_does_not_depend_on_the_node() {
        // Arrange — a Lightning node, no wallet bound, no mint remembered.
        let _g = escrow_lock();
        forget_wallet_mint().await;

        // Act / Assert — the wallet is always available (docs/cashu/README.md
        // §1.2): on a Lightning node it asks for a mint instead of refusing as
        // "not Cashu", and the operations that need a bound wallet say so.
        let connect = cashu_connect(None).await.unwrap_err();
        assert_eq!(connect.to_string(), "CashuNoMint");
        for err in [
            cashu_get_balance().await.unwrap_err(),
            cashu_create_token(1).await.unwrap_err(),
            cashu_sweep_spent_proofs().await.unwrap_err(),
        ] {
            assert!(
                err.to_string().contains("CashuNotConnected"),
                "expected an unbound wallet, got {err}"
            );
        }
        // With no mint set, receiving takes the token's mint; a token that
        // does not parse names none, and nothing is bound or remembered.
        let receive = cashu_receive_token("cashuBanything".to_string())
            .await
            .unwrap_err();
        assert!(
            receive.to_string().contains("CashuReceiveFailed"),
            "got {receive}"
        );
        assert!(!cashu_status().await.unwrap().connected);
    }

    #[tokio::test]
    // The globals lock must span the calls it guards.
    #[allow(clippy::await_holding_lock)]
    async fn a_mint_url_that_is_not_one_is_refused_before_any_connection() {
        // Arrange
        let _g = escrow_lock();
        forget_wallet_mint().await;

        // Act — nothing here may reach the network or the store.
        let err = cashu_connect(Some("ftp://mint.example.com".to_string()))
            .await
            .unwrap_err();

        // Assert — refused, and not remembered as the wallet's mint.
        assert!(err.to_string().contains("InvalidMintUrl"), "got {err}");
        assert_eq!(stored_wallet_mint().await.unwrap(), None);
    }

    #[test]
    fn a_remote_mint_must_use_https() {
        // Bearer proofs over cleartext HTTP are anyone's on the path.
        assert!(validate_wallet_mint_url("https://mint.example.com").is_ok());
        for remote in ["http://mint.example.com", "http://203.0.113.7:3338"] {
            assert!(
                validate_wallet_mint_url(remote)
                    .unwrap_err()
                    .to_string()
                    .contains("InvalidMintUrl"),
                "{remote} must be refused"
            );
        }
        // A test mint on this device is the exception.
        for local in [
            "http://localhost:3338",
            "http://127.0.0.1:3338",
            "http://[::1]:3338",
        ] {
            assert!(validate_wallet_mint_url(local).is_ok(), "{local} is local");
        }
        // And a user's request goes through the same rule.
        assert!(
            wallet_mint_target(Some("http://mint.example.com"), None, None)
                .unwrap_err()
                .to_string()
                .contains("InvalidMintUrl")
        );
    }

    #[test]
    // The globals lock must span the calls it guards.
    #[allow(clippy::await_holding_lock)]
    fn a_node_offers_no_cleartext_remote_mint_as_the_default() {
        let _g = escrow_lock();
        let node_on = |mint: &str| {
            escrow_mode::set_from_tags(
                escrow_mode::EscrowMode::Cashu,
                escrow_mode::CashuNodeConfig {
                    mint_urls: vec![mint.to_string()],
                    ..Default::default()
                },
            );
            node_default_mint()
        };

        assert_eq!(
            node_on("https://mint.a.com"),
            Some("https://mint.a.com".to_string())
        );
        assert_eq!(node_on("http://mint.a.com"), None);
    }

    #[tokio::test]
    // The globals lock must span the calls it guards.
    #[allow(clippy::await_holding_lock)]
    async fn a_recorded_escrow_is_quoted_without_the_wallet() {
        // Arrange — a single-mint node and a seller row whose escrow was
        // swapped at that mint; no wallet is bound (the user may have moved
        // it to another mint since).
        let _g = escrow_lock();
        forget_wallet_mint().await;
        escrow_mode::set_from_tags(
            escrow_mode::EscrowMode::Cashu,
            escrow_mode::CashuNodeConfig {
                mint_urls: vec!["https://mint.a.com".to_string()],
                ..Default::default()
            },
        );
        let order_id = uuid::Uuid::new_v4().to_string();
        let db = store().await;
        let mut trade = seller_trade(&order_id, Some("02"), "");
        trade.cashu_escrow_token = Some(format!("cashuB-{order_id}"));
        trade.cashu_mint_url = Some("https://mint.a.com".to_string());
        db.save_trade(&trade).await.unwrap();

        // Act
        let quote = cashu_escrow_quote(order_id).await.unwrap();

        // Assert — the retry stays possible, at the mint the token lives at.
        assert!(quote.pending_submission);
        assert_eq!(quote.mint_url, "https://mint.a.com");
    }

    #[test]
    fn a_wallet_serves_only_the_identity_it_was_built_for() {
        // The wallet outlives node switches, so nothing else resets it when
        // the user deletes their identity or imports another: its seed is the
        // previous user's, and so is the ecash it would spend.
        assert!(serves("npub-a", Some("npub-a")));
        assert!(!serves("npub-a", Some("npub-b")));
        assert!(!serves("npub-a", None));
    }

    #[test]
    fn an_escrow_needs_the_wallet_at_the_nodes_mint() {
        // The wallet's mint is the user's and may not be the node's; the
        // escrow is built from the wallet's proofs, so the two must match
        // before any swap.
        assert!(ensure_wallet_at("https://mint.a.com", "https://mint.a.com/").is_ok());
        assert_eq!(
            ensure_wallet_at("https://mint.b.com", "https://mint.a.com")
                .unwrap_err()
                .to_string(),
            "CashuWalletOnOtherMint"
        );
    }

    #[test]
    fn the_wallet_mint_is_the_users_and_the_node_only_offers_a_default() {
        let user = "https://mint.user.com";
        let stored = "https://mint.stored.com";
        let node = "https://mint.node.com";

        // A mint the user asks for wins over everything.
        assert_eq!(
            wallet_mint_target(Some(user), Some(stored), Some(node)).unwrap(),
            user
        );
        // Then the mint they set before: a node switch never changes it.
        assert_eq!(
            wallet_mint_target(None, Some(stored), Some(node)).unwrap(),
            stored
        );
        // Then the node's own mint, when a Cashu node pins exactly one.
        assert_eq!(wallet_mint_target(None, None, Some(node)).unwrap(), node);
        // A blank request is no request.
        assert_eq!(
            wallet_mint_target(Some("  "), Some(stored), None).unwrap(),
            stored
        );
        // Nothing to go on — a Lightning node on a fresh install.
        assert_eq!(
            wallet_mint_target(None, None, None)
                .unwrap_err()
                .to_string(),
            "CashuNoMint"
        );
        // A request that is not an http(s) URL with a host is refused.
        assert!(wallet_mint_target(Some("mint.example.com"), None, None)
            .unwrap_err()
            .to_string()
            .contains("InvalidMintUrl"));
    }

    #[tokio::test]
    // The globals lock must span the calls it guards.
    #[allow(clippy::await_holding_lock)]
    async fn a_set_mint_that_is_not_bound_is_still_named() {
        // Arrange — a mint is set but the wallet is not bound (the mint did
        // not answer when the wallet opened), and no identity is loaded here.
        let _g = escrow_lock();
        forget_wallet_mint().await;
        let db = store().await;
        db.set_setting(
            crate::db::settings_keys::CASHU_WALLET_MINT_URL,
            "https://mint.example.com",
        )
        .await
        .unwrap();

        // Act
        let status = cashu_status().await.unwrap();

        // Assert — the mint is named, so replacing it is never blind, and
        // what it holds is unknown here rather than a zero.
        assert!(!status.connected);
        assert_eq!(status.mint_url.as_deref(), Some("https://mint.example.com"));
        assert_eq!(status.balance_sats, None);
        forget_wallet_mint().await;
    }

    #[tokio::test]
    // The globals lock must span the calls it guards.
    #[allow(clippy::await_holding_lock)]
    async fn status_is_answerable_on_any_node_and_reports_disconnected() {
        // Arrange
        let _g = escrow_lock();
        forget_wallet_mint().await;

        // Act — status is deliberately ungated: the UI asks before it knows
        // anything, and "not connected" is truthful everywhere.
        let status = cashu_status().await.unwrap();

        // Assert — a disconnected wallet holds nothing, and that is a *known*
        // zero rather than an unreadable balance.
        assert!(!status.connected);
        assert_eq!(status.balance_sats, Some(0));
        assert_eq!(status.mint_url, None);
    }

    #[test]
    fn mints_are_compared_in_the_daemons_canonical_form() {
        // The wallet's mint against the one asked for, the node's, or an
        // order's: the same mint can arrive spelled two ways.
        let mint = "https://mint.example.com";

        assert!(same_mint(mint, Some(mint)));
        // Trailing slashes are a formatting difference, not a different mint.
        assert!(same_mint(mint, Some("https://mint.example.com/")));
        assert!(same_mint("https://mint.example.com/", Some(mint)));
        // So are host case and a default port: the node lists a mint as
        // configured, and publishes an order's mint canonicalised.
        assert!(same_mint(mint, Some("HTTPS://Mint.Example.com:443/")));
        assert!(same_mint(
            "http://Mint.example.com:80",
            Some("http://mint.example.com")
        ));
        // A port that is not the default is a different mint.
        assert!(!same_mint(mint, Some("https://mint.example.com:8443")));

        // Another host is another mint.
        assert!(!same_mint(mint, Some("https://other.example.com")));
        // No mint to compare against is never a match.
        assert!(!same_mint(mint, None));
    }

    #[tokio::test]
    async fn disconnect_is_idempotent_and_notifies() {
        // Arrange
        let _g = escrow_lock();
        let mut stream = on_cashu_wallet_changed();

        // Act — disconnecting a wallet that never existed must not error: this
        // runs on every node switch.
        cashu_disconnect().await.unwrap();

        // Assert
        let status = stream.next().await.unwrap();
        assert!(!status.connected);
    }

    /// A trade as the app stores it, with the two fields that decide whether an
    /// escrow can be built at all.
    fn seller_trade(
        order_id: &str,
        buyer_trade_pubkey: Option<&str>,
        counterparty_pubkey: &str,
    ) -> crate::api::types::TradeInfo {
        use crate::api::types::*;
        TradeInfo {
            id: order_id.to_string(),
            order: OrderInfo {
                id: order_id.to_string(),
                kind: OrderKind::Buy,
                status: OrderStatus::WaitingPayment,
                amount_sats: Some(10_000),
                fiat_amount: None,
                fiat_amount_min: None,
                fiat_amount_max: None,
                fiat_code: "USD".to_string(),
                payment_method: "cash".to_string(),
                premium: 0.0,
                creator_pubkey: counterparty_pubkey.to_string(),
                created_at: 0,
                expires_at: None,
                is_mine: false,
                rating: 0.0,
                total_reviews: 0,
                days_active: 0,
                maker_since: None,
                cashu_mint_url: None,
            },
            role: TradeRole::Seller,
            counterparty_pubkey: counterparty_pubkey.to_string(),
            current_step: TradeStep::Seller(SellerStep::TakerFound),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 1,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 0,
            completed_at: None,
            outcome: None,
            buyer_trade_pubkey: buyer_trade_pubkey.map(str::to_string),
            seller_trade_pubkey: None,
            cashu_mint_url: None,
            cashu_escrow_token: None,
            cashu_locked_at: None,
            cashu_rejected_escrow_tokens: Vec::new(),
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            peer_since: None,
            rated_at: None,
            bond: None,
        }
    }

    /// The app database, shared by the tests that read and write trade rows.
    async fn store() -> &'static impl crate::db::Storage {
        let path =
            std::env::temp_dir().join(format!("mostro_cashu_escrow_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        crate::db::app_db::db().expect("store initialised")
    }

    /// A seller row with an escrow already recorded, as `lock_escrow` leaves it
    /// between the swap and the daemon's answer.
    async fn recorded_escrow(order_id: &str) -> &'static impl crate::db::Storage {
        let db = store().await;
        let mut trade = seller_trade(order_id, Some("02"), "");
        trade.cashu_escrow_token = Some(format!("cashuB-{order_id}"));
        db.save_trade(&trade).await.unwrap();
        db
    }

    #[tokio::test]
    async fn a_resubmission_refused_by_status_is_not_claimed_as_locked() {
        // Arrange — the order is no longer waiting for the escrow: past
        // active, or closed while this device was offline. The wire does not
        // say which, so nothing may report the escrow as live.
        let order_id = uuid::Uuid::new_v4().to_string();
        let db = recorded_escrow(&order_id).await;

        // Act
        let err = settle_escrow_rejection(&order_id, "InvalidOrderStatus", true)
            .await
            .unwrap_err();

        // Assert — its own marker, and the token stays on record.
        assert_eq!(err.to_string(), "CashuEscrowOrderMovedOn");
        let row = db.get_trade_by_order_id(&order_id).await.unwrap().unwrap();
        assert_eq!(row.cashu_escrow_token, Some(format!("cashuB-{order_id}")));
    }

    #[tokio::test]
    async fn an_escrow_that_could_not_be_recorded_is_still_found_by_the_retry() {
        // Arrange — the swap happened but the row could not be written: the
        // token is held for the process instead, with the mint it lives at.
        let order_id = uuid::Uuid::new_v4().to_string();
        hold_unrecorded_escrow(&order_id, "https://mint.a", "cashuB-held");

        // Act — the retry looks before it builds.
        let found = recorded_or_held_escrow(&order_id, None);

        // Assert — the held token at its own mint, never a second swap.
        assert_eq!(
            found,
            Some(("https://mint.a".to_string(), "cashuB-held".to_string()))
        );
        // A recorded token wins over a held one, with the mint it was locked at.
        assert_eq!(
            recorded_or_held_escrow(&order_id, Some(("https://mint.b", "cashuB-row"))),
            Some(("https://mint.b".to_string(), "cashuB-row".to_string()))
        );
        forget_held_escrow(&order_id);
        assert_eq!(recorded_or_held_escrow(&order_id, None), None);
    }

    #[tokio::test]
    // The globals lock must span the call it guards; nothing else in this
    // test awaits on it.
    #[allow(clippy::await_holding_lock)]
    async fn a_cashu_node_without_a_single_mint_says_so_rather_than_not_cashu() {
        // Arrange — the node runs Cashu (override) and pins no mint, as an
        // open node or one that accepts several: routing sends the seller to
        // the escrow screen, which must explain why it cannot lock, not claim
        // the node is not Cashu.
        let _g = escrow_lock();
        escrow_mode::set_overrides(escrow_mode::EscrowOverrides {
            mode: escrow_mode::EscrowModeOverride::ForceCashu,
            mint_url: None,
        });

        // Act
        let err = lock_escrow("any-order".to_string()).await.unwrap_err();

        // Assert
        assert_eq!(err.to_string(), "CashuMintNotSupported");
    }

    #[tokio::test]
    // The globals lock must span the calls it guards.
    #[allow(clippy::await_holding_lock)]
    async fn an_order_on_another_mint_is_refused_before_any_swap() {
        // Arrange — a single-mint node, and an order that names another mint
        // (mostro#1047): a token locked at the wallet's mint would be refused
        // only after the swap.
        let _g = escrow_lock();
        escrow_mode::set_from_tags(
            escrow_mode::EscrowMode::Cashu,
            escrow_mode::CashuNodeConfig {
                mint_urls: vec!["https://mint.a.com".to_string()],
                ..Default::default()
            },
        );
        let order_id = uuid::Uuid::new_v4().to_string();
        let db = store().await;
        let mut trade = seller_trade(&order_id, Some("02"), "");
        trade.order.cashu_mint_url = Some("https://mint.b.com".to_string());
        db.save_trade(&trade).await.unwrap();

        // Act
        let err = cashu_escrow_quote(order_id).await.unwrap_err();

        // Assert
        assert_eq!(err.to_string(), "CashuMintNotSupported");
    }

    #[tokio::test]
    async fn a_first_submission_refused_by_status_is_an_error() {
        let order_id = uuid::Uuid::new_v4().to_string();
        let _db = recorded_escrow(&order_id).await;

        let err = settle_escrow_rejection(&order_id, "InvalidOrderStatus", false)
            .await
            .unwrap_err();

        assert_eq!(err.to_string(), "CashuEscrowRejected: InvalidOrderStatus");
    }

    #[tokio::test]
    async fn a_token_the_daemon_will_never_accept_is_retired_not_lost() {
        // Arrange
        let order_id = uuid::Uuid::new_v4().to_string();
        let db = recorded_escrow(&order_id).await;

        // Act
        let err = settle_escrow_rejection(&order_id, "InvalidCashuToken", true)
            .await
            .unwrap_err();

        // Assert — the next attempt builds anew, and the rejected token is kept:
        // it is the seller's money until its locktime refunds it.
        assert_eq!(err.to_string(), "CashuEscrowRejected: InvalidCashuToken");
        let row = db.get_trade_by_order_id(&order_id).await.unwrap().unwrap();
        assert_eq!(row.cashu_escrow_token, None);
        assert_eq!(
            row.cashu_rejected_escrow_tokens,
            vec![format!("cashuB-{order_id}")]
        );
    }

    #[tokio::test]
    async fn a_transient_refusal_keeps_the_token_for_the_retry() {
        // Arrange — the mint was unreachable when the daemon checked.
        let order_id = uuid::Uuid::new_v4().to_string();
        let db = recorded_escrow(&order_id).await;

        // Act
        let err = settle_escrow_rejection(&order_id, "CashuMintUnavailable", false)
            .await
            .unwrap_err();

        // Assert — the retry re-sends this token; no second swap.
        assert_eq!(err.to_string(), "CashuEscrowRejected: CashuMintUnavailable");
        let row = db.get_trade_by_order_id(&order_id).await.unwrap().unwrap();
        assert_eq!(row.cashu_escrow_token, Some(format!("cashuB-{order_id}")));
        assert!(row.cashu_rejected_escrow_tokens.is_empty());
    }

    #[tokio::test]
    async fn escrow_operations_on_one_order_are_serialized() {
        // Arrange — two attempts on the same order, one on another.
        let a = escrow_op_lock("order-a");
        let also_a = escrow_op_lock("order-a");
        let b = escrow_op_lock("order-b");

        // Act — the first holds its order.
        let _held = a.lock().await;

        // Assert — the second attempt on it waits; the other order does not.
        assert!(also_a.try_lock().is_err());
        assert!(b.try_lock().is_ok());
    }

    #[test]
    fn the_locktime_clears_the_daemons_floor() {
        // Arrange — the daemon's floor is `now + locktime_days`, evaluated when
        // it validates, which is later than ours by the publish delay.
        let days = 15u32;
        let ours = now_secs().unwrap()
            + u64::from(days) * SECONDS_PER_DAY
            + LOCKTIME_SUBMISSION_MARGIN_SECS;

        // Act — the daemon evaluates its floor some time later.
        let daemon_floor_later = now_secs().unwrap() + 60 + u64::from(days) * SECONDS_PER_DAY;

        // Assert — still above it. Matching the floor exactly made every lock a
        // race against the network, lost with the funds already swapped.
        assert!(
            ours > daemon_floor_later,
            "locktime {ours} must clear a floor evaluated a minute later ({daemon_floor_later})"
        );
    }

    #[test]
    fn the_proof_store_needs_an_initialised_database() {
        // Arrange / Act — with no app DB there is nowhere to put the store,
        // and guessing a path would create one the user never sees.
        //
        // Asked of the pure helper rather than of `proof_store_path()`: the
        // path behind it is a process-wide `OnceLock`, and other tests in this
        // binary (`api::escrow`, `api::reputation`) call `init_db`, so the
        // global answer depends on which test ran first.
        let err = sibling_store_path(None, LEGACY_STORE_NAME).unwrap_err();

        // Assert
        assert!(
            err.to_string().contains("CashuStoreUnavailable"),
            "got {err}"
        );
    }

    #[test]
    fn the_proof_store_sits_next_to_the_app_database() {
        // Arrange / Act / Assert — a native path gets a sibling file, never a
        // second schema inside the app's own database.
        assert_eq!(
            sibling_store_path(Some("/data/app/mostro.sqlite"), "cashu-ab.sqlite").unwrap(),
            "/data/app/cashu-ab.sqlite"
        );

        // On web `init_db` is given an IndexedDB *name*, which has no parent
        // directory. Joining onto `""` would put a stray relative file next to
        // the process's cwd, so the bare name is used instead.
        assert_eq!(
            sibling_store_path(Some("mostro"), "cashu-ab.sqlite").unwrap(),
            "cashu-ab.sqlite"
        );
    }

    #[test]
    fn each_identity_has_its_own_proof_store() {
        // cdk keys proofs by mint, not by seed: a shared store would hand one
        // user's bearer proofs to the next at the same mint.
        assert_ne!(identity_store_name("aa"), identity_store_name("bb"));
        assert_ne!(identity_store_name("aa"), LEGACY_STORE_NAME);
    }

    #[test]
    fn only_the_identity_loaded_at_the_upgrade_takes_the_shared_store() {
        // The first load after the upgrade records its owner and takes it.
        assert_eq!(legacy_store_decision(None, "a", true), (true, true));
        // A wallet open never claims an unowned store.
        assert_eq!(legacy_store_decision(None, "a", false), (false, false));
        // The owner takes it at any later load or open; nobody else ever does,
        // even after switching identities before the move completed.
        assert_eq!(legacy_store_decision(Some("a"), "a", false), (false, true));
        assert_eq!(legacy_store_decision(Some("a"), "b", true), (false, false));
    }

    /// A temporary directory holding an older install's shared store.
    fn shared_store_dir() -> (std::path::PathBuf, impl Fn(&str) -> String) {
        let dir = std::env::temp_dir().join(format!("mostro_cashu_move_{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let root = dir.clone();
        (dir, move |name: &str| {
            root.join(name).to_string_lossy().into_owned()
        })
    }

    #[test]
    fn the_shared_store_moves_with_its_wal() {
        // Arrange
        let (dir, path) = shared_store_dir();
        std::fs::write(path(LEGACY_STORE_NAME), b"proofs").unwrap();
        std::fs::write(format!("{}-wal", path(LEGACY_STORE_NAME)), b"wal").unwrap();

        // Act
        move_legacy_store(&path(LEGACY_STORE_NAME), &path("cashu-a.sqlite")).unwrap();

        // Assert
        assert_eq!(std::fs::read(path("cashu-a.sqlite")).unwrap(), b"proofs");
        assert_eq!(
            std::fs::read(format!("{}-wal", path("cashu-a.sqlite"))).unwrap(),
            b"wal"
        );
        assert!(!std::path::Path::new(&path(LEGACY_STORE_NAME)).exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_move_cut_short_is_completed_by_the_next_attempt() {
        // Arrange — the WAL moved, then the app stopped before the main file.
        let (dir, path) = shared_store_dir();
        std::fs::write(path(LEGACY_STORE_NAME), b"proofs").unwrap();
        std::fs::write(format!("{}-wal", path("cashu-a.sqlite")), b"wal").unwrap();

        // Act
        move_legacy_store(&path(LEGACY_STORE_NAME), &path("cashu-a.sqlite")).unwrap();

        // Assert — the main file joins its WAL; nothing is left behind.
        assert_eq!(std::fs::read(path("cashu-a.sqlite")).unwrap(), b"proofs");
        assert_eq!(
            std::fs::read(format!("{}-wal", path("cashu-a.sqlite"))).unwrap(),
            b"wal"
        );
        assert!(!std::path::Path::new(&path(LEGACY_STORE_NAME)).exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_store_the_identity_already_has_is_never_merged() {
        let (dir, path) = shared_store_dir();
        std::fs::write(path(LEGACY_STORE_NAME), b"shared").unwrap();
        std::fs::write(path("cashu-a.sqlite"), b"own").unwrap();

        move_legacy_store(&path(LEGACY_STORE_NAME), &path("cashu-a.sqlite")).unwrap();

        assert_eq!(std::fs::read(path("cashu-a.sqlite")).unwrap(), b"own");
        assert_eq!(std::fs::read(path(LEGACY_STORE_NAME)).unwrap(), b"shared");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
