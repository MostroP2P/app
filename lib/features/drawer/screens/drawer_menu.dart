import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';

/// Drawer menu overlay — slides from left, ~70% screen width.
///
/// Header: Mostro mascot icon + "Beta" label + "MOSTRO" title.
/// 3 menu items: Account, Settings, About.
class DrawerMenu extends StatelessWidget {
  const DrawerMenu({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
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
          child: Container(
            width: screenWidth * 0.7,
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
                        // Mascot icon placeholder (skull)
                        Icon(
                          Icons.psychology_outlined,
                          size: 48,
                          color: green,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            Text(
                              'MOSTRO',
                              style: theme.textTheme.headlineLarge!.copyWith(
                                color: green,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: green),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.chip),
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
                      onClose();
                      context.push(AppRoute.keyManagement);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _MenuItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () {
                      onClose();
                      context.push(AppRoute.settings);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _MenuItem(
                    icon: Icons.info_outline,
                    label: 'About',
                    onTap: () {
                      onClose();
                      context.push(AppRoute.about);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
    return InkWell(
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
    );
  }
}
