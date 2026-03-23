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
| `takeSell` | Buyer | `waitingBuyerInvoice` |
| `takeBuy` | Seller | `waitingPayment` |
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

> ⚠️ **Order-type-dependent transitions**: The next state after `addInvoice` depends on the order type:
> - **Sell order**: `addInvoice` → `waitingPayment` (seller still needs to pay hold invoice)
> - **Buy order**: `addInvoice` → `active` (seller already paid hold invoice, trade is now active)

**Available Actions:**
- Buyer can submit invoice
- Either party can cancel
- Either party can initiate dispute

**Transitions:**

| Action | By | Next State (Sell Order) | Next State (Buy Order) |
|--------|----|------------------------|------------------------|
| `addInvoice` | Buyer | `waitingPayment` | `active` |
| `cancel` | Either | `canceled` | `canceled` |
| `dispute` | Either | `dispute` | `dispute` |

---

### 3. WAITING_PAYMENT

**Visual:**
- Chip: Red/Orange background (`#7C2D12`), orange text (`#FED7AA`)
- Label: "Waiting Payment"

**Description:**
Seller must pay the hold invoice to lock the sats in escrow.

> ⚠️ **Order-type-dependent transitions**: The next state after `payInvoice` depends on the order type:
> - **Sell order** (seller created): `payInvoice` → `active` (hold invoice paid, buyer already provided invoice)
> - **Buy order** (buyer created): `payInvoice` → `waitingBuyerInvoice` (hold invoice paid, now waiting for buyer to provide their LN receive invoice)

**Available Actions:**
- Seller can pay the hold invoice
- Either party can cancel
- Either party can initiate dispute

**Transitions:**

| Action | By | Next State (Sell Order) | Next State (Buy Order) |
|--------|----|------------------------|------------------------|
| `payInvoice` | Seller | `active` | `waitingBuyerInvoice` |
| `paymentFailed` | System | `paymentFailed` | `paymentFailed` |
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
| `payInvoice` | Seller | `active` |
| `addInvoice` | Buyer | `waitingPayment` |
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
| `fiatSent` | Buyer | `fiatSent` |
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
| `release` | Seller | `settledHoldInvoice` |
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

> ⚠️ **Important:** The Mostro protocol does NOT change the order status when a cooperative cancel is requested. The order remains in its current status (`active`, `fiatSent`, etc.). Mostro only sends notification actions (`cooperative-cancel-initiated-by-you` / `cooperative-cancel-initiated-by-peer`) to inform both parties.

**Protocol Flow:**
1. One party sends `action: "cancel"` to Mostro
2. Mostro sends `cooperative-cancel-initiated-by-you` to the requester
3. Mostro sends `cooperative-cancel-initiated-by-peer` to the counterparty
4. **Order status does NOT change** — if it was `active`, it stays `active`

**What Happens Next:**

