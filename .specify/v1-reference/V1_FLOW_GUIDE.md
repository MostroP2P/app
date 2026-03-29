# Mostro Mobile v1 — Complete User Flow Guide

> This document captures the exact v1 behavior for replication in v2.
> Each section maps to a speckit phase/task and references existing docs.

---

## 1. First Launch — Key Generation + Walkthrough

**Ref:** [SESSION_AND_KEY_MANAGEMENT.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/SESSION_AND_KEY_MANAGEMENT.md), [AUTHENTICATION.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/AUTHENTICATION.md)

### What happens automatically (no user input):
- App generates a 12-word BIP-39 mnemonic
- Derives HD identity key (NIP-06)
- Stores mnemonic securely (encrypted local storage)
- User never sees this — it's invisible

### What the user sees:
- **Walkthrough screen** (`walkthrough_screen.dart`) — mini tutorial with slides
- Only shown on first launch (stored in SharedPreferences: `has_seen_walkthrough`)
- After walkthrough → navigates to `/` (home/order book)

### On subsequent launches:
- Straight to order book — no walkthrough, no login, no PIN

---

## 2. Persistent Backup Reminder

**Ref:** [NOTIFICATIONS_SYSTEM.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/NOTIFICATIONS_SYSTEM.md), [ACCOUNT_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ACCOUNT_SCREEN.md)

