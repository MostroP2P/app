# Feature Specification: Mostro Mobile v2 — P2P Bitcoin Lightning Exchange

**Feature Branch**: `004-mostro-p2p-client`
**Created**: 2026-03-29
**Status**: Draft
**Input**: User description: "Build Mostro Mobile v2 — a P2P Bitcoin Lightning exchange mobile app. The complete feature specification is already documented in .specify/v1-reference/V1_FLOW_GUIDE.md. That file is the single source of truth for every screen and interaction. Follow it exactly and replicate all 23 sections."

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — First Launch & Identity Setup (Priority: P1)

A new user opens the app for the first time. The app silently generates a unique cryptographic identity (12-word BIP-39 mnemonic + derived Nostr keypair) in the background — no sign-up, no email, no KYC, no internet connection required. The mnemonic is immediately stored in the platform's secure storage (iOS Keychain / Android Keystore). Once identity creation completes, a permanent backup reminder notification is pinned to the Notifications screen. The user is shown a 6-page illustrated walkthrough explaining the app's privacy model, security guarantees, encrypted chat, and how to trade. Once completed (or skipped), the user lands on the order book.

The notification bell in the app bar displays a red dot (no number) as long as the user has not confirmed their backup. The bell plays a subtle left-right shake animation whenever any indicator — red dot or numbered badge — is active. The backup notification is always the first item in the Notifications list until the user explicitly confirms backup via the Account screen. Tapping that notification takes the user directly to the Account screen where the Secret Words card is displayed.

**Why this priority**: Without identity creation and onboarding, no subsequent feature can function. This is the zero-state entry point for every user. Loss of the mnemonic means permanent loss of the account.

**Independent Test**: Can be fully tested by fresh-installing the app and verifying: (a) the 6-slide walkthrough appears only once, (b) subsequent launches skip straight to the order book, (c) the notification bell shows a red dot, shakes, and a backup reminder is pinned as the first notification, (d) tapping the notification lands on the Account screen.

**Acceptance Scenarios**:

1. **Given** it is the app's very first launch, **When** the app initializes, **Then** a 12-word BIP-39 mnemonic and derived Nostr keypair are generated silently in the background with no user interaction, no UI blocking, and no internet connection required, and the mnemonic is persisted to platform secure storage before any UI is shown.
2. **Given** identity creation has completed on first launch, **When** the app proceeds, **Then** a backup reminder notification is created and pinned as the first item in the Notifications screen; this notification persists until the user explicitly confirms backup and cannot be dismissed by swiping or marking as read.
3. **Given** it is the app's first launch, **When** the app opens, **Then** a 6-slide walkthrough is shown covering: welcome, privacy, security, encrypted chat, taking offers, and creating offers.
4. **Given** the user taps "Done" or "Skip" on the walkthrough, **When** the navigation completes, **Then** the user lands on the order book.
5. **Given** the user has previously completed the walkthrough, **When** they reopen the app, **Then** they go directly to the order book with no walkthrough.
6. **Given** the user has not yet confirmed their backup, **When** they look at the notification bell in the app bar, **Then** a red dot indicator (not a number badge) is visible on the bell icon.
7. **Given** the notification bell has an active red dot or a numbered unread badge, **When** the indicator first appears or the count changes, **Then** the bell icon plays a left-right shake animation (two oscillations, ~300 ms total, easing in and out).
8. **Given** the backup reminder notification is pinned, **When** the user taps it in the Notifications screen, **Then** they are navigated directly to the Account screen.

---

### User Story 2 — Secret Words Backup (Priority: P1)

The user taps the backup reminder or navigates to the Account screen. The Secret Words card displays the mnemonic fully masked (all 12 words hidden behind asterisks). The user taps "Show" to reveal the 12 words. At the exact moment the words become visible, a confirmation checkbox appears below them with the label "I have written down my words and backed them up securely". The backup is only confirmed when the user explicitly taps this checkbox — merely viewing the words is not sufficient. Once the checkbox is ticked, the backup notification is permanently removed, the red dot on the bell disappears permanently, and the checkbox state is persisted across sessions.

**Why this priority**: Funds recovery depends on these words. Without this flow the user has no way to restore their account after device loss. The explicit checkbox — rather than passive viewing — ensures intentional confirmation.

**Independent Test**: Can be fully tested by navigating to Account, tapping "Show" on the masked mnemonic, verifying all 12 words are revealed and the checkbox appears, ticking the checkbox, then confirming: (a) the backup notification is gone from the Notifications screen, (b) the red dot on the bell is gone, (c) reopening the app shows no backup reminder.

**Acceptance Scenarios**:

