import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/features/settings/models/node_selector_rules.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/providers/node_stats_provider.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/settings/widgets/node_card.dart';
import 'package:mostro/features/settings/widgets/node_operator_disclaimer.dart';
import 'package:mostro/features/walkthrough/providers/first_run_provider.dart';
import 'package:mostro/features/walkthrough/providers/node_prefetch_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';
import 'package:mostro/src/rust/api/node_stats.dart' show MostroNodeStats;

/// The first run's last step, after the walkthrough: which Mostro node to
/// trade on (v1's community selector).
///
/// The operator disclaimer, then every node of the registry as a [NodeCard],
/// the default node first, all in one scroll over the pinned actions
/// (DS-SPC-5). Tapping a card picks it and "Use this node" makes it the
/// active node; Skip keeps the default node. Either one completes the
/// first run, arms the backup reminder and goes home.
///
/// The figures were downloaded during the walkthrough
/// ([firstRunNodePrefetchProvider]); until they land a card shows the
/// node's cached settings and skeletons, as in the Settings selector.
class NodeChoiceScreen extends ConsumerStatefulWidget {
  const NodeChoiceScreen({super.key});

  @override
  ConsumerState<NodeChoiceScreen> createState() => _NodeChoiceScreenState();
}

class _NodeChoiceScreenState extends ConsumerState<NodeChoiceScreen> {
  /// The card the user tapped; `null` until they tap one.
  String? _picked;

  /// Set while the choice is being applied: one tap, one switch.
  bool _busy = false;

  Future<void> _complete(String pubkey) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    try {
      if (ref.read(mostroPubkeyProvider) != pubkey) {
        await ref.read(mostroNodesProvider.notifier).selectNode(pubkey);
      }
    } catch (e) {
      debugPrint('[NodeChoice] selectNode failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(l10n.errorSwitchingNode);
      return;
    }
    try {
      // The reminder first: once the first run is complete this screen never
      // comes back to arm it again.
      await ref.read(backupReminderProvider.notifier).showBackupReminder();
      await ref.read(firstRunProvider.notifier).markFirstRunComplete();
    } catch (e) {
      // A failed write must not leave both actions dead: say so, let a
      // retry in.
      debugPrint('[NodeChoice] saving the first run failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(l10n.nodeChoiceSaveFailed);
      return;
    }
    if (mounted) context.go(AppRoute.home);
  }

  void _onBlocked(NodeBlocker blocker) {
    final l10n = AppLocalizations.of(context);
    _snack(switch (blocker) {
      NodeBlocker.unreachable => l10n.nodeNotSelectableOffline,
    });
  }

  /// The selector's snackbar: card surface, radius 12, two seconds.
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
    ref.watch(firstRunNodePrefetchProvider);
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final picked = _picked;

    return Scaffold(
      backgroundColor: book.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: redesignSidePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _NodeList(
                  header: const _Header(),
                  picked: picked,
                  onPick: (pubkey) {
                    HapticFeedback.selectionClick();
                    setState(() => _picked = pubkey);
                  },
                  onBlocked: _onBlocked,
                  onCopyPubkey: () => _snack(l10n.nodePubkeyCopied),
                ),
              ),
              const SizedBox(height: 14),
              OrderPrimaryButton(
                label: l10n.nodeChoiceConfirm,
                onPressed:
                    picked == null || _busy ? null : () => _complete(picked),
              ).withAutomationId(AutomationIds.communityDone),
              _SkipLink(
                label: l10n.skip,
                onPressed: _busy ? null : () => _complete(defaultMostroPubkey),
              ).withAutomationId(AutomationIds.communitySkip),
            ],
          ),
        ),
      ),
    );
  }
}

/// The title, what is asked and the operator disclaimer: the top of the
/// scroll, so a narrow screen at large text still reaches the cards.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: Text(
            l10n.selectMostroNode,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.15,
              color: book.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.nodeChoiceSubtitle,
          style: TextStyle(fontSize: 14, height: 1.5, color: book.textBody),
        ),
        const SizedBox(height: 14),
        const NodeOperatorDisclaimer(),
      ],
    );
  }
}

/// [header], then the registry as node cards, the default node first and
/// the rest in the selector's order.
class _NodeList extends ConsumerWidget {
  const _NodeList({
    required this.header,
    required this.picked,
    required this.onPick,
    required this.onBlocked,
    required this.onCopyPubkey,
  });

  final Widget header;
  final String? picked;
  final ValueChanged<String> onPick;
  final ValueChanged<NodeBlocker> onBlocked;
  final VoidCallback onCopyPubkey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    // As in the Settings selector: live figures win as soon as they exist,
    // the cached settings only fill the wait.
    final stats = statsAsync.valueOrNull;
    final cachedStats =
        stats != null
            ? const <String, MostroNodeStats>{}
            : ref.watch(cachedNodeStatsProvider).valueOrNull ?? const {};
    final nodes = withNodeFirst(
      sortNodes(
        ref.watch(mostroNodesProvider).valueOrNull ?? const [],
        stats ?? const {},
        myFiat,
        now,
      ),
      defaultMostroPubkey,
    );

    return ListView.separated(
      itemCount: nodes.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i == 0) return header;
        final entry = nodes[i - 1];
        final live = stats?[entry.pubkey];
        return NodeCard(
          key: ValueKey(entry.pubkey),
          entry: entry,
          stats: live ?? cachedStats[entry.pubkey],
          statsCached: live == null,
          statsLoading: statsAsync.isLoading,
          myFiat: myFiat,
          flags: flags,
          btcPrice: btcPrice,
          selected: entry.pubkey == picked,
          now: now,
          onSelect: () => onPick(entry.pubkey),
          onBlocked: onBlocked,
          onCopyPubkey: onCopyPubkey,
        ).withAutomationId(AutomationIds.communityCard(entry.pubkey));
      },
    );
  }
}

/// Skip, as a full-width text link with a 48 dp target (DS-CMP-6, DS-CMP-20),
/// as on the walkthrough.
class _SkipLink extends StatelessWidget {
  const _SkipLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: book.textSecondary,
        minimumSize: const Size.fromHeight(48),
        // A button's textStyle replaces the theme's: name the family.
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Text(label),
    );
  }
}
