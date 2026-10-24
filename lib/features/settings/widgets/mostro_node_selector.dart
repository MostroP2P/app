import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/node_selector_palette.dart';
import 'package:mostro/features/account/restore/restore_after_switch.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/settings/models/node_display.dart';
import 'package:mostro/features/settings/models/node_selector_rules.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/providers/node_stats_provider.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/settings/widgets/add_custom_node_dialog.dart';
import 'package:mostro/features/settings/widgets/node_card.dart';
import 'package:mostro/features/settings/widgets/node_operator_disclaimer.dart';
import 'package:mostro/features/settings/widgets/node_switch_confirm_sheet.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/widgets/dashed_border.dart';
import 'package:mostro/src/rust/api/node_stats.dart' show MostroNodeStats;
import 'package:mostro/src/rust/api/types.dart';

export 'package:mostro/features/settings/models/node_display.dart'
    show localizedNodeError, nodeDisplayName, nodeNameOf, regionFlag;
export 'package:mostro/features/settings/providers/mostro_nodes_provider.dart'
    show mostroPubkeyProvider, truncatePubkey;
export 'package:mostro/features/settings/widgets/add_custom_node_dialog.dart'
    show AddCustomNodeDialog, showAddCustomNodeDialog;

/// `Elegir nodo` (handoff 9a): the Settings → node sheet.
///
/// One flat list — no `Trusted` / `Custom` sections, the chip on the card
/// says it — ordered by open orders in the user's currency, unreachable
/// nodes last. Each card answers "does it serve me?" (currencies, orders,
/// fee, range) before "do I trust it?" (custody, bond). Tapping a card
/// selects it and the sheet closes on its own; there is no confirm button.
///
/// Figures come from [nodeStatsProvider], fetched while the sheet is open.
/// Until they land each card shows the node's settings as last seen
/// ([cachedNodeStatsProvider]) and a skeleton for the order count — or
/// skeletons throughout for a node never seen — never a spinner over a card.
class MostroNodeSelector extends ConsumerStatefulWidget {
  const MostroNodeSelector({super.key, this.switched});

  /// Completed with the node switched to once a switch goes through, or with
  /// null once the sheet is gone without one. A switch still running when the
  /// user dismisses the sheet completes it when it ends (#813).
  final Completer<String?>? switched;

  @override
  ConsumerState<MostroNodeSelector> createState() => _MostroNodeSelectorState();
}

class _MostroNodeSelectorState extends ConsumerState<MostroNodeSelector> {
  /// Pubkey of the card just tapped: its radio fills while the sheet closes.
  String? _selectingPubkey;

  /// Set before the first await of a tap, so two quick taps cannot open two
  /// confirmation flows or race two `selectNode` calls.
  bool _switching = false;

  /// How long the filled radio is shown before the sheet closes itself.
  static const _closeDelay = Duration(milliseconds: 200);

  /// [MostroNodeSelector.switched], kept here: a switch that outlives the
  /// sheet reports through it after the widget is gone.
  late final Completer<String?>? _switched;

  @override
  void initState() {
    super.initState();
    _switched = widget.switched;
    // Opportunistic kind 0 refresh (names, avatars) each time the selector
    // opens; the cached registry shows meanwhile.
    Future.microtask(
      () => ref.read(mostroNodesProvider.notifier).refreshMetadata(),
    );
  }

  @override
  void dispose() {
    // A switch still running reports its own outcome when it ends.
    if (!_switching) _reportSwitch(null);
    super.dispose();
  }

  void _reportSwitch(String? node) {
    final switched = _switched;
    if (switched != null && !switched.isCompleted) switched.complete(node);
  }

  String _activeNodeName() => nodeNameOf(
    ref.read(mostroPubkeyProvider),
    ref.read(mostroNodesProvider).valueOrNull ?? const [],
  );

  Future<void> _onNodeTap(MostroNodeEntry entry) async {
    if (entry.isActive || _switching) return;
    _switching = true;
    try {
      await _switchTo(entry);
    } finally {
      _switching = false;
      // Dismissed while it ran: a switch that went through has reported its
      // node already, and anything else ends without one.
      if (!mounted) _reportSwitch(null);
    }
  }