1. **Given** the user arrives at the Account screen (via backup notification tap or direct navigation), **When** the screen loads, **Then** the first card is "Secret Words" and the mnemonic is fully masked — all 12 words are hidden (e.g., shown as bullet characters or asterisks) and none of the words are readable.
2. **Given** the Secret Words card is showing the masked mnemonic, **When** the user taps the "Show" button, **Then** all 12 words become fully visible in order, AND simultaneously a confirmation checkbox appears below the word list with the label "I have written down my words and backed them up securely".
3. **Given** the 12 words are visible and the confirmation checkbox is shown, **When** the user has NOT yet ticked the checkbox, **Then** the backup reminder notification remains pinned in the Notifications screen and the red dot on the bell remains active.
4. **Given** the 12 words are visible and the confirmation checkbox is shown, **When** the user taps the checkbox, **Then** the checkbox becomes checked, the backup is marked as confirmed in persistent storage, the backup reminder notification is permanently removed from the Notifications screen, and the red dot on the notification bell permanently disappears.
5. **Given** the user has confirmed backup in a previous session, **When** they navigate to the Account screen, **Then** the Secret Words card still shows the masked mnemonic and the "Show" button, but no backup reminder notification or red dot exists anywhere in the app.
6. **Given** the user generates a new identity (User Story 15), **When** the new mnemonic is created, **Then** the backup confirmation is reset: the backup reminder notification is re-pinned, the red dot reappears, and the checkbox is unchecked.

---

### User Story 3 — Browse the Order Book (Priority: P1)

A user browses available buy/sell offers in the public order book. The list is organized into two tabs (BUY BTC / SELL BTC) from the taker's perspective. Each order card shows fiat amount, currency, price type (market or fixed with premium), payment methods, and the maker's reputation stats. The user can filter by currency, payment method, rating range, and premium range.

**Why this priority**: This is the core discovery surface. Users must see and evaluate existing offers before taking or creating one.

**Independent Test**: Fully testable by opening the app and verifying the two-tab order book renders populated order cards with all fields; applying a filter reduces the visible order list.

**Acceptance Scenarios**:

1. **Given** the order book has pending orders, **When** a user opens the app, **Then** the order book shows two tabs (BUY BTC / SELL BTC) with a scrollable list of order cards.
2. **Given** an order card is rendered, **When** a user looks at it, **Then** they can see: fiat amount or range, currency code, country flag, price type, premium, payment methods, maker rating, trade count, and days active.
3. **Given** the user taps the Filter button, **When** they select a currency or payment method, **Then** only matching orders are shown and the offer count updates.
4. **Given** there are no matching orders for the active filter, **When** the filter is applied, **Then** a "No orders available" empty state is shown.

---

### User Story 4 — Create an Order (Priority: P1)

A user who cannot find a suitable offer creates their own buy or sell order. They specify the fiat amount (or a min–max range), currency, accepted payment methods, and choose between market price (with optional ±10% premium/discount) or a fixed satoshi amount. Once submitted, the order is published and appears in the public order book for others to take.

**Why this priority**: Makers (order creators) are the supply side of the marketplace. Without them there is no liquidity.

**Independent Test**: Fully testable by tapping the FAB (+), selecting Buy or Sell, filling in all required fields, submitting, and verifying the order appears in My Trades and the public order book.

**Acceptance Scenarios**:

1. **Given** a user taps the floating "+" button, **When** they choose Buy or Sell, **Then** they are taken to the Create Order screen with the selected order type pre-filled.
2. **Given** the Create Order form is open, **When** the user fills in fiat amount, currency, and at least one payment method, **Then** the Submit button becomes enabled.
3. **Given** the user selects "Market Price", **When** they adjust the premium slider, **Then** the value updates between -10% and +10%.
4. **Given** the user submits a valid order, **When** submission succeeds, **Then** the order appears in My Trades as "Pending" and is visible in the public order book.
5. **Given** the user tries to submit without any payment method selected, **When** they tap Submit, **Then** a validation error is shown and no order is sent.

---

### User Story 5 — Take an Existing Order (Priority: P1)

A user finds an offer in the order book and taps it to view the full order details: fiat amount, currency, payment methods, creation date, order UUID, and the maker's reputation. They tap Buy or Sell to take the order. For range orders, they first specify the exact fiat amount within the allowed range. The app submits the take action and transitions to the trade execution flow.

**Why this priority**: Taking an order is the primary path users use to enter a trade. It is the most common user action.

**Independent Test**: Fully testable by tapping an order card, reviewing details, tapping the action button, and verifying the trade appears in My Trades with the appropriate waiting state.

**Acceptance Scenarios**:

1. **Given** a user taps an order card, **When** the Take Order screen opens, **Then** it shows: fiat amount, currency, flag, payment methods, creation date, order ID (copyable), maker reputation stats, and a countdown to expiry.
2. **Given** the order is a range order, **When** the user taps the action button, **Then** a modal appears asking them to enter a specific fiat amount within the min–max bounds.
3. **Given** the user enters a valid amount and confirms, **When** the take action succeeds, **Then** the trade appears in My Trades and the user is navigated to the next step appropriate to their role.
4. **Given** the order has already been taken by another user, **When** this user submits, **Then** an error is shown and the user returns to the order book.

