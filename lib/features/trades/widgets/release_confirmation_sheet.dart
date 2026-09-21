import 'package:flutter/material.dart';

import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// Asks the seller to confirm the release. It is the only action of the
/// trade screen that asks: releasing cannot be undone, whereas marking the
/// fiat as sent is reversible through a dispute.
///
/// Returns `true` if the user confirms, `false` or `null` otherwise.
Future<bool?> showReleaseConfirmationSheet(BuildContext context) {
  return showMostroSheet<bool>(
    context: context,
    builder: (_) => const _ReleaseConfirmationSheet(),
  );
}

class _ReleaseConfirmationSheet extends StatelessWidget {
  const _ReleaseConfirmationSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return MostroSheet(
      title: l10n.releaseSheetTitle,
      body: l10n.releaseSheetBody,
      secondary: ModalAction(
        label: l10n.releaseSheetBack,
        onPressed: () => Navigator.pop(context, false),
      ),
      primary: ModalAction(
        label: l10n.releaseSheetConfirm,
        onPressed: () => Navigator.pop(context, true),
        automationId: AutomationIds.tradeReleaseConfirm,
      ),
    );
  }
}
