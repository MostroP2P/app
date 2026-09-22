import 'package:flutter/material.dart';

import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// Asks before switching nodes while a trade is in progress: changing node
/// changes market, and the running trade stays on the node it started on.
///
/// Returns `true` when the user confirms.
Future<bool> showNodeSwitchConfirmSheet(
  BuildContext context, {
  required String currentNode,
  required String newNode,
}) async {
  final confirmed = await showMostroSheet<bool>(
    context: context,
    builder:
        (_) =>
            _NodeSwitchConfirmSheet(currentNode: currentNode, newNode: newNode),
  );
  return confirmed ?? false;
}

class _NodeSwitchConfirmSheet extends StatelessWidget {
  const _NodeSwitchConfirmSheet({
    required this.currentNode,
    required this.newNode,
  });

  final String currentNode;
  final String newNode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return MostroSheet(
      title: l10n.nodeSwitchConfirmTitle,
      body: l10n.nodeSwitchConfirmBody(currentNode, newNode),
      secondary: ModalAction(
        label: l10n.cancel,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      primary: ModalAction(
        label: l10n.nodeSwitchConfirmAction,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    );
  }
}
