import 'package:flutter/material.dart';

import 'package:mostro/core/node_selector_palette.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// The operator disclaimer in full, v1's text, wherever a node is chosen:
/// the first run's node choice and the Settings selector. A warning, so amber
/// (DS-COL-9), in the warning box of the add-own-node dialog; the icon is
/// decoration, the text says it.
class NodeOperatorDisclaimer extends StatelessWidget {
  const NodeOperatorDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = NodeSelectorPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: pal.warnBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.warnBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: pal.dotWarn,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).nodeOperatorDisclaimer,
              style: TextStyle(fontSize: 12, height: 1.45, color: pal.warnInk),
            ),
          ),
        ],
      ),
    );
  }
}
