# Trade Execution Specification (Mostro Mobile v1)

> Detailed reference for section 5 (TRADE EXECUTION) based on the real Flutter/Dart implementation.

## Scope

This document covers:

- Routes `/pay_invoice/:orderId`, `/add_invoice/:orderId`, `/trade_detail/:orderId`
- Screens `PayLightningInvoiceScreen`, `AddLightningInvoiceScreen`, `TradeDetailScreen`
- Protocol actions involved: `pay-invoice`, `add-invoice`, `hold-invoice-payment-accepted`, `fiat-sent`, `fiat-sent-ok`, `release`, `purchase-completed`, `dispute`
- Status transitions and role-based button availability (`OrderState`, `MostroFSM`)
- Hold-invoice mechanics (NWC auto-pay, manual fallback, retries)
- Real-time updates via notifiers, session handling, error and timeout behavior

---

## Source files reviewed

### Screens & widgets
- `lib/features/order/screens/pay_lightning_invoice_screen.dart`
- `lib/shared/widgets/nwc_payment_widget.dart`
- `lib/shared/widgets/pay_lightning_invoice_widget.dart`
- `lib/features/order/screens/add_lightning_invoice_screen.dart`
- `lib/shared/widgets/nwc_invoice_widget.dart`
- `lib/shared/widgets/ln_address_confirmation_widget.dart`
- `lib/features/trades/screens/trade_detail_screen.dart`
- `lib/features/trades/widgets/trades_list.dart`
- `lib/features/trades/widgets/trades_list_item.dart`

### State, notifiers & services
- `lib/features/order/notifiers/order_notifier.dart`
- `lib/features/order/notifiers/abstract_mostro_notifier.dart`
- `lib/features/order/models/order_state.dart`
- `lib/core/mostro_fsm.dart`
- `lib/data/models/enums/action.dart`
- `lib/data/models/enums/status.dart`
- `lib/shared/providers/session_notifier_provider.dart`
- `lib/shared/providers/order_repository_provider.dart`
- `lib/services/mostro_service.dart`

---

## 1) Trade Execution entry points

### GoRouter configuration (`lib/core/app_routes.dart`)

| Route | Builder | Scenario |
| --- | --- | --- |
| `/pay_invoice/:orderId` | `PayLightningInvoiceScreen(orderId)` | Seller has to pay the hold invoice emitted after `take-buy`. |
| `/add_invoice/:orderId` | `AddLightningInvoiceScreen(orderId, lnAddress)` | Buyer has to provide their invoice (or confirm a Lightning Address) after `take-sell`. |
| `/trade_detail/:orderId` | `TradeDetailScreen(orderId)` | Central view for both roles while the trade is active (actions, countdown, chat). |

### How users arrive here

1. **Mostro events → automatic navigation** (`AbstractMostroNotifier.handleEvent`):
   - `Action.payInvoice` → `navProvider.go('/pay_invoice/$orderId')` for the seller.
   - `Action.addInvoice` / `Action.waitingBuyerInvoice` → `navProvider.go('/add_invoice/$orderId')` for the buyer (with `?lnAddress=` when defaults exist).
   - `Action.holdInvoicePaymentSettled`, `Action.released`, `Action.fiatSentOk`, dispute/admin events → `navProvider.go('/trade_detail/$orderId')` to keep both counterparts in sync.
2. **Manual taps** from `TradeDetailScreen` ("Pay invoice", "Add invoice", "Contact") call `context.push(...)` to the same routes.
3. **Deep links/notifications** reuse the same routes through `GoRouter`.

---

## 2) Seller flow — `PayLightningInvoiceScreen`

File: `lib/features/order/screens/pay_lightning_invoice_screen.dart`

- Watches `orderNotifierProvider(orderId)` to fetch `paymentRequest.lnInvoice`, sats (`order.amount`), and fiat info (`order.fiatAmount`, `order.fiatCode`).
- Uses `nwcProvider` to detect NWC connectivity and `_manualMode` to switch UI modes.

### NWC auto-pay

```dart
final showNwcPayment = isNwcConnected && !_manualMode && lnInvoice.isNotEmpty;
```

If `true`, the screen renders:

1. A summary text with fiat/sats amounts.
2. `NwcPaymentWidget` to send the hold invoice automatically.
   - `onPaymentSuccess`: `context.go('/')` and wait for Mostro to emit `hold-invoice-payment-accepted` (which will open `TradeDetail`).
   - `onFallbackToManual`: sets `_manualMode = true` to reveal the manual UI.
3. A red **Cancel** button calling `orderNotifier.cancelOrder()` followed by `context.go('/')`.

### Manual payment mode

When NWC is not connected or the user opts out:

- Displays `PayLightningInvoiceWidget` (QR + actions + copy buttons).
- `onSubmit`: once the user confirms the payment, navigate to `/` and let Mostro update the state.
- `onCancel`: same as above, invokes `cancelOrder()` before leaving.

