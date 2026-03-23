# Order States and Transitions Specification

> Complete specification of all order states, visual representation, and state transitions based on user actions.

## Overview

Mostro orders go through a well-defined lifecycle with 15 possible states. Each state is visually represented in the "My Trades" list with a colored status chip, and transitions occur based on actions by buyer, seller, or admin.

## Order States Reference

### 1. PENDING

**Visual:**
- Chip: Orange/Yellow background (`#854D0E`), yellow text (`#FCD34D`)
- Label: "Pending"

**Description:**
Order has been created by a seller or buyer and is waiting for a counterparty to take it.

**Available Actions:**
- Creator can cancel
- Buyer can take a sell order
- Seller can take a buy order

**Transitions:**

| Action | By | Next State |
|--------|----|------------|
| `take-sell` | Buyer | `waiting-buyer-invoice` |
| `take-buy` | Seller | `waiting-payment` |
| `cancel` | Creator | `canceled` |

---

### 2. WAITING_BUYER_INVOICE

**Visual:**
- Chip: Red/Orange background (`#7C2D12`), orange text (`#FED7AA`)
- Label: "Waiting Invoice"

**Description:**
The buyer must provide a Lightning invoice where they want to receive the sats. This state occurs at different points depending on order type:
- **Sell order**: Immediately after buyer takes the order (buyer takes → waitingBuyerInvoice)
- **Buy order**: After seller pays the hold invoice (seller pays → waitingBuyerInvoice)

> ⚠️ **Order-type-dependent transitions**: The next state after `add-invoice` depends on the order type:
> - **Sell order**: `add-invoice` → `waiting-payment` (seller still needs to pay hold invoice)
> - **Buy order**: `add-invoice` → `active` (seller already paid hold invoice, trade is now active)

**Available Actions:**
- Buyer can submit invoice
- Either party can cancel
- Either party can initiate dispute

**Transitions:**

| Action | By | Next State (Sell Order) | Next State (Buy Order) |
|--------|----|------------------------|------------------------|
| `add-invoice` | Buyer | `waiting-payment` | `active` |
| `cancel` | Either | `canceled` | `canceled` |
| `dispute` | Either | `dispute` | `dispute` |

---

### 3. WAITING_PAYMENT

**Visual:**
- Chip: Red/Orange background (`#7C2D12`), orange text (`#FED7AA`)
- Label: "Waiting Payment"

**Description:**
Seller must pay the hold invoice to lock the sats in escrow.

> ⚠️ **Order-type-dependent transitions**: The next state after `pay-invoice` depends on the order type:
> - **Sell order** (seller created): `pay-invoice` → `active` (hold invoice paid, buyer already provided invoice)
> - **Buy order** (buyer created): `pay-invoice` → `waiting-buyer-invoice` (hold invoice paid, now waiting for buyer to provide their LN receive invoice)

**Available Actions:**
- Seller can pay the hold invoice
- Either party can cancel
- Either party can initiate dispute

**Transitions:**

| Action | By | Next State (Sell Order) | Next State (Buy Order) |
|--------|----|------------------------|------------------------|
| `pay-invoice` | Seller | `active` | `waiting-buyer-invoice` |
| `payment-failed` | System | `payment-failed` | `payment-failed` |
| `cancel` | Either | `canceled` | `canceled` |
| `dispute` | Either | `dispute` | `dispute` |

---

### 4. PAYMENT_FAILED

**Visual:**
- Chip: Gray background (`#1F2937`), gray text (`#D1D5DB`)
- Label: "Payment Failed"

**Description:**
The seller failed to pay the hold invoice within the time window. The order is temporarily stalled.

**Available Actions:**
- Seller can retry payment
- Buyer can provide new invoice (optional)
- Either party can cancel
- Either party can initiate dispute

**Transitions:**

| Action | By | Next State |
|--------|----|------------|
| `pay-invoice` | Seller | `active` |
| `add-invoice` | Buyer | `waiting-payment` |
| `cancel` | Either | `canceled` |
| `dispute` | Either | `dispute` |

---

### 5. ACTIVE

**Visual:**
- Chip: Blue background (`#1E3A8A`), blue text (`#93C5FD`)
- Label: "Active"

