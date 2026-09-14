import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/backup_palette.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/account/screens/backup_ritual_screen.dart';
import 'package:mostro/features/account/widgets/backup_widgets.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Opens the `Secure your reputation` sheet (15c).
Future<void> showBackupTriggerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: BackupPalette.of(context).scrim,
    builder: (_) => const BackupTriggerSheet(),
  );
}

/// The sheet inviting the user into the 3-step backup (15c).
///
/// `Back up now` launches [BackupRitualScreen]. `I'll do it later` only
/// closes the sheet: the banner stays on Account until the words are backed
/// up. It still quiets the bell's reminder dot for a day, as the old
/// `Remind me tomorrow` did — the copy no longer promises that reminder.
class BackupTriggerSheet extends ConsumerWidget {
  const BackupTriggerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final steps = [
      l10n.backupStepWriteDown,
      l10n.backupStepVerifyRandom,
      l10n.backupStepSecured,
    ];

    return Container(
      decoration: BoxDecoration(
        color: book.surface,
        border: Border.all(color: pal.sheetBorder),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        26 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: pal.grabber,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pal.heroFill,
                ),
                child: Icon(Icons.star_rounded, size: 30, color: pal.amber),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.backupBannerTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: book.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(
                text: l10n.backupTriggerBody,
                children: [
                  TextSpan(
                    text: l10n.backupTriggerBodyHighlight,
                    style: TextStyle(
                      color: book.limeInk,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: book.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: pal.stepsFill,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < steps.length; i++)
                    _StepRow(number: i + 1, label: steps[i], divided: i > 0),
                ],
              ),
            ),
            const SizedBox(height: 14),
            BackupPrimaryButton(
              label: l10n.backupNowButton,
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BackupRitualScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () {
                ref.read(backupReminderProvider.notifier).snoozeUntilTomorrow();
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: book.textSecondary,
                minimumSize: const Size.fromHeight(40),
                textStyle: const TextStyle(
                  fontFamily: AppFonts.ui,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: Text(l10n.backupLaterButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.label,
    required this.divided,
  });

  final int number;
  final String label;

  /// Hairline above every row but the first.
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border:
            divided ? Border(top: BorderSide(color: pal.stepDivider)) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pal.stepNumberFill,
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: book.limeInk,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: book.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
