import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/node_selector_palette.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/settings/models/node_display.dart';
import 'package:mostro/features/settings/models/node_selector_rules.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/providers/node_stats_provider.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/settings/widgets/add_custom_node_dialog.dart';
import 'package:mostro/features/settings/widgets/node_card.dart';
import 'package:mostro/features/settings/widgets/node_switch_confirm_sheet.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/dashed_border.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/src/rust/api/types.dart';

export 'package:mostro/features/settings/models/node_display.dart'
    show localizedNodeError, nodeDisplayName, regionFlag;
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
/// Figures come from [nodeStatsProvider], fetched while the sheet is open;
/// until they land the metric strips show skeletons, never a spinner over a
/// card.
class MostroNodeSelector extends ConsumerStatefulWidget {
  const MostroNodeSelector({super.key});

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

  @override
  void initState() {
    super.initState();
    // Opportunistic kind 0 refresh (names, avatars) each time the selector
    // opens; the cached registry shows meanwhile.
    Future.microtask(
      () => ref.read(mostroNodesProvider.notifier).refreshMetadata(),
    );
  }

  /// A trade that has neither finished nor been resolved keeps living on the
  /// node it started on; switching then deserves a word first. `null` when
  /// the lookup itself failed — the caller must not switch on a guess.
  Future<bool?> _hasTradeInProgress() async {
    try {
      final trades = await ref.read(rawTradesProvider.future);
      return trades.any((t) => t.completedAt == null && t.outcome == null);
    } catch (e) {
      debugPrint('[MostroNodeSelector] trades lookup failed: $e');
      return null;
    }
  }

  String _activeNodeName() {
    final nodes = ref.read(mostroNodesProvider).valueOrNull ?? const [];
    for (final n in nodes) {
      if (n.isActive) return nodeDisplayName(n);
    }
    return truncatePubkey(ref.read(mostroPubkeyProvider));
  }

  Future<void> _onNodeTap(MostroNodeEntry entry) async {
    if (entry.isActive || _switching) return;
    _switching = true;
    try {
      await _switchTo(entry);
    } finally {
      _switching = false;
    }
  }

  Future<void> _switchTo(MostroNodeEntry entry) async {
    HapticFeedback.selectionClick();
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final inProgress = await _hasTradeInProgress();
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(l10n.deleteCustomNodeTitle),
            content: Text(l10n.deleteCustomNodeMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.deleteCustomNodeConfirm),
              ),
            ],
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
    final flags = ref.watch(currencyFlagsProvider);
    final btcPrice =
        myFiat == null
            ? null
            : ref.watch(exchangeRateProvider(myFiat)).valueOrNull;
    final now = clock.now();

    final stats = statsAsync.valueOrNull ?? const {};
    final nodes = sortNodes(
      nodesAsync.valueOrNull ?? const [],
      stats,
      myFiat,
      now,
    );
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: book.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
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
                      itemCount: nodes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final entry = nodes[i];
                        return NodeCard(
                          key: ValueKey(entry.pubkey),
                          entry: entry,
                          stats: stats[entry.pubkey],
                          statsLoading: statsAsync.isLoading,
                          myFiat: myFiat,
                          flags: flags,
                          btcPrice: btcPrice,
                          selected:
                              entry.isActive ||
                              entry.pubkey == _selectingPubkey,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AddOwnNodeButton(
                  enabled: _selectingPubkey == null,
                  onTap: () => showAddCustomNodeDialog(context),
                ).withAutomationId(AutomationIds.nodeAddCustom),
                const SizedBox(height: 11),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.info_outline,
                        size: 13,
                        color: book.textFaint,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.nodeDisclaimerShort,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.5,
                          color: book.textFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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

/// Open the node selector as a modal sheet over Settings.
Future<void> showMostroNodeSelector(BuildContext context) {
  final book = OrderBookPalette.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: book.scrim,
    builder: (_) => const MostroNodeSelector(),
  );
}
