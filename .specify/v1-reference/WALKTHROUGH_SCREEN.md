# Walkthrough Screen (v1 Reference)

> First-run onboarding tutorial. Shown once on first app launch, never again.

**Route:** `/walkthrough`
**File:** `lib/features/walkthrough/screens/walkthrough_screen.dart`
**Library:** `introduction_screen` (Flutter package)
**Provider:** `firstRunProvider` (`lib/features/walkthrough/providers/first_run_provider.dart`)

---

## When It Appears

- **First launch only:** Shown when `SharedPreferencesKeys.firstRunComplete` is NOT `true`
- After completing (Done or Skip) → sets `firstRunComplete = true` → never shown again
- On subsequent launches → redirects directly to `/` (home/order book)
- If provider errors → also redirects to `/` (fail-safe)

## What Happens in Background

Before the walkthrough is shown, the app has already:
1. Generated the user's 12-word BIP-39 mnemonic
2. Derived the HD identity key (NIP-06)
3. Stored everything securely in encrypted local storage

The user is unaware of this — they just see the tutorial slides.

## After Walkthrough Completes

When user taps "Done" or "Skip":
1. `markFirstRunComplete()` → persists `firstRunComplete = true`
2. `backupReminderProvider.showBackupReminder()` → activates the persistent backup notification (red dot on bell)
3. Navigate to `/` (home screen)

---

## Slides (6 pages)

### Page 1: Welcome
- **Title:** "Trade Bitcoin freely — no KYC"
- **Body:** "Mostro is a peer-to-peer exchange that lets you trade Bitcoin for any currency and payment method — no KYC, and no need to give your data to anyone. It's built on **Nostr**, which makes it **censorship-resistant**. No one can stop you from trading."
- **Image:** `assets/images/wt-1.png`
- **Highlighted terms (green):** "Nostr", "no KYC", "censorship-resistant"

### Page 2: Privacy by Default
- **Title:** "Privacy by default"
- **Body:** "Mostro generates a new identity for every exchange, so your trades can't be linked. You can also decide how private you want to be: • **Reputation mode** – Lets others see your successful trades and trust level. • **Full privacy mode** – No reputation is built, but your activity is completely anonymous. Switch modes anytime from the Account screen, where you should also save your secret words — they're the only way to recover your account."
- **Image:** `assets/images/wt-2.png`
- **Highlighted terms (green):** "Reputation mode", "Full privacy mode"

### Page 3: Security at Every Step
- **Title:** "Security at every step"
- **Body:** "Mostro uses **Hold Invoices**: sats stay in the seller's wallet until the end of the trade. This protects both sides. The app is also designed to be intuitive and easy for all kinds of users."
- **Image:** `assets/images/wt-3.png`
- **Highlighted terms (green):** "Hold Invoices"

### Page 4: Encrypted Chat
- **Title:** "Fully encrypted chat"
- **Body:** "Each trade has its own private chat, **end-to-end encrypted**. Only the two users involved can read it. In case of a dispute, you can give the shared key to an admin to help resolve the issue."
- **Image:** `assets/images/wt-4.png`
- **Highlighted terms (green):** "end-to-end encrypted"

### Page 5: Take an Offer
- **Title:** "Take an offer"
- **Body:** "Browse the **order book**, choose an offer that works for you, and follow the trade flow step by step. You'll be able to check the other user's profile, chat securely, and complete the trade with ease."
- **Image:** `assets/images/wt-5.png`
- **Highlighted terms (green):** "order book"

### Page 6: Create Your Own Offer
- **Title:** "Can't find what you need?"
- **Body:** "You can also **create your own offer** and wait for someone to take it. Set the amount and preferred payment method — Mostro handles the rest."
- **Image:** `assets/images/wt-6.png`
- **Highlighted terms (green):** "create your own offer"

---

## Highlight System

Certain key terms in the body text are highlighted in green (`AppTheme.mostroGreen`, #8CC63F) with semibold weight. This is done via `HighlightConfig` regex patterns that match terms in all supported languages (EN, ES, IT).

**File:** `lib/features/walkthrough/utils/highlight_config.dart`

| Step | Highlighted terms |
|------|------------------|
| Welcome | Nostr, no KYC, censorship-resistant |
| Privacy | Reputation mode, Full privacy mode |
| Security | Hold Invoices |
| Chat | end-to-end encrypted |
| Take offer | order book |
| Create offer | create your own offer |

---

## Navigation Controls

| Control | Position | Action |
|---------|----------|--------|
| **Skip** | Top-left text button | Skip all slides → `_onIntroEnd()` |
| **Back** (←) | Bottom-left arrow | Go to previous slide |
| **Next** (→) | Bottom-right arrow | Go to next slide |
| **Done** | Bottom-right text (last slide only) | Complete → `_onIntroEnd()` |
| **Dots indicator** | Bottom-center | Shows current page, active dot is wider (16x8) in primary color |

---

## Visual Specs

| Element | Style |
|---------|-------|
| Title | 22sp, bold, white |
| Body | 16sp, regular, `Colors.white70` |
| Highlighted terms | 16sp, semibold (w600), `AppTheme.mostroGreen` (#8CC63F) |
| Image | 200px height, centered, `BoxFit.contain` |
| Body padding | 16px horizontal, 8px vertical |
| Image top padding | 30px |
| Page body horizontal margin | 6% of screen width on each side |
| Dots active color | `theme.primaryColor` |
| Dots inactive color | `theme.cardColor` |
| Dots active size | 16x8 (pill shape, rounded) |
| Dots inactive size | 8x8 (circle) |
| Background | App dark theme background |

---

## Persistence

| Key | Storage | Default | Purpose |
|-----|---------|---------|---------|
| `firstRunComplete` | SharedPreferences (bool) | `null`/not set | `true` after walkthrough completed |

---

## i18n

All slide titles and body texts are localized via `S.of(context)!.*` (intl ARB files). Highlight patterns include translations for all 5 supported languages: EN, ES, IT, FR, DE.

---

## Cross-References

- [HOME_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/HOME_SCREEN.md) — destination after walkthrough
- [ACCOUNT_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ACCOUNT_SCREEN.md) — mentioned in Page 2 (save secret words)
- [NOTIFICATIONS_SYSTEM.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/NOTIFICATIONS_SYSTEM.md) — backup reminder activated after walkthrough
- [SESSION_AND_KEY_MANAGEMENT.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/SESSION_AND_KEY_MANAGEMENT.md) — key generation happens before walkthrough
- [AUTHENTICATION.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/AUTHENTICATION.md) — identity creation context
