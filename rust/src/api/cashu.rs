//! Cashu wallet surface for the UI — phase C2 of `docs/cashu/README.md`.
//!
//! Holds the single process-wide wallet, gates every entry point on the escrow
//! mode, and broadcasts changes so the UI never polls.
//!
//! **Nothing here runs on a Lightning node.** Every function returns
//! `CashuNotEnabled` unless [`crate::mostro::escrow_mode::is_cashu_mode`] is
//! true, which requires the active node to have advertised Cashu *and* a usable
//! mint. That gate is the whole reason this module is inert by default.
//!
//! Errors are stable markers (`CashuNotEnabled`, `CashuNotConnected`,
//! `CashuMintUnreachable`, …); Dart maps them to localized strings.

use anyhow::{bail, Result};
use std::sync::{Arc, OnceLock};
use tokio::sync::broadcast::error::RecvError;
use tokio::sync::{broadcast, RwLock};

use crate::api::types::CashuWalletStatus;
use crate::cashu::CashuWallet;
use crate::mostro::escrow_mode;

// ── Global wallet ─────────────────────────────────────────────────────────────

/// The wallet is held behind an `Arc` so callers can take a handle and drop the
/// lock before talking to the mint. Holding the read guard across a round trip
/// would park a waiting `cashu_disconnect` in tokio's write-preferring queue,
/// and every `cashu_status` behind it — a frozen screen for as long as the mint
/// takes to answer.
fn wallet_lock() -> &'static RwLock<Option<Arc<CashuWallet>>> {
    static WALLET: OnceLock<RwLock<Option<Arc<CashuWallet>>>> = OnceLock::new();
    WALLET.get_or_init(|| RwLock::new(None))
}

fn changes() -> &'static broadcast::Sender<CashuWalletStatus> {
    static CHANGES: OnceLock<broadcast::Sender<CashuWalletStatus>> = OnceLock::new();
    CHANGES.get_or_init(|| broadcast::channel(32).0)
}

/// Where the proof store lives: a sibling of the app database, never inside it.
///
/// `cdk` owns that file's schema and migrations; mixing it into the app's would
/// put two migration systems on one file.
fn proof_store_path() -> Result<String> {
    sibling_store_path(crate::db::app_db::app_db_path())
}

/// The proof store that belongs next to `app_db`, or `CashuStoreUnavailable`
/// when the app database was never opened.
///
/// Split from [`proof_store_path`] so it can be tested on its argument instead
/// of on a process-wide `OnceLock` that any other test in this binary may have
/// set — two of them in `api::escrow` and `api::reputation` call `init_db`.
fn sibling_store_path(app_db: Option<&str>) -> Result<String> {
    let app_db = app_db.ok_or_else(|| anyhow::anyhow!("CashuStoreUnavailable"))?;

    // `init_db`'s argument is a filesystem path on native and an IndexedDB
    // *database name* on web. A name has no parent, and joining onto `""` would
    // silently produce a relative file next to the process's cwd — so the two
    // cases are separated rather than left to `Path` semantics.
    let parent = std::path::Path::new(app_db)
        .parent()
        .filter(|p| !p.as_os_str().is_empty());

    Ok(match parent {
        Some(dir) => dir.join("cashu.sqlite").to_string_lossy().into_owned(),
        None => "cashu.sqlite".to_string(),
    })
}

/// Serializes wallet lifecycle changes: connect and disconnect.
///
/// Without it two connects both open the proof store and both hit the mint, and
/// — worse — a disconnect issued during a connect clears an empty slot which the
/// connect then fills, rebinding a wallet the caller just dropped.
fn lifecycle_lock() -> &'static tokio::sync::Mutex<()> {
    static LIFECYCLE: OnceLock<tokio::sync::Mutex<()>> = OnceLock::new();
    LIFECYCLE.get_or_init(|| tokio::sync::Mutex::new(()))
}

/// Is a wallet bound to `bound_to` still the right wallet for the active node?
///
/// Only if that node still resolves to the same mint. A node switch makes the
/// wallet stale — the funds it manages belong to the previous node's mint — and
/// that is true both of a wallet about to be installed and of one already
/// running, so both paths ask this question.
fn same_mint(bound_to: &str, resolved_now: Option<&str>) -> bool {
    resolved_now
        .map(|current| current.trim_end_matches('/') == bound_to.trim_end_matches('/'))
        .unwrap_or(false)
}