---

### User Story 6 — Trade Execution: Buyer Flow (Priority: P1)

A buyer (taker of a sell order) completes a trade. Without NWC, they manually enter a Lightning invoice or Lightning address so the platform knows where to send the sats. With NWC, this step is automatic. Once the seller pays the hold invoice, the trade goes active. The buyer contacts the seller, sends fiat, then taps "Fiat Sent". The seller verifies and releases the sats, completing the trade.

**Why this priority**: End-to-end trade completion is the core value of the app.

**Independent Test**: Fully testable by completing a full buy trade in both NWC and manual modes, verifying each step transitions correctly.

**Acceptance Scenarios**:

1. **Given** a buyer has taken a sell order and NWC is NOT configured, **When** the app prompts for a Lightning invoice, **Then** the buyer sees an input screen with the sats and fiat amounts, and can enter an invoice or Lightning address.
2. **Given** a buyer has taken a sell order and NWC IS configured, **When** the order is accepted, **Then** the invoice step is skipped entirely and the buyer proceeds to the active trade view.
3. **Given** the trade is in "active" status, **When** the buyer views Trade Detail, **Then** they see: trade summary, payment method, order ID, instructions to contact the seller, and buttons for Fiat Sent, Cancel, Dispute, and Contact.
4. **Given** the buyer has sent fiat payment, **When** they tap "Fiat Sent", **Then** the order status changes to "Fiat sent" and the seller sees instructions to verify and release.
5. **Given** the seller releases sats, **When** the buyer receives the Lightning payment, **Then** both parties are prompted to rate each other.

---

### User Story 7 — Trade Execution: Seller Flow (Priority: P1)

A seller (taker of a buy order) completes a trade. They must pay a hold Lightning invoice generated by the platform — either automatically via NWC or manually via QR code. While the hold invoice is held by the platform, the trade goes active. The seller waits for the buyer to send fiat and confirm. After verifying receipt, the seller taps "Release" and confirms, sending the sats to the buyer and completing the trade.

**Why this priority**: Sellers are the counterparty to every buyer. Both flows must work for trades to complete.

**Independent Test**: Fully testable by running a complete sell-side flow, verifying the QR screen (no NWC), the NWC auto-pay screen, and the release confirmation modal all work end-to-end.

**Acceptance Scenarios**:

1. **Given** a seller takes a buy order and NWC is NOT configured, **When** the hold invoice is ready, **Then** the seller sees a QR code with the invoice amount, a Copy button, a Share button, and a "Pay with Lightning wallet" button that launches the bolt11 into an external wallet via the `lightning:<bolt11>` URI scheme.
1a. **Given** no app on the device can handle the `lightning:` URI, **When** the seller taps "Pay with Lightning wallet", **Then** the app MUST surface a SnackBar explaining that no Lightning wallet was found, leaving the QR, Copy, and Share options still usable.
2. **Given** a seller takes a buy order and NWC IS configured, **When** the hold invoice is ready, **Then** a simplified screen appears with a "Pay with Wallet" button that auto-pays via the connected wallet. If NWC payment fails, the screen falls back to the QR view of scenario 1.
2a. **Given** the seller has paid the hold invoice (QR or NWC path), **When** mostrod confirms the HTLC and broadcasts the order update as Active, **Then** the app MUST auto-navigate from the pay-invoice screen to Trade Detail without any further user action; the navigation is driven by the live order status stream, not by the local wallet success callback.
2b. **Given** the seller is still on the pay-invoice screen, **When** mostrod broadcasts a terminal cancellation (canceled / cooperativelyCanceled / canceledByAdmin / expired), **Then** the app MUST leave the pay-invoice screen and surface a cancellation notice so the user is not stranded on a dead invoice.
3. **Given** the trade is active, **When** the seller views Trade Detail, **Then** they see instructions to contact the buyer with payment details and buttons: Close, Cancel, Dispute, Contact.
4. **Given** the buyer confirms "Fiat Sent", **When** the seller views Trade Detail, **Then** the status changes to "Fiat Sent" and a "Release" button becomes available.
5. **Given** the seller taps "Release", **When** the confirmation modal appears, **Then** tapping "Yes" releases the sats and transitions to the success/rating screen.

---

### User Story 8 — Encrypted P2P Chat (Priority: P1)

During an active trade, both parties communicate privately via an end-to-end encrypted in-app chat. Messages are visible only to the two trade participants. Users can also send encrypted image and file attachments. The chat room shows the peer's avatar, handle, a Trade Information panel, and a User Information panel including the shared encryption key (which can be optionally shared with a dispute admin to grant them read access to the chat history).

