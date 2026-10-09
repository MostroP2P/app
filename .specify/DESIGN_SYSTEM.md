# Mostro v2 — Design Guide

This guide is the standard a UI change is judged against. A proposal that keeps every **MUST**
here can be accepted on its design; a proposal that breaks one is rejected, or it changes this
guide first (§13). Every rule has an ID, so a review can say "breaks DS-COL-3" instead of
arguing taste.

The values come from the shipped redesign (the code under `lib/core/` and the screens built on
it), not from v1. v2 keeps v1's brand, the lime and the sell red on dark backgrounds, and its
information architecture. It does not keep v1's look.

---

## 0. How to read this guide

- **MUST** is a requirement: breaking it rejects the change. **SHOULD** is the default; a change
  that departs from it says why in the pull request. **MAY** is allowed, not required.
- **Check** says who catches a break:
  - *auto*: the **Design guide** CI job (`tool/design_check.dart`) fails the pull request and
    marks the line. It reads the code the pull request touches under `lib/` (outside
    `lib/core/`, where tokens are defined): every top-level declaration (a class, mixin, enum,
    extension, function or variable) with an added or changed line, **read whole**, so a
    button whose `icon:` changed is checked for its `style:`. A **screen** (a file under a
    `screens/` directory) is read whole instead: a rename or any added, changed or removed line
    checks the entire file. It judges literal values and
    named v1 tokens only: a value derived from a token is left to review. Run it locally with
    `dart tool/design_check.dart`.
  - *test*: an existing test fails.
  - *review*: a reviewer reads the diff and the screenshots.
- **Scope.** The rules apply to every line a pull request adds or changes under `lib/`, and the
  *auto* rules to every class it touches and every screen file it touches (above). Code that predates them is listed in §14 as
  known gaps. A gap is debt to pay down, never a precedent: "the next screen already does it"
  does not answer a break.
- **Redesigned and legacy areas.** Most screens are built on the redesign palettes (§2.2). A few
  still run on the v1 layer, `AppColors` and the theme's defaults: the chat room and its message
  bubbles, disputes, notifications, rating and the Cashu wallet. That code is
  §14 debt, not a style to match. **New code is v2 everywhere**, a legacy screen included: it
  reads a redesign palette (DS-COL-11) and never leans on the theme's v1 defaults (§1,
  principle 7). A change that touches a screen file **MUST** leave the whole file free of
  *auto* breaks, and one that touches a class elsewhere (a widget) MUST leave that class
  free of them; CI enforces both (#657 changed one icon of the Cashu wallet and shipped its
  v1 scaffold, app bar and buttons with a green check, then its dialogs' breaks once the
  check read only the classes it touched).

---

## 1. Principles

1. **One accent.** Lime `#92D64F` is the only accent and means "your move", "go" or "good".
   Nothing else is green.
2. **Legible first.** Every text color passes WCAG AA on the surface it really sits on, in both
   themes. A color that fails is adjusted until it passes, even when a handoff specifies it.
3. **Tokens, not numbers.** A widget reads its colors, fonts and radii from `lib/core/`. A literal
   in a widget is the beginning of a second design system.
4. **One component per job.** There is one way to show a dialog, one primary button, one chip
   shape. Before a new widget is built, the existing one is reused or extended.
5. **Both themes, every locale, every text size.** Dark is the default, and light is a full theme,
   not a fallback. Each screen holds up in German at 320 dp wide with text scaled to 2×.
6. **Calm.** Surfaces are flat. Motion is short. A screen in a waiting state has no call to
   action that shouts.
7. **No theme defaults.** `ThemeData` still carries v1's values: its scaffold background,
   app bar, input decoration and button shapes (a Material button with no style is a stadium in
   v1 colors). So a widget that leaves its style to the theme looks like v1 even with no literal
   in it. Material buttons, app bars, scaffolds and text fields always set their own style from
   the palette, or come from a shared component that does (DS-CMP-12, DS-CMP-17 to DS-CMP-19).

---

## 2. Color

### 2.1 Where colors come from

| ID | Rule | Check |
|---|---|---|
| DS-COL-1 | **MUST.** Outside `lib/core/`, no color literal: no `Color(0x…)`, `Color.fromARGB/fromRGBO`, or `Colors.<name>` other than `Colors.transparent`. Every color is a token of a palette in `lib/core/`. | auto |
| DS-COL-2 | **MUST.** A widget reads the palette of its area (§2.2). A screen in a new area reuses `OrderBookPalette` or adds `lib/core/<area>_palette.dart`, with a `dark` and a `light` constant, `of(context)`, and a contrast test (DS-COL-6). | review |
| DS-COL-3 | **MUST.** No new green. The accent is `lime` `#92D64F` everywhere, `AppColors.mostroGreen` included (`modal_contrast_test.dart`: "the app has exactly one accent"). | test |
| DS-COL-4 | **MUST.** A shape filled with an accent carries that accent's ink, never white: `onLime` `#12161F` on `lime` (10.6:1; white is 2.05:1), and `onSell` `#2A1015` on `sell`. | test, review |
| DS-COL-5 | **MUST.** On a light surface, lime as text or as a thin stroke uses the light ink, `limeText` `#3E6B1C` for text and `#5C9130` for dots and borders. Lime itself on white is 1.76:1. | review |
| DS-COL-6 | **MUST.** Every new text color in a palette is asserted at **4.5:1** against each surface it renders on, in dark and light, in that palette's `test/core/*_contrast_test.dart`. A translucent fill is first flattened onto its real surface with `flatten()`. | test |
| DS-COL-7 | **SHOULD.** Non-text elements that carry meaning (status dots, input borders, focus rings, meaningful icons) reach **3:1** against their surface (WCAG 1.4.11). No test checks this yet. | review |
| DS-COL-8 | **MUST.** A new token reuses a canonical value (§2.3). It differs only where a contrast test forces it, with a comment that says so (as `textFaint` does). | review |
| DS-COL-11 | **MUST.** New code never reads `AppColors`, the v1 layer, not even inside a legacy screen. It reads the area's redesign palette, or `OrderBookPalette` where the area has none. | auto |

