import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';

/// Drawer menu — overlay on mobile/tablet, persistent sidebar on desktop.
///
/// **Overlay mode** (`persistent: false`, default): renders as a full-screen
/// Stack with a 30 % black overlay and a 70 %-wide panel from the left edge.
/// **Persistent mode** (`persistent: true`): renders as a fixed-width
/// [240 px] sidebar column, suitable for embedding in a [Row] on desktop.
///
/// Header: Mostro mascot icon + "Beta" label + "MOSTRO" title.
/// 3 menu items: Account, Settings, About.
class DrawerMenu extends StatelessWidget {
  const DrawerMenu({
    super.key,
    this.onClose,
    this.persistent = false,
  });

  /// Called when the user taps the overlay background (overlay mode only).
  final VoidCallback? onClose;

  /// When `true` the widget renders as a sidebar column rather than an overlay.
  final bool persistent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);

    final panel = _SidebarContent(
      green: green,
      cardBg: cardBg,
      theme: theme,
      onNavigate: persistent ? null : onClose,
    );

    if (persistent) {
      return SizedBox(width: 240, child: panel);
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    return Stack(
      children: [
        // Black overlay — 30% opacity
        GestureDetector(
          onTap: onClose,
          child: Container(color: Colors.black.withValues(alpha: 0.3)),
        ),

        // Drawer panel — 70% screen width
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: screenWidth * 0.7, child: panel),
        ),
      ],
    );
  }
}

// ── Sidebar content (shared between overlay and persistent modes) ─────────────

class _SidebarContent extends StatelessWidget {
  const _SidebarContent({
    required this.green,
    required this.cardBg,
    required this.theme,
    required this.onNavigate,
  });

  final Color green;
  final Color cardBg;
  final ThemeData theme;

  /// Called before each navigation push (closes overlay drawer if not null).
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cardBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxl,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.psychology_outlined, size: 48, color: green),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Text(
                        'MOSTRO',
                        style: (theme.textTheme.headlineLarge ??
                                theme.textTheme.headlineMedium ??
                                const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ))
                            .copyWith(color: green, letterSpacing: 2),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: green),
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        child: Text(
                          'Beta',
                          style: TextStyle(
                            color: green,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),

            // Menu items
            _MenuItem(
              icon: Icons.key_outlined,
              label: 'Account',
              onTap: () {
                onNavigate?.call();
                context.push(AppRoute.keyManagement);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _MenuItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () {
                onNavigate?.call();
                context.push(AppRoute.settings);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _MenuItem(
              icon: Icons.info_outline,
              label: 'About',
              onTap: () {
                onNavigate?.call();
                context.push(AppRoute.about);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: AppSpacing.lg),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