**Why this priority**: Communication is critical for coordinating fiat payment delivery — trades cannot realistically complete without it.

**Independent Test**: Fully testable by opening a chat room during an active trade, sending text and an image from both sides, and verifying messages appear on both devices and persist after app restart.

**Acceptance Scenarios**:

1. **Given** a trade is active, **When** a user taps "Contact", **Then** they are taken to the chat room showing the peer's avatar, handle, and any existing message history.
2. **Given** the chat room is open, **When** the user taps "Exchange Information", **Then** a panel shows the order ID, sats and fiat amounts, trade status, payment method, and creation date.
3. **Given** the chat room is open, **When** the user taps "User Information", **Then** a panel shows the peer's public key and the shared ECDH key, both copyable.
4. **Given** the user sends a message, **When** it is submitted, **Then** it appears immediately in the conversation (before relay confirmation) and is end-to-end encrypted.
5. **Given** the user attaches an image or file, **When** it is sent, **Then** it uploads encrypted and the recipient can view or download it securely.
6. **Given** there are unread messages, **When** the user has not opened the chat, **Then** a red dot appears on the Chat tab in the bottom nav and on the specific chat list item.

---

### User Story 9 — Dispute System with Admin Chat (Priority: P2)

Either party can open a dispute during an active trade if they cannot resolve a disagreement. The platform assigns an admin (dispute resolver) who communicates with the user via a separate encrypted admin chat. The user can optionally share the shared key from the P2P chat so the admin can review the trade conversation. The admin can release sats to the buyer or cancel the order and refund the seller. The seller can also voluntarily release at any point during a dispute.

**Why this priority**: Disputes are the safety net that enables users to trust the platform. Without it, fraud cannot be addressed.

**Independent Test**: Fully testable by initiating a dispute on an active trade, verifying the dispute card appears in the Disputes tab, and simulating admin assignment, chat, and both resolution outcomes.

**Acceptance Scenarios**:

1. **Given** a trade is active or in "fiat-sent" status, **When** a user taps "Dispute" and confirms, **Then** the trade status changes to "Dispute" and a dispute card appears in the Disputes tab.
2. **Given** an admin is assigned, **When** the user views the Disputes tab, **Then** the dispute status shows "In progress" and the dispute chat is accessible.
3. **Given** the dispute chat is open and the admin has not yet sent a message, **When** the user views the screen, **Then** an informational card explains that the mediator will join shortly.
4. **Given** the dispute chat is active (admin assigned), **When** the user sends messages, **Then** the admin receives them and can respond.
5. **Given** the admin resolves in the buyer's favor, **When** resolution is processed, **Then** the chat becomes read-only with a lock message and the order completes as success.
6. **Given** the admin resolves in the seller's favor, **When** resolution is processed, **Then** the hold invoice is canceled, and the chat shows "The administrator canceled the order and refunded you."
7. **Given** the seller taps "Release" during a dispute, **When** confirmed, **Then** the dispute closes and the order transitions to success without admin involvement.

---

### User Story 10 — Post-Trade Rating (Priority: P2)

After a trade completes, both parties are prompted to rate each other on a 1–5 star scale. Rating is optional — users can close the prompt without consequence. Ratings accumulate into each user's public reputation, which is displayed on their order cards in the order book (average rating, total reviews, days active).

**Why this priority**: Reputation is the trust mechanism that allows users to confidently trade with strangers.

**Independent Test**: Fully testable by completing a trade, submitting a 4-star rating from both sides, and verifying the counterparty's reputation score updates on their order cards in the order book.

**Acceptance Scenarios**:

1. **Given** a seller releases sats, **When** the transaction settles, **Then** the seller is prompted to rate the buyer via a Rate button on the trade screen.
2. **Given** a buyer receives the Lightning payment, **When** the order reaches "success", **Then** the buyer is prompted to rate the seller.
3. **Given** the user taps "Rate", **When** the rating screen opens, **Then** 5 tappable stars are shown and the Submit button is disabled until at least 1 star is selected.
4. **Given** the user selects 4 stars and taps Submit, **When** the rating is sent, **Then** the screen closes and the trade moves to a completed state.
5. **Given** the user taps "Close" instead of rating, **When** they dismiss the prompt, **Then** they return to the order book without penalty.

---

### User Story 11 — NWC Wallet Integration (Priority: P2)

A user connects a Lightning wallet via Nostr Wallet Connect by pasting a connection URI or scanning a QR code in Settings. When connected, the wallet name, connection status, and balance are shown. With NWC active, buyers skip manual invoice entry and sellers skip manual invoice payment — everything is automatic. If auto-payment fails, a manual fallback is presented.

**Why this priority**: NWC significantly reduces trade friction and is the preferred payment path for power users.

**Independent Test**: Fully testable by connecting a real NWC-compatible wallet, running a buy trade and a sell trade, and verifying both the invoice generation and payment steps are skipped.

