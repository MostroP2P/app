# Drawer Menu (v1 Reference)

> Side drawer overlay for account access, settings, and app info.

**File:** `lib/shared/widgets/custom_drawer_overlay.dart`  
**State:** `lib/shared/providers/drawer_provider.dart`  
**Used in:** `HomeScreen` (wraps entire body via `CustomDrawerOverlay`)

---

## Overview

The drawer is a **custom overlay** (not Flutter's built-in `Drawer` widget). It is implemented as a `Stack`-based overlay that slides from the left over the app content. Only `HomeScreen` currently uses it.

The drawer state is managed by a Riverpod `StateProvider<bool>` called `drawerProvider`:
- `true` → drawer is open
- `false` → drawer is closed

---

## Visual Structure

```
┌────────────────────────────────────────────────────────────────────────┐
│ [overlay: black @ 30%]                                                │
│ ┌─────────────────────────────┐                                       │
│ │                             │                                       │
│ │      [Mostro logo 100px]    │  ← logo-beta.png, centered           │
│ │                             │                                       │
│ ├─────────────────────────────┤                                       │
│ │  ─────────────────────────  │  ← 1px white @ 10% divider           │
│ │                             │                                       │
│ │  👤  Account                │  → /key_management                    │
│ │  ⚙️  Settings               │  → /settings                         │
│ │  ℹ️  About                  │  → /about                            │
│ │                             │                                       │
│ │                             │                                       │
│ │                             │                                       │
│ │                             │                                       │
│ └─────────────────────────────┘  ← width: 70% screen, dark1 bg      │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Layout Details

| Element | Value |
|---------|-------|
| Width | `MediaQuery.of(context).size.width * 0.7` (70% of screen) |
| Background | `AppTheme.dark1` (`#141720`) |
| Border right | 1px white @ 10% opacity |
| Top padding | `MediaQuery.of(context).padding.top` (respects notch) |
| Logo area | 100px height, centered, `logo-beta.png` |
| Section spacing | 24px top/bottom, 16px between items |
| Divider | Below logo, 1px white @ 10% |

---

## Menu Items

| Icon | Label | Route | Screen |
|------|-------|-------|--------|
| `LucideIcons.user` | Account | `/key_management` | KeyManagementScreen |
| `LucideIcons.settings` | Settings | `/settings` | SettingsScreen |
| `LucideIcons.info` | About | `/about` | AboutScreen |

**Icon style:** `LucideIcons`, color `AppTheme.cream1` (`#F5F0E8`), size 22px  
**Label style:** `AppTheme.theme.textTheme.bodyLarge`, color `AppTheme.cream1`, `fontWeight: 500`

---

## Animation

```dart
AnimatedPositioned(
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeInOut,
  left: isDrawerOpen ? 0 : -MediaQuery.of(context).size.width * 0.7,
  top: 0,
  bottom: 0,
  child: /* drawer container */,
)
```

- **Open:** `left: 0` — drawer visible
- **Closed:** `left: -screenWidth * 0.7` — drawer hidden off-screen left
- **Duration:** 300ms
- **Curve:** `easeInOut`

---

## Close Drawer Triggers

| Trigger | Behavior |
|---------|----------|
| Tap overlay (black area) | `drawerProvider.closeDrawer()` |
| Swipe left on drawer | `drawerProvider.closeDrawer()` |
| Back button (Android) | `PopScope(canPop: false)` → `closeDrawer()` |
| Tap menu item | `closeDrawer()` then `context.push(route)` |

### Back Button Handling

```dart
PopScope(
  canPop: !isDrawerOpen,
  onPopInvokedWithResult: (didPop, result) {
    if (!didPop && isDrawerOpen) {
      ref.read(drawerProvider.notifier).closeDrawer();
    }
  },
  child: AnimatedPositioned(/* drawer */),
)
```

When the drawer is open, `canPop: false` prevents the system back button from navigating away. Instead, it closes the drawer.

---

## Drawer Provider

```dart
// lib/shared/providers/drawer_provider.dart
final drawerProvider = StateProvider<bool>((ref) => false);

extension DrawerNotifier on StateNotifier<bool> {
  void toggleDrawer() => state = !state;
  void closeDrawer() => state = false;
  void openDrawer() => state = true;
}
```

**Why a provider instead of a Flutter `Drawer`?**
- More control over animation (custom curve, duration, overlay)
- Can be applied to any screen (currently only HomeScreen)
- Overlay + drawer in single `Stack` without `Scaffold` complexity
- Consistent with the app's custom navigation model

---

## Implementation Notes

The `CustomDrawerOverlay` wraps a `Widget child` and renders the drawer as a sibling in a `Stack`:

```dart
class CustomDrawerOverlay extends ConsumerWidget {
  final Widget child;
  
  const CustomDrawerOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        child,                    // Main screen content (behind drawer)
        if (isDrawerOpen)        // Semi-transparent overlay
          GestureDetector(
            onTap: () => ref.read(drawerProvider.notifier).closeDrawer(),
            child: Container(color: Colors.black.withValues(alpha: 0.3)),
          ),
        AnimatedPositioned(/* drawer */),
      ],
    );
  }
}
```

This pattern allows any screen to use the drawer without duplicating the overlay logic — just wrap the screen's body with `CustomDrawerOverlay`.

---

## Cross-References

- **HomeScreen:** `.specify/v1-reference/HOME_SCREEN.md`
- **Navigation:** `.specify/v1-reference/NAVIGATION_ROUTES.md`
- **KeyManagement / Account:** `.specify/v1-reference/ACCOUNT_SCREEN.md`
- **Settings:** `.specify/v1-reference/SETTINGS_SCREEN.md`
- **About:** `.specify/v1-reference/ABOUT_SCREEN.md`
