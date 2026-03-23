# Mostro Mobile v2 — Design System

> ⚠️ **CRITICAL**: v2 must look like v1. This document contains exact visual specifications
> extracted from v1 screenshots. Follow these specs precisely.

**Status:** Reference document from v1 screenshots + v2 additions
**Visual Reference:** See `.specify/v1-screenshots/` for original images

---

## 1. Core Principles

### 1.1 Visual Continuity
v2 must be visually indistinguishable from v1. Same colors, same spacing, same feel.

### 1.2 Single Source of Truth
ALL colors must be defined in a central theme file. Zero hardcoded colors in widgets.

### 1.3 Semantic Naming
Use names that describe purpose, not appearance:
- ✅ `mostroGreen`, `backgroundCard`, `statusError`
- ❌ `lightGreen`, `darkGray`, `red2`

---

## 2. Color Palette (Exact from v1)

### 2.1 Background Hierarchy

| Level | Name | Hex | RGB | Usage |
|-------|------|-----|-----|-------|
| 0 | backgroundDark | `#1B1E28` | (27, 30, 40) | Main screen background |
| 1 | backgroundCard | `#1E2230` | (30, 34, 48) | Cards, elevated surfaces |
| 2 | backgroundInput | `#252A3A` | (37, 42, 58) | Input fields, interactive |
| 3 | backgroundElevated | `#2A2D35` | (42, 45, 53) | Modals, dialogs, message input |

### 2.2 Brand & Action Colors

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| mostroGreen | `#8CC63F` | (140, 198, 63) | Primary brand, buy, success, FAB |
| mostroGreenBright | `#A5FF00` | (165, 255, 0) | Highlighted active states |
| sellColor | `#FF8A8A` | (255, 138, 138) | Sell actions, negative |
| destructiveRed | `#D84D4D` | (216, 77, 77) | Cancel, dispute, errors |
| purpleButton | `#8359C2` | (131, 89, 194) | Submit buttons, sent messages |
| tealAccent | `#2DA69D` | (45, 166, 157) | "Taken by you" badge |
| blueAccent | `#35485E` | (53, 72, 94) | "Active" badge background |

### 2.3 Text Colors

| Name | Hex | Opacity | Usage |
|------|-----|---------|-------|
| textPrimary | `#FFFFFF` | 100% | Headings, primary content |
| textSecondary | `#B0B3C6` | 100% | Labels, supporting text |
| textSubtle | `#9A9A9C` | 100% | Timestamps, hints, placeholders |
| textDisabled | `#6C757D` | 100% | Disabled states |
| textLink | `#8CC63F` | 100% | Links, interactive text |

### 2.4 Chat Colors

| Element | Hex | Usage |
|---------|-----|-------|
| messageSent | `#8359C2` | Sent message bubbles (purple) |
| messageReceived | `#4B6349` | Received message bubbles (dark green) |
| systemMessage | `#2A2D35` | System/info messages |

### 2.5 Status Chip Colors

| Status | Background | Text |
|--------|------------|------|
| Pending | `#854D0E` | `#FCD34D` |
| Waiting | `#7C2D12` | `#FED7AA` |
| Active | `#1E3A8A` | `#93C5FD` |
| Success | `#065F46` | `#6EE7B7` |
| Dispute | `#7F1D1D` | `#FCA5A5` |
| Settled | `#581C87` | `#C084FC` |
| Inactive | `#1F2937` | `#D1D5DB` |

### 2.6 Role Chip Colors

| Role | Background | Text |
|------|------------|------|
| Created by you | `#1565C0` | white |
| Taken by you | `#2DA69D` | white |
| Positive premium | `#388E3C` | white |
| Negative premium | `#C62828` | white |

---

## 3. Typography

### 3.1 Font Family
- **Primary:** System sans-serif (SF Pro on iOS, Roboto on Android)
- **Fallback:** Roboto Condensed
- **Weights:** 400 (Regular), 500 (Medium), 700 (Bold)

### 3.2 Text Scale

| Style | Size | Weight | Line Height | Usage |
|-------|------|--------|-------------|-------|
| displayLarge | 32sp | Bold | 1.2 | Hero amounts |
| headingLarge | 24sp | Bold | 1.3 | Screen titles |
| headingMedium | 20sp | Bold | 1.3 | Section headers |
| headingSmall | 18sp | Medium | 1.4 | Card titles, prices |
| bodyLarge | 16sp | Regular | 1.5 | Primary body text |
| bodyMedium | 14sp | Regular | 1.5 | Secondary body, labels |
| bodySmall | 12sp | Regular | 1.4 | Captions, timestamps |
| labelLarge | 14sp | Medium | 1.3 | Button text |
| labelSmall | 11sp | Medium | 1.2 | Chip text, badges |

### 3.3 Amount Display