### Notification bell (top-right of AppBar):
- Icon: bell/campana
- **Two indicator states:**
  1. **Red dot** (no number): appears ONLY before user has viewed their secret words (backup reminder). Disappears permanently after viewing words in Account screen.
  2. **Number badge**: green circle (#8CC63F) with white number inside (e.g. "7"), positioned top-right of bell icon. Appears after backup is done, shows count of unread notifications. Number decreases as user opens each notification. Badge disappears when count reaches 0.
- **Shakes slightly** (left-right animation) whenever any indicator is active (red dot OR number badge)
- Once all notifications are read and backup is done → bell is static with no indicator

### Backup reminder:
- **Pinned notification** at the top of notification list (always first)
- Text: "You must back up your account / Back up your secret words to recover your account"
- Stays until user has viewed their secret words in Account screen
- Tapping the notification → navigates to Account screen (`/key_management`)

### Backup flow:
1. User taps backup notification → Account screen
2. First card: "Secret Words" with masked mnemonic (first 2 + last 2 visible, middle masked as •••)
3. User taps "Show" → all 12 words revealed
4. **This action = backup confirmed** (no verification, no re-type)
5. Backup notification dismissed permanently
6. Red dot disappears (if no other notifications pending)

---

## 3. Home Screen — Order Book

**Ref:** [HOME_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/HOME_SCREEN.md), [ORDER_BOOK.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_BOOK.md)

### Layout (top to bottom):
1. **AppBar:** Hamburger menu (left) | Mostro Logo (center, tappable → happy face 500ms) | Notification bell (right)
2. **Tabs:** BUY BTC / SELL BTC (swipeable)
3. **Filter button:** "🔍 Filter" + offer count ("12 offers")
4. **Order list:** Scrollable list of `OrderListItem`
5. **FAB:** Green circular "+" button (bottom-right) — `AddOrderButton`
6. **Bottom nav:** Order Book | My Trades | Chat

### Tab logic (counterintuitive but correct):
- "BUY BTC" tab → shows **sell** orders (makers selling, taker buys)
- "SELL BTC" tab → shows **buy** orders (makers buying, taker sells)
- Labels are from the **taker's perspective**

### Drawer:
- Slides from left (70% width, black 30% overlay behind)
- Contains: Settings, Account, About, Relays, Wallet, etc.

---

## 4. Screens Reference Map

| Screen | Route | v1-reference doc |
|--------|-------|-----------------|
| Walkthrough | `/walkthrough` | (code only) |
| Home/Order Book | `/` | [HOME_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/HOME_SCREEN.md), [ORDER_BOOK.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_BOOK.md) |
| Account | `/key_management` | [ACCOUNT_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ACCOUNT_SCREEN.md) |
| Settings | `/settings` | [SETTINGS_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/SETTINGS_SCREEN.md) |
| About | `/about` | [ABOUT_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ABOUT_SCREEN.md) |
| Create Order | `/add_order` | [ORDER_CREATION.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_CREATION.md) |
| Take Order | `/take_buy/:id`, `/take_sell/:id` | [TAKE_ORDER.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/TAKE_ORDER.md) |
| Trade Detail | `/trade_detail/:id` | [TRADE_EXECUTION.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/TRADE_EXECUTION.md) |
| My Trades | (tab in home) | [MY_TRADES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/MY_TRADES.md) |
| Chat | (tab in home) | [P2P_CHAT_SYSTEM.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/P2P_CHAT_SYSTEM.md) |
| Notifications | `/notifications` | [NOTIFICATIONS_SYSTEM.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/NOTIFICATIONS_SYSTEM.md) |
| Relays | `/relays` | [RELAY_SYNC_IMPLEMENTATION.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/RELAY_SYNC_IMPLEMENTATION.md) |
| Disputes | `/dispute_details/:id` | [DISPUTE_SYSTEM.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/DISPUTE_SYSTEM.md) |
| Rating | (after trade) | [RATING_SYSTEM.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/RATING_SYSTEM.md) |
| Drawer Menu | (overlay) | [DRAWER_MENU.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/DRAWER_MENU.md) |
| Order States | (logic) | [ORDER_STATES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_STATES.md), [ORDER_STATUS_HANDLING.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_STATUS_HANDLING.md) |
| Architecture | (logic) | [ARCHITECTURE.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ARCHITECTURE.md) |
| Nostr Integration | (logic) | [NOSTR.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/NOSTR.md) |
| Mostro Service | (logic) | [MOSTRO_SERVICE.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/MOSTRO_SERVICE.md) |
| Exchange Service | (logic) | [EXCHANGE_SERVICE.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/EXCHANGE_SERVICE.md) |
| NYM Identity | (logic) | [NYM_IDENTITY.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/NYM_IDENTITY.md) |
| Navigation Routes | (logic) | [NAVIGATION_ROUTES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/NAVIGATION_ROUTES.md) |

---

## 5. Home Screen — Visual Specification (from screenshot)

**Ref:** `.specify/v1-reference/HOME_SCREEN.md`
**Screenshot:** `assets/images/screenshot-1.jpg`

### AppBar (top):
- **Left:** Hamburger menu icon (☰) — white, opens drawer overlay
- **Center:** Mostro logo — green skull/monster icon (#8CC63F), tappable (shows happy face 500ms)
- **Right:** Notification bell — white. Shows **red dot** (before backup) or **number badge** (after backup, count of unread). Bell shakes left-right when any indicator is active.

### Tabs (below AppBar):
- **BUY BTC** (left) — active state: green text (#8CC63F) + green underline
- **SELL BTC** (right) — inactive state: gray text
- Swipeable left/right to switch tabs
- "BUY BTC" shows sell orders (taker perspective)

### Filter pill (below tabs):
- Rounded pill shape, full width
- Left: funnel icon + "FILTER" text
- Right: "12 offers" count
- Tapping opens filter dialog

### Order cards (scrollable list):
Each card contains:
1. **Top row:** "SELLING" label (gray) | "a moment ago" timestamp (gray, right-aligned)
2. **Main row:** Fiat amount/range in large white text ("2000 - 10000") + currency code ("ARS") + country flag (🇦🇷)
3. **Price row:** "Market Price" or "Market Price (+5.0%)" in gray
4. **Payment methods row:** Dark pill with payment app icon + comma-separated methods, truncated with "..."
5. **Stats row:** Star rating (green stars, e.g. "4.9 ★★★★★") | user icon + trade count ("20") | calendar icon + days active ("127")

### FAB (Floating Action Button):
**Ref:** [ORDER_CREATION.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_CREATION.md)

- **Collapsed state:** Circular (56dp), green (#8CC63F) background, black "+" icon. Bottom-right, floating above content and bottom nav.
- **Expanded state (on tap):**
  - Main FAB turns gray with black "×" (close) icon
  - Dark overlay dims the entire screen (~30% black)
  - Two rectangular sub-buttons appear stacked vertically above the FAB:
    1. **Buy button** (top): Green (#8CC63F) background, black lightning bolt icon pointing down → navigates to `/add_order` with `orderType: buy`
    2. **Sell button** (bottom): Salmon-pink/red (#FF8A8A) background, black lightning bolt icon pointing up → navigates to `/add_order` with `orderType: sell`
  - Tapping "×" or the overlay collapses the menu back to the green "+" FAB
- See ORDER_CREATION.md for full FAB specs (size, animation, positioning constraints)

### Bottom Navigation Bar:
3 persistent tabs, always visible on main screens. Dark background.

**Tab 1 — Order Book** (route: `/`)
- Icon: list/sheet icon
- Shows the public order book (buy/sell tabs + filtered list)
- This is the default/home screen

**Tab 2 — My Trades** (route: `/order_book`)
- Icon: lightning bolt
- Shows orders the user is participating in (maker or taker)
- Has a **red dot badge** (via `orderBookNotificationCountProvider`) when there are unseen trade updates
- Filterable by status (All, Pending, Active, Success, etc.)
- Sorted by newest first (expiration date descending)
- Tapping a trade → navigates to Trade Detail screen
- Only shows orders that have a local session (i.e., user's own trades)

**Tab 3 — Chat** (route: `/chat_list`)
- Icon: speech bubble
- Has a **red dot badge** (via `chatCountProvider`) when there are unread messages
- Two sub-tabs inside: **Messages** | **Disputes**
- Messages tab: list of chat rooms sorted by most recent, with peer avatar, handle, last message preview, timestamp, and unread dot
- Disputes tab: shows dispute chats (same component as disputes module)
- Tapping a chat room → navigates to `/chat_room/:orderId`
- Unread indicator: red dot on chat item until user opens the room, then marked as read

---

## 6. Drawer Menu (Slide-over from left)

**Ref:** [DRAWER_MENU.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/DRAWER_MENU.md)
**Screenshot:** `https://i.nostr.build/2rEtR7pzzCznarn9.jpg`

### Trigger:
- Tap hamburger icon (☰) on AppBar left
- Slides from left, covers ~70% of screen width
- Background: black overlay at ~30% opacity behind drawer

### Drawer Layout (top to bottom):

**Header:**
- Mostro mascot icon (green hooded character with yellow eyes)
- "Beta" label in yellow-orange text
- "MOSTRO" in large green uppercase text (#8CC63F)
- White horizontal divider line below

**Menu Items:**
| # | Icon | Label | Route | Description | Ref |
|---|------|-------|-------|-------------|-----|
| 1 | Person silhouette | Account | `/key_management` | Secret words backup, privacy mode, generate new user | [ACCOUNT_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ACCOUNT_SCREEN.md) |
| 2 | Gear icon | Settings | `/settings` | Language, fiat currency, lightning address, NWC wallet, relays, push notifications, dev tools, Mostro node selector | [SETTINGS_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/SETTINGS_SCREEN.md) |
| 3 | Info circle (ℹ️) | About | `/about` | App info, docs links, Mostro node details (from kind 38385 event) | [ABOUT_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ABOUT_SCREEN.md) |

### Visual specs:
- Dark background matching app theme
- White outline icons + white text labels
- Generous vertical spacing between items
- Simple, minimal — only 3 navigation items

---

## 7. Create Order Screen (Sell)

**Ref:** [`.specify/v1-reference/ORDER_CREATION.md`](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_CREATION.md)
**Screenshot:** https://i.nostr.build/kmLdjgSB7RqIZPKd.jpg
**Route:** `/add_order` with `extra: {'orderType': 'sell'}`

### AppBar:
- Back arrow (←) + title "CREATING NEW ORDER"

### Form sections (4 cards, top to bottom):

**Card 1 — Order Details:**
- Header: "You want to sell Bitcoin"
- Green currency icon
- Input field: "Enter amount" — fiat amount
- Fiat currency selector (tappable, shows currency selection dialog)
- Supports simple amount OR range mode (min/max)

**Card 2 — Payment Methods:**
- Header: "Payment methods for" + green banknote icon
- Dropdown: "Select payment methods" with ▼ arrow
- Opens multi-select list of payment methods
- Below: free-text input "Enter custom payment method"
- Can select multiple methods + add custom ones

**Card 3 — Price Type:**
- Header: "Price type" + info icon (ℹ️)
- Green dollar icon ($)
- "Market Price" label
- Toggle switch: Market ↔ Fixed
  - Market mode: uses exchange rate + premium/discount
  - Fixed mode: user enters sats amount directly

**Card 4 — Premium (%):**
- Header: "Premium (%)" + info icon (ℹ️)
- Editable value field showing "0" on purple background + pencil icon
- Slider with range: -10% to +10%
- Center marker at 0%
- Only visible when price type = Market

### Bottom action bar:
- **Cancel** button (gray/outline) — goes back
- **Send** button (green/primary) — submits the order
- Submit disabled until all required fields are filled

### Validation:
- Fiat amount required (or min+max for range)
- At least one payment method required
- Sats amount validated against Mostro instance min/max limits
- Custom payment method sanitized (special chars replaced)

---

## 8. Take Order Screen

**Ref:** [TAKE_ORDER.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/TAKE_ORDER.md)
**Screenshot:** https://i.nostr.build/YrTRGSN4fYHJbUa9.jpg
**Routes:** `/take_sell/:orderId` (taker buys BTC), `/take_buy/:orderId` (taker sells BTC)

### AppBar:
- Back arrow (←) + title "SELL ORDER DETAILS" (or "BUY ORDER DETAILS" depending on order type)

### Content: stacked cards with order information

**Card 1 — Order Description + Amount:**
- Text: "Someone is selling sats"
- Text: "for 500 MXN 🇲🇽 at market price (+4.0%)"
- Shows fiat amount, currency code, country flag, price type, and premium

**Card 2 — Payment Method:**
- Left: payment cards icon (white)
- Right: label "Payment Method" (gray) + value "SPEI, Cash at OXXO" (white)

**Card 3 — Creation Date:**
- Left: calendar icon (white)
- Right: label "Created on" (gray) + value "28 mar 2026 12:44" (white)

**Card 4 — Order ID:**
- Label "Order ID" (gray)
- Value: UUID displayed on two lines (white, monospace)
- Copy icon (📋) to copy order ID to clipboard

**Card 5 — Creator Reputation:**
- Label "Creator Reputation" (gray)
- Three stat columns in a horizontal row:
  | Stat | Icon | Example | Label |
  |------|------|---------|-------|
  | Rating | ⭐ (yellow) | 4.5 | "Rating" |
  | Reviews | 👤 (white) | 5 | "Reviews" |
  | Days | 📅 (white) | 32 | "Days" |
- Numbers are large and bold (white), labels are small and gray below

### Countdown Timer:
- Circular progress indicator (silver/gray wedges showing time remaining)
- Text: "Time remaining: 19:48:06"
- Shows how long before the order expires

### Bottom Action Buttons:
- **Close** (left): Green (#8CC63F) outline button, no fill, green text "CLOSE"
- **Buy/Sell** (right): Green (#8CC63F) filled button, dark text "BUY" (or "SELL")
- For range orders: an amount input field appears above buttons for the taker to specify exact fiat amount within the range

### Flow after tapping Buy/Sell:
1. App sends `take-sell` or `take-buy` action to Mostro via NIP-59
2. Shows loading/waiting state
3. On success → navigates to trade detail / order confirmation
4. On error → shows error message (e.g. "Order already taken", "Out of range")
5. On timeout → returns to order book

See [TAKE_ORDER.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/TAKE_ORDER.md) for complete protocol flow and error handling.
See [ORDER_STATES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_STATES.md) for the complete order state machine and all possible status transitions.

---

## 9. Add Lightning Invoice Screen

**Ref:** [TAKE_ORDER.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/TAKE_ORDER.md) (post-take flow)
**Screenshot:** https://i.nostr.build/cacqquWiN0SgjjkB.jpg
**Route:** Shown after taker takes a sell order (buying BTC) when NWC is not configured
**File:** `lib/features/order/screens/add_lightning_invoice_screen.dart`

### When this screen appears:
- User took a sell order (they are buying BTC)
- NWC (Nostr Wallet Connect) is NOT configured
- Mostro needs a Lightning invoice or address to send the BTC payment to

### AppBar:
- Back arrow (←) + title (order context)

### Content card (single rounded card):

**Info text:**
- "Enter a Lightning Invoice of [amount] Sats equivalent to [fiat_amount] [currency] to continue the exchange of the order with ID [order_id]"
- Gray text, left-aligned, multi-line
- Shows exact sats amount, fiat equivalent, and order UUID

**Input field:**
- Label: "Lightning Invoice" (floating label, gray)
- Multi-line text input (supports long invoice strings)
- Dark background input container with rounded corners
- Underline indicator at bottom
- Accepts either a Lightning invoice (lnbc...) or a Lightning address (user@domain)

### Bottom action buttons:
- **Cancel** (left): Text button, gray/white text, no background — goes back
- **Submit** (right): Filled green (#8CC63F) button, dark text "Submit" — sends invoice to Mostro

### Order state context:
This screen appears during the transition from `pending` → `waitingBuyerInvoice` → `waitingPayment` states. See [ORDER_STATES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_STATES.md) for the complete state machine.

### Alternative flow (when NWC IS configured):
- This screen is skipped entirely
- The app automatically generates an invoice via NWC and sends it to Mostro
- User goes directly to the waiting/payment state

### If user has a default Lightning address in settings:
- The input field is pre-filled with the saved address
- User can still modify it before submitting

---

## 10. Range Amount Modal

**Ref:** [TAKE_ORDER.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/TAKE_ORDER.md) (range order flow)
**Screenshot:** https://i.nostr.build/7utwYQ91XKNF73Yt.jpg

### When this modal appears:
- User taps "Buy" or "Sell" on a **range order** (order with min-max fiat amount)
- Shown as a centered dialog/modal over the Take Order screen
- Background dimmed behind the modal

### Modal layout:

**Title:**
- Text describing the action, e.g. "Enter the amount you want to trade"
- White text, left-aligned

**Input field:**
- Numeric input for the fiat amount
- Shows cursor in green (#8CC63F) when focused
- Digits-only keyboard
- Must be within the order's min-max range

**Helper/range text:**
- Shows the valid range, e.g. "Min: 150 - Max: 230 PEN"
- Gray secondary text below input

**Action buttons (bottom-right of modal):**
- **Cancel** (left): Text button, gray text, no background
- **Submit** (right): Filled green (#8CC63F) button, dark text

### Validation:
- Amount must be >= min and <= max of the order range
- Submit button disabled until valid amount entered
- Shows error if out of range

### After submit:
- Modal closes
- Take order flow continues (sends take action to Mostro with the specified fiat amount)
- Order transitions through states defined in [ORDER_STATES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_STATES.md)
- If buying BTC without NWC → shows Add Lightning Invoice screen next

---

## 11. Trade Detail Screen (Active Order — Buyer View)

**Ref:** [TRADE_EXECUTION.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/TRADE_EXECUTION.md), [ORDER_STATES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_STATES.md)
**Screenshot:** https://i.nostr.build/ulWzECZTQK9fzMyO.jpg
**Route:** `/trade_detail/:orderId`

### When this screen appears:
- Both buyer and seller have completed their initial steps
- Buyer submitted Lightning invoice/address
- Seller paid the hold invoice
- Order status: **active**

### AppBar:
- Back arrow (←) + title "ORDER DETAILS"

### Content cards (stacked vertically):

**Card 1 — Trade Summary:**
- "You are buying [sats] sats"
- "for [fiat_amount] [currency] 🇦🇷 [currency]"
- Shows exact sats amount, fiat equivalent, currency code, and country flag

**Card 2 — Payment Method:**
- Left: payment cards icon (gray)
- Right: label "Payment Method" (gray) + value e.g. "CBU" (white)

**Card 3 — Creation Date:**
- Left: calendar icon (gray)
- Right: label "Created on" (gray) + value e.g. "28 mar 2026 17:16" (white)

**Card 4 — Order ID:**
- Label "Order ID" (gray)
- UUID value on two lines (white)
- Copy icon (📋) to copy to clipboard

**Card 5 — Instructions + Status:**
- Green lightning bolt icon (top-left)
- Instructional text (white): "Contact the seller [peer_handle] to arrange how to send [fiat_amount] [currency] using [payment_method]. Once you have sent the fiat money, notify me by pressing the Fiat Sent button."
- Status label at bottom: "Active order"

### Action Buttons (bottom, stacked in rows):

**Row 1 (primary actions):**
| Button | Style | Color | Action |
|--------|-------|-------|--------|
| CLOSE | Outline, green border + green text | #8CC63F outline | Close detail view, go back |
| FIAT SENT | Filled, green bg + dark text | #8CC63F filled | Confirm fiat payment sent → changes order status to `fiat-sent` |

**Row 2 (warning actions):**
| Button | Style | Color | Action |
|--------|-------|-------|--------|
| CANCEL | Filled, red bg + white text | ~#D34F4F | Request cooperative cancel → requires both parties to agree |
| DISPUTE | Filled, red bg + white text | ~#D34F4F | Open dispute → admin intervention |

**Row 3 (communication):**
| Button | Style | Color | Action |
|--------|-------|-------|--------|
| CONTACT | Filled, green bg + dark text, full width | #8CC63F | Open P2P chat with counterparty (`/chat_room/:orderId`) |

### State-dependent button visibility:
Buttons change based on order status as defined in [ORDER_STATES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_STATES.md):
- "FIAT SENT" only visible to buyer in `active` state
- "CANCEL" available to both parties
- "DISPUTE" available to both parties
- "CONTACT" always available during active trade

See [TRADE_EXECUTION.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/TRADE_EXECUTION.md) for complete state machine and button visibility rules per status.

---

## 12. Trade Detail Screen (Fiat Sent — Seller View)

**Ref:** [TRADE_EXECUTION.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/TRADE_EXECUTION.md), [ORDER_STATES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_STATES.md)
**Screenshot:** https://i.nostr.build/4H586RMh5cwIBVXQ.png
**Route:** `/trade_detail/:orderId`
**Order status:** `fiat-sent`

### Context:
- The buyer has confirmed fiat payment by pressing "Fiat Sent"
- The seller now sees this screen with instructions to verify and release

### Info cards:
Same layout as Section 11 (buyer view) — trade summary, payment method, creation date, order ID. The key difference is:

**Card 5 — Instructions + Status:**
- Green lightning bolt icon
- Instructional text: "The buyer [peer_handle] has confirmed that they have sent you [fiat_amount] [currency] using [payment_method]. Once you verify the payment, release the sats."
- Status label: "Fiat sent" (instead of "Active order")

### Action Buttons (seller's view after fiat-sent):

**Row 1 (4 buttons side by side):**
| Button | Style | Color | Action |
|--------|-------|-------|--------|
| CLOSE | Outline, green border + green text | #8CC63F outline | Close detail view |
| RELEASE | Filled, green bg + dark text | #8CC63F filled | **Release sats to buyer** — irreversible, completes the trade |
| CANCEL | Filled, red/coral bg + white text | ~#D34F4F | Request cooperative cancel |
| DISPUTE | Filled, red/pink bg + white text | ~#D34F4F | Open dispute — escalate to admin |

**Row 2 (1 button, full width, centered):**
| Button | Style | Color | Action |
|--------|-------|-------|--------|
| CONTACT | Filled, green bg + dark text | #8CC63F filled | Open P2P chat with buyer |

### Key difference from buyer view (Section 11):
- **Buyer** sees "FIAT SENT" as primary action (confirm payment)
- **Seller** sees "RELEASE" as primary action (release sats after verifying payment)
- The button set changes based on the order status AND the user's role (buyer vs seller)

### Release Confirmation Modal:
**Screenshot:** https://i.nostr.build/bZidPuPN82Ugd1BI.png

When the seller taps RELEASE, a confirmation modal appears centered on screen:

- **Background:** Dark overlay dimming the trade detail screen behind
- **Icon:** Large gray info/confirmation icon at top
- **Title:** "Release Bitcoin" (white, bold)
- **Body:** "Are you sure you want to release the Satoshis to the buyer?" (gray text)
- **Buttons (bottom):**
  - **No** (left): Gray button, white text — dismisses modal, no action
  - **Yes** (right): Green (#8CC63F) button, white text — confirms release

After confirming "Yes":
- Sends `release` action to Mostro via NIP-59
- Order status → `settled-hold-invoice` → `success`
- Buyer receives Lightning payment
- Both parties prompted to rate each other

See [ORDER_STATES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_STATES.md) for complete state transitions.

---

## 13. Rating Screen

**Ref:** [RATING_SYSTEM.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/RATING_SYSTEM.md), [ORDER_STATES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_STATES.md)
**Screenshot:** https://i.nostr.build/8Kz22TeQzN5XWudw.jpg
**File:** `lib/features/rate/rate_counterpart_screen.dart`

### When this screen appears:
- **Seller rates buyer:** when order transitions to `settled-hold-invoice` (sats released, payment in flight)
- **Buyer rates seller:** when order transitions to `success` (buyer received Lightning payment)
- Each party is prompted independently at different moments in the flow

### Screen layout:

**Header:**
- Label: "RATE" (uppercase, gray, small)

**Success indicator:**
- Green double-lightning-bolt icon (indicates successful trade)
- Text: "Successful order" (white)

**Rating prompt:**
- The screen prompts the user to rate their counterparty
- Tapping "RATE" opens the actual rating interface (star selection)

### Action buttons:

| Button | Style | Color | Action |
|--------|-------|-------|--------|
| CLOSE | Outline, green border + green text | #8CC63F outline | Skip rating, return to order book |
| RATE | Filled, green bg + white text | #8CC63F filled | Open star rating interface to submit rating |

### Rating flow:
1. User taps "RATE" on the success screen
2. Navigates to "Rate Counterpart" screen

### Rate Counterpart Screen:
**Screenshot:** https://i.nostr.build/dLYmWtL9T61X48mF.png

**AppBar:**
- Back arrow (←) + title "Rate Counterpart" (white)

**Center content (vertically centered):**
- Label: "RATE" (uppercase, centered)
- **5 star rating widget:**
  - 5 horizontal stars, tappable
  - Selected stars: filled lime green (#8CC63F)
  - Unselected stars: dark gray outline only
  - User taps to select rating (1-5)
- Rating display: "4 / 5" (white text, centered below stars)

**Submit button (bottom, centered):**
- Filled green (#8CC63F) button, rounded corners
- Text: "Submit Rating" (green/white text)
- Sends rating to Mostro via protocol
- After submit → returns to My Trades / order book

### Skip behavior:
- User can tap "CLOSE" to skip rating entirely
- Rating is optional but encouraged
- No penalty for skipping

### Rating timing per role:
| Role | Prompted when | Order status |
|------|--------------|-------------|
| Seller | After releasing sats | `settled-hold-invoice` |
| Buyer | After receiving payment | `success` |

---

## 14. Settings Screen

**Ref:** [SETTINGS_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/SETTINGS_SCREEN.md)
**Screenshot:** https://i.nostr.build/1rDSSUd1xeQ1TgRH.png
**Route:** `/settings` (from Drawer menu)

### 8 setting cards (top to bottom):

| # | Icon | Setting | Action |
|---|------|---------|--------|
| 1 | 🌐 | Language | Tap → modal language list. Default = system locale |
| 2 | 💱 | Default Fiat Currency | Tap → searchable currency dialog (see below) |
| 3 | ⚡ | Lightning Address | Text field (optional), auto-saves |
| 4 | 👛 | NWC Wallet | Shows connection status + balance. Tap → `/wallet_settings` (see NWC section below) |
| 5 | 📡 | Relays | Inline list with status dot (🟢/🔴) + ON/OFF toggle + "Add Relay" button |
| 6 | 🔔 | Push Notifications | Tap → `/notification_settings` |
| 7 | 🛠️ | Log Report | Tap → `/logs` (dev tools) |
| 8 | ⚡ | Mostro Node | Shows truncated pubkey + "Trusted" badge. Tap → node selector modal |

### NWC Wallet (Nostr Wallet Connect):
**Ref:** [NWC_ARCHITECTURE.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/NWC_ARCHITECTURE.md)

**Settings card — disconnected state:**
**Screenshot:** https://i.nostr.build/5rDjTznZCiq6aYYS.png
- Wallet icon + title "Wallet"
- Subtitle: "Connect your Lightning wallet via NWC"
- No balance shown
- Tap → `/connect_wallet`

**Settings card — connected state:**
**Screenshot:** https://i.nostr.build/HsqqrqN3d5RWcfrf.png
- Wallet icon + title "NWC"
- Shows: "Connected. Balance: 11 sats"
- Tap → `/wallet_settings`

**Connect Wallet screen (`/connect_wallet`) — no NWC configured:**
**Screenshot:** https://i.nostr.build/08lXrao4jq8pNVCM.png
- Back arrow (←) + title
- Chain/link icon
- Text input field to paste NWC connection URI (`nostr+walletconnect://...`)
- QR scan button to scan NWC URI from QR code
- Green "Connect" button
- After successful connection → shows balance, redirects to wallet settings

**Wallet Settings screen (`/wallet_settings`) — NWC configured:**
**Screenshot:** https://i.nostr.build/CKLPZQ9B8P812c7e.png
- Back arrow (←) + title "Wallet Configuration"
- **Wallet Info card:** Shows wallet alias, connection status, balance
- **Disconnect button:** To remove the NWC connection
- When NWC is connected, the app auto-generates Lightning invoices during trades (skips the manual Add Invoice screen)

---

### Currency Selection Dialog:
**Screenshot:** https://i.nostr.build/led9hsgIjQLlguLU.jpg

- Full-screen modal dialog
- **Search bar** at top: magnifying glass icon + placeholder "Search currencies..."
- **Scrollable list** of all supported fiat currencies
- Each item: country flag 🇦🇷 + currency code (ARS) + full name (Argentine Peso)
- Tap an item → sets as default fiat currency, dialog closes
- Currency data loaded from `assets/data/fiat.json`

See [SETTINGS_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/SETTINGS_SCREEN.md) for full architecture, persistence, side effects, and sub-screens.

---

## 15. Notifications Screen

**Ref:** [NOTIFICATIONS_SYSTEM.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/NOTIFICATIONS_SYSTEM.md)
**Screenshots:** https://i.nostr.build/88eRv8TknhhzdpD4.png, https://i.nostr.build/2VjCp98YrNVsW63A.png
**Route:** `/notifications`

### Entry point:
- Tap the notification bell icon (top-right of AppBar)
- Bell has red dot when unread notifications exist
- Bell shakes slightly when red dot is active

### AppBar:
- Back arrow (←) + title "Notifications"
- Overflow menu (⋮) on right with:
  - ✅ "Mark all as read" (green checkmark icon)
  - 🗑️ "Clear all" (red trash icon)

### Notification list:
Vertically scrollable list of notification cards on dark background.

### Notification card structure:

```text
┌────────────────────────────────────────────────────────┐
│  [Icon]  Title text                        • ⋮         │
│          Subtitle / description text                   │
│          ┌──────────────────────────────────────────┐  │
│          │ 👤 Buyer: unbanked-bull                  │  │  (optional detail field)
│          │ 🕒 Time limit: 15 minutes                │  │
│          └──────────────────────────────────────────┘  │
│          hace 4 minutos                                │
└────────────────────────────────────────────────────────┘
```

### Card elements:

| Element | Position | Style |
|---------|----------|-------|
| **Icon** (left) | Circular container | Varies by type: ⭐ yellow (rating), 💲 blue (payment), 📄 green (invoice), ➕ green (order taken) |
| **Title** | Top-right of icon | White, bold/semi-bold, ~16sp. E.g. "Rating requested", "Payment settled", "Fiat payment confirmed" |
| **Subtitle** | Below title | Light gray, regular, ~14sp. Description of the event |
| **Detail field** (optional) | Below subtitle, nested card | Darker background with blue left border. Shows key-value pairs: buyer handle, time limit, etc. |
| **Timestamp** | Bottom-left | Gray, small (~12sp). Relative time: "4 minutes ago" |
| **Unread dot** | Top-right corner | Small green (#8CC63F) circle — indicates unread |
| **Item menu** (⋮) | Far right | Three dots for per-item actions |

### Notification types (from screenshots):

| Type | Icon | Title | Detail field |
|------|------|-------|-------------|
| Rating requested | ⭐ yellow | "Rating requested" | — |
| Payment settled | 💲 blue | "Payment settled" | — |
| Fiat payment confirmed | 💲 blue | "Fiat payment confirmed" | — |
| Contact buyer | ➕ green | "Contact the Buyer" | 👤 Buyer: [handle], 🕒 Time limit: 15 min |
| Payment required | 💳 blue | "Payment required" | — |
| Waiting for invoice | 📄 green | "Waiting for invoice" | — |
| **Backup reminder** (pinned) | 🔑 | "You must back up your account" | — (always first, until backup done) |

### Behavior:
- Tapping a notification navigates to the relevant screen (trade detail, rating, etc.)
- Viewing a notification marks it as read (green dot disappears)
- Backup reminder stays pinned at top until user views secret words in Account screen

---

## 16. My Trades Screen

**Ref:** [MY_TRADES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/MY_TRADES.md), [ORDER_STATES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_STATES.md)
**Screenshot:** https://i.nostr.build/JhlLMm5WVUrAY8pO.png
**Route:** `/order_book` (bottom nav tab 2)

### AppBar:
- Same as Home: Hamburger (☰) | Mostro Logo | Notification bell (🔔)

### Sub-header:
- Left: title "My Trades" (bold, white)
- Right: status filter dropdown button: "▼ Status | All"
  - Dropdown allows filtering by order status (All, Pending, Active, Fiat Sent, Success, etc.)
  - Filters are session-only (not persisted to disk)

### Trade cards (scrollable list):
Each trade the user participates in (as maker or taker) is shown as a card:

```text
┌────────────────────────────────────────────────────────┐
│  Selling Bitcoin                                    >  │  Action + chevron
│  [Success]  [Created by you]                           │  Status badge + role badge
│  🏦  966 ARS                                    4m     │  Amount + currency + time ago
│  CBU                                                   │  Payment method
└────────────────────────────────────────────────────────┘
```

### Card elements:

| Element | Position | Style |
|---------|----------|-------|
| **Action text** | Top-left | "Selling Bitcoin" or "Buying Bitcoin" (white, bold) |
| **Chevron** (>) | Top-right | White arrow indicating tappable → navigates to Trade Detail |
| **Status badge** | Below action, left | Colored chip: green "Success", blue "Active", yellow "Pending", etc. |
| **Role badge** | Next to status | Blue chip with "Created by you" or "Taken by you" text |
| **Fiat amount + currency** | Below badges, left | Large white text e.g. "966 ARS" with bank/payment icon |
| **Time ago** | Right of amount | Gray, small text e.g. "4m" |
| **Payment method** | Bottom-left | Gray small text e.g. "CBU", "SPEI", "Mercado Pago" |

### Status badge colors:
See [ORDER_STATES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_STATES.md) for the full list. Key statuses:

| Status | Badge color | Text |
|--------|------------|------|
| Pending | Yellow/amber | "Pending" |
| Waiting Buyer Invoice | Orange | "Waiting invoice" |
| Waiting Payment | Orange | "Waiting payment" |
| Active | Blue | "Active" |
| Fiat Sent | Blue | "Fiat sent" |
| Success | Green | "Success" |
| Canceled | Gray | "Canceled" |
| Dispute | Red | "Dispute" |

### Sorting:
- Sorted by newest first (most recent trade at top)
- Only shows orders where the user has a local session (maker or taker)

### Tap navigation:
- Tapping a card → `/trade_detail/:orderId` (Trade Detail screen)

### Empty state:
- When no trades exist: centered text "No trades" with icon

### Bottom nav:
- **My Trades** tab is highlighted (green icon + text) indicating current screen
- Red dot badge on this tab when there are unseen trade updates

---

## Pending Sections (to document with Negrunch)

- [ ] Create Order flow (add_order_screen)
- [ ] Take Order flow (buy vs sell)
- [ ] Trade execution flow (step by step)
- [ ] P2P Chat during trade
- [ ] Dispute flow
- [ ] Rating after trade
- [ ] Settings screen details
- [ ] Relay management
- [ ] NWC wallet connection
- [ ] Session recovery (12-word restore)

---

*Last updated: 2026-03-28*
