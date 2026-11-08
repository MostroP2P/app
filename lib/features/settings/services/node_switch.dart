/// A node switch asked for from outside Settings: a `mostro:` order link,
/// a notification card of another node. Settings keeps its own flow, which
/// closes its sheet around the switch.
///
/// Two steps, so that the caller can close its own dialog or waiting view
/// between them: [switchActiveNode], then [afterNodeSwitch] once it went
/// through.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/account/restore/restore_after_switch.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart'
    show showOrderDetailSnackBar;
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Makes [pubkey] the active node, the Settings path: persists the choice
/// and re-targets every subscription before it returns. Whether it went
/// through; a failure is logged and left to the caller to tell.
Future<bool> switchActiveNode(WidgetRef ref, String pubkey) async {
  try {
    await ref.read(mostroNodesProvider.notifier).selectNode(pubkey);
    return true;
  } catch (e) {
    debugPrint('[node-switch] switch to $pubkey failed: $e');
    return false;
  }
}

/// What follows a switch that went through: says so, then restores the
/// account on the new node, as a switch from Settings does (#813).
/// Resolves once the restore sheet closes.
Future<void> afterNodeSwitch(
  BuildContext context,
  WidgetRef ref,
  String nodeName,
) async {
  showOrderDetailSnackBar(
    context,
    AppLocalizations.of(context).nodeSwitchedSuccess(nodeName),
  );
  await ref.read(restoreAfterNodeSwitchProvider)(context);
}