**Acceptance Scenarios**:

1. **Given** NWC is not configured, **When** the user taps the Wallet card in Settings, **Then** a connection screen appears with a text field for the NWC URI and a QR scan option.
2. **Given** a valid NWC URI is entered, **When** the user taps Connect, **Then** the wallet connects and the Settings card shows "Connected. Balance: X sats".
3. **Given** NWC is connected and a buyer takes a sell order, **When** Mostro requests an invoice, **Then** the app auto-generates and submits the invoice without showing the manual Add Invoice screen.
4. **Given** NWC is connected and a seller takes a buy order, **When** a hold invoice arrives, **Then** a simplified screen with "Pay with Wallet" appears instead of the QR code screen.
5. **Given** NWC auto-payment fails, **When** the error occurs, **Then** the manual payment fallback is shown.

---

### User Story 12 — My Trades List (Priority: P1)

A user views all their active and historical trades in the My Trades tab. Each card shows the action (buying/selling), current status badge, their role (created by / taken by), fiat amount, currency, payment method, and relative time. Trades are filterable by status. Tapping a card opens Trade Detail. A badge on the tab signals unseen trade updates.

**Why this priority**: Users need real-time visibility into the state of their active trades, especially during time-sensitive steps.

**Independent Test**: Fully testable by creating a trade, navigating to My Trades, verifying the card appears with correct details, and applying a status filter.

**Acceptance Scenarios**:

1. **Given** the user has at least one trade, **When** they open the My Trades tab, **Then** a list of trade cards is shown with status badge, role badge, fiat amount, currency, payment method, and timestamp.
2. **Given** the user applies a status filter, **When** a status is selected from the dropdown, **Then** only trades with that status are shown.
3. **Given** a trade has a status update the user has not yet seen, **When** they look at the bottom nav bar, **Then** a red dot badge appears on the My Trades tab.
4. **Given** the user taps a trade card, **When** they navigate, **Then** the Trade Detail screen for that specific trade opens.

---

### User Story 13 — Notifications Center (Priority: P2)

The user receives in-app notifications for all trade lifecycle events: order taken, payment required, invoice waiting, fiat confirmed, payment settled, rating requested, etc. The notification bell shows a numbered badge for unread items. Tapping a notification navigates to the relevant screen. Users can mark all as read or clear all.

**Why this priority**: Notifications keep users informed during asynchronous trade steps without requiring them to actively poll.

**Independent Test**: Fully testable by completing a trade and verifying each event generates a notification, the badge counts correctly, and tapping each notification navigates appropriately.

**Acceptance Scenarios**:

1. **Given** a trade event occurs, **When** the app receives it, **Then** a notification card appears in the Notifications screen with an icon, title, subtitle, and timestamp.
2. **Given** there are unread notifications, **When** the user looks at the app bar, **Then** the bell shows a numbered badge (pill shape, dark gold) with the unread count and animates.
3. **Given** the user taps a notification, **When** they navigate to the relevant screen, **Then** the notification is marked as read and its indicator disappears.
4. **Given** the user opens the overflow menu in Notifications, **When** they tap "Mark all as read", **Then** all notifications are marked read and the badge disappears.

---

### User Story 14 — Settings & Preferences (Priority: P2)

Users configure app preferences from the Settings screen: language, default fiat currency, default Lightning address (pre-filled in invoice inputs), NWC wallet connection, relay list with on/off toggles, push notification preferences, Mostro node selection, and access to debug logs.

**Why this priority**: Default currency and language settings directly affect usability in each user's local market.

**Independent Test**: Fully testable by changing the default fiat currency to MXN and verifying it is pre-selected on the next Create Order.

**Acceptance Scenarios**:

1. **Given** the user opens Settings, **When** they view the screen, **Then** 8 configuration cards are shown: Language, Default Fiat Currency, Lightning Address, NWC Wallet, Relays, Push Notifications, Log Report, and Mostro Node.
2. **Given** the user taps Default Fiat Currency, **When** the currency dialog opens, **Then** they can search by name or code, and selecting one saves it as the default.
3. **Given** the user has a Lightning address saved, **When** they start a buy trade, **Then** the invoice input is pre-filled with the saved address.
4. **Given** the user manages relays, **When** they toggle a relay off, **Then** the app stops connecting to that relay.

---

### User Story 15 — Account & Identity Management (Priority: P2)

Users manage their cryptographic identity from the Account screen: view their 12 secret recovery words, toggle between Reputation mode (public trade history) and Full Privacy mode (anonymous), and optionally generate a fresh identity.

**Why this priority**: Privacy mode is a core differentiator — users trading in sensitive jurisdictions need full anonymity.

**Independent Test**: Fully testable by toggling privacy mode and verifying the identity used in subsequent trades changes accordingly.

**Acceptance Scenarios**:

