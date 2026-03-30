import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/disputes/widgets/dispute_list_item.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Disputes list widget — driven by [userDisputeDataProvider].
///
/// Used in the Chat screen Disputes tab (Phase 12).
///
/// States:
/// - Loading → spinner
/// - Error → message + retry button
/// - Empty → gavel icon + "Your disputes will appear here"
/// - Populated → [ListView] of [DisputeListItem]
class DisputesList extends ConsumerWidget {
  const DisputesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>();
    assert(colors != null, 'AppColors theme extension must be registered');
    if (colors == null) return const SizedBox.shrink();

    final disputesAsync = ref.watch(userDisputeDataProvider);

    return disputesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) {
        debugPrint('Disputes load error: $err\n$stack');
        return _ErrorState(
          message: AppLocalizations.of(context).disputeLoadError,
          colors: colors,
          onRetry: () => ref.invalidate(userDisputeDataProvider),
        );
      },
      data: (disputes) => disputes.isEmpty
          ? _EmptyState(colors: colors)
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: disputes.length,
              separatorBuilder: (_, __) => Divider(
                color: colors.backgroundElevated,
                height: 1,
                indent: AppSpacing.lg,
                endIndent: AppSpacing.lg,
              ),
              itemBuilder: (context, index) =>
                  DisputeListItem(dispute: disputes[index]),
            ),
    );
  }
}

// ── Private widgets ───────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gavel, size: 64, color: colors.textSubtle),
          const SizedBox(height: AppSpacing.lg),
          Text(
            AppLocalizations.of(context).disputesEmptyState,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.colors,
    required this.onRetry,
  });

  final String message;
  final AppColors colors;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: colors.destructiveRed),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.textSubtle),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