| Counterparty Action | Result |
|---------------------|--------|
| Accepts cancel (sends `cancel`) | Mostro sends `cooperative-cancel-accepted` → order → `canceled` |
| Sends `fiatSent` | Trade continues normally → order → `fiatSent` |
| Sends `release` | Trade completes → order → `settledHoldInvoice` |
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
| `adminSettle` | Admin | `settledByAdmin` |
| `adminCancel` | Admin | `canceledByAdmin` |
| `adminComplete` | Admin | `completedByAdmin` |

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
| `waitingBuyerInvoice` | `#7C2D12` (orange-900) | `#FED7AA` (orange-200) | `statusWaiting` |
| `waitingPayment` | `#7C2D12` (orange-900) | `#FED7AA` (orange-200) | `statusWaiting` |
| `paymentFailed` | `#1F2937` (gray-800) | `#D1D5DB` (gray-300) | `statusInactive` |
| `active` | `#1E3A8A` (blue-900) | `#93C5FD` (blue-300) | `statusActive` |
| `fiatSent` | `#065F46` (emerald-900) | `#6EE7B7` (emerald-300) | `statusSuccess` |
| `settledHoldInvoice` | `#854D0E` (amber-900) | `#FCD34D` (amber-300) | `statusPending` |
| `success` | `#065F46` (emerald-900) | `#6EE7B7` (emerald-300) | `statusSuccess` |
| `canceled` / `canceledByAdmin` | `#1F2937` (gray-800) | `#D1D5DB` (gray-300) | `statusInactive` |
| `cooperativelyCanceled` | `#7C2D12` (orange-900) | `#FED7AA` (orange-200) | `statusWaiting` |
| `dispute` | `#7F1D1D` (red-900) | `#FCA5A5` (red-300) | `statusDispute` |
| `settledByAdmin` | `#581C87` (purple-900) | `#C084FC` (purple-300) | `statusSettled` |
| `completedByAdmin` | `#065F46` (emerald-900) | `#6EE7B7` (emerald-300) | `statusSuccess` |
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
| `pending` | `takeSell` | `waitingBuyerInvoice` | - |
| `pending` | `takeBuy` | - | `waitingPayment` |
| `pending` | `cancel` | `canceled` | `canceled` |
| `waitingBuyerInvoice` | `addInvoice` | `waitingPayment` | - |
| `waitingBuyerInvoice` | `cancel` | `canceled` | `canceled` |
| `waitingPayment` | `payInvoice` | - | `active` |
| `waitingPayment` | `paymentFailed` | `paymentFailed` | `paymentFailed` |
| `paymentFailed` | `payInvoice` | - | `active` |
| `paymentFailed` | `addInvoice` | `waitingPayment` | - |
| `active` | `fiatSent` | `fiatSent` | `fiatSent` |
| `fiatSent` | `release` | - | `settledHoldInvoice` |
| `settledHoldInvoice` | (auto) | `success` | `success` |
| `active` | `dispute` | `dispute` | `dispute` |
| `fiatSent` | `dispute` | `dispute` | `dispute` |
| `dispute` | `adminSettle` | `settledByAdmin` | `settledByAdmin` |
| `dispute` | `adminCancel` | `canceledByAdmin` | `canceledByAdmin` |

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
```

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
```

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

Mostro communicates with the app via encrypted gift wrap messages (NIP-59). Each message contains an `action` that determines the new status. This mapping is action-driven, not role-specific — role differentiation happens because Mostro sends different actions to buyer and seller.

### Seller Actions (Seller's Perspective)

| Action | Status | When |
|--------|--------|------|
| `waitingSellerToPay` | `waitingPayment` | Seller must pay the hold invoice |
| `payInvoice` | `waitingPayment` | Seller receives the invoice to pay |
| `takeSell` | `waitingPayment` | Seller takes a buy order |
| `buyerTookOrder` | `active` | Seller is notified a buyer took their order |
| `fiatSentOk` | `fiatSent` | Seller is notified fiat was sent |
| `holdInvoicePaymentSettled` | `success` | Seller's hold invoice settled (trade complete) |
| `release` | `settledHoldInvoice` → `success` | Seller releases sats |

### Buyer Actions (Buyer's Perspective)

| Action | Status | When |
|--------|--------|------|
| `waitingBuyerInvoice` | `waitingBuyerInvoice` | Buyer must provide a Lightning invoice |
| `addInvoice` | `waitingBuyerInvoice` | Buyer receives request to add invoice (see Status Preservation below) |
| `takeBuy` | `waitingBuyerInvoice` | Buyer takes a sell order |
| `holdInvoicePaymentAccepted` | `active` | Buyer is notified the seller paid the hold invoice |
| `buyerInvoiceAccepted` | `active` | Buyer's invoice was accepted |
| `fiatSent` | `fiatSent` | Buyer confirms fiat payment sent |
| `fiatSentOk` | `fiatSent` | Counterpart is notified fiat was sent |
| `released` | `settledHoldInvoice` | Buyer receives this when seller releases (intermediate state) |
| `purchaseCompleted` | `success` | Buyer receives confirmation that the LN payment completed |

### Dispute Actions

| Action | Status | When |
|--------|--------|------|
| `disputeInitiatedByYou` | `dispute` | User opened a dispute |
| `disputeInitiatedByPeer` | `dispute` | Counterpart opened a dispute |
| `dispute` | `dispute` | General dispute action |
| `adminTakeDispute` / `adminTookDispute` | `dispute` | Admin took the dispute |
| `adminSettle` / `adminSettled` | `settledByAdmin` | Admin resolved by releasing sats |
| `adminCancel` / `adminCanceled` | `canceled` | Admin canceled the order |

### Terminal Actions

| Action | Final Status |
|--------|--------------|
| `canceled` | `canceled` |
| `cancel` | `canceled` |
| `cooperativeCancelAccepted` | `canceled` |
| `holdInvoicePaymentCanceled` | `canceled` |
| `rate` / `rateUser` / `rateReceived` | Preserves current status (rating UI only) |