1. **Given** the user opens Account, **When** the screen loads, **Then** they see the masked mnemonic, a privacy mode toggle, and a "Generate New User" option.
2. **Given** the user is in Reputation mode, **When** they switch to Full Privacy mode, **Then** a new identity is used for trades and no reputation data is accumulated.
3. **Given** the user generates a new identity, **When** confirmed, **Then** a new 12-word mnemonic is created and the backup reminder reactivates.

---

### Edge Cases

- What happens when the user's order expires before anyone takes it? → The order is removed from the public order book and a cancellation notification is shown.
- How does the system handle Lightning payment failures? → Status transitions to "payment-failed"; the buyer is prompted to re-enter a new invoice manually (auto-submit via NWC is disabled for retries).
- What happens if the seller does not respond after a take attempt? → A session timeout fires, returns the user to the order book with a timeout notification.
- What happens if a dispute is opened but no admin is available? → The dispute shows "Initiated" status; the user waits in the Disputes tab until an admin picks up the case.
- What happens when a user tries to submit a 0-star rating? → The Submit button remains disabled; at least 1 star must be selected.
- What happens when a cooperative cancel is pending agreement from the other party? → The Cancel button is grayed out (disabled) and a Contact button appears to allow both parties to coordinate.
- What happens if the shared key for dispute chat is not yet established? → The dispute chat input is hidden; the system retries key establishment automatically and shows it once available.

---

## Requirements *(mandatory)*

### Functional Requirements

**Onboarding & Identity**

- **FR-001**: The system MUST generate a 12-word BIP-39 mnemonic and derive a Nostr keypair automatically on first launch, with no user input, no registration, and no internet connection required. Generation MUST complete before any trade-related UI is accessible.
- **FR-002**: The generated mnemonic MUST be persisted to platform secure storage (iOS Keychain / Android Keystore) immediately after generation, before any UI transition occurs.
- **FR-002a**: If secure storage persistence fails during first launch, the system MUST: (a) halt onboarding and display a blocking error message instructing the user to check device settings and restart the app; (b) NOT proceed to the walkthrough or any other UI; (c) NOT proceed to the order book in any state where the mnemonic is not durably persisted. Recovery path: the user restarts the app and the system retries persistence on the next launch.
- **FR-003**: The system MUST display a 6-page illustrated walkthrough on first launch only; it MUST NOT appear on subsequent launches.
- **FR-004**: Upon successful identity generation on first launch, the system MUST create a backup reminder notification and pin it as the first item in the Notifications screen. This notification MUST NOT be dismissible by swipe-to-dismiss or "Mark all as read" — it can only be removed by the user confirming their backup via the Secret Words checkbox.
- **FR-005**: The notification bell icon in the app bar MUST display a red dot indicator (no number) whenever the backup has not yet been confirmed by the user. Once backup is confirmed, the red dot MUST disappear permanently and MUST NOT reappear unless a new identity is generated.
- **FR-006**: The notification bell MUST display a numbered badge (pill shape, dark gold) showing the count of unread non-backup notifications once the backup is confirmed. The red dot and the numbered badge are mutually exclusive: the red dot takes priority while backup is pending.
- **FR-007**: The notification bell MUST play a left-right shake animation (two oscillations, approximately 300 ms, ease-in-out) whenever any indicator becomes active (red dot appears, or unread badge count increases). The animation MUST NOT loop continuously — it fires once per state change.
- **FR-008**: Tapping the backup reminder notification MUST navigate the user directly to the Account screen.
- **FR-009**: The Secret Words card on the Account screen MUST display the mnemonic fully masked by default (all 12 words hidden). None of the words are visible until the user explicitly taps "Show".
- **FR-010**: When the user taps "Show" on the Secret Words card, the system MUST simultaneously: (a) reveal all 12 mnemonic words in order, and (b) display a confirmation checkbox below the word list with the label "I have written down my words and backed them up securely".
- **FR-011**: The backup MUST only be marked as confirmed when the user explicitly taps the confirmation checkbox. Viewing the words without ticking the checkbox MUST NOT confirm the backup.
- **FR-012**: When the user ticks the backup confirmation checkbox, the system MUST: (a) persist the confirmed state to local storage, (b) permanently remove the backup reminder notification from the Notifications screen, and (c) permanently remove the red dot from the notification bell. These changes MUST survive app restart.
- **FR-013**: If the user generates a new identity (via Account screen), the backup confirmation state MUST be reset to unconfirmed, re-triggering the backup reminder notification and the red dot on the bell.

**Order Book**

- **FR-014**: The system MUST display a public order book with two tabs (BUY BTC / SELL BTC) labeled from the taker's perspective.
- **FR-015**: Each order card MUST display: fiat amount or range, currency code, country flag, price type, premium, payment methods, maker rating, total trade count, and days active.
- **FR-016**: The order book MUST support filtering by fiat currency (multi-select), payment method (multi-select), rating range (slider), and premium range (slider).
- **FR-017**: The system MUST display only orders with "pending" status in the public order book.
- **FR-018**: Orders in the public order book MUST be sorted by ascending expiration time (soonest expiring first).

