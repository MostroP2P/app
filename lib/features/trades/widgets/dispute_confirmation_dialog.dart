import 'package:flutter/material.dart';

import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// Shows the open-dispute confirmation dialog.
///
/// A dispute escalates the trade to an admin and cannot be undone, so — like
/// the release and cancel actions in the same row — it is confirmed first.
/// Returns `true` if the user confirms, `false`/`null` if cancelled (#280).
Future<bool?> showDisputeConfirmationDialog(BuildContext context) {
  return showMostroDialog<bool>(
    context: context,
    builder: (dialogContext) => const _DisputeConfirmationDialog(),
  );
}

class _DisputeConfirmationDialog extends StatelessWidget {
  const _DisputeConfirmationDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return MostroDialog(
      title: l10n.openDisputeTitle,
      body: l10n.openDisputeConfirmation,
      icon: Icons.gavel,
      iconTone: ModalTone.destructive,
      secondary: ModalAction(
        label: l10n.noButtonLabel,
        onPressed: () => Navigator.pop(context, false),
      ),
      primary: ModalAction(
        label: l10n.yesButtonLabel,
        onPressed: () => Navigator.pop(context, true),
        tone: ModalTone.destructive,
        automationId: AutomationIds.tradeDisputeConfirm,
      ),
    );
  }
}