### 2.2 Palette per area

| Area | Palette (`lib/core/`) |
|---|---|
| Order book, shell (bottom bar, app bars, create-order button), modals | `order_book_palette.dart` (`OrderBookPalette`, the base the others extend) |
| Order detail, take order, my order | `order_detail_palette.dart` |
| Create order, payment-method picker | `create_order_palette.dart` |
| Invoices and bonds | `invoice_palette.dart` |
| Trade detail, timeline, action bar | `trade_palette.dart` |
| Trades list, chat list, disputes list, notification groups, bond banner | `activity_palette.dart` |
| Settings, relays, wallet, logs | `settings_palette.dart` |
| Node selector | `node_selector_palette.dart` |
| Account and backup | `backup_palette.dart` |
| Restore | `restore_palette.dart` |
| About | `about_palette.dart` |
| Drawer | `DrawerPalette` in `app_theme.dart` |
| Legacy areas (§0) | Built on `AppColors`, the v1 layer: debt (§14). New code there reads `OrderBookPalette` (DS-COL-11). |

All dialogs and sheets render on `OrderBookPalette.surface` with `OrderBookPalette.scrim`. The
theme applies this through `dialogTheme` and `bottomSheetTheme`, so no modal sets it itself.

### 2.3 Canonical values

New tokens take these values (DS-COL-8). Format: dark / light.

| Role | Value | Typical token |
|---|---|---|
| Page background | `#12161F` / `#F4F6F4` | `bg` |
| Card and modal surface | `#1A2030` / `#FFFFFF` | `surface` |
| Bottom bar and action bar | `#151A24` / `#FFFFFF` | `surfaceNav` |
| Scrim | `#080B10` at 82% (both) | `scrim` |
| Accent fill + ink | `#92D64F` + `#12161F` (both) | `lime`, `onLime` |
| Accent as text | `#92D64F` / `#3E6B1C` | `limeText` |
| Soft accent ink (chips, valid) | `#C6F09A` / `#3E6B1C` | `limeInk`, `*ActiveInk`, `validInk` |
| Accent icon | `#B7E38A` / `#4E7D28` | `limeIcon` |
| Accent dot or stroke | `#92D64F` / `#5C9130` | `*Dot`, `online` |
| Sell fill + ink | `#FF8B8B` + `#2A1015` (both) | `sell`, `onSell` |
| Sell-side text | `#FFB4B4` / `#9A2F2A` | `sellInk` |
| Danger and error text | `#FF8B8B` / `#C2403A` | `danger`, `error` |
| Waiting and warning text | `#F7DE72` / `#7A5D00` | `*WaitInk`, `warnInk` |
| Waiting and warning dot | `#F2D14B` / `#D8AF19` | `*Dot` |
| Neutral and closed text | `#A6B0C2` / `#3F4756` | `*DoneInk`, `neutralInk` |
| Neutral and offline dot | `#5D6879` / `#8A94A6` | `offline`, `muted` |
| Text, primary | `#EEF1F6` / `#12161F` | `textPrimary` |
| Text, body | `#D6DCE8` / `#2A303C` | `textBody` |
| Text, secondary | `#8B97AD` / `#5A6474` | `textSecondary` |
| Text, labels and group headers | `#808A9E` / `#5F6979` | `fieldLabel`, `groupHeader` |

### 2.4 What the colors mean

| ID | Rule | Check |
|---|---|---|
| DS-COL-9 | **MUST.** Colors keep one meaning each. Lime means the user's turn, success or valid. Amber means waiting or a warning. Red (`sell`/`danger`) means the sell side, an error or danger. Neutral grey means closed, done or inactive. A dispute is red. No color is used against its meaning: a red success, or a lime warning. | review |
| DS-COL-10 | **MUST.** Color is never the only signal. A status also has a visible word, or an icon that carries a semantic label (`semanticLabel`, or `Semantics(label: …)`), so a colorblind user and a screen reader both get it. An icon without a label fixes the first and not the second. | review |

---

## 3. Typography

### 3.1 Families

| ID | Rule | Check |
|---|---|---|
| DS-TYP-1 | **MUST.** Two families, both through `AppFonts`: `AppFonts.ui` (Outfit) for interface text, which is the theme default and needs no setting, and `AppFonts.figures` (Manrope). A third, `AppFonts.flags`, is a fallback for flags only (DS-TYP-8). No family is named as a string literal. Machine strings (invoices, keys, hashes, event ids) MAY use `'monospace'`. | auto |
| DS-TYP-2 | **MUST.** Figures that line up or get compared use `AppFonts.figures`, with tabular digits: amounts, sats, fiat, premiums, ratings, counters, countdowns. | review |
| DS-TYP-3 | **MUST.** Manrope always sets `fontWeight` explicitly to 500, 600 or 700. Only those weights are bundled; an unset (400) weight renders as Medium. | review |
| DS-TYP-8 | **MUST.** A flag (a currency's, a node's region) is drawn from `AppFonts.flags`, the flags of Noto Color Emoji bundled with the app, never left to the OS: Linux and Windows have no flag glyphs and print two boxed letters (`AR`). Both themes carry it as `fontFamilyFallback`, so text that inherits the theme needs nothing; a style with `inherit: false` or its own `fontFamilyFallback` adds `flagFontFallback`. iOS and macOS are the exception: Core Text cannot draw the font's bitmaps (CBDT), and their own emoji font has every flag. The font is built by `tool/flags_font/build_font.py`, never edited by hand. | test (`flag_font_test.dart`) |

