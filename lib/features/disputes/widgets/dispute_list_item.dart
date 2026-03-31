import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// A single row in the disputes list.
///
/// Layout:
/// ⚠️  Order dispute                          [Status chip] ● (unread dot)
///     truncated-order-uuid
///     "You opened this dispute" / resolution text
class DisputeListItem extends ConsumerWidget {
  const DisputeListItem({super.key, required this.dispute});

  final DisputeItem dispute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) throw StateError('AppColors theme extension must be registered');
    final textTheme = Theme.of(context).textTheme;

    final (statusBg, statusFg, statusLabel) = _statusChip(dispute.status);
    final truncatedId = dispute.tradeId.length > 16
        ? '${dispute.tradeId.substring(0, 16)}…'
        : dispute.tradeId;

    return InkWell(
      onTap: () {
        ref.read(disputeNotifierProvider.notifier).markRead(dispute.id);
        context.push(AppRoute.disputeDetailsPath(dispute.id));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Warning icon ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 2, right: AppSpacing.md),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 24,
                color: colors.badgeGold,
              ),
            ),

            // ── Main content ────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + status chip
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context).orderDispute,
                          style: textTheme.bodyLarge?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _StatusChip(
                        label: statusLabel,
                        background: statusBg,
                        foreground: statusFg,
                      ),
                      if (!dispute.isRead) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors.destructiveRed,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),

                  // Truncated order ID
                  Text(
                    truncatedId,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSubtle,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),

                  // Description
                  Text(
                    dispute.description,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static (Color, Color, String) _statusChip(DisputeStatus status) {
    return switch (status) {
      DisputeStatus.open => (
        AppColors.statusPending.$1,
        AppColors.statusPending.$2,
        'Initiated',
      ),
      DisputeStatus.inReview => (
        AppColors.statusActive.$1,
        AppColors.statusActive.$2,
        'In progress',
      ),
      DisputeStatus.resolved => (
        AppColors.statusInactive.$1,
        AppColors.statusInactive.$2,
        'Closed',
      ),
    };
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
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
