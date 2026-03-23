# Feature Specification: Mostro Mobile v2 — P2P Exchange Client

**Feature Branch**: `001-mostro-p2p-client`
**Created**: 2026-03-22
**Status**: Draft
**Input**: User description: "Multi-platform client for Mostro P2P Bitcoin/Lightning exchange with privacy-first design, offline capability, and responsive layouts across mobile, web, and desktop."

---

## 🔴 Critical Reference: Mostro Protocol

> **All client-server communication MUST follow the Mostro Protocol specification.**
>
> - **Protocol Repository**: https://github.com/MostroP2P/protocol
> - **Local Reference**: [../../.specify/PROTOCOL.md](../../.specify/PROTOCOL.md)

### Order State Machine

The protocol defines 15 order states that the client must support:

```text
pending → waitingBuyerInvoice → waitingPayment → active → fiatSent → settledHoldInvoice → success
                                                    ↓          ↓                              ↑
                                                 dispute → settledByAdmin / completedByAdmin ─┘
                                                    ↓
                                               canceledByAdmin
Any state → canceled (timeout/explicit) / cooperativelyCanceled / expired
waitingPayment → paymentFailed (buyer may resubmit invoice)
```

### Protocol Actions

| Category | Actions |
|----------|---------|
| Order creation | new-order, take-sell, take-buy |
| Trade flow | pay-invoice, add-invoice, fiat-sent, release |
| Cancellation | cancel, cooperative-cancel-initiated-by-you, cooperative-cancel-initiated-by-peer, cooperative-cancel-accepted |
| Disputes | dispute, admin-take-dispute, admin-settle, admin-cancel |
| Rating | rate, rate-received |
| Session management | restore, orders, last-trade-index |

### NIP-59 Three-Layer Encryption

All Mostro messages use NIP-59 Gift Wrap for privacy:

```text
Layer 1: Rumor (kind 38383) — original Mostro message
  ↓ encrypted
Layer 2: Seal (kind 13) — authentication layer (signed by identity key or trade key)
  ↓ encrypted
Layer 3: Gift Wrap (kind 1059) — outer envelope (ephemeral key, no metadata leak)
```

### Protocol Versioning

The protocol may evolve. The client must handle version negotiation from Mostro daemon announcements and be aware of backward compatibility and deprecation warnings.
>
> The protocol defines:
> - Message formats and actions (new-order, take-sell, release, etc.)
> - Order lifecycle and state machine
> - NIP-59 Gift Wrap encryption requirements
> - Event kinds (38383) and tags
>
> **Read the protocol before implementing any Mostro interaction.**

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Complete a Buy Trade (Priority: P1)

A buyer opens the app, browses available sell orders, takes one, pays the Lightning hold invoice, sends fiat payment to the seller, marks fiat as sent, and receives the Bitcoin once the seller confirms receipt. Throughout the trade, a visual progress indicator shows the buyer exactly which step they are on.

**Why this priority**: The core value proposition of the app is enabling peer-to-peer Bitcoin purchases. Without a working buy flow, the app has no purpose.

**Independent Test**: A single user can take a sell order, follow the guided steps, and complete a purchase end-to-end — delivering immediate value.

**Acceptance Scenarios**:

1. **Given** a buyer on the home screen, **When** they filter orders by "Buy" and select a sell order, **Then** they see order details (amount, price, payment method, seller reputation) and a "Take Order" button.
2. **Given** a buyer has taken a sell order, **When** the hold invoice is presented, **Then** they can pay via a connected NWC wallet (automatic) or their external Lightning wallet (QR code or copy-paste).
3. **Given** a buyer with a connected NWC wallet, **When** a hold invoice is presented, **Then** the app pays it automatically and advances the trade without manual copy-paste.
4. **Given** a buyer has paid the hold invoice and sent fiat, **When** they tap "Fiat Sent", **Then** the trade progress indicator advances to "Awaiting Release" and the seller is notified.
5. **Given** the seller confirms fiat receipt, **When** funds are released, **Then** the buyer sees the trade marked as "Complete" and the trade appears in their history.
6. **Given** any step of the trade, **When** the buyer views the active trade screen, **Then** a progress indicator clearly shows the current step, completed steps, and remaining steps.

---

### User Story 2 - Complete a Sell Trade (Priority: P1)

A seller creates a new sell order (or has one taken by a buyer), receives the buyer's Lightning payment into escrow, waits for fiat payment, confirms receipt, and releases the Bitcoin. The progress indicator guides the seller through each step.