/// A handle to the live wallet, once it is established that it is the wallet
/// the *active* node should be using.
///
/// Every operating entry point goes through here rather than reading the lock
/// itself: `is_cashu_mode()` says the node speaks Cashu, not that it pins the
/// mint this wallet is bound to. Without the second check, switching node A → B
/// keeps spending and receiving at A's mint.
///
/// The `Arc` is cloned out and the guard dropped, so the mint round trip that
/// follows holds no lock.
///
/// **Errors**: `CashuNotEnabled`, `CashuNotConnected`, `CashuMintChanged`.
async fn active_wallet() -> Result<Arc<CashuWallet>> {
    ensure_enabled()?;

    let wallet = wallet_lock()
        .read()
        .await
        .clone()
        .ok_or_else(|| anyhow::anyhow!("CashuNotConnected"))?;

    let resolved = escrow_mode::get_resolved();
    if !same_mint(wallet.mint_url(), resolved.config.mint_url.as_deref()) {
        log::warn!(
            "[cashu] wallet is bound to {}, the active node resolves to {:?}",
            wallet.mint_url(),
            resolved.config.mint_url
        );
        bail!("CashuMintChanged");
    }

    Ok(wallet)
}

/// Fail closed unless the active node was positively identified as Cashu.
fn ensure_enabled() -> Result<()> {
    if !escrow_mode::is_cashu_mode() {
        bail!("CashuNotEnabled");
    }
    Ok(())
}

async fn snapshot() -> CashuWalletStatus {
    // Cloned out so the balance read below — which can reach the store — runs
    // with no lock held.
    let wallet = wallet_lock().read().await.clone();
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
        None => CashuWalletStatus {
            connected: false,
            mint_url: None,
            // Not connected is a known state, and a wallet with no binding
            // genuinely holds nothing spendable here.
            balance_sats: Some(0),
            missing_capabilities: Vec::new(),
        },
    }
}

