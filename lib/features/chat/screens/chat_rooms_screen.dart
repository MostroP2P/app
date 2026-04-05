import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/chat/widgets/chat_list_item.dart';
import 'package:mostro/features/disputes/widgets/disputes_list.dart';
import 'package:mostro/features/drawer/screens/drawer_menu.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart';
import 'package:mostro/shared/widgets/notification_bell.dart';

/// Route: /chat_list
///
/// Top-level chat screen with two tabs: Messages and Disputes.
///
/// On init, syncs [chatRoomsFromTradesProvider] into [chatRoomsNotifierProvider]
/// so the Messages tab is populated from the trade DB rather than always empty.
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
    // Populate the chat rooms list from trades asynchronously.
    // Any subsequent live updates are pushed by ChatRoomScreen via upsertRoom.
    _syncRoomsFromTrades();
  }

  Future<void> _syncRoomsFromTrades() async {
    try {
      final rooms =
          await ref.read(chatRoomsFromTradesProvider.future);
      if (!mounted) return;
      ref.read(chatRoomsNotifierProvider.notifier).setRooms(rooms);
    } catch (e) {
      debugPrint('[chat] syncRoomsFromTrades failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) throw StateError('AppColors theme extension must be registered');
    final textTheme = Theme.of(context).textTheme;
    final green = colors.mostroGreen;

    final isDesktop =
        MediaQuery.sizeOf(context).width >= AppBreakpoints.desktop;

    final mainContent = Column(
      children: [
        if (!isDesktop)
          SafeArea(
            bottom: false,
            child: _ChatAppBar(
              green: green,
              onMenuTap: () => setState(() => _drawerOpen = true),
            ),
          ),
        TabBar(
          indicatorColor: colors.mostroGreen,
          labelColor: colors.mostroGreen,
          unselectedLabelColor: colors.textSubtle,
          tabs: const [
            Tab(text: 'Messages'),
            Tab(text: 'Disputes'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              _MessagesTab(colors: colors, textTheme: textTheme),
              _DisputesTab(colors: colors, textTheme: textTheme),
            ],
          ),
        ),
      ],
    );

    final body = isDesktop
        ? Row(
            children: [
              const DrawerMenu(persistent: true),
              const VerticalDivider(width: 1),
              Expanded(child: SafeArea(child: mainContent)),
            ],
          )
        : Stack(
            children: [
              mainContent,
              if (_drawerOpen)
                DrawerMenu(
                  onClose: () => setState(() => _drawerOpen = false),
                ),
            ],
          );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: body,
        bottomNavigationBar: const BottomNavBar(),
      ),
    );
  }
}

// ── Mobile app bar ─────────────────────────────────────────────────────────────

class _ChatAppBar extends StatelessWidget {
  const _ChatAppBar({required this.green, required this.onMenuTap});

  final Color green;
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onMenuTap,
            icon: const Icon(Icons.menu, size: 24),
            tooltip: 'Menu',
          ),
          const Spacer(),
          Icon(Icons.psychology, size: 28, color: green),
          const Spacer(),
          const NotificationBell(),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }
}

// ── Messages tab ──────────────────────────────────────────────────────────────

class _MessagesTab extends ConsumerWidget {
  const _MessagesTab({
    required this.colors,
    required this.textTheme,
  });

  final AppColors colors;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(sortedChatRoomsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tab description text
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            'Your active trade conversations',
            style: textTheme.bodySmall?.copyWith(color: colors.textSubtle),
          ),
        ),

        Expanded(
          child: rooms.isEmpty
              ? _EmptyMessages(colors: colors, textTheme: textTheme)
              : ListView.separated(
                  itemCount: rooms.length,
                  separatorBuilder: (_, __) => Divider(
                    color: colors.backgroundElevated,
                    height: 1,
                    indent: AppSpacing.lg,
                    endIndent: AppSpacing.lg,
                  ),
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    return ChatListItem(
                      room: room,
                      onTap: () {
                        context.push(AppRoute.chatRoomPath(room.orderId));
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages({
    required this.colors,
    required this.textTheme,
  });

  final AppColors colors;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: colors.textSubtle),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'No messages available',
            style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Disputes tab ──────────────────────────────────────────────────────────────

class _DisputesTab extends StatelessWidget {
  const _DisputesTab({
    required this.colors,
    required this.textTheme,
  });

  final AppColors colors;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tab description text
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            'Disputes and admin chat',
            style: textTheme.bodySmall?.copyWith(color: colors.textSubtle),
          ),
        ),
        const Expanded(child: DisputesList()),
      ],
    );
  }
}