```
┌─────────────────────────────────────┐
│  1,500 - 80,000                     │  ← headingSmall, bold, white
│  🇻🇪 VES                            │  ← bodySmall, flag + currency code
│  Market price: 0.12% above          │  ← bodySmall, textSecondary, green % 
└─────────────────────────────────────┘
```

---

## 4. Component Specifications

### 4.1 Order Card (from v1 screenshots)

```
┌─────────────────────────────────────────────────────┐
│  ┌─────────┐                                        │
│  │BUY BTC  │  ← Chip: mostroGreen bg, white text    │
│  └─────────┘                                        │
│                                                     │
│  1,500 - 80,000     🇻🇪                             │
│  ← headingSmall     ← Flag icon (16x12)             │
│                                                     │
│  VES · Market price 0.12% ↑                         │
│  ← bodySmall, textSecondary                         │
│                                                     │
│  ⭐ 4.8 (12)  ·  15 trades                          │
│  ← Rating + trade count, bodySmall                  │
│                                                     │
│  └── Payment methods: Mercado Pago, Zinli...        │
│      ← bodySmall, textSubtle, truncated             │
└─────────────────────────────────────────────────────┘

Specs:
- Background: backgroundCard (#1E2230)
- Border radius: 12px
- Padding: 16px
- Margin between cards: 12px
- Shadow: none (flat design)
```

### 4.2 Buttons

| Type | Background | Text | Border Radius | Height | Padding |
|------|------------|------|---------------|--------|---------|
| Primary (Buy) | `#8CC63F` | white | 8px | 48px | 16px horizontal |
| Primary (Sell) | `#FF8A8A` | white | 8px | 48px | 16px horizontal |
| Secondary | `#8359C2` | white | 8px | 48px | 16px horizontal |
| Destructive | `#D84D4D` | white | 8px | 48px | 16px horizontal |
| Ghost | transparent | textSecondary | 8px | 40px | 12px horizontal |
| FAB | `#8CC63F` | white icon | 50% (circle) | 56px | centered |

### 4.3 Input Fields

```
┌─────────────────────────────────────┐
│  Amount                             │  ← Label: bodySmall, textSecondary
│  ┌─────────────────────────────────┐│
│  │ 50,000                          ││  ← Input: bodyLarge, textPrimary
│  │ _____________________________ ↓ ││  ← Underline: mostroGreen when focused
│  └─────────────────────────────────┘│
└─────────────────────────────────────┘

Specs:
- Background: backgroundInput (#252A3A)
- Border: none (underline style)
- Underline color: mostroGreen when focused, textSubtle when unfocused
- Border radius: 8px top only
- Padding: 12px
- Height: 56px
```

### 4.4 Chips/Badges

```
┌──────────────┐
│  BUY BTC     │
└──────────────┘

Specs:
- Background: varies by type (see colors)
- Text: labelSmall, bold
- Border radius: 6px
- Padding: 4px 8px
- Height: 24px
```

### 4.5 Bottom Navigation Bar

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│   📖          📋          💬                        │
│  Order Book   My Trades   Chat                      │
│                                                     │
│  (inactive)   (active)    (inactive)                │
│  textSubtle   mostroGreen textSubtle                │
│                                                     │
└─────────────────────────────────────────────────────┘