### State notes

- If the `PaymentRequest` has not arrived yet, the UI remains empty (Mostro will resend `pay-invoice` once ready).
- `OrderState.status` stays in `waiting-payment` during this phase (see `OrderState._getStatusFromAction`).

---

## 3) Buyer flow — `AddLightningInvoiceScreen`

File: `lib/features/order/screens/add_lightning_invoice_screen.dart`

- Streams the latest order payload via `mostroOrderStreamProvider(orderId)` (amount, fiat data, methods).
- Reads `nwcProvider` and `settingsProvider` to decide between Lightning Address confirmation, NWC invoice generation, or manual entry.

### Priority ladder

1. **Lightning Address confirmation** (route param or default setting):
   - Renders `LnAddressConfirmationWidget` with `S.of(context)!.lnAddressConfirmHeader(orderId)`.
   - `onConfirm` → `_submitLnAddress()` → `orderNotifier.sendInvoice(orderId, lnAddress, null)` → `context.go('/')`.
   - `onManualFallback` → `_manualMode = true`.
2. **NWC invoice generation** (wallet connected, no LN address, amount > 0):
   - Uses `NwcInvoiceWidget` to create an invoice in the wallet.
   - `onInvoiceConfirmed(invoice)` → `_submitInvoice(invoice, amount)`.
   - `onFallbackToManual` → `_manualMode = true`.
3. **Manual entry** (`AddLightningInvoiceWidget`):
   - `onSubmit`: validates `invoiceController.text`, then `orderNotifier.sendInvoice`.
   - `onCancel`: `orderNotifier.cancelOrder()` and stay on `/`.

### Payment failure retries

- `AbstractMostroNotifier._handleAddInvoiceWithAutoLightningAddress` prevents auto Lightning Address usage when `state.status == Status.paymentFailed`; the user must re-enter the invoice manually.
- Errors are surfaced via `SnackBarHelper.showTopSnackBar` with `failedToUpdateInvoice` messages.

---

## 4) `TradeDetailScreen` — central trade view

File: `lib/features/trades/screens/trade_detail_screen.dart`

### Data sources

- `orderNotifierProvider(orderId)` → `OrderState` (status, last action, payment request, dispute, peer).
- `sessionProvider(orderId)` → user role (`Role.buyer` or `Role.seller`).
- `eventProvider(orderId)` → public order metadata (premium, fiat range, etc.).
- `orderRepositoryProvider` → `MostroInstance` (`expirationHours`) for countdown timers.
- `orderMessagesStreamProvider(orderId)` → feed for `MostroMessageDetail`.

### Layout

1. Amount & order ID cards (`_buildSellerAmount`, `OrderIdCard`).
2. Either creator reputation info (pending maker) or `MostroMessageDetail`.
3. `_CountdownWidget` (pending / waiting states, color-coded as time elapses).
4. Button row = `_buildActionButtons` + `_buildButtonRow`:
   - Pulls allowed actions from `OrderState.getActions(session.role)`.
   - Each button = `MostroReactiveButton`, which listens to `mostroMessageStreamProvider` to stop the spinner or show success.

Example button:

```dart
MostroReactiveButton(
  label: S.of(context)!.payInvoiceButton,
  action: actions.Action.payInvoice,
  backgroundColor: AppTheme.mostroGreen,
  orderId: orderId,
  onPressed: () => context.push('/pay_invoice/$orderId'),
)
```

### Key actions by role

| UI Action | Role | Required status | Callback |
| --- | --- | --- | --- |
| **Pay invoice** | Seller | `Status.waitingPayment` and `paymentRequest` present | `context.push('/pay_invoice/:id')` |
| **Add invoice** | Buyer | `Status.waitingBuyerInvoice` | `context.push('/add_invoice/:id')` |
| **Fiat sent** | Buyer | `Status.active` | `orderNotifier.sendFiatSent()` |
| **Release** | Seller | `Status.fiatSent` (or `active` if FSM allows) | Confirm dialog → `orderNotifier.releaseOrder()` |
| **Cancel** | Both | Depends on status/action | Confirm dialog → `orderNotifier.cancelOrder()` |
| **Dispute** | Both | `Status.active` / `fiatSent` / `dispute` | Confirm dialog → `disputeRepositoryProvider.createDispute(orderId)` |
| **Contact** | Both | Cooperative cancel/dispute contexts | `context.push('/chat_room/:id')` |

Additional buttons:
- `VIEW DISPUTE` appears whenever the last action is `dispute-*` or `admin-took-dispute` and `tradeState.dispute?.disputeId` exists.
- `Status.cooperativelyCanceled` forces the "Contact" button even if `send-dm` is not part of the action set.

---

## 5) Action ↔ status mapping