**Why this priority**: Selling is the complementary side of buying — both flows are required for the exchange to function. Equal priority with US1.

**Independent Test**: A single user can create a sell order, have it taken, and complete the sell flow end-to-end.

**Acceptance Scenarios**:

1. **Given** a seller on the home screen, **When** they tap "Create Order" and select "Sell", **Then** they can enter amount (fixed or min/max range, in sats or fiat equivalent), price type (market or fixed), and accepted payment method.
2. **Given** a seller has published an order, **When** a buyer takes it, **Then** the seller receives a notification and the progress indicator advances to "Taker Found".
3. **Given** the buyer has paid the hold invoice, **When** the seller sees "Payment Locked" on the progress indicator, **Then** they know funds are in escrow and they should wait for fiat.
4. **Given** the seller receives fiat payment outside the app, **When** they tap "Confirm Fiat Received", **Then** the escrowed Bitcoin is released to the buyer and the trade completes.
5. **Given** the seller wants to cancel before a taker appears, **When** they tap "Cancel Order", **Then** the order is removed and no further action is required.

---

### User Story 3 - Onboarding and Identity Setup (Priority: P1)

A new user opens the app for the first time, creates a new identity (or imports an existing one), optionally sets up device security (PIN or biometric), and connects to relays — arriving at the home screen ready to trade.

**Why this priority**: Users cannot perform any action without an identity. This is the gateway to all other functionality.

**Independent Test**: A new user can install the app, complete onboarding, and arrive at the home screen with a working identity — verifiable without any trades.

**Acceptance Scenarios**:

1. **Given** a first-time user launches the app, **When** onboarding starts, **Then** they see a welcome screen with options to "Create New Identity" or "Import Existing".
2. **Given** a user chooses "Create New Identity", **When** generation completes, **Then** they are shown a mnemonic backup phrase and prompted to confirm they have saved it.
3. **Given** a user chooses "Import Existing", **When** they enter a valid mnemonic phrase or private key, **Then** their identity is restored and they proceed to the next step.
4. **Given** identity is set up, **When** the user is prompted for device security, **Then** they can optionally set a PIN or enable biometric unlock (or skip).
5. **Given** onboarding is complete, **When** the user reaches the home screen, **Then** the app is connected to default relays and displays available orders.

---

### User Story 4 - Browse and Filter Orders (Priority: P2)

A user opens the app and sees a list of available orders from the Mostro network. They can filter by type (buy/sell), fiat currency, and payment method to find relevant offers.

**Why this priority**: Browsing is the entry point to all trades but depends on identity (US3) being set up first. Not independently valuable without the ability to then take an order (US1/US2).

**Independent Test**: A user with a working identity can open the app, see orders, and apply filters — verifiable by observing filtered results.

**Acceptance Scenarios**:

1. **Given** a user with an active identity opens the app, **When** the home screen loads, **Then** they see a list of available orders with key details (type, amount, price, payment method).
2. **Given** the order list is displayed, **When** the user applies a "Buy" filter, **Then** only buy orders are shown.
3. **Given** the order list is displayed, **When** the user filters by a specific fiat currency, **Then** only orders in that currency appear.
4. **Given** the user is offline, **When** they open the order list, **Then** previously cached orders are displayed with a clear "offline" indicator.
5. **Given** orders are displayed, **When** the user taps an order, **Then** they see full order details including amount, price, payment method, and available actions.

---

### User Story 5 - Encrypted Peer-to-Peer Chat During Trade (Priority: P2)

During an active trade, both parties can exchange encrypted messages to coordinate fiat payment details, share payment confirmations, or resolve questions — all without any third party being able to read the messages.

**Why this priority**: Chat is essential for coordinating fiat payments but is only useful during an active trade (depends on US1/US2).

**Independent Test**: Two parties in an active trade can send and receive messages that are delivered and displayed in real time.

**Acceptance Scenarios**:

1. **Given** two users are in an active trade, **When** one sends a message, **Then** the other receives it within a few seconds (when both are online).
2. **Given** a user is offline during a trade, **When** they come back online, **Then** they receive all messages sent while they were offline.
3. **Given** a trade is active, **When** viewing the active trade screen, **Then** the chat interface is accessible alongside the trade progress indicator.
4. **Given** messages are exchanged, **When** either party or any third party inspects network traffic, **Then** message contents are not readable (encrypted end-to-end).
5. **Given** a user in an active trade, **When** they attach a file (image, document, or video up to 25MB), **Then** the file is encrypted, uploaded to a decentralized storage server, and the counterparty can download and view it.
6. **Given** a user receives an image attachment, **When** it downloads, **Then** an inline preview is shown automatically. Non-image files show a download button.
7. **Given** a user closes and reopens the app during an active trade, **When** they view the chat history, **Then** previously received messages are available (loaded from encrypted local storage) without requiring re-download from relays.

---

### User Story 6 - Dispute Resolution (Priority: P2)

If a trade goes wrong (e.g., fiat not received, payment disputes), either party can initiate a dispute. An admin reviews the evidence, communicates with both parties, and resolves the dispute by releasing funds to the appropriate party.

**Why this priority**: Disputes are critical for trust in the platform but are an exception flow — most trades complete without disputes.

**Independent Test**: A user in an active trade can initiate a dispute, submit evidence, receive admin messages, and see the resolution.

**Acceptance Scenarios**:

1. **Given** a user is in an active trade, **When** they tap "Open Dispute", **Then** a dispute is initiated and both parties plus the admin are notified.
2. **Given** a dispute is open, **When** a party submits text evidence, **Then** the evidence is recorded and visible to the admin.
3. **Given** a dispute is open, **When** the admin sends a message, **Then** the relevant party receives it in the dispute chat.
4. **Given** the admin resolves the dispute, **When** funds are released, **Then** both parties see the resolution outcome and the trade moves to a final state.
5. **Given** a dispute is in progress, **When** the user views the trade screen, **Then** the progress indicator shows a clear dispute state distinct from normal trade flow.

---

### User Story 7 - Settings and Relay Management (Priority: P3)

A user can manage their relay connections, view and export their identity, configure app preferences (theme, language), and manage device security settings.

**Why this priority**: Settings are supporting functionality. Sensible defaults mean users can trade without ever visiting settings.

**Independent Test**: A user can open settings, add/remove a relay, change theme, and export their identity backup.

**Acceptance Scenarios**:

1. **Given** a user navigates to settings, **When** they view the relay list, **Then** they see connected relays with health status indicators.
2. **Given** a user in relay settings, **When** they add a new relay URL, **Then** the app connects to it and it appears in the active relay list.
3. **Given** a user in identity settings, **When** they tap "Export Backup", **Then** they receive an encrypted backup of their identity (mnemonic or key file).
4. **Given** a user in preferences, **When** they switch between System, Dark, and Light theme options, **Then** the app immediately reflects the change with a smooth transition and no flash.
5. **Given** a user has not changed any theme setting, **When** the OS is in dark mode, **Then** the app displays in dark theme; when the OS switches to light mode, the app follows automatically without restart.
6. **Given** a user in preferences, **When** they change the language, **Then** all UI text updates to the selected language.
7. **Given** a user in wallet settings, **When** they paste a NWC URI, **Then** the app connects to their wallet and shows connection status and optional balance.
8. **Given** a user has connected relays, **When** the Mostro daemon publishes updated relay lists (kind 10002), **Then** the app auto-syncs new relays without disconnecting existing ones.
9. **Given** a user in developer tools, **When** they enable diagnostic logging and perform actions, **Then** events are captured in memory. They can view, filter, and export logs. Logs contain no sensitive data (keys, tokens, mnemonics). On app restart, logging is disabled and the buffer is empty.

---

### User Story 8 - Trade History (Priority: P3)

A user can view a history of their past trades, including details like date, amount, counterparty, status, and outcome.

**Why this priority**: History is a reference feature — useful but not blocking any core trade functionality.

**Independent Test**: A user who has completed at least one trade can open history and see it listed with correct details.

**Acceptance Scenarios**:

1. **Given** a user with completed trades, **When** they navigate to the history screen, **Then** they see a chronological list of past trades.
2. **Given** the history list is displayed, **When** the user taps a trade, **Then** they see full details including date, amounts, payment method, and final status.
3. **Given** a user with no trade history, **When** they navigate to history, **Then** they see an empty state with guidance on how to start trading.

---

### User Story 9 - Multi-Platform Responsive Experience (Priority: P2)

The app adapts its layout and navigation to the user's screen size: single-column with bottom navigation on phones, optional master-detail on tablets, and multi-panel with side navigation on desktops. Platform-specific features (camera for QR, push notifications, biometric unlock) degrade gracefully where unavailable.