**Description:**
Sats are locked in escrow (hold invoice paid). The buyer must now send fiat to the seller. This is the main trading state.

**Available Actions:**
- Buyer can mark fiat as sent
- Either party can cancel
- Either party can initiate dispute

**Transitions:**

| Action | By | Next State |
|--------|----|------------|
| `fiat-sent` | Buyer | `fiat-sent` |
| `cancel` | Either | `canceled` |
| `dispute` | Either | `dispute` |

---

### 6. FIAT_SENT

**Visual:**
- Chip: Green background (`#065F46`), green text (`#6EE7B7`)
- Label: "Fiat Sent"

**Description:**
Buyer has marked the fiat as sent. Seller must verify receipt and release the sats from escrow.

**Available Actions:**
- Seller can release sats
- Either party can initiate dispute if something is wrong

**Transitions:**

| Action | By | Next State |
|--------|----|------------|
| `release` | Seller | `settled-hold-invoice` |
| `dispute` | Either | `dispute` |

---

### 7. SETTLED_HOLD_INVOICE

**Visual:**
- Chip: Orange/Yellow background (`#854D0E`), yellow text (`#FCD34D`)
- Label: "Settled"

**Description:**
Seller has released the sats. The hold invoice is being settled and sats are being routed to the buyer's invoice. This is a transient state before completion.

**Available Actions:**
- None (automatic transition)

**Transitions:**

| Action | By | Next State |
|--------|----|------------|
| (automatic) | System | `success` |

---

### 8. SUCCESS

**Visual:**
- Chip: Green background (`#065F46`), green text (`#6EE7B7`)
- Label: "Success"

**Description:**
Trade completed successfully. Sats have been received by the buyer. Both parties can now rate each other.

**Available Actions:**
- Either party can rate the counterparty

**Transitions:**

| Action | By | Next State |
|--------|----|------------|
| `rate` | Either | `success` (remains, but rated flag set) |

---

### 9. CANCELED

**Visual:**
- Chip: Gray background (`#1F2937`), gray text (`#D1D5DB`)
- Label: "Canceled"

**Description:**
Order was canceled by a party before completion. No funds were exchanged.

**Available Actions:**
- None (terminal state)

---

### 10. COOPERATIVELY_CANCELED

**Visual:**
- Chip: Red/Orange background (`#7C2D12`), orange text (`#FED7AA`)
- Label: "Canceling"

**Description:**
`cooperativelyCanceled` is a **client-side UI state**, not a protocol-level order status change.

> ⚠️ **Important:** The Mostro protocol does NOT change the order status when a cooperative cancel is requested. The order remains in its current status (`active`, `fiat-sent`, etc.). Mostro only sends notification actions (`cooperative-cancel-initiated-by-you` / `cooperative-cancel-initiated-by-peer`) to inform both parties.

**Protocol Flow:**
1. One party sends `action: "cancel"` to Mostro
2. Mostro sends `cooperative-cancel-initiated-by-you` to the requester
3. Mostro sends `cooperative-cancel-initiated-by-peer` to the counterparty
4. **Order status does NOT change** — if it was `active`, it stays `active`

**What Happens Next:**

| Counterparty Action | Result |
|---------------------|--------|
| Accepts cancel (sends `cancel`) | Mostro sends `cooperative-cancel-accepted` → order → `canceled` |
| Sends `fiat-sent` | Trade continues normally → order → `fiat-sent` |
| Sends `release` | Trade completes → order → `settled-hold-invoice` |
| Opens `dispute` | Escalated → order → `dispute` |
| Does nothing | Trade remains in current state, cancel request is pending |

**UI Display:**
The app shows the "Canceling" chip as a **visual overlay** on the current state to indicate a cancel was requested, but the underlying order status has not changed.

| Aspect | Cooperative Cancel Request | `canceled` (terminal) |
|--------|---------------------------|----------------------|
| Protocol status change? | **No** — order keeps its current status | **Yes** — status is `canceled` |
| UI label | "Canceling" (orange overlay) | "Cancel" (gray) |
| Trade can continue? | **Yes** — all normal actions available | **No** — terminal state |
| Both parties agree? | Required for cancel to complete | Already completed |

---

### 11. DISPUTE