**Order Creation**

- **FR-019**: Users MUST be able to create both buy and sell orders from the floating action button on the home screen.
- **FR-020**: The create order form MUST require: fiat amount (or min/max range), fiat currency, at least one payment method, and price type (market or fixed).
- **FR-021**: Market price orders MUST support a premium/discount slider ranging from -10% to +10%.
- **FR-022**: Users MUST be able to add custom free-text payment methods in addition to selecting from the predefined list.
- **FR-023**: The Submit button MUST remain disabled until all required fields are valid.

**Taking an Order**

- **FR-024**: Tapping an order card MUST navigate to a Take Order detail screen showing all order parameters and maker reputation.
- **FR-025**: For range orders, the system MUST show a modal prompting the taker to enter a specific fiat amount within the order's min–max bounds before confirming.
- **FR-026**: The Take Order screen MUST display a countdown timer showing time remaining until the order expires.

**Trade Execution**

- **FR-027**: When a buyer takes a sell order and NWC is NOT configured, the system MUST prompt them to manually enter a Lightning invoice or Lightning address.
- **FR-028**: When NWC is configured, the system MUST automatically generate and submit a Lightning invoice on the buyer's behalf, bypassing the manual entry screen.
- **FR-029**: When a seller takes a buy order and NWC is NOT configured, the system MUST display the hold invoice as a QR code with Copy, Share, and "Pay with Lightning wallet" actions. The "Pay with Lightning wallet" action MUST launch the bolt11 via the `lightning:<bolt11>` URI (using `url_launcher` with `LaunchMode.externalApplication`), and MUST surface a "no Lightning wallet found" SnackBar if no handler is available. Android builds MUST declare a `<queries>` intent for the `lightning` scheme so the launcher can resolve it on Android 11+.
- **FR-030**: When NWC is configured for a seller, the system MUST present a "Pay with Wallet" button that auto-pays the hold invoice. On NWC failure, the system MUST fall back to the manual QR flow defined in FR-029.
- **FR-030a**: The pay-invoice screen MUST subscribe to the live order-status stream (`tradeStatusProvider`) and auto-navigate to Trade Detail on `Active` (or any later non-cancel status) regardless of the local wallet's success callback. This guarantees that the navigation is driven by mostrod's confirmation of the HTLC, not by the seller's wallet reporting a local send, so both QR and NWC paths converge on the same source of truth.
- **FR-030b**: While the seller remains on the pay-invoice screen, terminal cancellation statuses (`canceled`, `cooperativelyCanceled`, `canceledByAdmin`, `expired`) MUST trigger navigation away from the dead invoice with a user-visible cancellation notice.
- **FR-031**: The Trade Detail screen MUST display role-appropriate action buttons based on the current order status and the user's role (buyer or seller).
- **FR-032**: The buyer MUST have a "Fiat Sent" button available when the trade is in "active" status.
- **FR-033**: The seller MUST have a "Release" button available when the trade is in "fiat-sent" status; tapping it MUST show a confirmation modal before executing.
- **FR-034**: Both parties MUST have "Cancel" (cooperative) and "Dispute" buttons available during active trades.

**P2P Chat**

- **FR-035**: Each active trade MUST have a dedicated encrypted chat room accessible from the Trade Detail screen via the Contact button.
- **FR-036**: The chat MUST support text messages, encrypted image attachments, and encrypted file attachments.
- **FR-037**: The chat room MUST display the peer's avatar, handle, and provide access to a Trade Information panel and a User Information panel.
- **FR-038**: The User Information panel MUST display the shared ECDH encryption key as a copyable value so it can optionally be shared with a dispute admin.
- **FR-039**: Messages MUST appear optimistically immediately after send, before relay confirmation.
- **FR-040**: The Chat tab in the bottom navigation MUST show a red dot badge when there are unread messages in any chat room.

**Dispute System**

- **FR-041**: Users MUST be able to open a dispute from the Trade Detail screen when the trade is in "active" or "fiat-sent" status.
- **FR-042**: All disputes MUST appear in a dedicated "Disputes" sub-tab within the Chat screen.
- **FR-043**: Each dispute MUST have a separate encrypted chat room for communication between the user and the assigned admin.
- **FR-044**: The dispute chat input MUST be hidden once the dispute is resolved or closed; the chat becomes read-only with a visible lock message.
- **FR-045**: The seller MUST be able to voluntarily release sats from the Trade Detail screen even while a dispute is active.
- **FR-046**: The system MUST display the dispute resolution outcome clearly (admin released sats vs. admin refunded seller).

**Rating**

