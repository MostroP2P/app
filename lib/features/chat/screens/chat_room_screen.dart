import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/chat/widgets/info_panels.dart';
import 'package:mostro/features/chat/widgets/message_bubble.dart';
import 'package:mostro/features/chat/widgets/message_input.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';

/// Route: /chat_room/:orderId
///
/// Individual trade chat room screen with message history, info panels,
/// and a composition bar.
class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({
    super.key,
    required this.orderId,
  });

  final String orderId;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  bool _showTradeInfo = false;
  bool _showUserInfo = false;
  bool _isAttaching = false;

  /// Optimistic message list (client-side until bridge is wired).
  final List<ChatMessage> _messages = [
    const ChatMessage(
      id: 'sys-0',
      tradeId: '',
      content: 'Chat connected. Messages are end-to-end encrypted.',
      isMine: false,
      isRead: true,
      hasAttachment: false,
      createdAt: 0,
      messageType: 'system',
    ),
  ];

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onSend(String text) {
    if (text.trim().isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    setState(() {
      _messages.add(
        ChatMessage(
          id: 'local-${now}_${_messages.length}',
          tradeId: widget.orderId,
          content: text.trim(),
          isMine: true,
          isRead: false,
          hasAttachment: false,
          createdAt: now,
        ),
      );
    });
    // Scroll to bottom after the frame is rendered.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _onAttach() async {
    setState(() => _isAttaching = true);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _isAttaching = false);
  }

  void _toggleTradeInfo() {
    setState(() {
      _showTradeInfo = !_showTradeInfo;
      if (_showTradeInfo) _showUserInfo = false;
    });
  }

  void _toggleUserInfo() {
    setState(() {
      _showUserInfo = !_showUserInfo;
      if (_showUserInfo) _showTradeInfo = false;
    });
  }

  // ── Build helpers ──────────────────────────────────────────────────────────

  /// Resolve ChatRoomState for this orderId, or fall back to a placeholder.
  ChatRoomState _resolveRoom() {
    final rooms = ref.watch(chatRoomsNotifierProvider);
    return rooms.firstWhere(
      (r) => r.orderId == widget.orderId,
      orElse: () => ChatRoomState(
        orderId: widget.orderId,
        peerPubkey: '',
        peerHandle: 'Unknown',
        peerIconIndex: 0,
        peerColorHue: 180,
        isSelling: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orderId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(child: Text('Invalid trade ID')),
        bottomNavigationBar: const BottomNavBar(),
      );
    }

    final room = _resolveRoom();
    final colors = Theme.of(context).extension<AppColors>();
    assert(colors != null, 'AppColors theme extension must be registered');
    if (colors == null) return const SizedBox.shrink();

    return Scaffold(
      // Keyboard avoidance is handled manually via viewInsets.bottom padding
      // on the composition bar so the BottomNavBar does not push content twice.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: const BackButton(),
        title: _AppBarTitle(room: room),
        actions: [
          IconButton(
            tooltip: 'Exchange Info',
            icon: Icon(
              Icons.info_outline,
              color: _showTradeInfo ? colors.mostroGreen : null,
            ),
            onPressed: _toggleTradeInfo,
          ),
          IconButton(
            tooltip: 'User Info',
            icon: Icon(
              Icons.person_outline,
              color: _showUserInfo ? colors.mostroGreen : null,
            ),
            onPressed: _toggleUserInfo,
          ),
        ],
      ),
      body: Column(
        children: [
          // Animated info panels
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _showTradeInfo
                ? TradeInformationTab(
                    key: const ValueKey('trade'),
                    orderId: widget.orderId,
                  )
                : _showUserInfo
                    ? UserInformationTab(
                        key: const ValueKey('user'),
                        peerHandle: room.peerHandle,
                        peerPubkey: room.peerPubkey,
                        peerIconIndex: room.peerIconIndex,
                        peerColorHue: room.peerColorHue,
                      )
                    : const SizedBox.shrink(key: ValueKey('none')),
          ),

          // Message list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return MessageBubble(
                  message: _messages[index],
                  peerColorHue: room.peerColorHue,
                );
              },
            ),
          ),

          // Composition bar
          Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.sm,
              right: AppSpacing.sm,
              bottom: MediaQuery.of(context).viewInsets.bottom +
                  AppSpacing.sm,
              top: AppSpacing.xs,
            ),
            child: MessageInput(
              onSendText: _onSend,
              onAttachFile: _onAttach,
              isAttaching: _isAttaching,
            ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNavBar(),
    );
  }
}

// ── AppBar title widget ───────────────────────────────────────────────────────

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.room});

  final ChatRoomState room;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    assert(colors != null, 'AppColors theme extension must be registered');
    if (colors == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NymAvatar(
              iconIndex: room.peerIconIndex,
              colorHue: room.peerColorHue,
              size: 28,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              room.peerHandle,
              style: textTheme.headlineSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        Text(
          'You are chatting with ${room.peerHandle}',
          style: textTheme.bodySmall?.copyWith(color: colors.textSubtle),
        ),
      ],
    );
  }
}
