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
use crate::db::Storage;
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
    if escrow_mode::is_cashu_mode() {
        return Ok(());
    }
    // A Cashu node with no mint to reach: the seller is routed to the escrow
    // screen on the mode alone (there is no hold invoice on such a node), so
    // it must say what is missing rather than "not Cashu".
    if escrow_mode::get_resolved().mode.is_cashu() {
        bail!("CashuMintUnknown");
    }
    bail!("CashuNotEnabled")
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
/// **Errors**: `CashuNotEnabled`, `CashuOrderAmountUnknown`, `CashuMintUnknown`,
/// `CashuNotConnected`, `CashuBalanceUnknown`.
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
    // An escrow locked at the wrong mint is rejected only after the swap, so an
    // unknown mint fails here instead of defaulting to an empty URL.
    let mint_url = resolved
        .config
        .mint_url
        .filter(|url| !url.trim().is_empty())
        .ok_or_else(|| anyhow::anyhow!("CashuMintUnknown"))?;

    // Connect before reading the balance. An unconnected wallet reports zero,
    // and a quote that reports zero turns into "insufficient funds" on a wallet
    // that is fully funded — the screen connects first, but a retry from
    // anywhere else would not.
    cashu_connect().await?;

    let balance = {
        let guard = wallet_lock().read().await;
        match guard.as_ref() {
            Some(wallet) => wallet
                .balance()
                .await
                .map_err(|e| anyhow::anyhow!("CashuBalanceUnknown: {e}"))?,
            None => bail!("CashuNotConnected"),
        }
    };

    Ok(crate::api::types::CashuEscrowQuote {
        order_id,
        amount_sats,
        fee_sats,
        total_sats: amount_sats.saturating_add(fee_sats),
        balance_sats: balance,
        mint_url,
        locktime_days: resolved
            .config
            .escrow_locktime_days
            .unwrap_or(PROTOCOL_DEFAULT_LOCKTIME_DAYS),
        pending_submission: trade.cashu_escrow_token.is_some(),
    })
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
/// `CashuMintUnknown`, `CashuInsufficientFunds`, `NotTheSeller`,
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
        .mint_url
        .unwrap_or_default();
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

    let guard = wallet_lock().read().await;
    let wallet = guard
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("CashuNotConnected"))?;
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
            // The escrow entry points too: these move real money, and the
            // seller reaches them from a trade screen rather than a wallet one.
            cashu_escrow_quote("any-order".to_string())
                .await
                .unwrap_err(),
            lock_escrow("any-order".to_string()).await.unwrap_err(),
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
    async fn a_cashu_node_without_a_mint_says_so_rather_than_not_cashu() {
        // Arrange — the node runs Cashu (override) but names no mint: routing
        // sends the seller to the escrow screen, which must explain why it
        // cannot lock, not claim the node is not Cashu.
        let _g = escrow_lock();
        escrow_mode::set_overrides(escrow_mode::EscrowOverrides {
            mode: escrow_mode::EscrowModeOverride::ForceCashu,
            mint_url: None,
        });

        // Act
        let err = lock_escrow("any-order".to_string()).await.unwrap_err();

        // Assert
        assert_eq!(err.to_string(), "CashuMintUnknown");
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