  Future<void> _switchTo(MostroNodeEntry entry) async {
    HapticFeedback.selectionClick();
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // A trade in progress stays on the node it started on: switching then
    // deserves a word first.
    final inProgress = await ref.read(tradeInProgressLookupProvider)();
    if (!mounted) return;
    if (inProgress == null) {
      // Unknown whether a trade would be left behind: do not switch on a
      // guess, say so, and let the user try again.
      _snack(l10n.nodeTradesCheckFailed);
      return;
    }
    if (inProgress) {
      final ok = await showNodeSwitchConfirmSheet(
        context,
        currentNode: _activeNodeName(),
        newNode: nodeDisplayName(entry),
      );
      if (!ok || !mounted) return;
    }

    setState(() => _selectingPubkey = entry.pubkey);
    try {
      await Future.wait([
        ref.read(mostroNodesProvider.notifier).selectNode(entry.pubkey),
        Future<void>.delayed(_closeDelay),
      ]);
      _reportSwitch(entry.pubkey);
      // The user may have dismissed the sheet during the switch; popping via
      // the captured navigator would then close the route underneath it.
      if (mounted) navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.nodeSwitchedSuccess(nodeDisplayName(entry))),
        ),
      );
    } catch (e) {
      debugPrint('[MostroNodeSelector] selectNode failed: $e');
      if (mounted) setState(() => _selectingPubkey = null);
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorSwitchingNode)));
    }
  }

  void _onBlocked(NodeBlocker blocker) {
    final l10n = AppLocalizations.of(context);
    _snack(switch (blocker) {
      NodeBlocker.unreachable => l10n.nodeNotSelectableOffline,
    });
  }

  Future<void> _onDeleteNode(MostroNodeEntry entry) async {
    if (entry.isTrusted || entry.isActive) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showMostroDialog<bool>(
      context: context,
      builder:
          (ctx) => MostroDialog(
            title: l10n.deleteCustomNodeTitle,
            body: l10n.deleteCustomNodeMessage,
            secondary: ModalAction(
              label: l10n.cancel,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            primary: ModalAction(
              label: l10n.deleteCustomNodeConfirm,
              onPressed: () => Navigator.of(ctx).pop(true),
              tone: ModalTone.destructive,
            ),
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(mostroNodesProvider.notifier)
          .removeCustomNode(entry.pubkey);
      messenger.showSnackBar(SnackBar(content: Text(l10n.nodeRemovedSuccess)));
    } catch (e) {
      debugPrint('[MostroNodeSelector] removeCustomNode failed: $e');
      messenger.showSnackBar(
        SnackBar(content: Text(localizedNodeError(l10n, e))),
      );
    }
  }

  /// The sheet's snackbar: card surface, radius 12, two seconds.
  void _snack(String text) {
    final book = OrderBookPalette.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, style: TextStyle(color: book.textStrong)),
          backgroundColor: book.surface,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final nodesAsync = ref.watch(mostroNodesProvider);
    final statsAsync = ref.watch(nodeStatsProvider);
    final myFiat = ref.watch(
      settingsProvider.select((s) => s.defaultFiatCode?.toUpperCase()),
    );
    final btcPrice =
        myFiat == null
            ? null
            : ref.watch(exchangeRateProvider(myFiat)).valueOrNull;
    final now = clock.now();

    // Live figures win as soon as they exist; the cached settings only fill
    // the wait (and stay if the fetch fails). They never order the list:
    // without order counts every node would tie anyway.
    final stats = statsAsync.valueOrNull;
    final cachedStats =
        stats != null
            ? const <String, MostroNodeStats>{}
            : ref.watch(cachedNodeStatsProvider).valueOrNull ?? const {};
    final nodes = sortNodes(
      nodesAsync.valueOrNull ?? const [],
      stats ?? const {},
      myFiat,
      now,
    );
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: book.bg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.modal),
        ),
        border: Border(
          top: BorderSide(color: book.textPrimary.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: book.textPrimary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          _Header(myFiat: myFiat),
          Flexible(
            child:
                nodesAsync.isLoading && nodes.isEmpty
                    ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                    : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      // The operator disclaimer first, in full and in the
                      // scroll, as on the first run's node choice.
                      itemCount: nodes.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (i == 0) return const NodeOperatorDisclaimer();
                        final entry = nodes[i - 1];
                        final live = stats?[entry.pubkey];
                        return NodeCard(
                          key: ValueKey(entry.pubkey),
                          entry: entry,
                          stats: live ?? cachedStats[entry.pubkey],
                          statsCached: live == null,
                          statsLoading: statsAsync.isLoading,
                          myFiat: myFiat,
                          btcPrice: btcPrice,
                          // One radio at a time: while a switch is in
                          // flight the tapped node owns it, not the node
                          // that is still active underneath.
                          selected:
                              _selectingPubkey == null
                                  ? entry.isActive
                                  : entry.pubkey == _selectingPubkey,
                          now: now,
                          onSelect: () => _onNodeTap(entry),
                          onBlocked: _onBlocked,
                          onCopyPubkey: () => _snack(l10n.nodePubkeyCopied),
                          onLongPress:
                              entry.isTrusted || entry.isActive
                                  ? null
                                  : () => _onDeleteNode(entry),
                        );
                      },
                    ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              14,
              18,
              18 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: _AddOwnNodeButton(
              enabled: _selectingPubkey == null,
              onTap: () => showAddCustomNodeDialog(context),
            ).withAutomationId(AutomationIds.nodeAddCustom),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.myFiat});

  final String? myFiat;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);

    // The currency code is set in lime inside the localized sentence: find it
    // in the rendered string rather than splitting the template by hand.
    final subtitleStyle = TextStyle(fontSize: 11, color: book.textTertiary);
    final Widget subtitle;
    final code = myFiat;
    if (code == null) {
      subtitle = Text(
        l10n.nodeSelectorSubtitleNoCurrency,
        style: subtitleStyle,
      );
    } else {
      final text = l10n.nodeSelectorSubtitle(code);
      final at = text.indexOf(code);
      subtitle =
          at < 0
              ? Text(text, style: subtitleStyle)
              : Text.rich(
                TextSpan(
                  style: subtitleStyle,
                  children: [
                    TextSpan(text: text.substring(0, at)),
                    TextSpan(
                      text: code,
                      style: TextStyle(
                        color: book.limeIcon,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: text.substring(at + code.length)),
                  ],
                ),
              );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.selectMostroNode,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: book.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                subtitle,
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, size: 20, color: book.textSecondary),
            tooltip: l10n.closeButtonLabel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ).withAutomationId(AutomationIds.nodeCustomCancel),
        ],
      ),
    );
  }
}

