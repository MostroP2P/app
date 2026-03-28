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
- **Red dot** appears when there are unread notifications
- **Shakes slightly** (left-right animation) when red dot is active
- Red dot disappears only when user views all notifications

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
- **Right:** Notification bell — white, with **red dot badge** when unread notifications. Bell shakes slightly when active.

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
| 2 | Gear icon | Settings | `/settings` | Language, default fiat, lightning address, notifications | [SETTINGS_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/SETTINGS_SCREEN.md) |
| 3 | Info circle (ℹ️) | About | `/about` | Mostro instance info, version, relays, pubkey | [ABOUT_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ABOUT_SCREEN.md) |

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

See [TAKE_ORDER.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/TAKE_ORDER.md) for complete protocol flow, state transitions, and error handling.

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
