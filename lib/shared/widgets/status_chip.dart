import 'package:flutter/material.dart';
import 'package:mostro/core/app_theme.dart';

/// Small rounded chip used for order/trade status labels and role badges.
///
/// Presentation-only: callers pass the resolved [background]/[foreground]
/// colors (typically an `AppColors.statusXxx` tuple) and the display [label].
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
      ),
    );
  }
}

/// Chip identifying the local user's role in a trade. Uses the shared
/// "active" palette; the role-to-label mapping stays at the call site.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: label,
      background: AppColors.statusActive.$1,
      foreground: AppColors.statusActive.$2,
    );
  }
}
