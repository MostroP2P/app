import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/chat/widgets/chat_list_item.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart';

/// Route: /chat_list
///
/// Top-level chat screen with two tabs: Messages and Disputes.
class ChatRoomsScreen extends ConsumerWidget {
  const ChatRoomsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>();
    assert(colors != null, 'AppColors theme extension must be registered');
    if (colors == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chat'),
          bottom: TabBar(
            indicatorColor: colors.mostroGreen,
            labelColor: colors.mostroGreen,
            unselectedLabelColor: colors.textSubtle,
            tabs: const [
              Tab(text: 'Messages'),
              Tab(text: 'Disputes'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MessagesTab(colors: colors, textTheme: textTheme),
            _DisputesTab(colors: colors, textTheme: textTheme),
          ],
        ),
        bottomNavigationBar: const BottomNavBar(),
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
        Expanded(
          child: Center(
            child: Text(
              'Dispute chat — Phase 12',
              style: textTheme.bodyMedium?.copyWith(color: colors.textSubtle),
            ),
          ),
        ),
      ],
    );
  }
}