async fn notify() {
    let _ = changes().send(snapshot().await);
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Connect the wallet to the mint the active node pins, unless already connected.
///
/// Lazy by design: nothing connects at startup, so a Lightning user never opens
/// a proof store or contacts a mint. Repeat calls are cheap — an already
/// connected wallet is returned as is rather than reconnected.
///
/// **Errors**: `CashuNotEnabled` when the node is not a usable Cashu node,
/// `NoIdentity` before an identity is loaded, `CashuNoMnemonic` for an
/// nsec-imported identity (there is no seed to derive), plus the markers from
/// [`CashuWallet::connect`].
pub async fn cashu_connect() -> Result<CashuWalletStatus> {
    ensure_enabled()?;

    // One lifecycle change at a time — see [`lifecycle_lock`].
    let _lifecycle = lifecycle_lock().lock().await;

    // An already connected wallet is reused — but only while it is still bound
    // to the mint the active node pins. After a node switch it is the previous
    // node's wallet, and returning it here would be the same stale-binding bug
    // the install check below guards against, just one call later.
    {
        let live = wallet_lock().read().await.clone();
        if let Some(wallet) = live {
            let resolved = escrow_mode::get_resolved();
            if same_mint(wallet.mint_url(), resolved.config.mint_url.as_deref()) {
                return Ok(snapshot().await);
            }
            log::info!(
                "[cashu] dropping the wallet bound to {}: the active node now resolves to {:?}",
                wallet.mint_url(),
                resolved.config.mint_url
            );
            *wallet_lock().write().await = None;
        }
    }

    // The gate above implies a mint URL, but a concurrent node switch could
    // have cleared it — handled rather than unwrapped.
    let mint_url = escrow_mode::get_resolved()
        .config
        .mint_url
        .ok_or_else(|| anyhow::anyhow!("CashuNotEnabled"))?;

    let seed = crate::api::identity::current_bip39_seed().await?;

    let db_path = proof_store_path()?;
    let wallet = CashuWallet::connect(&mint_url, seed, &db_path).await?;

    // Re-check before installing. Holding the lifecycle lock keeps a
    // `cashu_disconnect` from interleaving, but the *escrow mode* is not under
    // that lock: a node switch during the mint round trip changes which mint we
    // should be bound to, and installing anyway would leave the wallet pointing
    // at the previous node's mint.
    let resolved_now = escrow_mode::get_resolved();
    if !same_mint(&mint_url, resolved_now.config.mint_url.as_deref()) {
        log::warn!(
            "[cashu] discarding a wallet for {mint_url}: the active node now resolves to {:?}",
            resolved_now.config.mint_url
        );
        bail!("CashuNotEnabled");
    }

    {
        let mut guard = wallet_lock().write().await;
        if guard.is_none() {
            *guard = Some(Arc::new(wallet));
        }
    }

    notify().await;
    Ok(snapshot().await)
}

/// Current wallet status. Safe to call on any node — a Lightning node simply
/// reports "not connected".
pub async fn cashu_status() -> Result<CashuWalletStatus> {
    Ok(snapshot().await)
}

/// Spendable balance in satoshis.
///
/// **Errors**: `CashuNotEnabled`, `CashuNotConnected`.
pub async fn cashu_get_balance() -> Result<u64> {
    active_wallet().await?.balance().await
}

/// Redeem an encoded Cashu token into the wallet, returning the amount received.
///
/// **Errors**: `CashuNotEnabled`, `CashuNotConnected`, `CashuReceiveFailed`
/// (wrong mint, already spent, malformed).
pub async fn cashu_receive_token(encoded: String) -> Result<u64> {
    let amount = active_wallet().await?.receive_token(&encoded).await?;
    notify().await;
    Ok(amount)
}

/// Export `amount_sats` from the wallet as an encoded token.
///
/// **Errors**: `CashuNotEnabled`, `CashuNotConnected`, `CashuAmountZero`,
/// `CashuSendFailed` (insufficient funds included).
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
/// **Errors**: `CashuNotEnabled`, `CashuNotConnected`, `CashuMintChanged`.
pub async fn cashu_sweep_spent_proofs() -> Result<()> {
    active_wallet().await?.sweep_spent_proofs().await?;
    notify().await;
    Ok(())
}

/// Drop the in-memory wallet. Proofs stay on disk — this is a disconnect, not a
/// wipe. Called when the active node changes, so a wallet bound to one node's
/// mint never serves another's.
pub async fn cashu_disconnect() -> Result<()> {
    // Shares the lifecycle lock with `cashu_connect`, so a disconnect issued
    // during a connect waits for it and then clears the slot, instead of
    // clearing an empty slot and having the connect fill it back in.
    let _lifecycle = lifecycle_lock().lock().await;
    {
        let mut guard = wallet_lock().write().await;
        *guard = None;
    }
    notify().await;
    Ok(())
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

    #[tokio::test]
    async fn every_entry_point_is_shut_on_a_lightning_node() {
        // Arrange — the default state: nothing fetched, so not Cashu.
        let _g = escrow_lock();

        // Act / Assert — the gate is the whole safety story, so check every
        // door rather than trusting one of them.
        for err in [
            cashu_connect().await.unwrap_err(),
            cashu_get_balance().await.unwrap_err(),
            cashu_receive_token("cashuBanything".to_string())
                .await
                .unwrap_err(),
            cashu_create_token(1).await.unwrap_err(),
            cashu_sweep_spent_proofs().await.unwrap_err(),
        ] {
            assert!(
                err.to_string().contains("CashuNotEnabled"),
                "expected the gate to close, got {err}"
            );
        }
    }

    #[tokio::test]
    async fn status_is_answerable_on_any_node_and_reports_disconnected() {
        // Arrange
        let _g = escrow_lock();

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
    fn a_wallet_serves_only_the_node_whose_mint_it_is_bound_to() {
        // Two scenarios, one question. A connect awaiting the mint when the
        // user switches node would otherwise store a wallet bound to the
        // *previous* node's mint; an already-connected wallet would otherwise
        // keep serving that mint after the switch. Both ask this.
        let mint = "https://mint.example.com";

        // Still the active mint — keep it.
        assert!(same_mint(mint, Some(mint)));
        // Trailing slashes are a formatting difference, not a different mint.
        assert!(same_mint(mint, Some("https://mint.example.com/")));
        assert!(same_mint("https://mint.example.com/", Some(mint)));

        // The node switched to a different Cashu node — drop it.
        assert!(!same_mint(mint, Some("https://other.example.com")));
        // The node switched to Lightning, or the mode was cleared — drop it.
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

    #[test]
    fn the_proof_store_needs_an_initialised_database() {
        // Arrange / Act — with no app DB there is nowhere to put the store,
        // and guessing a path would create one the user never sees.
        //
        // Asked of the pure helper rather than of `proof_store_path()`: the
        // path behind it is a process-wide `OnceLock`, and other tests in this
        // binary (`api::escrow`, `api::reputation`) call `init_db`, so the
        // global answer depends on which test ran first.
        let err = sibling_store_path(None).unwrap_err();

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
            sibling_store_path(Some("/data/app/mostro.sqlite")).unwrap(),
            "/data/app/cashu.sqlite"
        );

        // On web `init_db` is given an IndexedDB *name*, which has no parent
        // directory. Joining onto `""` would put a stray relative file next to
        // the process's cwd, so the bare name is used instead.
        assert_eq!(sibling_store_path(Some("mostro")).unwrap(), "cashu.sqlite");
    }
}
