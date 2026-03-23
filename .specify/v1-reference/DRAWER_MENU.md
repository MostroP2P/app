# Drawer Menu (v1 Reference)

> Side menu accessed via hamburger icon in the app bar.

## Overview

The drawer slides in from the left (70% screen width) with a semi-transparent overlay behind it.

## Structure

```text
┌─────────────────────────────────────┐
│                                     │
│         [Logo - beta.png]           │
│                                     │
├─────────────────────────────────────┤
│                                     │
│  👤  Account                        │  → /key_management
│                                     │
│  ⚙️  Settings                       │  → /settings
│                                     │
│  ℹ️  About                          │  → /about
│                                     │
│                                     │
│                                     │
│                                     │
│                                     │
└─────────────────────────────────────┘
```

## Specs

| Property | Value |
|----------|-------|
| Width | 70% of screen |
| Background | `backgroundCard` (#1E2230) |
| Border right | 1px white @ 10% opacity |
| Animation | 300ms easeInOut slide |
| Overlay | black @ 30% opacity |

## Menu Items

| Icon | Label | Route | Description |
|------|-------|-------|-------------|
| `LucideIcons.user` | Account | `/key_management` | Identity, mnemonic, privacy mode |
| `LucideIcons.settings` | Settings | `/settings` | Language, currency, relays, wallet |
| `LucideIcons.info` | About | `/about` | App info, docs, Mostro node |

## Behavior

- Tap outside drawer → closes drawer
- Swipe left on drawer → closes drawer
- Back button when drawer open → closes drawer (doesn't navigate back)
- Tap menu item → closes drawer, then navigates

## Implementation

```dart
class CustomDrawerOverlay extends ConsumerWidget {
  final Widget child;
  
  const CustomDrawerOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDrawerOpen = ref.watch(drawerProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Stack(
      children: [
        // Main content
        child,
        
        // Semi-transparent overlay
        if (isDrawerOpen)
          GestureDetector(
            onTap: () => ref.read(drawerProvider.notifier).closeDrawer(),
            child: Container(
              color: Colors.black.withOpacity(0.3),
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        
        // Animated drawer
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          left: isDrawerOpen ? 0 : -screenWidth * 0.7,
          top: 0,
          bottom: 0,
          width: screenWidth * 0.7,
          child: Container(
            color: AppTheme.backgroundCard,
            child: Column(
              children: [
                // Drawer content here
                const SizedBox(height: 24),
                // Logo, menu items, etc.
              ],
            ),
          ),
        ),
      ],
    );
  }
}
```
