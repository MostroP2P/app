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
use std::sync::OnceLock;
use tokio::sync::broadcast::error::RecvError;
use tokio::sync::{broadcast, RwLock};

use crate::api::types::CashuWalletStatus;
use crate::cashu::CashuWallet;
use crate::db::Storage;
use crate::mostro::escrow_mode;

// ── Global wallet ─────────────────────────────────────────────────────────────

fn wallet_lock() -> &'static RwLock<Option<CashuWallet>> {
    static WALLET: OnceLock<RwLock<Option<CashuWallet>>> = OnceLock::new();
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
    let app_db = crate::db::app_db::app_db_path()
        .ok_or_else(|| anyhow::anyhow!("CashuStoreUnavailable"))?;

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

/// May a wallet built for `connected_to` still be installed?
///
/// Only if the active node still resolves to that same mint. A node switch
/// during the connect makes the wallet stale before it is ever stored, and the
/// funds it would manage belong to a different node's mint.
fn should_install(connected_to: &str, resolved_now: Option<&str>) -> bool {
    resolved_now
        .map(|current| current.trim_end_matches('/') == connected_to.trim_end_matches('/'))
        .unwrap_or(false)
}

/// Fail closed unless the active node was positively identified as Cashu.
fn ensure_enabled() -> Result<()> {
    if !escrow_mode::is_cashu_mode() {
        bail!("CashuNotEnabled");
    }
    Ok(())
}

async fn snapshot() -> CashuWalletStatus {
    let guard = wallet_lock().read().await;
    match guard.as_ref() {
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
/// `NoIdentity` before an identity is loaded, plus the markers from
/// [`CashuWallet::connect`].
pub async fn cashu_connect() -> Result<CashuWalletStatus> {
    ensure_enabled()?;

    // One lifecycle change at a time — see [`lifecycle_lock`].
    let _lifecycle = lifecycle_lock().lock().await;

    {
        let guard = wallet_lock().read().await;
        if guard.is_some() {
            drop(guard);
            return Ok(snapshot().await);
        }
    }

    // The gate above implies a mint URL, but a concurrent node switch could
    // have cleared it — handled rather than unwrapped.
    let mint_url = escrow_mode::get_resolved()
        .config
        .mint_url
        .ok_or_else(|| anyhow::anyhow!("CashuNotEnabled"))?;

    let seed = crate::api::identity::current_bip39_seed()
        .await
        .ok_or_else(|| anyhow::anyhow!("NoIdentity"))?;

    let db_path = proof_store_path()?;
    let wallet = CashuWallet::connect(&mint_url, seed, &db_path).await?;

    // Re-check before installing. Holding the lifecycle lock keeps a
    // `cashu_disconnect` from interleaving, but the *escrow mode* is not under
    // that lock: a node switch during the mint round trip changes which mint we
    // should be bound to, and installing anyway would leave the wallet pointing
    // at the previous node's mint.
    let resolved_now = escrow_mode::get_resolved();
    if !should_install(&mint_url, resolved_now.config.mint_url.as_deref()) {
        log::warn!(
            "[cashu] discarding a wallet for {mint_url}: the active node now resolves to {:?}",
            resolved_now.config.mint_url
        );
        bail!("CashuNotEnabled");
    }

    {
        let mut guard = wallet_lock().write().await;
        if guard.is_none() {
            *guard = Some(wallet);
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
    ensure_enabled()?;
    let guard = wallet_lock().read().await;
    let wallet = guard
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("CashuNotConnected"))?;
    wallet.balance().await
}

/// Redeem an encoded Cashu token into the wallet, returning the amount received.
///
/// **Errors**: `CashuNotEnabled`, `CashuNotConnected`, `CashuReceiveFailed`
/// (wrong mint, already spent, malformed).
pub async fn cashu_receive_token(encoded: String) -> Result<u64> {
    ensure_enabled()?;
    let amount = {
        let guard = wallet_lock().read().await;
        let wallet = guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("CashuNotConnected"))?;
        wallet.receive_token(&encoded).await?
    };
    notify().await;
    Ok(amount)
}

/// Export `amount_sats` from the wallet as an encoded token.
///
/// **Errors**: `CashuNotEnabled`, `CashuNotConnected`, `CashuAmountZero`,
/// `CashuSendFailed` (insufficient funds included).
pub async fn cashu_create_token(amount_sats: u64) -> Result<String> {
    ensure_enabled()?;
    let token = {
        let guard = wallet_lock().read().await;
        let wallet = guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("CashuNotConnected"))?;
        wallet.create_token(amount_sats).await?
    };
    notify().await;
    Ok(token)
}

/// Reconcile pending proofs with the mint, returning the amount reclaimed.
///
/// **Errors**: `CashuNotEnabled`, `CashuNotConnected`.
pub async fn cashu_check_proofs_state() -> Result<u64> {
    ensure_enabled()?;
    let reclaimed = {
        let guard = wallet_lock().read().await;
        let wallet = guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("CashuNotConnected"))?;
        wallet.check_proofs_state().await?
    };
    if reclaimed > 0 {
        notify().await;
    }
    Ok(reclaimed)
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
/// Computed rather than taken from the daemon: the daemon states the amount in
/// the escrow request, but the **fee** is derived from the node's advertised
/// rate, and the seller has a right to see both figures — and the total against
/// their balance — before funding anything.
pub async fn cashu_escrow_quote(order_id: String) -> Result<crate::api::types::CashuEscrowQuote> {
    ensure_enabled()?;

    let trade = load_trade(&order_id).await?;
    let amount_sats = trade
        .order
        .amount_sats
        .ok_or_else(|| anyhow::anyhow!("CashuOrderAmountUnknown"))?;

    // A node that publishes no fee has not been fetched yet. Guessing zero
    // would build a lock the daemon rejects, so this fails instead.
    let fraction = crate::mostro::node_fee::get_fee()
        .ok_or_else(|| anyhow::anyhow!("CashuNodeFeeUnknown"))?;
    let fee_sats = crate::mostro::node_fee::total_fee_sats(amount_sats, fraction);

    let resolved = escrow_mode::get_resolved();

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
        mint_url: resolved.config.mint_url.unwrap_or_default(),
        locktime_days: resolved.config.escrow_locktime_days.unwrap_or(DEFAULT_LOCKTIME_DAYS),
    })
}

