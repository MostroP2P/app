import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Asks the seller to confirm the release. It is the only action of the
/// trade screen that asks: releasing cannot be undone, whereas marking the
/// fiat as sent is reversible through a dispute.
///
/// Returns `true` if the user confirms, `false` or `null` otherwise.
Future<bool?> showReleaseConfirmationSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: OrderBookPalette.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _ReleaseConfirmationSheet(),
  );
}

class _ReleaseConfirmationSheet extends StatelessWidget {
  const _ReleaseConfirmationSheet();

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: book.textPrimary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.releaseSheetTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: book.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.releaseSheetBody,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: book.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: book.lime,
                foregroundColor: book.onLime,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontFamily: AppFonts.ui,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(l10n.releaseSheetConfirm),
            ).withAutomationId(AutomationIds.tradeReleaseConfirm),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: book.textSecondary,
                textStyle: const TextStyle(
                  fontFamily: AppFonts.ui,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: Text(l10n.releaseSheetBack),
            ),
          ],
        ),
      ),
    );
  }
}