/// `+ Agregar nodo propio`: full width, dashed border, the same pattern as
/// the `Agregar` chip of create order.
class _AddOwnNodeButton extends StatelessWidget {
  const _AddOwnNodeButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = NodeSelectorPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return CustomPaint(
      foregroundPainter: DashedBorderPainter(color: pal.dashedBorder),
      child: Material(
        color: pal.dashedFill,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 14, color: book.limeIcon),
                const SizedBox(width: 6),
                Text(
                  l10n.addCustomNode,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: book.textBody,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Open the node selector as a modal sheet over Settings. Once a switch
/// goes through, [afterSwitch] restores the account on the new node (#813),
/// also when the user dismissed the sheet while the switch ran; a sheet
/// closed without one, or a failed switch, restores nothing.
Future<void> showMostroNodeSelector(
  BuildContext context, {
  Future<void> Function(BuildContext) afterSwitch = restoreAfterNodeSwitch,
}) async {
  final switched = Completer<String?>();
  // A screen, not a question: it paints its own page backdrop and its own
  // footer, so it opens `bare` rather than inside a [MostroSheet].
  await showMostroSheet<void>(
    context: context,
    bare: true,
    builder: (_) => MostroNodeSelector(switched: switched),
  );
  if (await switched.future == null || !context.mounted) return;
  await afterSwitch(context);
}