Derived from `OrderState._getStatusFromAction()` and `MostroFSM`:

| Mostro event | Resulting status | Notes |
| --- | --- | --- |
| `take-buy` | `waiting-payment` | Seller takes a buy order → must pay hold invoice. |
| `take-sell` | `waiting-buyer-invoice` | Buyer takes a sell order → must upload invoice. |
| `pay-invoice`, `waiting-seller-to-pay` | `waiting-payment` | Forces seller into `PayLightningInvoiceScreen`. |
| `add-invoice`, `waiting-buyer-invoice` | `waiting-buyer-invoice` | Forces buyer into `AddLightningInvoiceScreen`. |
| `hold-invoice-payment-accepted` | `active` | Hold invoice settled; chat + actions enabled. |
| `fiat-sent`, `fiat-sent-ok` | `fiat-sent` | Buyer declared fiat sent; seller gains **Release** button. |
| `release`, `purchase-completed`, `hold-invoice-payment-settled` | `success` / `settled-hold-invoice` | Completion path prior to rating. |
| `payment-failed` | `payment-failed` | Auto retries + manual invoice re-entry. |
| `cooperative-cancel-*` | `cooperatively-canceled` → `canceled` | Pending cooperative cancel, then terminal state. |
| `dispute-*`, `admin-*` | `dispute`, `settled-by-admin`, `canceled-by-admin` | TradeDetail locks down to dispute UI. |

`MostroFSM.nextStatus()` is used to ensure the UI never renders actions invalid for the user’s role (e.g., buyers never see **Release**).

---

## 6) Real-time updates & session handling

### `OrderNotifier`

- Subscribes to `mostroMessageStreamProvider(orderId)` and keeps `OrderState` in sync (including `paymentRequest`, `peer`, `dispute`).
- Creates sessions via `sessionNotifier.newSession` when a take is initiated, storing the role and peer info.
- Exposes methods consumed by the UI: `sendInvoice`, `sendFiatSent`, `releaseOrder`, `disputeOrder`, `cancelOrder`, etc.

### `AbstractMostroNotifier`

- Dispatches navigation (`navProvider.go`) based on incoming actions.
- Starts 10s session timeouts (`startSessionTimeoutCleanup`) to clean up failed takes.
- Deletes sessions and shows notifications when Mostro emits `canceled` (expiration, cooperative cancel, etc.).
- Detects `hold-invoice-payment-accepted` to populate `session.peer` and enable chat.
- Forces manual invoice entry when `paymentFailed` is active.

### Trades overview

- `/order_book` lists the user’s trades via `filteredTradesWithOrderStateProvider`.
- `TradesListItem` renders status/role chips from `orderNotifierProvider(orderId)` and navigates to `/trade_detail/:orderId`.

---

## 7) Errors, timeouts, and disputes

| Scenario | App behavior |
| --- | --- |
| Maker-side expiration | `OrderNotifier._subscribeToPublicEvents` watches `orderEventsProvider`; when a pending maker order turns `canceled`, it deletes the session and posts `orderCanceled`. |
| Taker timeout (no response within 10s) | `startSessionTimeoutCleanup` fires, shows `sessionTimeoutMessage`, and navigates home. |
| Hold invoice payment failure | Mostro sends `payment-failed`; status switches to `paymentFailed`, buyers only see **Add invoice**, sellers only **Pay invoice** until a new request arrives. |
| Disputes | "Dispute" button triggers `disputeRepositoryProvider.createDispute`. Once a dispute exists, "View dispute" links to `/dispute_details/:id` and the chat switches to admin shared keys (see [DISPUTE_SYSTEM.md](./DISPUTE_SYSTEM.md)). |
| Cooperative cancel | Pending cancel renders grey button (disabled) + "Contact" button to coordinate. |
| Invoice/payment errors | UI surfaces `SnackBarHelper.showTopSnackBar` messages but keeps the user on the same screen. |

**Dispute flow recap:** trade participants can file a dispute once the order is `active`/`fiat-sent`; the repository sends an encrypted `MostroMessage(Action.dispute)`, `OrderState` transitions to `Status.dispute`, and admins may later take the case (`adminTookDispute`), settle (`adminSettled`), or refund (`adminCanceled`). UI details, unread badges, and the dedicated dispute chat live in [DISPUTE_SYSTEM.md](./DISPUTE_SYSTEM.md).

---

## 8) Cross-references

- `.specify/v1-reference/TAKE_ORDER.md` — links here as soon as the take completes.
- `.specify/v1-reference/ORDER_STATES.md` — references this spec for execution-state transitions.
- `.specify/v1-reference/NAVIGATION_ROUTES.md` — routes `/pay_invoice`, `/add_invoice`, `/trade_detail`, `/order_book` point here.
- `.specify/v1-reference/README.md` — includes this document in the index (screens & navigation).
