# Mostro Mobile v2 — Design System

**Status:** Reference document from v1 + v2 additions
**Based on:** Mobile v1 DESIGN_SYSTEM.md (January-February 2026)

---

## 1. Core Principles

### 1.1 Single Source of Truth
ALL colors must be defined in a central theme file. Zero hardcoded colors in widgets.

### 1.2 Semantic Naming
Use names that describe purpose, not appearance:
- ✅ `mostroGreen`, `backgroundCard`, `statusError`
- ❌ `lightGreen`, `darkGray`, `red2`

### 1.3 No Duplication
Use aliases instead of duplicate values:
```dart
static const Color mostroGreen = Color(0xFF8CC63F);
static const Color buyColor = mostroGreen;  // Alias, not duplicate

───

2. Final Color Palette

2.1 Brand Colors

| Name        | Hex     | RGB            | Usage                               |
| ----------- | ------- | -------------- | ----------------------------------- |
| mostroGreen | #8CC63F | (140, 198, 63) | Primary brand, buy actions, success |

2.2 Action Colors

| Name         | Hex     | RGB             | Usage                                 |
| ------------ | ------- | --------------- | ------------------------------------- |
| buyColor     | #8CC63F | (140, 198, 63)  | Buy buttons, positive actions         |
| sellColor    | #FF8A8A | (255, 138, 138) | Sell buttons, negative premiums       |
| red1         | #D84D4D | (216, 77, 77)   | Destructive actions (cancel, dispute) |
| purpleButton | #7856AF | (120, 86, 175)  | Submit buttons, accents               |

2.3 Status Colors

| Name          | Hex     | RGB             | Usage                      |
| ------------- | ------- | --------------- | -------------------------- |
| statusSuccess | #8CC63F | (140, 198, 63)  | Success messages           |
| statusWarning | #F3CA29 | (243, 202, 41)  | Warnings, pending          |
| statusError   | #EF6A6A | (239, 106, 106) | Error messages, validation |
| statusInfo    | #2A7BD6 | (42, 123, 214)  | Informational              |

2.4 Background Hierarchy (4 levels)

| Level | Name               | Hex     | Usage                                |
| ----- | ------------------ | ------- | ------------------------------------ |
| 0     | backgroundDark     | #171A23 | Main screen background (darkest)     |
| 1     | backgroundCard     | #1E2230 | Cards, list items, elevated surfaces |
| 2     | backgroundInput    | #252A3A | Input fields, interactive elements   |
| 3     | backgroundElevated | #303544 | Modals, dialogs (lightest)           |

2.5 Text Colors

| Name          | Value          | Usage                   |
| ------------- | -------------- | ----------------------- |
| textPrimary   | Colors.white   | Primary content         |
| textSecondary | #CCCCCC        | Supporting text, labels |
| textSubtle    | Colors.white60 | Timestamps, hints       |
| textDisabled  | #8A8D98        | Disabled text           |

2.6 Status Chip Colors

| Status   | Background | Text    |
| -------- | ---------- | ------- |
| Pending  | #854D0E    | #FCD34D |
| Waiting  | #7C2D12    | #FED7AA |
| Active   | #1E3A8A    | #93C5FD |
| Success  | #065F46    | #6EE7B7 |
| Dispute  | #7F1D1D    | #FCA5A5 |
| Settled  | #581C87    | #C084FC |
| Inactive | #1F2937    | #D1D5DB |

2.7 Role Chip Colors

| Role             | Hex     | Usage              |
| ---------------- | ------- | ------------------ |
| createdByYouChip | #1565C0 | Orders you created |
| takenByYouChip   | #00796B | Orders you took    |
| premiumPositive  | #388E3C | Positive premium   |
| premiumNegative  | #C62828 | Negative premium   |

───

3. Responsive Design

3.1 Breakpoints

| Name  | Widt
h      | Layout                      |
| ------- | ---------- | --------------------------- |
| Mobile  | < 600px    | Single column, BottomNav    |
| Tablet  | 600-1200px | Master-detail optional      |
| Desktop | > 1200px   | Multi-panel, NavigationRail |

3.2 Layout Components

Mobile:

┌─────────────┐
│   AppBar    │
├─────────────┤
│   Content   │
├─────────────┤
│  BottomNav  │
└─────────────┘

Desktop:

┌─────────────────────────────────────────┐
│              TopBar                      │
├──────────┬──────────────┬───────────────┤
│ NavRail  │  Order List  │  Trade Panel  │
└──────────┴──────────────┴───────────────┘

3.3 Responsive Utilities

// Use LayoutBuilder or MediaQuery
bool isMobile(BuildContext context) => 
    MediaQuery.of(context).size.width < 600;

bool isDesktop(BuildContext context) => 
    MediaQuery.of(context).size.width > 1200;

───

4. Component Patterns

4.1 Buttons

| Type           | Background   | Text          | Usage                 |
| -------------- | ------------ | ------------- | --------------------- |
| Primary (Buy)  | mostroGreen  | textPrimary   | Main positive actions |
| Primary (Sell) | sellColor    | textPrimary   | Sell actions          |
| Destructive    | red1         | textPrimary   | Cancel, dispute       |
| Secondary      | purpleButton | textPrimary   | Submit, confirm       |
| Ghost          | transparent  | textSecondary | Low-emphasis          |

4.2 Cards

Container(
  decoration: BoxDecoration(
    color: AppTheme.backgroundCard,
    borderRadius: BorderRadius.circular(12),
  ),
)

4.3 Input Fields

TextField(
  decoration: InputDecoration(
    fillColor: AppTheme.backgroundInput,
    filled: true,
  ),
)

4.4 Trade Progress Stepper

// Horizontal on desktop, vertical on mobile
Stepper(
  type: isMobile(context) 
      ? StepperType.vertical 
      : StepperType.horizontal,
  currentStep: currentTradeStep,
  steps: [...],
)

───

5. Typography

5.1 Font Family

• Primary: Roboto Condensed
• Weights: 400 (Regular), 500 (Medium), 700 (Bold)

5.2 Text Styles

| Style          | Size | Weight  | Color         |
| -------------- | ---- | ------- | ------------- |
| Heading 1      | 24sp | Bold    | textPrimary   |
| Heading 2      | 20sp | Medium  | textPrimary   |
| Body           | 16sp | Regular | textPrimary   |
| Body Secondary | 14sp | Regular | textSecondary |
| Caption        | 12sp | Regular | textSubtle    |

───

6. Iconography

• Primary: Lucide Icons (lucide_icons package)
• Secondary: Heroicons for specific cases
• Size: 24px default, 20px compact, 32px large

───

7. Animation & Motion

7.1 Durations

• Fast: 150ms (micro-interactions)
• Normal: 300ms (transitions)
• Slow: 500ms (complex animations)

7.2 Curves

• Default: Curves.easeInOut
• Enter: Curves.easeOut
• Exit: Curves.easeIn

───

8. Accessibility

8.1 Contrast Ratios

• Text on backgrounds: Minimum 4.5:1
• Large text: Minimum 3:1
• Interactive elements: Minimum 3:1

8.2 Touch Targets

• Minimum: 44x44px
• Recommended: 48x48px

8.3 Screen Readers

• All interactive elements have semantic labels
• Images have alt text
• Focus order is logical

───

9. Platform Considerations

9.1 Web

• QR scanning: WebRTC camera or file upload fallback
• No haptic feedback
• Hover states for interactive elements

9.2 Desktop

• Keyboard navigation support
• Right-click context menus (future)
• Window resize handling

9.3 Mobile

• Haptic feedback on key actions
• Native camera for QR
• Pull-to-refresh patterns

───

10. Migration from v1

Colors Removed (do not use)

• ❌ green2 (unused)
• ❌ red2 (duplicate of statusError)
• ❌ purpleAccent (merged into purpleButton)
• ❌ backgroundNavBar (use backgroundDark)
• ❌ backgroundInactive (use backgroundInput)
• ❌ dark1 (use backgroundCard)
• ❌ dark2 (renamed to backgroundElevated)

Colors Kept

• ✅ All colors in Section 2 of this document

## 11. Theme Support

### Dark/Light Mode

The app supports both dark and light themes, switchable by user preference or system setting.

#### Theme Detection
- Default: Follow system setting (MediaQuery.platformBrightness)
- User override: Stored in local preferences
- Persist across sessions

#### Color Mapping

| Semantic Color | Dark Theme | Light Theme |
|---------------|------------|-------------|
| background | `#171A23` | `#FFFFFF` |
| backgroundCard | `#1E2230` | `#F5F5F5` |
| backgroundInput | `#252A3A` | `#EEEEEE` |
| textPrimary | `#FFFFFF` | `#1A1A1A` |
| textSecondary | `#CCCCCC` | `#666666` |
| mostroGreen | `#8CC63F` | `#8CC63F` (same) |
| sellColor | `#FF8A8A` | `#FF8A8A` (same) |

#### Implementation
- Use `ThemeData` with `ColorScheme`
- Wrap app in `ThemeProvider` (Riverpod)
- All colors via `Theme.of(context)` — never hardcoded