**Visual:**
- Chip: Red background (`#7F1D1D`), red text (`#FCA5A5`)
- Label: "Dispute"

**Description:**
A dispute has been initiated by either party. An admin will review the case and make a resolution.

**Available Actions:**
- Both parties can submit evidence via chat
- Admin can settle (release to buyer)
- Admin can cancel (return to seller)

**Transitions:**

| Action | By | Next State |
|--------|----|------------|
| `admin-settle` | Admin | `settled-by-admin` |
| `admin-cancel` | Admin | `canceled-by-admin` |
| `admin-complete` | Admin | `completed-by-admin` |

---

### 12. SETTLED_BY_ADMIN

**Visual:**
- Chip: Purple background (`#581C87`), purple text (`#C084FC`)
- Label: "Settled"

**Description:**
Admin resolved the dispute in favor of the buyer. Sats were released to buyer.

**Available Actions:**
- None (terminal state)

---

### 13. CANCELED_BY_ADMIN

**Visual:**
- Chip: Gray background (`#1F2937`), gray text (`#D1D5DB`)
- Label: "Canceled"

**Description:**
Admin resolved the dispute in favor of the seller. Sats were returned to seller.

**Available Actions:**
- None (terminal state)

---

### 14. COMPLETED_BY_ADMIN

**Visual:**
- Chip: Green background (`#065F46`), green text (`#6EE7B7`)
- Label: "Completed"

**Description:**
Admin marked the trade as completed. This is a force-complete action.

**Available Actions:**
- None (terminal state)

---

### 15. EXPIRED

**Visual:**
- Chip: Gray background (`#1F2937`), gray text (`#D1D5DB`)
- Label: "Expired"

**Description:**
Order expired without being taken within the configured time limit.

**Available Actions:**
- None (terminal state)

---

## Complete Flow Diagrams

### Sell Order Flow (Seller Creates, Buyer Takes)

```text
┌──────────┐    takeSell     ┌──────────────────┐
│  PENDING │ ───────────────▶ │ WAITING_BUYER_   │
│          │                  │ INVOICE          │
└──────────┘                  └──────────┬───────┘
                                         │
                                         │ addInvoice
                                         ▼
                              ┌──────────────────┐
                              │ WAITING_PAYMENT  │
                              └──────────┬───────┘
                                         │
                                         │ payInvoice
                                         ▼
                              ┌──────────────────┐
                              │     ACTIVE       │
                              └──────────┬───────┘
                                         │
                                         │ fiatSent
                                         ▼
                              ┌──────────────────┐
                              │    FIAT_SENT     │
                              └──────────┬───────┘
                                         │
                                         │ release
                                         ▼
                              ┌──────────────────┐
                              │ SETTLED_HOLD_    │
                              │ INVOICE          │
                              └──────────┬───────┘
                                         │
                                         │ (auto)
                                         ▼
                              ┌──────────────────┐
                              │     SUCCESS      │
                              └──────────────────┘
```text

### Buy Order Flow (Buyer Creates, Seller Takes)

```text
┌──────────┐    takeBuy      ┌──────────────────┐
│  PENDING │ ───────────────▶ │ WAITING_PAYMENT  │
│          │                  │                  │
└──────────┘                  └──────────┬───────┘
                                         │
                                         │ payInvoice
                                         ▼
                              ┌──────────────────┐
                              │ WAITING_BUYER_   │
                              │ INVOICE          │
                              └──────────┬───────┘
                                         │
                                         │ (buyer adds invoice)
                                         ▼
                              ┌──────────────────┐
                              │     ACTIVE       │
                              └──────────┬───────┘
                                         │
                                         │ fiatSent
                                         ▼
                              ┌──────────────────┐
                              │    FIAT_SENT     │
                              └──────────┬───────┘
                                         │
                                         │ release
                                         ▼
                              ┌──────────────────┐
                              │ SETTLED_HOLD_    │
                              │ INVOICE          │
                              └──────────┬───────┘
                                         │
                                         │ (auto)
                                         ▼
                              ┌──────────────────┐
                              │     SUCCESS      │
                              └──────────────────┘
```text

## My Trades List Item Layout

