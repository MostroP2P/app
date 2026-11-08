import 'package:flutter/material.dart';

import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// Asked when the user opens a notification of a trade on another node
/// (#811): switch to that node? [onSwitch] runs while the dialog stays open,
/// its action busy, since a switch re-targets every subscription and can
/// take seconds. Resolves to whether the switch went through, or null when
/// the user said no.
Future<bool?> showOtherNodeSwitchDialog(
  BuildContext context, {
  required String nodeName,
  required Future<bool> Function() onSwitch,
}) => showMostroDialog<bool>(
  context: context,
  builder: (_) => OtherNodeSwitchDialog(nodeName: nodeName, onSwitch: onSwitch),
);

class OtherNodeSwitchDialog extends StatefulWidget {
  const OtherNodeSwitchDialog({
    super.key,
    required this.nodeName,
    required this.onSwitch,
  });

  final String nodeName;
  final Future<bool> Function() onSwitch;

  @override
  State<OtherNodeSwitchDialog> createState() => _OtherNodeSwitchDialogState();
}

class _OtherNodeSwitchDialogState extends State<OtherNodeSwitchDialog> {
  bool _switching = false;

  Future<void> _switch() async {
    setState(() => _switching = true);
    // A throw counts as a failed switch: left busy, the dialog could not be
    // closed (Cancel disabled, canPop false).
    var switched = false;
    try {
      switched = await widget.onSwitch();
    } catch (e) {
      debugPrint('[node-switch] switch failed: $e');
    }
    if (mounted) Navigator.of(context).pop(switched);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Neither the barrier nor back closes it mid-switch: the switch would
    // go on with no one left to open the trade after it.
    return PopScope(
      canPop: !_switching,
      child: MostroDialog(
        icon: Icons.swap_horiz_rounded,
        title: l10n.otherNodeCardDialogTitle,
        body: l10n.otherNodeCardSwitchPrompt(widget.nodeName),
        secondary: ModalAction(
          label: l10n.cancel,
          onPressed: _switching ? null : () => Navigator.of(context).pop(),
        ),
        primary: ModalAction(
          label: l10n.nodeSwitchConfirmAction,
          busy: _switching,
          onPressed: _switch,
        ),
      ),
    );
  }
}
