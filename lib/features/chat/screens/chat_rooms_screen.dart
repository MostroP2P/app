import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/activity_palette.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart' show AppBreakpoints;
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/chat/models/chat_list_rules.dart';
import 'package:mostro/features/chat/providers/chat_list_provider.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/chat/widgets/chat_list_item.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/disputes/widgets/disputes_list.dart';
import 'package:mostro/features/drawer/screens/drawer_menu.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart';
import 'package:mostro/shared/widgets/tab_app_bar.dart';

const _side = 18.0;

/// Route: /chat_list — handoff 11b.
///
/// `Mensajes` / `Disputas` as a segmented control with pending counts, the
/// conversations grouped by whether their trade is still open, closed ones
/// stepped back.
///
/// On init, syncs [chatRoomsFromTradesProvider] into [chatRoomsNotifierProvider]
/// so the Messages segment is populated from the trade DB rather than empty.
class ChatRoomsScreen extends ConsumerStatefulWidget {
  const ChatRoomsScreen({super.key});

  @override
  ConsumerState<ChatRoomsScreen> createState() => _ChatRoomsScreenState();
}

class _ChatRoomsScreenState extends ConsumerState<ChatRoomsScreen> {
  bool _drawerOpen = false;

  @override
  void initState() {
    super.initState();
    // Any subsequent live updates are pushed by ChatRoomScreen via upsertRoom.
    _syncRoomsFromTrades();
  }

  Future<void> _syncRoomsFromTrades() async {
    try {
      final rooms = await ref.read(chatRoomsFromTradesProvider.future);
      if (!mounted) return;
      // Upsert rather than replace: a room added concurrently by
      // ChatRoomScreen.upsertRoom (a message landing mid-fetch) survives.
      final notifier = ref.read(chatRoomsNotifierProvider.notifier);
      for (final room in rooms) {
        notifier.upsertRoom(room);
      }
    } catch (e) {
      debugPrint('[chat] syncRoomsFromTrades failed: $e');
    }
  }

  Future<void> _refresh() async {
    refreshTrades(ref);
    ref.invalidate(chatRoomsFromTradesProvider);
    await _syncRoomsFromTrades();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = OrderBookPalette.of(context);
    final isDesktop =
        MediaQuery.sizeOf(context).width >= AppBreakpoints.desktop;

    // Keep every room live while the list is on screen: a message received
    // here updates its preview, badge, the segment count and the order.
    final rooms = ref.read(chatRoomsNotifierProvider.notifier);
    for (final room in ref.watch(chatRoomsNotifierProvider)) {
      ref.listen(
        incomingMessageProvider(room.orderId),
        (_, next) =>
            next.whenData((msg) => rooms.foldIncoming(room.orderId, msg)),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabAppBar(
          onMenuTap:
              isDesktop ? null : () => setState(() => _drawerOpen = true),
        ),
        const _Segments(),
        Expanded(
          child: TabBarView(
            children: [_MessagesTab(onRefresh: _refresh), const DisputesList()],
          ),
        ),
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

    return DefaultTabController(
      length: 2,
      child: Theme(
        data: theme.copyWith(scaffoldBackgroundColor: book.bg),
        child: Scaffold(
          backgroundColor: book.bg,
          body: body,
          bottomNavigationBar: const BottomNavBar(),
        ),
      ),
    );
  }
}

// ── Segmented control ─────────────────────────────────────────────────────────

class _Segments extends ConsumerWidget {
  const _Segments();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = DefaultTabController.of(context);
    final unread = ref.watch(chatCountProvider);
    final disputes = ref.watch(disputeUnreadCountProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(_side, 2, _side, 14),
      child: AnimatedBuilder(
        animation: controller,
        builder:
            (context, _) => Row(
              children: [
                Expanded(
                  child: _Segment(
                    label: l10n.messagesTab,
                    count: unread,
                    selected: controller.index == 0,
                    onTap: () => controller.animateTo(0),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _Segment(
                    label: l10n.disputesTab,
                    count: disputes,
                    selected: controller.index == 1,
                    onTap: () => controller.animateTo(1),
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = ActivityPalette.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? pal.chipActionBg : pal.segIdleBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? pal.chipActionBorder : pal.segIdleBorder,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? pal.chipActionInk : book.textMuted,
                    ),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  CountBadge(
                    count: count,
                    size: 17,
                    background: pal.badgeBg,
                    foreground: pal.badgeInk,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Messages ──────────────────────────────────────────────────────────────────

class _MessagesTab extends ConsumerWidget {
  const _MessagesTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = OrderBookPalette.of(context);
    final pal = ActivityPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final groups = ref.watch(groupedChatRowsProvider);

    return RefreshIndicator(
      color: book.lime,
      backgroundColor: book.surface,
      onRefresh: onRefresh,
      child:
          groups.isEmpty
              ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.5,
                    child: const _EmptyMessages(),
                  ),
                ],
              )
              : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(_side, 0, _side, 18),
                children: [
                  for (final (i, group) in groups.indexed) ...[
                    if (i > 0) const SizedBox(height: 18),
                    GroupHeader(
                      title: switch (group.group) {
                        ChatGroup.active => l10n.chatGroupActive,
                        ChatGroup.closed => l10n.tradesGroupClosed,
                      },
                      count: group.rows.length,
                      color: pal.groupHeader,
                    ),
                    const SizedBox(height: 10),
                    Opacity(
                      opacity:
                          group.group == ChatGroup.closed
                              ? ActivityPalette.closedOpacity
                              : 1,
                      child: Material(
                        color: book.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(color: book.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeInOut,
                          alignment: Alignment.topCenter,
                          child: Column(
                            children: [
                              for (final (j, row) in group.rows.indexed)
                                ChatListItem(
                                  key: ValueKey(row.room.orderId),
                                  row: row,
                                  isLast: j == group.rows.length - 1,
                                  onTap: () {
                                    // Optimistic: the badge goes the moment
                                    // the room opens; the room itself marks
                                    // the messages read in Rust.
                                    ref
                                        .read(
                                          chatRoomsNotifierProvider.notifier,
                                        )
                                        .markRead(row.room.orderId);
                                    context.push(
                                      AppRoute.chatRoomPath(row.room.orderId),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const _Footnote(),
                ],
              ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.lock_outline_rounded,
              size: 13,
              color: book.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).chatListFootnote,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: book.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages();

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 28,
              color: ActivityPalette.of(context).chevronIdle,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.chatListEmptyTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: book.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.chatListEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: book.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
