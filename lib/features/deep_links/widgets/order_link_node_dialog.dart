import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/widgets/node_operator_disclaimer.dart'
    show NodeWarningNote;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// Asks to change to the node that published a linked order. Resolves to
/// `true` when the user agrees; nothing changes until then — a link never
/// switches nodes on its own.
///
/// [nodeName] is the order's node as the registry names it, or its truncated
/// pubkey. [isKnown] says whether the registry holds that node at all: one the
/// user never trusted nor added gets a warning, since only the link vouches
/// for it. [tradeLeftOn] names the active node when a trade in progress stays
/// behind there, as the Settings switch says it.
Future<bool> showOrderLinkNodeDialog(
  BuildContext context, {
  required String nodeName,
  required bool isKnown,
  String? tradeLeftOn,
}) async {
  final confirmed = await showMostroDialog<bool>(
    context: context,
    builder:
        (_) => OrderLinkNodeDialog(
          nodeName: nodeName,
          isKnown: isKnown,
          tradeLeftOn: tradeLeftOn,
        ),
  );
  return confirmed ?? false;
}

/// The question [showOrderLinkNodeDialog] asks.
class OrderLinkNodeDialog extends StatelessWidget {
  const OrderLinkNodeDialog({
    super.key,
    required this.nodeName,
    required this.isKnown,
    this.tradeLeftOn,
  });

  final String nodeName;
  final bool isKnown;
  final String? tradeLeftOn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final book = OrderBookPalette.of(context);
    // The dialog's body prose, set by hand: `MostroDialog` takes `body` or
    // `content`, and the notes need the latter.
    Text prose(String text) => Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 14, height: 1.5, color: book.textSecondary),
    );
    final paragraphs = [
      prose(l10n.orderLinkOtherNodeBody(nodeName)),
      if (!isKnown) NodeWarningNote(l10n.orderLinkUnknownNodeWarning),
      if (tradeLeftOn case final current?)
        prose(l10n.nodeSwitchConfirmBody(current, nodeName)),
    ];

    return MostroDialog(
      icon: Icons.swap_horiz_rounded,
      title: l10n.orderLinkOtherNodeTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, paragraph) in paragraphs.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            paragraph,
          ],
        ],
      ),
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