Specs:
- Background: backgroundDark (#1B1E28)
- Height: 64px
- Icon size: 24px
- Label: bodySmall
- Active color: mostroGreen
- Inactive color: textSubtle (#6C757D)
- Border top: 1px solid backgroundCard
```

### 4.6 App Bar

```
┌─────────────────────────────────────────────────────┐
│  ☰                              🔔                  │
│  (hamburger)                    (notifications)     │
└─────────────────────────────────────────────────────┘

Specs:
- Background: backgroundDark (#1B1E28)
- Height: 56px
- Icon size: 24px
- Icon color: textPrimary
- Elevation: 0 (flat)
```

### 4.7 Chat Message Bubbles

```
Sent (right-aligned):
                    ┌─────────────────────┐
                    │ Payment sent! ✓     │
                    └─────────────────────┘
                    Background: #8359C2 (purple)
                    Border radius: 16px 16px 4px 16px
                    Max width: 75% of screen
                    Padding: 12px 16px

Received (left-aligned):
┌─────────────────────┐
│ Got it, releasing   │
└─────────────────────┘
Background: #4B6349 (dark green)
Border radius: 16px 16px 16px 4px
Max width: 75% of screen
Padding: 12px 16px
```

### 4.8 List Items (Settings)

```
┌─────────────────────────────────────────────────────┐
│  🌐  Language                                    ▼  │
│      English                                        │
├─────────────────────────────────────────────────────┤
│  💱  Currency                                    ▼  │
│      VES                                            │
└─────────────────────────────────────────────────────┘

Specs:
- Icon: 24px, colored (green for language, blue for currency)
- Title: bodyLarge, textPrimary
- Subtitle: bodyMedium, textSecondary
- Chevron: 16px, textSubtle
- Divider: 1px, backgroundCard
- Height: 64px
- Padding: 16px horizontal
```

---

## 5. Layout & Spacing

### 5.1 Spacing Scale

| Token | Value | Usage |
|-------|-------|-------|
| xs | 4px | Tight spacing, between badge elements |
| sm | 8px | Compact spacing, chip padding |
| md | 12px | Default between list items |
| lg | 16px | Card padding, section spacing |
| xl | 24px | Between major sections |
| xxl | 32px | Screen edge padding on tablets |

### 5.2 Screen Padding

| Breakpoint | Horizontal Padding |
|------------|-------------------|
| Mobile (<600px) | 16px |
| Tablet (600-1200px) | 24px |
| Desktop (>1200px) | 32px |

### 5.3 Card Grid

```
Mobile (single column):
┌─────────────────────────┐
│         Card 1          │
└─────────────────────────┘
         12px gap
┌─────────────────────────┐
│         Card 2          │
└─────────────────────────┘

Tablet (2 columns):
┌───────────┐  12px  ┌───────────┐
│   Card 1  │  gap   │   Card 2  │
└───────────┘        └───────────┘

Desktop (3 columns):
┌─────────┐ 12px ┌─────────┐ 12px ┌─────────┐
│  Card 1 │ gap  │  Card 2 │ gap  │  Card 3 │
└─────────┘      └─────────┘      └─────────┘
```

---

## 6. Navigation Patterns

### 6.1 Bottom Navigation (Mobile)

3 tabs:
1. **Order Book** - Browse orders
2. **My Trades** - Active/past trades
3. **Settings** - Profile & settings

### 6.2 Drawer Menu (Mobile)

Accessed via hamburger icon. Contains:
- Profile info
- Settings
- About
- Logout

### 6.3 Navigation Rail (Desktop)

Same 3 sections as bottom nav, but vertical on left side.

---

## 7. Responsive Breakpoints

| Name | Width | Layout |
|------|-------|--------|
| Mobile | <600px | Single column, BottomNav |
| Tablet | 600-1200px | Master-detail optional |
| Desktop | >1200px | Multi-panel, NavigationRail |

### 7.1 Layout Shells

```
Mobile:
┌─────────────────────────┐
│        AppBar           │
├─────────────────────────┤
│                         │
│        Content          │
│                         │
├─────────────────────────┤
│      BottomNav          │
└─────────────────────────┘

Tablet:
┌─────────────────────────────────────┐
│              AppBar                  │
├──────────────┬──────────────────────┤
│   List       │      Detail          │
│   Panel      │      Panel           │
├──────────────┴──────────────────────┤
│           BottomNav                  │
└─────────────────────────────────────┘

Desktop:
┌─────────────────────────────────────────────────┐
│                   TopBar                         │
├─────────┬───────────────┬───────────────────────┤
│         │               │                        │
│  Nav    │   Order List  │    Trade Detail        │
│  Rail   │               │                        │
│         │               │                        │
└─────────┴───────────────┴───────────────────────┘
```

---

## 8. Iconography

### 8.1 Icon Library
- **Primary:** Lucide Icons (`lucide_icons` package)
- **Flags:** Country flag emojis or `flag_icons` package

### 8.2 Icon Sizes

| Context | Size |
|---------|------|
| Navigation | 24px |
| Inline with text | 16px |
| Large buttons | 20px |
| FAB | 24px |
| List item leading | 24px |

### 8.3 Icon Colors
- Active nav: mostroGreen
- Inactive nav: textSubtle
- Action buttons: textPrimary (white)
- Info icons: varies by section (green, blue, etc.)

---

## 9. Loading States

### 9.1 Skeleton Loading (Shimmer Effect)

Use skeleton placeholders instead of spinners. Shows content structure while loading.

```
Loading:                          Loaded:
┌─────────────────────────┐      ┌─────────────────────────┐
│ ░░░░░░░░░░░░            │      │ BUY BTC                 │
│ ░░░░░░░░░░░░░░░░░░░░░░  │  →   │ 1,500 - 80,000 🇻🇪      │
│ ░░░░░░░░░░              │      │ VES · 0.12% above       │
└─────────────────────────┘      └─────────────────────────┘

(shimmer animation sweeps left→right)
```

**Implementation:**

```yaml
# pubspec.yaml
dependencies:
  shimmer: ^3.0.0
```

```dart
import 'package:shimmer/shimmer.dart';

// Order card skeleton
Widget buildOrderCardSkeleton() {
  return Shimmer.fromColors(
    baseColor: Color(0xFF1E2230),      // backgroundCard
    highlightColor: Color(0xFF2A2D35), // backgroundElevated
    child: Container(
      height: 100,
      margin: EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}

// List of skeletons while loading
Widget buildOrderListSkeleton() {
  return ListView.builder(
    itemCount: 5, // Show 5 placeholder cards
    itemBuilder: (_, __) => buildOrderCardSkeleton(),
  );
}
```

**Skeleton Colors:**

| Element | Color | Hex |
|---------|-------|-----|
| Base (static) | backgroundCard | `#1E2230` |
| Highlight (shimmer) | backgroundElevated | `#2A2D35` |
| Animation duration | — | 1500ms |

**When to Use:**
- ✅ Order book loading
- ✅ Trade list loading
- ✅ Profile/settings loading
- ✅ Chat history loading
- ❌ Button loading (use disabled state + spinner)
- ❌ Form submission (use button spinner)

### 9.2 Other Loading States

| Context | Pattern |
|---------|---------|
| Initial app load | Splash screen with logo |
| Button action | Disabled + CircularProgressIndicator inside |
| Pull-to-refresh | RefreshIndicator (standard Flutter) |
| Infinite scroll | Skeleton row at bottom |
| Image loading | Shimmer placeholder → fade in |

---

## 10. Animation & Motion

### 10.1 Durations

| Type | Duration | Curve |
|------|----------|-------|
| Micro (hover, press) | 100ms | easeOut |
| Fast (toggles, chips) | 150ms | easeInOut |
| Normal (page transitions) | 300ms | easeInOut |
| Slow (modals, drawers) | 400ms | easeInOut |

### 9.2 Transitions
- Page transitions: Slide from right (forward), slide from left (back)
- Modal: Fade + scale up from center
- Bottom sheet: Slide up from bottom
- List items: Staggered fade in (50ms delay between items)

---

## 11. Accessibility

### 10.1 Contrast Ratios
- Text on backgrounds: Minimum 4.5:1 ✓
- Large text (>18sp): Minimum 3:1 ✓
- Interactive elements: Minimum 3:1 ✓

### 10.2 Touch Targets
- Minimum: 44x44px
- Recommended: 48x48px
- FAB: 56x56px

### 10.3 Screen Reader Support
- All interactive elements have semantic labels
- Images have alt text
- Focus order follows visual order
- Announcements for state changes

---

## 12. Theme Support

### 11.1 Dark Mode (Default)
All colors in this document are for dark mode, which is the primary theme.

### 11.2 Light Mode (Optional)

| Semantic Color | Dark | Light |
|----------------|------|-------|
| backgroundDark | `#1B1E28` | `#FFFFFF` |
| backgroundCard | `#1E2230` | `#F5F5F5` |
| backgroundInput | `#252A3A` | `#EEEEEE` |
| textPrimary | `#FFFFFF` | `#1A1A1A` |
| textSecondary | `#B0B3C6` | `#666666` |
| mostroGreen | `#8CC63F` | `#8CC63F` |
| sellColor | `#FF8A8A` | `#FF8A8A` |

### 11.3 Implementation
- Wrap app in `ThemeProvider` (Riverpod)
- All colors via `Theme.of(context).extension<AppColors>()`
- Never hardcode colors in widgets
- System preference detection via `MediaQuery.platformBrightness`

---

## 13. v1 Screenshot Reference

The following screenshots from v1 should be used as the visual reference:

| Screen | Description | Key Elements |
|--------|-------------|--------------|
| Order Book | Main list of buy/sell orders | Order cards, filter button, FAB |
| Order Detail | Single order expanded | Price, payment methods, rating |
| Create Order | Form for new order | Inputs, dropdowns, submit button |
| Settings | Profile and preferences | List items, icons, toggles |
| About | App information | Links, version, documentation |
| My Trades | User's active trades | Trade cards, status badges |
| Chat | Trade conversation | Message bubbles, input field |
| Invoice Entry | Lightning invoice input | Text input, amount display |

---

## 14. Quick Reference Card

```
COLORS (copy-paste ready)
─────────────────────────
Background:     #1B1E28
Card:           #1E2230
Input:          #252A3A
Elevated:       #2A2D35

Brand Green:    #8CC63F
Sell Red:       #FF8A8A
Purple:         #8359C2
Destructive:    #D84D4D

Text Primary:   #FFFFFF
Text Secondary: #B0B3C6
Text Subtle:    #9A9A9C

Chat Sent:      #8359C2
Chat Received:  #4B6349

SPACING
─────────────────────────
xs: 4px   sm: 8px   md: 12px
lg: 16px  xl: 24px  xxl: 32px

RADIUS
─────────────────────────
Cards: 12px
Buttons: 8px
Chips: 6px
Bubbles: 16px

TYPOGRAPHY
─────────────────────────
Display: 32sp bold
Heading: 20sp bold
Body: 16sp regular
Caption: 12sp regular
```