**Why this priority**: The app targets six platforms from day one. Users on any device must have a usable experience.

**Independent Test**: The same app instance renders correctly on a phone-width screen, a tablet-width screen, and a desktop-width screen — verifiable visually.

**Acceptance Scenarios**:

1. **Given** a user on a phone-width screen (<600px), **When** they use the app, **Then** they see a single-column layout with bottom navigation.
2. **Given** a user on a desktop-width screen (>1200px), **When** they use the app, **Then** they see a multi-panel layout with side navigation rail.
3. **Given** a user on the web version without camera access, **When** they need to scan a QR code, **Then** they can paste the content from clipboard or upload an image as a fallback.
4. **Given** a user on a platform without push notification support, **When** a trade event occurs, **Then** they see the update when they next open/focus the app (no silent failure).
5. **Given** a user resizes their browser window across breakpoints, **When** the width crosses a threshold, **Then** the layout transitions smoothly to the appropriate variant.

---

### User Story 10 - Session Recovery (Priority: P2)

A returning user who lost their device or reinstalled the app can enter their mnemonic phrase and recover their active trades, disputes, and trade history from the Mostro daemon. The app reconstructs local state from the daemon's records.

**Why this priority**: Users must trust that their trades are recoverable. Without recovery, users risk losing access to active trades and funds in escrow.

**Independent Test**: A user with a known mnemonic and existing trades on the daemon can restore their session and see active/past trades.

**Acceptance Scenarios**:

1. **Given** a user with a mnemonic and existing trades, **When** they import their mnemonic during onboarding, **Then** the app sends a restore request to the Mostro daemon.
2. **Given** the daemon responds with active order IDs and disputes, **When** the app processes the response, **Then** all active trades and disputes are reconstructed locally with correct state.
3. **Given** recovery completes, **When** the user views their trade list, **Then** they see all active and historical trades with accurate progress indicators.
4. **Given** the user is in privacy mode (no reputation), **When** they attempt recovery, **Then** the app explains that session recovery is unavailable in privacy mode.
5. **Given** recovery completes successfully, **When** the app processes daemon responses, **Then** the trade key index is synchronized so that new trades use the correct next key index without collisions.

---

### User Story 11 - Reputation and Rating (Priority: P2)

After a trade completes successfully, both parties can rate their counterparty. Ratings are stored by the Mostro daemon. Users can optionally trade in privacy mode where no reputation is tracked and trades are fully anonymous.

**Why this priority**: Reputation builds trust in the P2P marketplace. Privacy mode is essential for users who prioritize anonymity.

**Independent Test**: After completing a trade, a user sees a rating prompt, submits a rating, and receives confirmation.

**Acceptance Scenarios**:

1. **Given** a trade completes successfully, **When** the completion screen appears, **Then** the user sees a prompt to rate their counterparty.
2. **Given** a user submits a rating, **When** the rating is sent, **Then** the Mostro daemon acknowledges receipt.
3. **Given** a user receives a rating, **When** a notification arrives, **Then** they can view it.
4. **Given** a user in privacy mode, **When** a trade completes, **Then** no rating prompt appears and no reputation data is sent or received.
5. **Given** a user browsing orders, **When** they view an order's details, **Then** the creator's reputation score is visible (if available and not in privacy mode).

---

### User Story 12 - Deep Links and Order Sharing (Priority: P3)

Users can share orders via deep links (`mostro://order/<id>`) or QR codes. Clicking a shared link opens the app directly to the order detail screen.

**Why this priority**: Enables viral sharing of orders outside the app, but not blocking core trading.

**Independent Test**: A user shares an order link, another user clicks it, and the app opens to that order's detail screen.

**Acceptance Scenarios**:

1. **Given** a user viewing an order, **When** they tap "Share", **Then** the app generates a deep link and/or QR code for the order.
2. **Given** a user with the app installed, **When** they click a `mostro://order/<id>` link, **Then** the app opens directly to that order's detail screen.
3. **Given** a user without the app installed, **When** they click a deep link, **Then** they are directed to download the app.

---

### User Story 13 - Cooperative Cancel (Priority: P2)

During an active trade, either party can request a cooperative cancellation. The counterparty receives the request and can accept or ignore it. If accepted, the trade is canceled and escrowed funds are returned.

**Why this priority**: Cooperative cancel is a common real-world need (e.g., buyer's bank is down, seller can't fulfill). It avoids unnecessary disputes.