### Status Preservation Edge Cases

**paymentFailed + addInvoice:**
When `addInvoice` is received while in `paymentFailed` status, the status is **preserved** (stays `paymentFailed`) for UI consistency. The user sees the payment failed context while providing a new invoice. If we changed to `waitingBuyerInvoice`, the user would lose the failure context.

**Restoring Sessions:**
When restoring sessions after app restart, orders may have a status but no recent action. The app synthesizes the appropriate action based on status and role. See "Restore Flow" below.

---

## Appendix B: Role-Specific Status Display

Mostro sends different actions to buyer and seller for the same event. This creates natural role differentiation without explicit role checks in the status mapping.

### Seller Releases Flow

```
Seller Action                Buyer Action
     │                            │
     │   (seller clicks Release)   │
     ▼                            ▼
  success               settledHoldInvoice
  (immediate)           ("Paying sats")
                        │
                        └── Later: purchaseCompleted → success
```

The seller sees `success` immediately because their part is done. The buyer sees `settledHoldInvoice` ("Paying sats") until the Lightning payment actually completes.

### Why Not Map `released` Directly to `success`?

Earlier versions mapped `Action.released` directly to `success`, but this gave buyers a false sense of completion. If the Lightning payment subsequently failed, the buyer had already seen "Success" which was incorrect. The intermediate `settledHoldInvoice` status accurately reflects: sats are being paid but not yet received.

---

## Appendix C: Restore Flow

When restoring sessions after app restart, the app receives orders with a status but no action history. The restore system synthesizes the appropriate action:

| Status | Buyer Action | Seller Action |
|--------|--------------|---------------|
| `pending` | `newOrder` | `newOrder` |
| `waitingBuyerInvoice` | `addInvoice` | `waitingBuyerInvoice` |
| `waitingPayment` | `waitingSellerToPay` | `payInvoice` |
| `active` | `holdInvoicePaymentAccepted` | `buyerTookOrder` |
| `fiatSent` | `fiatSentOk` | `fiatSentOk` |
| `settledHoldInvoice` | `released` | `holdInvoicePaymentSettled` |
| `success` | `purchaseCompleted` | `purchaseCompleted` |
| `canceled` | `canceled` | `canceled` |
| `paymentFailed` | `paymentFailed` | `paymentFailed` |
| `dispute` | `disputeInitiatedByPeer` | `disputeInitiatedByPeer` |

**Critical for `settledHoldInvoice`:** The buyer sees the intermediate "Paying sats" state, while the seller sees `success`. This matches the live flow where buyers must wait for Lightning payment confirmation.

---

## Appendix D: Dispute Auto-Closure

When an order with an active dispute reaches a terminal state through user action (not admin), the dispute is automatically closed:

| Order Reaches | Dispute Status | Dispute Action | Trigger |
|---------------|----------------|----------------|---------|
| `success` | `closed` | `user-completed` | Seller receives `holdInvoicePaymentSettled` |
| `settledHoldInvoice` | `closed` | `user-completed` | Buyer receives `released` |
| `canceled` | `closed` | `cooperative-cancel` | Both receive `cooperativeCancelAccepted` |

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
| `active` | "Active" | Green |
| `pending` | "Pending" | Yellow |
| `waitingPayment` | "Waiting payment" | Orange |
| `waitingBuyerInvoice` | "Waiting invoice" | Orange |
| `paymentFailed` | "Payment Failed" | Gray |
| `fiatSent` | "Fiat-sent" | Green |
| `settledHoldInvoice` | "Paying sats" | Yellow |
| `success` | "Success" | Green |
| `canceled` | "Cancel" | Gray |
| `cooperativelyCanceled` | "Canceling" | Orange |
| `dispute` | "Dispute" | Red |
| `settledByAdmin` | "Settled" | Purple |

### Order Details (Descriptive Labels)

| Status | Descriptive Label |
|--------|-------------------|
| `active` | "Active order" |
| `fiatSent` | "Fiat sent" |
| `settledHoldInvoice` | "Paying sats" |
| `paymentFailed` | "Payment failed" |
| `cooperativelyCanceled` | "Cooperative cancellation" |
| `canceledByAdmin` | "Order canceled by an administrator" |
| `settledByAdmin` | "Sats released by an administrator" |

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
```

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
```