### 3.2 Scale

The redesign writes sizes per role rather than reading `textTheme`. These are the sizes in use,
and the only ones allowed:

| Size (sp) | Role |
|---|---|
| 10 | Chip and caps labels, bottom-bar labels, badges. **The minimum.** |
| 11 | Meta text, captions, group headers, timestamps |
| 12 | Secondary body, helper and error text under a field |
| 13 | Body inside cards and rows, compact buttons, links |
| 14 | Primary body, dialog body |
| 15 | Buttons, app-bar title, card title |
| 17 | Dialog and sheet title, section title |
| 19 | Screen headline, headline figure in a list |
| 22 | Hero title (walkthrough, empty states, sheets that open a flow) |
| 26, 38 | Hero figures only (`AppFonts.figures`): an amount that is the screen's subject |

| ID | Rule | Check |
|---|---|---|
| DS-TYP-4 | **MUST.** A literal `fontSize` is one of the sizes above. No half points and nothing under 10. A `textTheme` role counts as its size: only the roles the theme sets on the scale (`bodyMedium` 14, `bodySmall` 12, `labelLarge` 14, `labelSmall` 11) are allowed. | auto |
| DS-TYP-5 | **SHOULD.** Weights: 400 for running text, 500 for labels and secondary buttons, 600 for titles, primary buttons and emphasis (the default for emphasis), 700 for hero figures. Write `FontWeight.wNNN`. | review |
| DS-TYP-6 | **SHOULD.** Multi-line body text uses a line height of 1.4–1.5. Letter spacing is reserved for caps labels (0.3–0.6) and large figures (negative). | review |
| DS-TYP-7 | **MUST.** Text scaling is never disabled or clamped: no `TextScaler.noScaling`, and no `MediaQuery` override of `textScaler`. A button label stays on one line and may shrink to fit (`FittedBox(fit: BoxFit.scaleDown)`, as `OrderPrimaryButton` does). Body text wraps. | auto, review |

In legacy areas the theme's `textTheme` roles (`bodySmall`, `bodyMedium`, …) remain in use; new
code there sets its sizes from the scale above. A role the theme does not define (`titleMedium`, `titleLarge`, `labelMedium`)
falls back to Material defaults and is not allowed in new code.

---

## 4. Shape and elevation

| Radius | Use |
|---|---|
| 999 (pill) | Chips, segmented controls, count badges, sheet grabber |
| 24 | Dialog and sheet containers (`AppRadius.modal`, applied by the theme) |
| 18 | Cards, list rows, grouped settings sections, drawer rows |
| 16 | In-page call to action (primary and its outlined sibling) |
| 14 | Modal actions (`AppRadius.cta`), compact secondary buttons, boxed inputs |
| 12 | Tiles inside a card, snackbars, small containers |
| 8 | Thumbnails, QR frames, small insets |

| ID | Rule | Check |
|---|---|---|
| DS-SHP-1 | **MUST.** A radius is one of the values above. | auto |
| DS-SHP-2 | **SHOULD.** Through a named constant, an `AppRadius` token or a file-level `const`, rather than a bare number in a `BorderRadius`. | review |
| DS-SHP-3 | **MUST.** Surfaces are flat: no `elevation` above 0 and no shadow, except the primary call to action's `ctaShadow` and the dialog's own shadow. Depth comes from the surface color, `inset` and the 1-px `border` tokens. | review |
| DS-SHP-4 | **MUST.** New code does not read the radius tokens that keep v1's roles: `AppRadius.card` (12; a card is 18), `AppRadius.button` and `AppRadius.input` (8; a call to action is 16, a boxed input 14) and `AppRadius.chip` (6; a chip is a pill). `AppRadius.modal`, `AppRadius.cta` and `AppRadius.bubble` are the redesign's. | auto |

---

## 5. Spacing and layout

| ID | Rule | Check |
|---|---|---|
| DS-SPC-1 | **MUST.** Screen content is inset **18** from the side edges (`redesignSidePadding`). The drawer predates the rule with its own 22/14 (§14). | review |
| DS-SPC-2 | **MUST.** Paddings, gaps and margins come from the 2-pt scale **2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 24, 28, 32**. Odd values are not allowed, except 1 for a hairline. | auto |
| DS-SPC-3 | **SHOULD.** Card inner padding is 14. Rows in a list are 12 apart, sections 18–24 apart. A label sits 6–8 above its field. | review |
| DS-SPC-4 | **MUST.** Breakpoints come from `AppBreakpoints` (600 tablet, 1200 desktop); no other width threshold. Mobile has 1 column, a bottom bar and an overlay drawer. Tablet has 2 columns. Desktop has 3 columns and a persistent drawer, and no bottom bar. | auto, review |
| DS-SPC-5 | **MUST.** Every screen works from 320 dp wide. Content that can outgrow the screen scrolls, and the action bar stays pinned at the bottom inside a `SafeArea`. | test, review |

---

## 6. Components

Reuse before building (principle 4). These are the parts a new screen is assembled from.

### 6.1 Modals