```text
┌─────────────────────────────────────────────────────┐
│                                                     │
│  Buying Bitcoin / Selling Bitcoin                   │  ← Role indicator
│                                                     │
│  ┌──────────┐  ┌──────────────┐        [+/-]X%     │  ← Status + Role chips
│  │ [Status] │  │ Created/     │                   │     + Premium/discount
│  └──────────┘  │ Taken by you │                   │
│                └──────────────┘                   │
│                                                     │
│  🇻🇪  100 - 500 VES                                │  ← Amount range + currency
│                                                     │
│  Bank Transfer, Mercado Pago                       │  ← Payment methods
│                                                     │
│                                            ▸      │  ← Navigate arrow
└─────────────────────────────────────────────────────┘
```text

### Status Chip Colors

| State | Background | Text | Semantic Color Token |
|-------|------------|------|----------------------|
| `pending` | `#854D0E` (amber-900) | `#FCD34D` (amber-300) | `statusPending` |
| `waiting-buyer-invoice` | `#7C2D12` (orange-900) | `#FED7AA` (orange-200) | `statusWaiting` |
| `waiting-payment` | `#7C2D12` (orange-900) | `#FED7AA` (orange-200) | `statusWaiting` |
| `payment-failed` | `#1F2937` (gray-800) | `#D1D5DB` (gray-300) | `statusInactive` |
| `active` | `#1E3A8A` (blue-900) | `#93C5FD` (blue-300) | `statusActive` |
| `fiat-sent` | `#065F46` (emerald-900) | `#6EE7B7` (emerald-300) | `statusSuccess` |
| `settled-hold-invoice` | `#854D0E` (amber-900) | `#FCD34D` (amber-300) | `statusPending` |
| `success` | `#065F46` (emerald-900) | `#6EE7B7` (emerald-300) | `statusSuccess` |
| `canceled` / `canceled-by-admin` | `#1F2937` (gray-800) | `#D1D5DB` (gray-300) | `statusInactive` |
| `cooperativelyCanceled` | `#7C2D12` (orange-900) | `#FED7AA` (orange-200) | `statusWaiting` |
| `dispute` | `#7F1D1D` (red-900) | `#FCA5A5` (red-300) | `statusDispute` |
| `settled-by-admin` | `#581C87` (purple-900) | `#C084FC` (purple-300) | `statusSettled` |
| `completed-by-admin` | `#065F46` (emerald-900) | `#6EE7B7` (emerald-300) | `statusSuccess` |
| `expired` | `#1F2937` (gray-800) | `#D1D5DB` (gray-300) | `statusInactive` |

### Role Chips

| Role | Background | Text |
|------|------------|------|
| `createdByYou` | `#1565C0` (blue-800) | White |
| `takenByYou` | `#2DA69D` (teal) | White |

## Action Buttons by State

The trade detail screen shows different action buttons based on the current state and user's role:

### PENDING (as Creator)
- **Cancel Order** - Destructive button

### PENDING (as Taker)
- **Take Order** - Primary button

### WAITING_BUYER_INVOICE (as Buyer)
- **Add Invoice** - Primary button
- **Cancel** - Destructive
- **Dispute** - Warning

### WAITING_PAYMENT (as Seller)
- **Pay Hold Invoice** - Primary button (shows QR/invoice)
- **Cancel** - Destructive
- **Dispute** - Warning

### PAYMENT_FAILED (as Seller)
- **Retry Payment** - Primary button
- **Cancel** - Destructive

### ACTIVE (as Buyer)
- **Fiat Sent** - Success button (primary action)
- **Cancel** - Destructive
- **Dispute** - Warning

### ACTIVE (as Seller)
- **Cancel** - Destructive
- **Dispute** - Warning
- (Waiting for buyer to mark fiat sent)

### FIAT_SENT (as Seller)
- **Release Sats** - Success button (primary action)
- **Dispute** - Warning

