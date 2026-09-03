import 'package:flutter/material.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Shows the open-dispute confirmation dialog.
///
/// A dispute escalates the trade to an admin and cannot be undone, so — like
/// the release and cancel actions in the same row — it is confirmed first.
/// Returns `true` if the user confirms, `false`/`null` if cancelled (#280).
Future<bool?> showDisputeConfirmationDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (dialogContext) => const _DisputeConfirmationDialog(),
  );
}

class _DisputeConfirmationDialog extends StatelessWidget {
  const _DisputeConfirmationDialog();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final destructive = colors?.destructiveRed ?? const Color(0xFFD84D4D);
    final l10n = AppLocalizations.of(context);

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gavel, size: 48, color: destructive),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.openDisputeTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.openDisputeConfirmation,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors?.textSecondary,
                      side: BorderSide(
                        color: colors?.textSecondary ?? Colors.grey,
                      ),
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: Text(l10n.noButtonLabel),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: destructive,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: Text(l10n.yesButtonLabel),
                  ).withAutomationId(AutomationIds.tradeDisputeConfirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