| ID | Rule | Check |
|---|---|---|
| DS-CMP-1 | **MUST.** Every dialog and bottom sheet goes through `showMostroDialog` / `showMostroSheet` with `MostroDialog` / `MostroSheet` (`lib/shared/widgets/mostro_modal.dart`). Buttons are `ModalAction`s and links are `ModalLink`s. | test (`modal_guard_test.dart`) |
| DS-CMP-2 | **MUST.** A modal has at most one primary action, "the answer", on the right or on top when the actions stack. The secondary is "the way out". An irreversible answer uses `ModalTone.destructive`. While it runs, the action shows `busy`; the modal is not swapped for a spinner. | review |
| DS-CMP-26 | **MUST.** The answer of a modal opened by a named action repeats that action's verb, in a key of its own: the range dialog opened from "Take order" answers "Take order", not "Submit"; a cancel confirmation answers "Yes, cancel". A generic answer ("OK", "Yes", "Confirm", "Continue", "Submit") is kept for a modal that only informs. The answer's key holds the same wording as the opener in every language, so a translator can keep them together. | review |

### 6.2 Buttons

| ID | Rule | Check |
|---|---|---|
| DS-CMP-3 | **MUST.** A screen state has at most **one** primary call to action: filled lime, `onLime` ink, radius 16, 15/w600, vertical padding 14. When the user can only wait, it has none (`TradeActionBar`). Reuse `OrderPrimaryButton`, `TradeActionBar` or `InvoicePrimaryButton`. | review |
| DS-CMP-4 | **MUST.** Secondary actions are outlined (`border` token, `textBody` ink) with the same radius as their primary. Cancel and dispute are never two red buttons of the same weight. A way out (a dismissal, a cancel) is placed and weighted as DS-CMP-20 says. | review |
| DS-CMP-5 | **MUST.** A filled red button is used only for the answer to an irreversible question inside a modal (DS-CMP-2). On a page, danger is an outlined or link action in `danger` ink, chosen as DS-CMP-20 says. | review |
| DS-CMP-6 | **MUST.** Every tappable target is at least **48 × 48** dp. A small glyph is padded out to it, as `TabAppBar` does with `_target = 48`. | review |
| DS-CMP-7 | **MUST.** An icon-only button has a `tooltip` or a semantic label. | review |
| DS-CMP-17 | **MUST.** A `FilledButton`, `OutlinedButton` or `ElevatedButton` always passes `style:` (radius and palette colors as DS-CMP-3 and DS-CMP-4 say), or comes from a shared component that does (`OrderPrimaryButton`, `ModalAction`). Without one it is the theme's stadium in v1 colors. A `TextButton` used as a link colors its label from the palette, or is a `ModalLink`. | auto |
| DS-CMP-20 | **MUST.** A screen's way out is weighted by what it undoes. **Leaving without consequence** (discarding a form, closing a finished screen, "Not now", skipping) is a text link in `textSecondary` under the screen's actions (`InvoiceCancelLink` with `danger: false`), or the back arrow alone. It is never an outlined button beside the primary, which would give leaving the weight of acting. **Cancelling something that exists** (a published order, a trade, a bond window) is in `danger` ink and always asks first, through a `MostroDialog` whose answer is `ModalTone.destructive` (DS-CMP-2). It is an outlined button when it shares the action bar with the primary (`TradeActionBar`'s secondary, `_CancelButton` on `/my_order`), and a link when it sits under the screen's actions (`InvoiceCancelLink` with `danger: true`). | review |

### 6.3 Cards, rows and chips

| ID | Rule | Check |
|---|---|---|
| DS-CMP-8 | **MUST.** A card or row sits on `surface`, has radius 18, padding 14 and no elevation. When tappable, it is `Material` + `InkWell`, so the ripple follows the radius. | review |
| DS-CMP-9 | **MUST.** A status chip is a pill: 6-px dot, upper-case 10-sp label, padding 8 × 4 (horizontal × vertical), 6 between dot and label, with a tinted fill and border from the area's `chip*` tokens (`TradeListChip`, `TradeStatusChip`). The legacy `StatusChip` / `RoleBadge` with `AppColors.status*` is not used in new code. | review |
| DS-CMP-22 | **MUST.** An order or trade id reads `shortOrderId`: the first 8 characters, `…`, the last 4 (`09150348…99b5`), in `AppFonts.figures`. It sits in an "ID" row of the screen's card, never in the app bar. The whole row copies the full id: it shows a visible `copy_rounded` icon, 16, in the area's lime icon ink, and confirms with the "Copied" snackbar (DS-CMP-15). The full id is shown only where it must be read whole, in the dispute info card. A mention that is not a control (a notification line) uses the same short form, without copy. `OrderIdRow` is the reference. | review |
| DS-CMP-25 | **MUST.** A note that explains what a step does with the user's sats (an escrow, a hold, a deposit) is an `ExplanatoryNote` (`lib/features/order/widgets/explanatory_note.dart`), on every screen: the invoice palette's `subtleFill` with a `subtleBorder` hairline, radius 12, padding 14 × 12, a 14-dp icon 8 before 11-sp `textSecondary` text at height 1.45. The icon says what the note is about, and the lock (`Icons.lock_outline`) always means "your sats are held". The note sits in the body, after the content it explains, never in an action bar: the bar holds only actions. | review |
| DS-CMP-23 | **MUST.** The amount a screen is about, its hero, is one `HeroAmountCard` (`lib/features/order/widgets/hero_amount_card.dart`; `InvoiceHeroCard` is the same card for a sats figure). It is left-aligned on a card. A sentence-case label sits above (12 sp, `textSecondary`), never upper-cased. The figure is `AppFonts.figures` 38/w700, and its unit (`ARS`, `sats`) sits on the figure's baseline at 15/w600 in `textSecondary`, never in a chip. A figure that does not fit at 38 drops to 26 and then wraps; it is never truncated. When the screen trades one amount for another (take order: you pay → you receive), the second stacks under a divider: its label, then its figure at 19/w600 in `limeInk` with the rest of its line at 13. An optional context line (12 sp, `textSecondary`) closes the card. A QR, when there is one, sits below it in the same card. | review |
| DS-CMP-24 | **MUST.** Facts read as label → value (an order's data, the counterpart, the fiat side of a trade, a deposit's context) are rows of one card: `OrderDataCard` holding `OrderDataRow`s (`lib/features/order/widgets/order_detail_cards.dart`). A row has a leading 16-dp icon in `textTertiary` (DS-ICO-3), 10 to the label at 12 sp in `textSecondary`, and the value flush right at 12 sp, w500, in `textStrong` (`OrderDataValue`, in `AppFonts.figures` when it is an amount or a count), with 14 above and below (DS-SPC-2). A hairline `rowDivider` separates the rows. Something said about the value (the counterpart's reputation) trails it at 11 sp in `textSecondary`. A row that copies or opens something is tappable as a whole (`onTap`). No screen draws its own label → value list; the one exception is a set of short figures compared at a glance, which is DS-CMP-28. | review |
| DS-CMP-27 | **MUST.** A value the user can change in place says so: the value in `limeInk` with a trailing `expand_more` chevron (16, `sortLabel`), the whole value a target of at least 48 × 48 dp (DS-CMP-6), wrapped in `Semantics(button: true)` with a hint that names the change ("Select currency"). The same value read-only is neutral, in `textStrong` or the `currencyChipFill` chip, with no chevron. References: `CurrencyInlineSelector` and `CurrencyRowSelector` (editable, create order) against `OrderCurrencyChip` (read-only, take order). A list edited in place is lime-ink chips with a remove control (`payment_method_section.dart`); read-only it is plain text. A color that already means something (the premium's favour, DS-COL-9) keeps it and takes no chevron. A row that opens another screen or sheet is a row, not an editable value: neutral value and a trailing `chevron_right` (`settings_section.dart`). | review |
| DS-CMP-28 | **MUST.** Short figures read side by side at a glance (the connected node's limits and terms on About, 12a) are cells of an `AboutFactGrid` (`lib/features/about/widgets/about_widgets.dart`), never a grid of the screen's own. A cell is a label at 10 sp in `textSecondary`, on one line and read whole, over the value at 13 sp, w600, in `textStrong` and `AppFonts.figures`. An optional unit or qualifier (`sats`, `min. 1,000 sats`) at 11 sp in `textSecondary` sits on the value's baseline beside it, or whole on the line below when it does not fit. Cells use `AboutPalette.cell`, radius 12, padding 10 × 8, with 8 between them. A row holds three cells, or two, or one: the most that keeps every label, every word of a value and every unit whole, with every value at full size. A value is never shrunk to fit. Each cell is one semantics node: label, value, unit. A fact that needs an icon, a long value, a copy or a tap is an `OrderDataRow` (DS-CMP-24). | review |

### 6.4 Inputs

| ID | Rule | Check |
|---|---|---|
| DS-CMP-10 | **MUST.** A single-value form field (amount, address, name) is an underline field. The label sits above in `fieldLabel`, turning `fieldLabelFocus` on focus. The underline turns lime on focus and red on error. The error text sits underneath at 12 sp. `UnderlineAmountField` is the reference. | review |
| DS-CMP-11 | **MUST.** A multi-line or pasted value (invoice, chat composer, search) is a boxed field at radius 14 on the area's field fill (`inset`, `textareaFill`). The invoice field (`InvoiceInputField`) is the reference. | review |
| DS-CMP-19 | **MUST.** A `TextField`'s `InputDecoration` sets `enabledBorder`, `focusedBorder` and `filled` (`false`, or `true` with a palette `fillColor`), as `InvoiceInputField` does. Whatever it leaves out comes from the theme, which is v1's: measured under the app theme, `border: InputBorder.none`, `isCollapsed` and `InputDecoration.collapsed` all still paint the `#252A3A` fill and `#9A9A9C` underline, because `border:` is only the fallback for states the theme leaves unset. A decoration built by a helper is left to review. | auto |

### 6.5 Bars, feedback and states

| ID | Rule | Check |
|---|---|---|
| DS-CMP-12 | **MUST.** A pushed screen uses `redesignAppBar()`. A tab root uses `TabAppBar`, the same bar in every tab: menu, the Mostro mascot (`HeaderMascot`), bell (#770). The bottom bar is `BottomNavBar`. An `AppBar` built in place sets `backgroundColor` and its icon and title colors from the palette (as `add_order_screen.dart` does); one that leaves them to the theme is v1. | auto, review |
| DS-CMP-18 | **MUST.** A `Scaffold` sets `backgroundColor` from the palette (`bg`). The theme's is v1's `#1B1E28`. | auto |
| DS-CMP-13 | **MUST.** A list that loads shows a shimmer skeleton in the shape of its rows (`OrderListSkeleton`), never a centered spinner. A button that works shows its own spinner and keeps its size. | review |
| DS-CMP-14 | **MUST.** An empty list explains itself: the mascot, a title, the reason, and the action that fixes it when there is one (`OrderListEmpty`). | review |
| DS-CMP-15 | **SHOULD.** A snackbar confirms something that already happened ("Copied"). It is floating, on `surface`, radius 12, about 2 s (`showOrderDetailSnackBar`). It never carries an error the user must act on; that belongs in the screen or a modal. | review |
| DS-CMP-16 | **MUST.** A pseudonym avatar is `NymAvatar`, with the glyph always white on its hue (FR-011c). | review |
| DS-CMP-21 | **MUST.** A time left says what runs out: a label ("The invoice expires in", "You have", "Expires in") stands with the figure, never a bare figure. It sits in the body (a banner, a step block or a card row), never in the app bar. One formatter, `formatCountdown` (`lib/shared/utils/countdown.dart`), prints it: `12:40` (mm:ss) under an hour, the localized `1 h 05` / `23 h 12` from an hour up, never `23:12` for hours. One tone function, `countdownTone`, colors it: calm is lime while it is the user's turn and amber while they wait; warning is amber under an hour; urgent is coral under 5 minutes, or under 1 minute when the whole window lasts 15 minutes or less. Turning urgent while on screen is announced once, with the label and the time left (`CountdownUrgencyAnnouncer`, `lib/shared/widgets/countdown_urgency_announcer.dart`, DS-A11Y-2); a countdown already urgent when it first shows is not announced, since its label is read on focus. The ticking figure is never a `liveRegion`: its label changes every second, so a screen reader would read every tick. The figure is `AppFonts.figures` with tabular digits (DS-TYP-2). | review |

### 6.6 Icons

| ID | Rule | Check |
|---|---|---|
| DS-ICO-1 | **MUST.** Material `Icons` only; no other icon package. Images come from bundled assets. | review |
| DS-ICO-2 | **SHOULD.** One style per screen, `_rounded` or `_outlined`, not mixed with the plain style. | review |
| DS-ICO-3 | **MUST.** Icon sizes: 12, 14, 16, 18, 20, 22, 24 for interface icons; 32, 44 or 48 for an illustration or a dialog's icon. | auto |

---

## 7. Motion

| ID | Rule | Check |
|---|---|---|
| DS-MOT-1 | **MUST.** No page transitions; the theme disables them on purpose (`_NoTransitionBuilder`). A screen does not add its own. | review |
| DS-MOT-2 | **SHOULD.** Durations: 150 ms for fades and micro feedback, 200 ms for swaps and openings, 240 ms for moves. Curves: `easeOut`, or `easeInOut` for back-and-forth. | review |
| DS-MOT-3 | **MUST.** A looping or decorative animation (pulse, shimmer, mascot, blinking cursor) stops when `MediaQuery.disableAnimationsOf(context)` is true. | review |

---

## 8. Accessibility

Contrast is in §2 (DS-COL-6, DS-COL-7, DS-COL-10), target size and labels in §6.2 (DS-CMP-6,
DS-CMP-7), and text scaling in §3 (DS-TYP-7). In addition:

| ID | Rule | Check |
|---|---|---|
| DS-A11Y-1 | **MUST.** A custom tappable widget (an `InkWell` or `GestureDetector` that is not a Material button) is wrapped in `Semantics(button: true, label: …)`, with `enabled` reflecting its state. The exception is a gesture on decoration that only plays itself or shows a seasonal greeting (the mascot's tap and long press, `MostroMascot`): it changes nothing in the app and tells nothing the user needs, so it stays under `ExcludeSemantics` with the decoration (DS-A11Y-3), and the gesture detector sets `excludeFromSemantics: true`. A gesture that navigates, changes a setting or shows any other information is not an exception. | review |
| DS-A11Y-2 | **MUST.** A status that changes while the user watches (a countdown result, a payment received) is announced through `liveRegion` or `SemanticsService`. | review |
| DS-A11Y-3 | **MUST.** Focus and reading order follow the visual order. Decoration is excluded with `ExcludeSemantics`. | review |
| DS-A11Y-4 | **MUST.** A new screen, or a changed action bar or modal, has a widget test at 2× text scale and 320 dp wide in German that expects no overflow (`tester.takeException()` is null). Precedents: `order_detail_golden_test.dart`, `trade_detail_screen_test.dart`. | test |

---

## 9. Copy and localization

| ID | Rule | Check |
|---|---|---|
| DS-L10N-1 | **MUST.** Every user-facing string comes from `AppLocalizations`, in all six ARB files (en, es, fr, de, it, nl). CI fails on an untranslated key. | test |
| DS-L10N-2 | **MUST.** A layout is sized for the longest translation, usually German, never for English. A button label fits or scales down, and never truncates a verb. | review |
| DS-L10N-3 | **MUST.** Numbers, amounts and dates are formatted for the locale, never by hand. | review |
| DS-L10N-4 | **MUST.** One word per concept, in every locale: a string names a trade concept with the word the glossary below gives it, and a new concept joins the glossary in the same change that first uses it. Protocol jargon ("hold", "bolt11", "NIP") is not shown to the user as a term to know; the string says what it does in plain words. | review |

**Glossary.** The words the app uses, in English and Spanish; the other locales keep the same
one-to-one choice in their ARB files.

| Concept | en | es | Not |
|---|---|---|---|
| An offer in the book | order | orden | oferta |
| Accepting someone else's order | take | tomar | aceptar |
| The two sides | seller, buyer | vendedor, comprador | — |
| The other person in a trade | counterpart | contraparte | — |
| A taken order, until it ends | trade | operación | intercambio |
| The anti-abuse amount a node asks for | deposit | depósito | fianza, garantía |
| Paying the invoice that keeps sats in escrow | lock (the sats) | bloquear (los sats) | — |
| Sats a hold invoice keeps in the payer's wallet | held | retenidos | "hold" as a term |
| The seller handing the sats over | release | liberar | — |
| A Lightning payment request | invoice | factura | — |
| A trade a solver decides | dispute | disputa | — |
| Payment methods the user ticked | selected | seleccionado(s) | elegido(s), chosen |

---

## 10. Themes

| ID | Rule | Check |
|---|---|---|
| DS-THM-1 | **MUST.** Every change is designed and checked in dark (the default) and light. A palette token always has both values. | review |
| DS-THM-2 | **MUST.** A golden for a new or changed component covers both themes (`pumpForGolden(..., brightness:)`). Goldens are regenerated only by the `update-goldens.yml` workflow (`docs/golden-tests.md`). | test, review |

---

## 11. Automation identifiers

A widget a test or tool drives carries `.withAutomationId(...)`. Renaming one is a contract
change (`docs/automation-contract.md`). It is not a design rule, but a UI change must not drop
one.

---

## 12. What a UI pull request shows

The template's **Screenshots** section asks for before and after screenshots. For a UI change
judged against this guide, the description also gives:

1. **Rules touched**: the IDs that apply ("DS-CMP-3, DS-COL-6"), and any SHOULD it departs from,
   with the reason.
2. **New tokens**: name and both values, and the contrast test that covers them.
3. **Screenshots** as CONTRIBUTING asks: before and after, in dark and light for a change of
   colour, contrast or layout, and one at 2× text scale when a layout changed.
4. **Reference**: the issue's mockup or handoff the change implements (CONTRIBUTING: a UI change
   needs an accepted issue that shows the intended result).

## 13. Changing this guide

The guide changes in its own pull request, or in the same pull request as the first code that
needs the change, with the guide diff called out in the description. A maintainer approves it.
Changing a value (a new size, radius or spacing step) also updates the check that enforces it,
so the guide and CI never disagree: `test/ci/design_check_test.dart` fails while the scales in
§3.2, §4, DS-SPC-2 and DS-ICO-3 differ from the ones `tool/design/design_check.dart` enforces.

A line that breaks an *auto* rule on purpose takes a comment naming the rule and the reason,
on that line or alone on the line above:

```dart
// design-check: ignore DS-COL-1 — a QR code must be pure black on white to scan
color: Colors.black,
```

Without a reason the comment silences nothing. The reviewer judges the reason; it is not a way
around a rule the change could keep.

**Standing exception: the startup failure screen.** `lib/core/startup_failure.dart` is shown
when startup fails before the app can run, and localization, the app theme and the area
palettes can be the very thing that failed (#389). So it hard-codes its English and its colors:
DS-L10N-1 and DS-COL-2 do not apply to it. Its four colors are named constants on
`StartupFailureApp`, and `test/core/startup_failure_contrast_test.dart` asserts each text color
at 4.5:1 on its background (DS-COL-6 still applies: a test needs nothing at runtime). It still
follows every other rule that needs nothing at runtime, such as DS-TYP-1 and DS-A11Y-4.

---

## 14. Known gaps (code that predates this guide)

Each gap below is debt. A change in the same code SHOULD close it, and MUST NOT copy it. The
CI check reports a gap once a pull request touches its screen file, or elsewhere its class (or,
outside a class, the top-level function or variable it sits in), and that change MUST close
every *auto* gap there (§0). `dart tool/design_check.dart --all`
lists every one the check can see (595 when the theme-default rules were added, 640 once
DS-SHP-4 and the `textTheme` roles of DS-TYP-4 joined them).

| Gap | Where | Rule |
|---|---|---|
| About 50 `Color(0x…)` literals in 21 files and about 86 `Colors.<name>` in 30 files. Many are v1 fallbacks (`#8CC63F`), mostly in notifications and chat attachments. | §2.1 | DS-COL-1 |
| `ThemeData` defines no button, chip, snackbar or switch theme; every button styles itself. | §6.2 | DS-CMP-3 |
| `textTheme` (32/24/20/18/16/14/12) does not match the redesign scale. 13 half-point sizes and three 9-sp labels exist. | §3.2 | DS-TYP-4 |
| `'Manrope'` is written as a literal in `tab_app_bar.dart`. | §3.1 | DS-TYP-1 |
| `AppRadius.card` is 12, while redesigned cards use 18. `AppRadius.button` (8) is unused by the redesign, which uses 16. About 180 literal radii, including 4, 11, 13, 20, 26 and 28. | §4 | DS-SHP-1, DS-SHP-2, DS-SHP-4 |
| No spacing grid in practice: about 70% of padding literals are on the 2-pt scale, and odd values (11, 13, 9, 15…) are common. `AppSpacing.xxl` is unused. | §5 | DS-SPC-2 |
| Odd icon sizes (13, 15, 17, 19) are common. | §6.6 | DS-ICO-3 |
| Chips are padded 9 × 3 or 8 × 3 with a 5 gap, and in-page calls to action use vertical padding 15 in places (`_TakeButton`, `TradeActionBar`), all off the spacing scale. The drawer insets its content 22. | §5, §6 | DS-SPC-1, DS-SPC-2, DS-CMP-3, DS-CMP-9 |
| Reds differ across palettes: `E4685D` (invoice, about), `F27868` (restore), `B0352F`, `A8262B`, `9E2B26` in light. `AppColors.sellColor` is `FF8A8A` against `sell` `FF8B8B`. | §2.3 | DS-COL-8 |
| `RestorePalette` redefines its own surfaces (`sheet` `#161C28`) instead of extending `OrderBookPalette`. | §2.2 | DS-COL-2 |
| Chat: `AppColors.systemMessage` (`#2A2D35`) is used as a **text** color on the dark background, which is illegible. The dispute chat's received bubble is a literal `#2D3142`. Bubble colors have no contrast test. | §2 | DS-COL-1, DS-COL-6 |
| `AppColors.status*` chip tuples are the same in light and dark and have no contrast test. `RoleBadge` is never used. | §6.3 | DS-CMP-9 |
| My order's amount block (`_AmountBlock` in `my_order_screen.dart`) still puts the currency in a chip over a 34-sp `OrderAmountFigure` instead of a `HeroAmountCard`. | §6.3 | DS-CMP-23 |
| Most of the 87 `showSnackBar` calls are not floating and are styled by hand; there is no shared helper. | §6.5 | DS-CMP-15 |
| Only three widgets honour `disableAnimations` (restore sheet, invoice field, mascot). | §7 | DS-MOT-3 |
| No test checks 3:1 for non-text, and none uses Flutter's `meetsGuideline` for tap targets or labels. | §8 | DS-COL-7, DS-CMP-6 |
| `app_theme.dart` cites `test/core/accent_consistency_test.dart`, which does not exist. The check lives in `modal_contrast_test.dart`. | §2.1 | — |
| About 100 reads of `AppColors` in the legacy areas and in a few redesigned files. | §2.2 | DS-COL-11 |
| The create-order screen states the maker's deposit in `OrderPreviewBar` (`notice`), with a shield icon, inside the action bar rather than as an `ExplanatoryNote` in the body. | §6.3 | DS-CMP-25 |
| Modal answers that do not repeat their opener: the open-dispute confirmation answers "Yes" (`dispute_confirmation_dialog.dart`), the Cashu send dialog "Confirm" (`cashu_wallet_screen.dart`) and the new-user dialog "Continue" (`account_screen.dart`). | §6.1 | DS-CMP-26 |
| `ThemeData` holds v1's defaults: scaffold background `#1B1E28`, app bar, filled-underline input decoration, and no button themes (so a bare button is a stadium). 16 unstyled Material buttons, 11 app bars and 11 scaffolds on the theme background, and 13 text fields that leave part of their decoration to the theme rely on them, mostly in the Cashu, chat, dispute and notification screens and in error states. One redesigned field is among them: the premium field in `price_section.dart` sets only `border: InputBorder.none`, so the v1 fill shows behind the percentage. Moving the theme's defaults to the redesign values would make a bare widget look right and retire most of these. | §1 | DS-CMP-12, DS-CMP-17 to DS-CMP-19 |
| Words the glossary (§9) retires are still in use: "intercambio" next to "operación" for a trade, "fianza" next to "depósito", and "hold invoice" / "factura hold" in the seller's waiting and payment steps and in About. | §9 | DS-L10N-4 |
| The invoice time band (`InvoiceTimeBand`) and the bond pill (`BondAmountRow`) stay amber when calm, where the user's turn calls for lime: `InvoicePalette` has amber `time*` and red `error*` band tokens only. Only a maker's bond window can last over an hour. The chat header's countdown (`_CountdownChip`) keeps amber when calm because the header does not know whose turn it is, and takes that amber from the v1 header. | §6.5 | DS-CMP-21 |
| The order-book sort control (`home_screen.dart`) is a value changed in place, shown in neutral `sortLabel` with a chevron, a target about 24 dp tall and no button semantics. | §6.3 | DS-CMP-27, DS-CMP-6, DS-A11Y-1 |
| `ThemeData` holds v1's defaults: scaffold background `#1B1E28`, app bar, filled-underline input decoration, and no button themes (so a bare button is a stadium). 16 unstyled Material buttons, 11 app bars and 11 scaffolds on the theme background, and 14 text fields that leave part of their decoration to the theme rely on them, mostly in the Cashu, chat, dispute and notification screens and in error states. Redesigned fields are among them: `UnderlineAmountField` and the premium field in `price_section.dart` set only `border: InputBorder.none`, so the v1 fill shows behind the amount (`add_order_5b_single_fixed_dark.png`). Moving the theme's defaults to the redesign values would make a bare widget look right and retire most of these. | §1 | DS-CMP-12, DS-CMP-17 to DS-CMP-19 |

---

## 15. Review checklist

For the reviewer of a UI change. Each line is a MUST unless marked.

- [ ] No color, font family, font size, radius, spacing or icon-size literal outside the
      allowed values, no v1 radius token and no off-scale `textTheme` role (DS-COL-1,
      DS-TYP-1, DS-TYP-4, DS-SHP-1, DS-SHP-4, DS-SPC-2, DS-ICO-3).
- [ ] Colors come from the area's palette; new tokens use canonical values and have a 4.5:1
      test in both themes (DS-COL-2, DS-COL-6, DS-COL-8).
- [ ] Lime is the only green; filled lime and sell carry their dark inks (DS-COL-3, DS-COL-4,
      DS-COL-5).
- [ ] Colors keep their meaning and never carry it alone (DS-COL-9, DS-COL-10).
- [ ] Figures use Manrope with an explicit weight (DS-TYP-2, DS-TYP-3).
- [ ] At most one primary call to action; secondaries outlined; danger not a filled page button
      (DS-CMP-3, DS-CMP-4, DS-CMP-5).
- [ ] Modals through `mostro_modal.dart`; one answer (DS-CMP-1, DS-CMP-2).
- [ ] No v1: no `AppColors`, and no button, app bar, scaffold or text field left to the theme's
      defaults (DS-COL-11, DS-CMP-12, DS-CMP-17 to DS-CMP-19).
- [ ] Targets at least 48 dp; icon buttons labelled; custom tappables have semantics
      (DS-CMP-6, DS-CMP-7, DS-A11Y-1).
- [ ] Existing components reused: app bars, chips, cards, inputs, skeletons, empty states
      (DS-CMP-8 to DS-CMP-14).
- [ ] Works at 320 dp, at 2× text and in German, with a test that proves it (DS-SPC-5,
      DS-TYP-7, DS-A11Y-4, DS-L10N-2).
- [ ] Dark and light screenshots; goldens in both themes from the workflow (DS-THM-1,
      DS-THM-2).
- [ ] Animations short; loops honour reduced motion (DS-MOT-2 SHOULD, DS-MOT-3).
- [ ] The description names the rules touched and any SHOULD it departs from (§12).