### FIAT_SENT (as Buyer)
- (Waiting for seller to release)
- **Dispute** - Warning (if seller doesn't release)

### DISPUTE (as Either)
- (No actions - waiting for admin)
- Chat available for submitting evidence

### SUCCESS / Terminal States
- **Rate Counterparty** - Star rating component

## State Transitions Table

| Current State | Action | Buyer Next State | Seller Next State |
|---------------|--------|------------------|-------------------|
| `pending` | `take-sell` | `waiting-buyer-invoice` | - |
| `pending` | `take-buy` | - | `waiting-payment` |
| `pending` | `cancel` | `canceled` | `canceled` |
| `waiting-buyer-invoice` | `add-invoice` | `waiting-payment` | - |
| `waiting-buyer-invoice` | `cancel` | `canceled` | `canceled` |
| `waiting-payment` | `pay-invoice` | - | `active` |
| `waiting-payment` | `payment-failed` | `payment-failed` | `payment-failed` |
| `payment-failed` | `pay-invoice` | - | `active` |
| `payment-failed` | `add-invoice` | `waiting-payment` | - |
| `active` | `fiat-sent` | `fiat-sent` | `fiat-sent` |
| `fiat-sent` | `release` | - | `settled-hold-invoice` |
| `settled-hold-invoice` | (auto) | `success` | `success` |
| `active` | `dispute` | `dispute` | `dispute` |
| `fiat-sent` | `dispute` | `dispute` | `dispute` |
| `dispute` | `admin-settle` | `settled-by-admin` | `settled-by-admin` |
| `dispute` | `admin-cancel` | `canceled-by-admin` | `canceled-by-admin` |

## Implementation Notes for v2

### Rust Side

The state machine should be implemented in Rust for consistency:

```rust
// rust/src/api/order_fsm.rs

#[frb]
pub enum OrderStatus {
    Pending,
    WaitingBuyerInvoice,
    WaitingPayment,
    PaymentFailed,
    Active,
    FiatSent,
    SettledHoldInvoice,
    Success,
    Canceled,
    CooperativelyCanceled,
    Dispute,
    SettledByAdmin,
    CanceledByAdmin,
    CompletedByAdmin,
    Expired,
}

#[frb]
pub fn next_status(
    current: OrderStatus,
    role: Role,
    action: Action,
) -> Option<OrderStatus> {
    // Return None if no valid transition
    // Return Some(new_status) if transition is valid
}

#[frb]
pub fn possible_actions(
    current: OrderStatus,
    role: Role,
) -> Vec<Action> {
    // Return list of actions available to this role in this state
}
```rust

### Flutter Side

```dart
// lib/src/widgets/order_status_chip.dart

class OrderStatusChip extends StatelessWidget {
  final OrderStatus status;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final colors = _getStatusColors(status);
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 8,
        vertical: isCompact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.background.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _getStatusLabel(status),
        style: TextStyle(
          color: colors.text,
          fontSize: isCompact ? 11 : 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
```dart

### State Persistence

- All order states must be persisted locally in SQLite
- State transitions should be atomic (update both local DB and emit Nostr event)
- On app start, sync with relays to catch any missed state updates
- Display "syncing" indicator when state may be stale

### UI Responsiveness

- Status chips must update immediately on local action (optimistic update)
- Revert to previous state if Nostr confirmation fails
- Show error snackbar if transition is rejected by Mostro daemon
- Animate state transitions (color fade, text change)

## Appendix A: Action-to-Status Mapping

Mostro communicates with the app via encrypted gift wrap messages (NIP-59). Each message contains an `action` that either:
1. **Changes the order status** — e.g., `hold-invoice-payment-accepted` → `active`
2. **Notifies without changing status** — e.g., `cooperative-cancel-initiated-by-you` keeps current status

This mapping documents status-changing actions. Role differentiation happens because Mostro sends different actions to buyer and seller.

> ⚠️ **Not all actions change status:** Actions like `cooperative-cancel-initiated-by-you`, `cooperative-cancel-initiated-by-peer`, and `dispute-initiated-by-peer` are **notifications only** — the order remains in its current status.

### Seller Actions (Seller's Perspective)

| Action | Status | When |
|--------|--------|------|
| `waiting-seller-to-pay` | `waiting-payment` | Seller must pay the hold invoice |
| `pay-invoice` | `waiting-payment` | Seller receives the invoice to pay |
| `take-sell` | `waiting-payment` | Seller takes a buy order |
| `buyer-took-order` | `active` | Seller is notified a buyer took their order |
| `fiat-sent-ok` | `fiat-sent` | Seller is notified fiat was sent |
| `hold-invoice-payment-settled` | `success` | Seller's hold invoice settled (trade complete) |
| `release` | `settled-hold-invoice` → `success` | Seller releases sats |

### Buyer Actions (Buyer's Perspective)

| Action | Status | When |
|--------|--------|------|
| `waiting-buyer-invoice` | `waiting-buyer-invoice` | Buyer must provide a Lightning invoice |
| `add-invoice` | `waiting-buyer-invoice` | Buyer receives request to add invoice (see Status Preservation below) |
| `take-buy` | `waiting-buyer-invoice` | Buyer takes a sell order |
| `hold-invoice-payment-accepted` | `active` | Buyer is notified the seller paid the hold invoice |
| `buyer-invoice-accepted` | `active` | Buyer's invoice was accepted |
| `fiat-sent` | `fiat-sent` | Buyer confirms fiat payment sent |
| `fiat-sent-ok` | `fiat-sent` | Counterpart is notified fiat was sent |
| `released` | `settled-hold-invoice` | Buyer receives this when seller releases (intermediate state) |
| `purchase-completed` | `success` | Buyer receives confirmation that the LN payment completed |

### Dispute Actions

| Action | Status | When |
|--------|--------|------|
| `dispute-initiated-by-you` | `dispute` | User opened a dispute |
| `dispute-initiated-by-peer` | `dispute` | Counterpart opened a dispute |
| `dispute` | `dispute` | General dispute action |
| `admin-take-dispute` / `admin-took-dispute` | `dispute` | Admin took the dispute |
| `admin-settle` / `admin-settled` | `settled-by-admin` | Admin resolved by releasing sats |
| `admin-cancel` / `admin-canceled` | `canceled-by-admin` | Admin canceled the order |

### Terminal Actions

| Action | Final Status |
|--------|--------------|
| `canceled` | `canceled` |
| `cancel` | `canceled` |
| `cooperative-cancel-accepted` | `canceled` |
| `hold-invoice-payment-canceled` | `canceled` |
| `rate` / `rate-user` / `rate-received` | Preserves current status (rating UI only) |

### Status Preservation Edge Cases

**paymentFailed + addInvoice:**
When `add-invoice` is received while in `payment-failed` status, the status is **preserved** (stays `payment-failed`) for UI consistency. The user sees the payment failed context while providing a new invoice. If we changed to `waiting-buyer-invoice`, the user would lose the failure context.

**Restoring Sessions:**
When restoring sessions after app restart, orders may have a status but no recent action. The app synthesizes the appropriate action based on status and role. See "Restore Flow" below.

---

## Appendix B: Role-Specific Status Display

Mostro sends different actions to buyer and seller for the same event. This creates natural role differentiation without explicit role checks in the status mapping.

### Seller Releases Flow

```text
Seller Action                Buyer Action
     │                            │
     │   (seller clicks Release)   │
     ▼                            ▼
  success               settledHoldInvoice
  (immediate)           ("Paying sats")
                        │
                        └── Later: purchaseCompleted → success
```text

The seller sees `success` immediately because their part is done. The buyer sees `settled-hold-invoice` ("Paying sats") until the Lightning payment actually completes.

### Why Not Map `released` Directly to `success`?

Earlier versions mapped `Action.released` directly to `success`, but this gave buyers a false sense of completion. If the Lightning payment subsequently failed, the buyer had already seen "Success" which was incorrect. The intermediate `settled-hold-invoice` status accurately reflects: sats are being paid but not yet received.

---

## Appendix C: Restore Flow

When restoring sessions after app restart, the app receives orders with a status but no action history. The restore system synthesizes the appropriate action:

| Status | Buyer Action | Seller Action |
|--------|--------------|---------------|
| `pending` | `newOrder` | `newOrder` |
| `waiting-buyer-invoice` | `add-invoice` | `waiting-buyer-invoice` |
| `waiting-payment` | `waiting-seller-to-pay` | `pay-invoice` |
| `active` | `hold-invoice-payment-accepted` | `buyer-took-order` |
| `fiat-sent` | `fiat-sent-ok` | `fiat-sent-ok` |
| `settled-hold-invoice` | `released` | `hold-invoice-payment-settled` |
| `success` | `purchase-completed` | `purchase-completed` |
| `canceled` | `canceled` | `canceled` |
| `payment-failed` | `payment-failed` | `payment-failed` |
| `dispute` | `dispute-initiated-by-peer` | `dispute-initiated-by-peer` |

**Critical for `settled-hold-invoice`:** The buyer sees the intermediate "Paying sats" state, while the seller sees `success`. This matches the live flow where buyers must wait for Lightning payment confirmation.

---

## Appendix D: Dispute Auto-Closure

When an order with an active dispute reaches a terminal state through user action (not admin), the dispute is automatically closed:

| Order Reaches | Dispute Status | Dispute Action | Trigger |
|---------------|----------------|----------------|---------|
| `success` | `closed` | `user-completed` | Seller receives `hold-invoice-payment-settled` |
| `settled-hold-invoice` | `closed` | `user-completed` | Buyer receives `released` |
| `canceled` | `closed` | `cooperative-cancel` | Both receive `cooperative-cancel-accepted` |

The app infers dispute closure from order terminal state rather than subscribing to dispute resolution events (kind 38386), because:
- No protocol expansion needed
- No backend changes required
- Data already available in OrderState
- Simple logic: "order finished = dispute finished"

The `dispute.action` field distinguishes closure reason:
- `user-completed` — trade finished normally
- `cooperative-cancel` — parties agreed to cancel
- `admin-settled` / `admin-canceled` — admin resolved

---

## Appendix E: UI Labels Reference

### My Trades List (Compact Chips)

| Status | Short Label | Color |
|--------|-------------|-------|
| `active` | "Active" | Blue |
| `pending` | "Pending" | Yellow |
| `waiting-payment` | "Waiting payment" | Orange |
| `waiting-buyer-invoice` | "Waiting invoice" | Orange |
| `payment-failed` | "Payment Failed" | Gray |
| `fiat-sent` | "Fiat-sent" | Green |
| `settled-hold-invoice` | "Paying sats" | Yellow |
| `success` | "Success" | Green |
| `canceled` | "Cancel" | Gray |
| `cooperatively-canceled` | "Canceling" | Orange |
| `dispute` | "Dispute" | Red |
| `settled-by-admin` | "Settled" | Purple |

### Order Details (Descriptive Labels)

| Status | Descriptive Label |
|--------|-------------------|
| `active` | "Active order" |
| `fiat-sent` | "Fiat sent" |
| `settled-hold-invoice` | "Paying sats" |
| `payment-failed` | "Payment failed" |
| `cooperativelyCanceled` | "Cooperative cancellation" |
| `canceled-by-admin` | "Order canceled by an administrator" |
| `settled-by-admin` | "Sats released by an administrator" |

---

## Testing Scenarios

### Unit Tests (Rust)

```rust
#[test]
fn test_sell_order_flow() {
    // pending → waitingBuyerInvoice
    let status = next_status(
        OrderStatus::Pending,
        Role::Buyer,
        Action::TakeSell
    );
    assert_eq!(status, Some(OrderStatus::WaitingBuyerInvoice));
    
    // waitingBuyerInvoice → waitingPayment
    let status = next_status(
        OrderStatus::WaitingBuyerInvoice,
        Role::Buyer,
        Action::AddInvoice
    );
    assert_eq!(status, Some(OrderStatus::WaitingPayment));
    
    // waitingPayment → active
    let status = next_status(
        OrderStatus::WaitingPayment,
        Role::Seller,
        Action::PayInvoice
    );
    assert_eq!(status, Some(OrderStatus::Active));
}

#[test]
fn test_invalid_transition() {
    // Cannot cancel an already success order
    let status = next_status(
        OrderStatus::Success,
        Role::Buyer,
        Action::Cancel
    );
    assert_eq!(status, None);
}
```rust

### Widget Tests (Flutter)

```dart
testWidgets('status chip displays correctly', (tester) async {
  for (final status in OrderStatus.values) {
    await tester.pumpWidget(
      MaterialApp(
        home: OrderStatusChip(status: status),
      ),
    );
    
    expect(find.text(status.label), findsOneWidget);
    
    final container = tester.widget<Container>(find.byType(Container));
    // Verify background color matches spec
  }
});
```dart
