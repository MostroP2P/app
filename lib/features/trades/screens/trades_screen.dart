import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/activity_palette.dart';
import 'package:mostro/core/app_theme.dart' show AppBreakpoints;
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/drawer/screens/drawer_menu.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/features/trades/widgets/trade_card.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart' show BottomNavBar;
import 'package:mostro/shared/widgets/tab_app_bar.dart';

const _side = 18.0;
const _move = Duration(milliseconds: 240);

/// My Trades — handoff 11a. Route [AppRoute.orderBook] (bottom nav tab 1).
///
/// Grouped by what each trade asks of the user — `Requieren tu acción`,
/// `En curso`, `Cerradas` — rather than by date, so the one that waits for
/// the user never looks like one cancelled fifteen hours ago.
class TradesScreen extends ConsumerStatefulWidget {
  const TradesScreen({super.key});

  @override
  ConsumerState<TradesScreen> createState() => _TradesScreenState();
}

class _TradesScreenState extends ConsumerState<TradesScreen> {
  bool _drawerOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = OrderBookPalette.of(context);
    final isDesktop =
        MediaQuery.sizeOf(context).width >= AppBreakpoints.desktop;

    // Something just became the user's to do.
    ref.listen<int>(needsActionCountProvider, (prev, next) {
      if (prev == 0 && next > 0) HapticFeedback.mediumImpact();
    });

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabAppBar(
          onMenuTap:
              isDesktop ? null : () => setState(() => _drawerOpen = true),
        ),
        const _Header(),
        const Expanded(child: _TradesBody()),
      ],
    );

    final body =
        isDesktop
            ? Row(
              children: [
                const DrawerMenu(persistent: true),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
            : Stack(
              children: [
                content,
                if (_drawerOpen)
                  DrawerMenu(
                    onClose: () => setState(() => _drawerOpen = false),
                  ),
              ],
            );

    return Theme(
      data: theme.copyWith(scaffoldBackgroundColor: book.bg),
      child: Scaffold(
        backgroundColor: book.bg,
        body: body,
        bottomNavigationBar: const BottomNavBar(),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = OrderBookPalette.of(context);
    final pal = ActivityPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(tradeListFilterProvider);
    final applied = filter != TradeListFilter.all;

    return Padding(
      padding: const EdgeInsets.fromLTRB(_side, 2, _side, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.navMyTrades,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.19,
                color: book.textPrimary,
              ),
            ),
          ),
          Material(
            color: applied ? pal.chipActionBg : pal.filterBg,
            shape: StadiumBorder(
              side: BorderSide(
                color: applied ? pal.chipActionBorder : pal.filterBorder,
              ),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => _pickFilter(context, ref, filter),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.filter_list_rounded,
                      size: 12,
                      color: applied ? pal.chipActionInk : book.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      filterText(filter, l10n),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: applied ? pal.chipActionInk : book.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String filterText(TradeListFilter f, AppLocalizations l10n) =>
      switch (f) {
        TradeListFilter.all => l10n.tradeListFilterAll,
        TradeListFilter.active => l10n.tradeListFilterActive,
        TradeListFilter.completed => l10n.tradeListFilterCompleted,
        TradeListFilter.cancelled => l10n.tradeListFilterCancelled,
      };

  Future<void> _pickFilter(
    BuildContext context,
    WidgetRef ref,
    TradeListFilter current,
  ) async {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<TradeListFilter>(
      context: context,
      backgroundColor: book.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    child: Text(
                      l10n.tradeListFilterTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: book.textPrimary,
                      ),
                    ),
                  ),
                  for (final f in TradeListFilter.values)
                    ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      title: Text(
                        filterText(f, l10n),
                        style: TextStyle(fontSize: 13, color: book.textStrong),
                      ),
                      trailing:
                          f == current
                              ? Icon(Icons.check_rounded, color: book.limeIcon)
                              : null,
                      onTap: () => Navigator.of(ctx).pop(f),
                    ),
                ],
              ),
            ),
          ),
    );
    if (picked != null) {
      await ref.read(tradeListFilterProvider.notifier).select(picked);
    }
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _TradesBody extends ConsumerWidget {
  const _TradesBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = OrderBookPalette.of(context);
    final grouped = ref.watch(groupedTradeRowsProvider);

    Future<void> refresh() async {
      refreshTrades(ref);
      try {
        await ref.read(rawTradesProvider.future);
      } catch (_) {
        // The error state below says so.
      }
    }

    return grouped.when(
      loading: () => Center(child: CircularProgressIndicator(color: book.lime)),
      error: (e, st) {
        debugPrint('[TradesScreen] load error: $e\n$st');
        return _Message(
          icon: Icons.error_outline_rounded,
          title: AppLocalizations.of(context).couldNotLoadTradesMessage,
          action: TextButton(
            onPressed: () => ref.invalidate(rawTradesProvider),
            child: Text(AppLocalizations.of(context).retry),
          ),
        );
      },
      data:
          (groups) => RefreshIndicator(
            color: book.lime,
            backgroundColor: book.surface,
            onRefresh: refresh,
            child:
                groups.isEmpty
                    ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.5,
                          child: _Message(
                            icon: Icons.bolt_outlined,
                            title: AppLocalizations.of(context).noTradesTitle,
                            subtitle:
                                AppLocalizations.of(context).noTradesSubtitle,
                          ),
                        ),
                      ],
                    )
                    : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(_side, 0, _side, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final group in TradeGroup.values)
                            _GroupSection(
                              key: ValueKey(group),
                              group: group,
                              rows:
                                  groups
                                      .where((g) => g.group == group)
                                      .firstOrNull
                                      ?.rows ??
                                  const [],
                              isFirst:
                                  groups.isNotEmpty &&
                                  groups.first.group == group,
                            ),
                        ],
                      ),
                    ),
          ),
    );
  }
}

/// A group, or nothing when it is empty. Its height animates as cards move
/// in or out, so a trade changing group never jumps under the finger; a
/// group appearing fades in and slides 8 dp.
class _GroupSection extends StatelessWidget {
  const _GroupSection({
    super.key,
    required this.group,
    required this.rows,
    required this.isFirst,
  });

  final TradeGroup group;
  final List<TradeRow> rows;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final pal = ActivityPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final title = switch (group) {
      TradeGroup.needsAction => l10n.tradesGroupNeedsAction,
      TradeGroup.inProgress => l10n.tradesGroupInProgress,
      TradeGroup.closed => l10n.tradesGroupClosed,
    };

    return AnimatedSwitcher(
      duration: _move,
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      transitionBuilder:
          (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: AnimatedBuilder(
                animation: animation,
                child: child,
                builder:
                    (context, child) => Transform.translate(
                      offset: Offset(0, 8 * (1 - animation.value)),
                      child: child,
                    ),
              ),
            ),
          ),
      child:
          rows.isEmpty
              ? const SizedBox(key: ValueKey('empty'), width: double.infinity)
              : Padding(
                key: const ValueKey('rows'),
                padding: EdgeInsets.only(top: isFirst ? 0 : 18),
                child: AnimatedSize(
                  duration: _move,
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GroupHeader(
                        title: title,
                        count: rows.length,
                        color: pal.groupHeader,
                      ),
                      for (final row in rows) ...[
                        const SizedBox(height: 10),
                        TradeCard(key: ValueKey(row.orderId), row: row),
                      ],
                    ],
                  ),
                ),
              ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 28,
              color: ActivityPalette.of(context).chevronIdle,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: book.textMuted,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: book.textTertiary),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
