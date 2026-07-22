import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';

// ── Shared helpers ────────────────────────────────────────────────────────────

void _copyToClipboard(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(AppLocalizations.of(context).aboutCopiedToClipboard),
      duration: const Duration(seconds: 2),
    ),
  );
}

// ── TradeInformationTab ───────────────────────────────────────────────────────

/// Expandable panel showing trade / order details.
///
/// Field values are placeholder dashes until the trade provider is wired
/// (Phase 10+).
class TradeInformationTab extends StatelessWidget {
  const TradeInformationTab({
    super.key,
    required this.orderId,
  });

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) throw StateError('AppColors theme extension must be registered');
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.all(AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Text(
              AppLocalizations.of(context).tradeInformationTitle,
              style: textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.md),

            // Order ID (copyable)
            _InfoRow(
              label: AppLocalizations.of(context).orderIdLabel,
              value: orderId,
              colors: colors,
              textTheme: textTheme,
              copyable: true,
            ),
            _InfoRow(
              label: AppLocalizations.of(context).fiatAmountLabel,
              value: '—',
              colors: colors,
              textTheme: textTheme,
            ),
            _InfoRow(
              label: AppLocalizations.of(context).satsAmountLabel,
              value: '—',
              colors: colors,
              textTheme: textTheme,
            ),
            _InfoRow(
              label: AppLocalizations.of(context).statusLabel,
              value: null, // rendered as chip below
              colors: colors,
              textTheme: textTheme,
              customValue: _StatusChip(colors: colors),
            ),
            _InfoRow(
              label: AppLocalizations.of(context).paymentMethodLabel,
              value: '—',
              colors: colors,
              textTheme: textTheme,
            ),
            _InfoRow(
              label: AppLocalizations.of(context).createdLabel,
              value: '—',
              colors: colors,
              textTheme: textTheme,
            ),

            const SizedBox(height: AppSpacing.md),

            // Phase note
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.backgroundInput,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Text(
                AppLocalizations.of(context).tradeDetailsPlaceholder,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSubtle,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── UserInformationTab ────────────────────────────────────────────────────────

/// Expandable panel showing peer identity details.
class UserInformationTab extends StatelessWidget {
  const UserInformationTab({
    super.key,
    required this.peerHandle,
    required this.peerPubkey,
    required this.peerIconIndex,
    required this.peerColorHue,
  });

  final String peerHandle;
  final String peerPubkey;
  final int peerIconIndex;
  final int peerColorHue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) throw StateError('AppColors theme extension must be registered');
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.all(AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Text(AppLocalizations.of(context).userInformationTitle,
                style: textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.md),

            // Avatar + handle
            Row(
              children: [
                NymAvatar(
                  iconIndex: peerIconIndex,
                  colorHue: peerColorHue,
                  size: 56,
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  peerHandle,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Peer public key
            Text(
              AppLocalizations.of(context).peerPublicKeyLabel,
              style: textTheme.bodySmall?.copyWith(color: colors.textSubtle),
            ),
            const SizedBox(height: AppSpacing.xs),
            GestureDetector(
              onTap: () => _copy(context, peerPubkey),
              child: Text(
                peerPubkey,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.blueAccent,
                  fontFamily: 'monospace',
                ),
                softWrap: true,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Shared key
            Text(
              AppLocalizations.of(context).yourSharedKeyLabel,
              style: textTheme.bodySmall?.copyWith(color: colors.textSubtle),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              AppLocalizations.of(context).sharedKeyPlaceholder,
              style: textTheme.bodySmall?.copyWith(
                color: colors.textSubtle,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Safety note
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.backgroundInput,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: colors.textSubtle,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).sharedKeySafetyNote,
                      style: textTheme.bodySmall
                          ?.copyWith(color: colors.textSubtle),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copy(BuildContext context, String text) =>
      _copyToClipboard(context, text);
}

// ── Private helpers ───────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.colors,
    required this.textTheme,
    this.copyable = false,
    this.customValue,
  });

  final String label;
  final String? value;
  final AppColors colors;
  final TextTheme textTheme;
  final bool copyable;
  final Widget? customValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(color: colors.textSubtle),
            ),
          ),
          Expanded(
            child: customValue ??
                GestureDetector(
                  onTap: copyable && value != null
                      ? () => _copyToClipboard(context, value!)
                      : null,
                  child: Text(
                    value ?? '—',
                    style: textTheme.bodySmall?.copyWith(
                      color: copyable ? colors.textLink : colors.textSecondary,
                    ),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.statusActive.$1,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        AppLocalizations.of(context).tradeStatusActive,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.statusActive.$2,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}