- **FR-047**: Both parties MUST be prompted to rate each other after a trade completes: the seller when sats are released, the buyer when payment is confirmed received.
- **FR-048**: The rating interface MUST display 5 tappable stars; the Submit button MUST remain disabled until at least 1 star is selected.
- **FR-049**: Rating MUST be optional — users MUST be able to close the rating prompt without any penalty.
- **FR-050**: Accumulated reputation (average rating, total reviews, days active) MUST be visible on order cards in the public order book.

**NWC Integration**

- **FR-051**: Users MUST be able to connect a Lightning wallet via a NWC URI entered as text or scanned via QR code.
- **FR-052**: The Settings screen MUST display wallet connection status and current balance when NWC is connected.
- **FR-053**: When NWC auto-payment fails, the system MUST fall back to the appropriate manual payment flow without losing trade state.

**Navigation & App Structure**

- **FR-054**: The app MUST have a persistent 3-tab bottom navigation bar: Order Book, My Trades, Chat.
- **FR-055**: A slide-in drawer menu (from left, approximately 70% of screen width) MUST provide access to Account, Settings, and About.
- **FR-056**: The My Trades tab MUST show a red dot badge when there are unseen trade status updates.
- **FR-057**: The Notifications screen MUST be accessible from the notification bell in the app bar and MUST support "Mark all as read" and "Clear all" actions. These actions MUST NOT affect the backup reminder notification.

**Settings & Preferences**

- **FR-058**: Users MUST be able to configure: app language (5 languages: EN, ES, IT, FR, DE), default fiat currency, default Lightning address, relay list (add/toggle), push notification preferences, and Mostro node.

### Key Entities

- **Order**: A buy or sell offer published to the network. Attributes: type (buy/sell), status, fiat amount or min/max range, currency, payment methods, price type, premium, expiration time, maker reputation.
- **Trade**: An in-progress or completed exchange between a maker and a taker. Attributes: user role (buyer/seller), status, fiat amount, sats amount, payment method, creation date, peer identity, session keys.
- **Session**: Local state representing the user's participation in a specific trade. Stores role, counterparty shared encryption key, admin shared encryption key (for disputes).
- **Chat Room**: An encrypted message thread between trade parties, indexed by order ID. Supports text, encrypted images, and encrypted files.
- **Dispute**: A formal escalation of a trade conflict. Attributes: status (initiated → in-progress → resolved/seller-refunded/closed), dispute ID, admin assignment, dedicated encrypted chat.
- **Notification**: An in-app event triggered by trade lifecycle transitions. Attributes: type, icon, title, subtitle, timestamp, read status.
- **Identity / Account**: The user's cryptographic identity (12-word mnemonic, derived keys). Supports two privacy modes: Reputation and Full Privacy.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A new user completes onboarding and reaches the order book in under 2 minutes from first app launch.
- **SC-002**: Users can browse, filter, and identify a suitable order in under 30 seconds without leaving the order book.
- **SC-003**: A complete trade (creation → take → payment → release) can be executed in under 10 minutes by two cooperating users.
- **SC-004**: At least 90% of trades initiated reach completion (success or mutual cancel) without requiring a dispute.
- **SC-005**: Account recovery via 12 secret words succeeds 100% of the time on a new device — users never permanently lose access to their identity.
- **SC-006**: Chat messages are delivered to the counterparty within 5 seconds under normal network conditions.
- **SC-007**: The order book loads and displays available orders within 3 seconds of opening the app on a standard mobile connection.
- **SC-008**: The app is fully localized in all 5 supported languages (EN, ES, IT, FR, DE) with no untranslated strings visible to users.
- **SC-009**: Dispute resolution is reachable within 2 taps from the Trade Detail screen for any active trade.
- **SC-010**: When NWC is connected and responsive, the manual invoice steps are eliminated for 100% of trades.

---

## Assumptions

- The app supports dark mode (default on first launch) and light mode. Both themes must be fully implemented and switchable from Settings.
- The Mostro protocol over Nostr is the sole backend transport; no centralized server or REST API is used.
- Hold invoices are a protocol-level constraint for securing seller funds during a trade; the app cannot change this mechanism.
- The 5 languages (EN, ES, IT, FR, DE) are covered by the existing v1 localization files; new strings follow the same format.
- "Days active" in reputation refers to days since the user's first recorded rating, not account creation date.
- The app targets mobile (iOS and Android), web (PWA), and desktop (macOS, Windows, Linux) as per Constitution Principle V. Web is not optional — it must be a fully functional target from day one. Mobile is the primary design reference.
- Push notifications use a background delivery mechanism; in-app notifications handle foreground delivery.
- The Mostro node selector allows connecting to different Mostro protocol instances; the default is the production trusted node.
- Order expiration is enforced server-side by the Mostro node; the app displays a countdown but does not control it.
- All fiat currency and country flag data is loaded from a bundled asset file; no external currency API is required.