**Independent Test**: One party initiates a cancel request, the other accepts, and the trade is canceled with funds returned.

**Acceptance Scenarios**:

1. **Given** an active trade, **When** one party taps "Request Cancel", **Then** the counterparty receives a cancel request notification.
2. **Given** a cancel request received, **When** the counterparty taps "Accept Cancel", **Then** the trade is cooperatively canceled and funds returned.
3. **Given** a cancel request received, **When** the counterparty ignores it (no response), **Then** the trade continues normally and the requester is informed.
4. **Given** a cooperative cancel is accepted, **When** the trade is finalized, **Then** both parties see the trade in history as "Cooperatively Canceled".

---

### Edge Cases

- **Connectivity loss mid-trade**: The app queues outgoing messages and displays a clear offline indicator. Trade state is preserved locally. When connectivity resumes, queued messages are sent and remote state is synced.
- **Mostro daemon goes offline**: The app displays a "daemon unreachable" status. Cached orders remain visible (marked as stale). The user can switch to a different Mostro daemon in settings.
- **Invalid mnemonic during import**: The app validates the mnemonic format immediately and shows a clear error before proceeding. No identity is created from invalid input.
- **Trade timeout (buyer never pays)**: The Mostro protocol handles timeouts server-side. The client reflects the timeout by advancing the trade to a "Canceled/Expired" state with a clear explanation.
- **Force-close during active trade**: Trade state is persisted locally. On next launch, the app resumes from the last known state and syncs with relays to catch up on missed events.
- **Simultaneous order-taking race condition**: The Mostro daemon resolves the race — only one taker succeeds. The losing taker sees an "Order already taken" message.
- **File upload fails mid-transfer**: The app retries the upload. If all retries fail, the file remains in an "unsent" state with a retry button. The text portion of the message (if any) is sent independently.
- **NWC wallet disconnects during invoice payment**: The app detects the disconnect, shows the invoice QR/copy-paste as fallback, and notifies the user to pay manually.
- **Recovery in privacy mode**: The app clearly explains that session recovery is not available in privacy mode (by design — no server-side history).
- **Cooperative cancel after fiat sent**: If the buyer has already marked "Fiat Sent", cooperative cancel still works but displays a strong warning that funds may already be in transit.
- **Payment failed after release**: The Lightning payment to the buyer can fail after the seller releases funds. The client must show a distinct "payment failed" state and allow the buyer to resubmit a new invoice.
- **Admin dispute resolution outcomes**: An admin may settle a dispute (releasing funds to one party) or cancel it (returning funds). The client must display settledByAdmin, completedByAdmin, and canceledByAdmin as distinct final states from normal success/cancel.
- **Mostro instance change**: When the user switches to a different Mostro daemon in settings, all non-default relays must be reset. The client must warn the user before proceeding.
- **NWC wallet reconnection failure**: If the wallet connection drops and auto-reconnect fails within the trade timeout, the client must fall back to manual invoice payment and notify the user.
- **Theme switch during active modal**: If the user or OS triggers a theme change while a modal, dialog, or form is open, the theme must transition without closing the modal or losing user input.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Users MUST be able to create a new identity with a mnemonic backup phrase during onboarding.
- **FR-002**: Users MUST be able to import an existing identity using a mnemonic phrase or private key.
- **FR-003**: Users MUST be able to browse available orders from the Mostro network with key details (type, amount, price, payment method).
- **FR-004**: Users MUST be able to filter orders by type (buy/sell), fiat currency, and payment method.
- **FR-005**: Users MUST be able to create new buy or sell orders specifying amount (fixed or min/max range), price type (market/fixed), and payment method.
- **FR-006**: Users MUST be able to take an existing order, initiating a trade.
- **FR-007**: The system MUST guide the buyer through the complete buy flow: take order, pay invoice, send fiat, mark sent, receive Bitcoin.
- **FR-008**: The system MUST guide the seller through the complete sell flow: publish order, receive taker, lock payment, confirm fiat, release Bitcoin.
- **FR-009**: A visual trade progress indicator MUST show the current step, completed steps, and remaining steps at all times during an active trade.
- **FR-010**: The progress indicator MUST differentiate between buyer flow steps and seller flow steps.
- **FR-011**: Users MUST be able to exchange encrypted peer-to-peer messages during an active trade.
- **FR-012**: Users MUST be able to initiate a dispute during an active trade.
- **FR-013**: Users MUST be able to submit text evidence during a dispute.
- **FR-014**: The system MUST display admin messages and dispute resolution outcomes.
- **FR-015**: Users MUST be able to view a history of past trades with details.
- **FR-016**: Users MUST be able to configure relay connections (add, remove, view status).
- **FR-017**: Users MUST be able to export an encrypted backup of their identity.
- **FR-018**: Users MUST be able to set a PIN or enable biometric device unlock.
- **FR-019**: The system MUST support dark and light themes with a complete set of semantic color tokens that adapt to the active theme, covering backgrounds, text, actions, status indicators, and brand colors.
- **FR-019a**: The system MUST default to following the operating system's theme preference on first launch.
- **FR-019b**: Users MUST be able to override the theme in settings with three options: System (follow OS, default), Dark, or Light.
- **FR-019c**: Theme preference MUST be stored locally on the device and MUST NOT be tied to the user's identity or synced across devices.
- **FR-019d**: Theme transitions (both manual and OS-triggered) MUST be smooth with no flash of the wrong theme on app launch or theme switch.
- **FR-019e**: Both themes MUST meet WCAG AA contrast requirements: minimum 4.5:1 for normal text and 3:1 for large text and interactive elements.
- **FR-019f**: Brand and action colors (buy/sell indicators, status chips, submit buttons) MUST remain visually consistent and recognizable across both themes.
- **FR-020**: The system MUST support multiple languages (internationalization).
- **FR-021**: The system MUST notify users of trade events (new taker, payment received, trade complete, dispute updates).
- **FR-022**: The system MUST provide QR code scanning for Lightning invoices, with a paste/upload fallback on platforms without camera access.
- **FR-023**: Users MUST be able to cancel their own unpublished or untaken orders.
- **FR-024**: The system MUST persist all trade state, messages, and orders locally so that data is never lost due to connectivity issues.
- **FR-025**: The system MUST queue outgoing messages when offline and deliver them when connectivity resumes.
- **FR-026**: The system MUST work with any conforming Mostro daemon, not a specific instance.
- **FR-027**: Users MUST be able to connect a Nostr Wallet Connect (NWC-compatible) wallet by pasting a NWC URI.
- **FR-028**: When a NWC wallet is connected, the system MUST pay hold invoices automatically during trades.
- **FR-029**: Users MUST be able to send encrypted file attachments (images, documents, videos up to 25MB) during trade chat, stored on decentralized Blossom servers.
- **FR-030**: Image attachments MUST show inline previews; non-image files MUST show a download button.
- **FR-031**: Users MUST be able to recover active trades and disputes by importing their mnemonic phrase (reputation mode only).
- **FR-032**: The system MUST derive trade-specific keys using a deterministic path from the master mnemonic.
- **FR-033**: Users MUST be able to rate their counterparty after a successful trade.
- **FR-034**: Users MUST be able to trade in privacy mode (no reputation tracking, anonymous trades).
- **FR-035**: Users MUST be able to share orders via deep links and QR codes.
- **FR-036**: The app MUST handle `mostro://order/<id>` deep links by opening the corresponding order.
- **FR-037**: Either party in an active trade MUST be able to request a cooperative cancellation.
- **FR-038**: The counterparty MUST be able to accept or ignore a cooperative cancel request.
- **FR-039**: The system MUST auto-sync relay lists from the Mostro daemon's kind 10002 events.
- **FR-040**: The system MUST display countdown timers for time-limited trade states.
- **FR-041**: The system MUST support background notifications for trade events on mobile (even when app is killed).
- **FR-042**: For sell orders, the buyer MUST be able to submit a Lightning invoice for receiving payment.
- **FR-043**: The system MUST display all 15 protocol-defined order states (pending, waitingBuyerInvoice, waitingPayment, active, fiatSent, settledHoldInvoice, success, paymentFailed, canceled, cooperativelyCanceled, dispute, settledByAdmin, completedByAdmin, canceledByAdmin, expired) with visually distinct indicators for each.
- **FR-044**: The system MUST support both standard privacy mode (reputation-linked identity) and full privacy mode (trade-key-only identity with no cross-trade linking) as a global toggle in settings. The selected mode applies to all future trades; existing trades retain the mode they were started with.
- **FR-045**: Chat messages MUST be stored encrypted at rest and decrypted only in active memory, never persisted in plaintext.
- **FR-046**: The NWC wallet connection MUST auto-reconnect on failure with backoff, and MUST fall back to manual invoice payment if the wallet remains unreachable.
- **FR-047**: File attachment uploads MUST fall back across multiple decentralized storage servers if the primary server is unreachable.
- **FR-048**: The system MUST handle the paymentFailed order state by displaying a distinct status and allowing the buyer to resubmit a Lightning invoice.
- **FR-049**: Push notifications MUST NOT expose trade content or message text; notification payloads MUST be silent/contentless on platforms that support push.
- **FR-050**: The system MUST provide an opt-in diagnostic logging mode accessible from a developer/debug section in settings. Logging MUST capture events in an in-memory buffer (not persisted to disk), strip all sensitive data (keys, tokens, mnemonics), and reset to disabled on each app restart.
- **FR-051**: Users MUST be able to view, filter, search, and export diagnostic logs from within the app. Exported logs MUST be shareable via the system share sheet or saved to a file.

