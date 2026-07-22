import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/account/screens/backup_ritual_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Opens the backup ritual trigger bottom sheet.
///
/// "Back up now" launches the 3-step [BackupRitualScreen];
/// "Remind me tomorrow" snoozes the reminder for ~24 hours.
Future<void> showBackupTriggerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const BackupTriggerSheet(),
  );
}

/// Bottom sheet inviting the user to start the backup ritual.
class BackupTriggerSheet extends ConsumerWidget {
  const BackupTriggerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final elevated = colors?.backgroundElevated ?? const Color(0xFF2A2D35);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final textDisabled = colors?.textDisabled ?? const Color(0xFF6C757D);
    final amber = colors?.warningAmber ?? const Color(0xFFE89C3C);
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Hero circle
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      green.withValues(alpha: 0.33),
                      green.withValues(alpha: 0.10),
                    ],
                  ),
                ),
                child: Icon(Icons.star_rounded, size: 40, color: amber),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              l10n.backupBannerTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge!
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text.rich(
              TextSpan(
                text: l10n.backupTriggerBody,
                children: [
                  TextSpan(
                    text: l10n.backupTriggerBodyHighlight,
                    style:
                        TextStyle(color: green, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium!
                  .copyWith(color: textSec, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 3-step preview
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: elevated,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Column(
                children: [
                  for (final (n, label) in [
                    (1, l10n.backupStepWriteDown),
                    (2, l10n.backupStepVerifyRandom),
                    (3, l10n.backupStepSecured),
                  ]) ...[
                    if (n > 1) const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: green.withValues(alpha: 0.15),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$n',
                            style: TextStyle(
                              color: green,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(label, style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Primary CTA
            FilledButton(
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BackupRitualScreen(),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(54),
                textStyle:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(l10n.backupNowButton),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Ghost CTA
            TextButton(
              onPressed: () {
                ref
                    .read(backupReminderProvider.notifier)
                    .snoozeUntilTomorrow();
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: textSec,
                minimumSize: const Size.fromHeight(44),
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: Text(l10n.remindMeTomorrowButton),
            ),
          ],
        ),
      ),
    );
  }
}