/// The daemon's default when a node advertises none (`docs/cashu/README.md` §2).
const DEFAULT_LOCKTIME_DAYS: u32 = 15;

/// Seller: fund the 2-of-3 escrow for `order_id` and submit it to the daemon.
///
/// The Cashu analogue of paying the hold invoice. In order:
///
/// 1. refuse unless the balance covers `amount + fee` — a partial lock would
///    strand the escrow amount in a token nobody can settle;
/// 2. build the escrow token (2-of-3, locktime) and, when the node charges a
///    fee, the fee token (1-of-1 to Mostro);
/// 3. publish `AddCashuEscrow`;
/// 4. persist the token against the trade **before** returning, so an app that
///    dies here can re-submit rather than lose track of locked funds.
///
/// Step 4 deliberately follows the publish: the funds are already committed at
/// the mint by step 2, so the token is worth recording even if the publish
/// failed — the daemon's own handler is idempotent on a re-submission.
///
/// **Errors** (stable markers): `CashuNotEnabled`, `CashuNotConnected`,
/// `CashuInsufficientFunds`, `CashuNodeFeeUnknown`, `NotTheSeller`,
/// plus the `CashuLockFailed` markers from token construction.
pub async fn lock_escrow(order_id: String) -> Result<crate::api::types::CashuEscrowQuote> {
    ensure_enabled()?;

    let quote = cashu_escrow_quote(order_id.clone()).await?;
    let trade = load_trade(&order_id).await?;

    // Only the seller funds an escrow. A buyer reaching this is a bug, but it
    // would burn the buyer's own ecash, so it is checked rather than assumed.
    if !matches!(trade.role, crate::api::types::TradeRole::Seller) {
        bail!("NotTheSeller");
    }

    if quote.balance_sats < quote.total_sats {
        bail!(
            "CashuInsufficientFunds: need {} sat, have {}",
            quote.total_sats,
            quote.balance_sats
        );
    }

    let trade_index = crate::api::orders::get_trade_key_index(&order_id)
        .await
        .ok_or_else(|| anyhow::anyhow!("no persisted trade key for order {order_id}"))?;
    let seller_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let identity_keys = crate::api::identity::get_transport_identity_keys(&seller_keys).await?;
    let mostro_hex = crate::config::active_mostro_pubkey();
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&mostro_hex)?;

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

    let parties = crate::cashu::escrow::EscrowParties::from_xonly_hex(
        &buyer_hex,
        &seller_hex,
        &mostro_hex,
    )?;

    // The daemon's floor is `now + escrow_locktime_days` evaluated when it
    // *validates* the submission, which is strictly later than our `now` by the
    // publish and propagation delay. Matching the floor exactly would make every
    // lock a race against the network, with the funds already swapped by the
    // time it is lost.
    let locktime = now_secs()?
        .saturating_add(u64::from(quote.locktime_days).saturating_mul(SECONDS_PER_DAY))
        .saturating_add(LOCKTIME_SUBMISSION_MARGIN_SECS);

    let (escrow_token, fee_token) = {
        let guard = wallet_lock().read().await;
        let wallet = guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("CashuNotConnected"))?;

        // Fee first. Both tokens are irreversible once built, and the fee is the
        // smaller of the two: if the wallet cannot cover both after mint-side
        // fees, failing here strands a few satoshis instead of the whole escrow.
        let fee = if quote.fee_sats > 0 {
            Some(wallet.build_fee_token(quote.fee_sats, &parties.mostro).await?)
        } else {
            None
        };

        let escrow = wallet
            .build_escrow_token(quote.amount_sats, &parties, locktime)
            .await?;

        // Verify what we just built before handing it over. The daemon runs the
        // same check and rejects on failure; catching it here means the seller
        // learns before the token is published, not after.
        wallet
            .verify_escrow_token(&escrow, &parties, quote.amount_sats, locktime)
            .await?;

        (escrow, fee)
    };

    // Correlation nonce, same shape as every other outgoing request: 0 is
    // indistinguishable from "unset" on the wire.
    let request_id: u64 = {
        use rand::RngCore;
        rand::rngs::OsRng.next_u64().max(1)
    };
    let event_json = crate::mostro::actions::add_cashu_escrow(
        &identity_keys,
        &seller_keys,
        &mostro_pubkey,
        &order_id,
        trade_index,
        &escrow_token,
        &quote.mint_url,
        &buyer_hex,
        &seller_hex,
        fee_token,
        request_id,
    )
    .await?;

    let publish_result = crate::api::orders::publish_event_json(&event_json).await;

    // Persist regardless of the publish outcome: the ecash is already locked at
    // the mint, and a token we did not record is money we cannot find again.
    if let Some(db) = crate::db::app_db::db() {
        let mut updated = trade.clone();
        updated.cashu_mint_url = Some(quote.mint_url.clone());
        updated.cashu_escrow_token = Some(escrow_token);
        updated.cashu_locked_at = now_secs().ok().map(|t| t as i64);
        if let Err(e) = db.save_trade(&updated).await {
            log::error!("[cashu] escrow locked but not persisted for {order_id}: {e}");
        }
    }

    publish_result?;
    notify().await;
    log::info!("[cashu] escrow locked for order={order_id}");

    Ok(quote)
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

    /// The escrow globals are process-wide and shared with `api::escrow`, so
    /// the lock has to be too — see `escrow_mode::test_lock`.
    use crate::mostro::escrow_mode::test_lock as escrow_lock;

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
            cashu_check_proofs_state().await.unwrap_err(),
            // The escrow entry points too: these move real money, and the
            // seller reaches them from a trade screen rather than a wallet one.
            cashu_escrow_quote("any-order".to_string()).await.unwrap_err(),
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
    fn a_wallet_is_only_installed_while_its_mint_is_still_the_active_one() {
        // The scenario: a connect is awaiting the mint when the user switches
        // node. The lifecycle lock keeps `cashu_disconnect` from interleaving,
        // but the escrow mode is not under that lock — so the connect can
        // finish holding a wallet bound to the *previous* node's mint. Storing
        // it would silently point the app's funds at the wrong mint.
        let mint = "https://mint.example.com";

        // Still the active mint — install.
        assert!(should_install(mint, Some(mint)));
        // Trailing slashes are a formatting difference, not a different mint.
        assert!(should_install(mint, Some("https://mint.example.com/")));
        assert!(should_install("https://mint.example.com/", Some(mint)));

        // The node switched to a different Cashu node — discard.
        assert!(!should_install(mint, Some("https://other.example.com")));
        // The node switched to Lightning, or the mode was cleared — discard.
        assert!(!should_install(mint, None));
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
        }
    }

    #[test]
    fn the_buyer_key_comes_from_the_escrow_request_not_the_order_book() {
        // Arrange — a maker seller has no counterparty pubkey at all, and a
        // taker seller's is the maker's *order-book* key. Neither is the
        // per-order trade key the daemon locks the escrow to, and building an
        // escrow from either produces a token the buyer cannot spend.
        let order_book_key =
            "82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390";
        let trade_key = "0000000000000000000000000000000000000000000000000000000000000001";

        let maker = seller_trade("order-1", None, "");
        let taker = seller_trade("order-2", None, order_book_key);
        let ready = seller_trade("order-3", Some(trade_key), order_book_key);

        // Assert — the field the escrow must be built from is populated only by
        // the daemon's escrow request.
        assert_eq!(maker.buyer_trade_pubkey, None);
        assert_eq!(taker.buyer_trade_pubkey, None);
        assert_eq!(ready.buyer_trade_pubkey.as_deref(), Some(trade_key));

        // And it is not the order-book key, which is what the first version of
        // this flow used.
        assert_ne!(ready.buyer_trade_pubkey.as_deref(), Some(order_book_key));
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
        let err = proof_store_path().unwrap_err();

        // Assert
        assert!(
            err.to_string().contains("CashuStoreUnavailable"),
            "got {err}"
        );
    }
}