### Key Entities

- **Identity**: The user's cryptographic identity — includes public/private keypair and mnemonic backup. One identity per app installation. Supports two privacy modes: standard mode (identity key signs the encryption seal, enabling reputation linking across trades) and privacy mode (trade key signs the seal, preventing cross-trade reputation linking). Key derivation follows a deterministic hierarchical path from the master mnemonic (identity key at index 0, trade keys at index ≥ 1).
- **Order**: A buy or sell offer on the Mostro network — includes type (buy/sell), amount (fixed or min/max range), price, fiat currency, payment method, status, and creator identity. Orders transition through 15 protocol-defined states: pending, waitingBuyerInvoice, waitingPayment, active, fiatSent, settledHoldInvoice, success, paymentFailed, canceled, cooperativelyCanceled, dispute, settledByAdmin, completedByAdmin, canceledByAdmin, expired.
- **Trade**: An active transaction between a buyer and seller — links an order, both parties' identities, the current progress step, and associated messages. Only one trade active at a time (v2.0 scope).
- **Message**: An encrypted communication between two parties (or between a party and admin during disputes). Uses three-layer NIP-59 encryption (Rumor inside Seal inside Gift Wrap). P2P chat messages use a shared key derived via ECDH between trade keys; admin/dispute messages use the trade key directly. Messages are stored encrypted on disk and decrypted only in active memory. Includes sender, recipient, content, timestamp, and read status.
- **Relay**: A connection endpoint the app communicates through — includes URL, connection status, health metrics, and source classification (default, Mostro-discovered, user-added). Users can add, remove, and blacklist relays. Blacklisted relays are not re-added even if the daemon announces them.
- **Dispute**: An exception flow on an active trade — includes initiator, evidence submissions, admin communications, and resolution outcome. Uses a separate chat channel from P2P chat, encrypted with the trade key.
- **NWC Wallet**: A Nostr Wallet Connect connection — includes wallet pubkey, relay URL, secret, connection status, and optional balance. Uses a dedicated connection isolated from the main relay pool. Payment priority: automatic via connected wallet first, then manual fallback (QR/copy-paste). Must auto-reconnect with backoff on failure and provide periodic health monitoring.
- **File Attachment**: An encrypted file sent in trade chat — includes file type, size, encryption metadata, Blossom server URL, and download status. Supported types: images (JPG, PNG, GIF, WEBP with auto-preview), documents (PDF, DOC, TXT, RTF), videos (MP4, MOV, AVI, WEBM). Maximum 25 MB per file. Linked to a message.
- **Rating**: A post-trade counterparty rating — includes trade ID, score, and submission status. Only available in reputation mode.
- **Theme Preference**: A device-local setting with three values: System (follow OS), Dark, or Light. Persisted across app restarts. Not tied to user identity or mnemonic backup.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A buyer can complete a purchase from order selection to Bitcoin receipt within a single session, with the progress indicator accurately reflecting each step.
- **SC-002**: A seller can create an order and complete a sale from publication to fund release within a single session, with the progress indicator accurately reflecting each step.
- **SC-003**: A new user can complete onboarding (identity creation, optional security setup, relay connection) and reach the home screen in under 2 minutes.
- **SC-004**: The app launches and displays the order list within 2 seconds on standard mobile hardware.
- **SC-005**: Online messages between trade parties are delivered and displayed within 1 second.
- **SC-006**: The app remains fully functional for browsing cached orders and composing messages while offline, sending queued messages within 5 seconds of reconnection.
- **SC-007**: The app renders correctly and is fully usable on all six target platforms (iOS, Android, Web, macOS, Windows, Linux) with appropriate layout for each screen size.
- **SC-008**: On platforms without camera access, users can complete QR-dependent actions (e.g., paying a Lightning invoice) via paste or file upload within the same number of steps.
- **SC-009**: All peer-to-peer and daemon communications pass independent encryption verification — no plaintext message content is observable on the network.
- **SC-010**: Users who force-close and reopen the app during a trade resume from the correct step with no data loss.
- **SC-011**: Dispute initiation, evidence submission, and resolution display work end-to-end with clear status distinct from normal trade flow.
- **SC-012**: The app works correctly with at least two different Mostro daemon instances, confirming no single-daemon dependency.
- **SC-013**: A user with a connected NWC wallet can complete a buy trade without manually copying/scanning any invoice — the payment happens automatically.
- **SC-014**: Users can send and receive encrypted file attachments (images with preview, documents with download) during a trade chat.
- **SC-015**: A user who reinstalls the app can recover active trades and history by entering their mnemonic phrase (reputation mode).
- **SC-016**: After a successful trade, both parties can rate their counterparty, and ratings are reflected in order listings.
- **SC-017**: A shared order deep link opens the correct order detail screen when clicked on any supported platform.
- **SC-018**: Cooperative cancellation completes within one interaction per party — requester taps "Request Cancel", counterparty taps "Accept".
- **SC-019**: Both dark and light themes meet WCAG AA contrast requirements (4.5:1 normal text, 3:1 large text) across all screens, verified by automated contrast checking.
- **SC-020**: The app follows the OS theme preference by default and responds to OS theme changes within 1 second without requiring a restart.
- **SC-021**: All 15 protocol-defined order states are visually distinguishable in the trade progress indicator and trade history.
- **SC-022**: Chat messages stored on disk cannot be read without the corresponding decryption key — verified by inspecting local storage directly.

### Assumptions

- The Mostro protocol specification is stable and publicly documented. Trade timeouts and escrow mechanics are handled server-side by the daemon.
- One active trade at a time is sufficient for v2.0 (multiple simultaneous trades are a future enhancement).
- Fiat payment happens outside the app — the app only tracks that the user has marked fiat as sent/received.
- A built-in Lightning wallet is out of scope — users pay invoices via external wallet or connected NWC wallet.
- Default relay connections are preconfigured so users can start trading immediately after onboarding.
- Push notification availability varies by platform; the app gracefully falls back to in-app notifications where push is unavailable.
- All protocol logic — NIP-59 encryption/decryption, key derivation, order state machine enforcement, message serialization/deserialization — MUST run in a shared core layer, not in the UI layer. The UI layer handles only rendering and platform-specific concerns (camera, notifications, biometrics, file system). Implementation details (language/runtime, bridging mechanism) are documented in [ARCHITECTURE.md](../../.specify/ARCHITECTURE.md).
- The NIP-59 three-layer encryption model (Rumor inside Seal inside Gift Wrap) is a Mostro protocol requirement. All client-daemon and peer-to-peer communication must use this model.
- The key derivation path m/44'/1237'/38383'/0/N (N=0 identity key, N≥1 trade keys) is fixed by the Mostro protocol for cross-client compatibility.

## Clarifications

### Session 2026-03-23

- Q: Does this app include admin dispute management UI, or only the user side? → A: User-side only — this app shows dispute status and receives admin messages, but has no admin login or dispute management screens. Admins use a separate tool.
- Q: When does the user choose between standard and privacy mode? → A: Global toggle in settings — user can switch mode anytime, applies to all future trades. Existing trades retain the mode they were started with.
- Q: Does the app support range orders (min/max amount) or fixed amounts only? → A: Range orders supported — user can specify min/max amount; taker picks exact amount within range. This preserves v1 parity with the Mostro protocol.
- Q: Should the app include a diagnostics/logging feature? → A: Yes — include as P3. Opt-in diagnostic logging with in-memory buffer, log viewer, export, privacy-safe (no keys/secrets), resets to off on each app restart.

### Non-Goals (v2.0 Scope)

- Multiple simultaneous active trades
- Fiat payment integration or escrow
- Built-in Lightning wallet (NWC integration is in scope; built-in node is not)
- Order book aggregation across multiple Mostro daemons
- Admin dispute management UI (admins use a separate tool; this app only displays the user side of disputes)
