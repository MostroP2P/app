import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/chat/widgets/info_panels.dart';
import 'package:mostro/features/chat/widgets/message_bubble.dart';
import 'package:mostro/features/chat/widgets/message_input.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';
import 'package:mostro/src/rust/api/messages.dart' as messages_api;
import 'package:mostro/src/rust/api/types.dart' as rust_types;

/// Route: /chat_room/:orderId
///
/// Individual trade chat room screen with message history, info panels,
/// and a composition bar.
///
/// The Rust bridge is fully wired:
/// - [messages_api.getMessages] seeds message history on open.
/// - [messages_api.sendMessage] encrypts and publishes outbound messages via
///   NIP-59 gift wrap, directed to the ECDH shared-key pubkey per the Mostro
///   P2P chat protocol.
/// - [incomingMessageProvider] delivers real-time incoming messages from the
///   Rust `subscribe_incoming_chat` background task.
/// - [messages_api.markAsRead] resets unread count when the room is entered.
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
  bool _isSending = false;

  /// Message list seeded from bridge history, then appended via stream.
  final List<rust_types.ChatMessage> _messages = [];
  bool _historyLoaded = false;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _markRead();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── Bridge calls ──────────────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    try {
      final msgs = await messages_api.getMessages(tradeId: widget.orderId);
      if (!mounted) return;
      setState(() {
        // Merge history into the existing list rather than clearing it.
        // The stream listener (_onIncomingMessage) may already have added
        // messages that arrived between initState and this await completing.
        // Deduplication uses the same id check as _onIncomingMessage so the
        // invariant is identical in both paths.
        for (final msg in msgs) {
          if (!_messages.any((m) => m.id == msg.id)) {
            _messages.add(msg);
          }
        }
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _historyLoaded = true;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('[chat] loadHistory failed: $e');
      if (mounted) setState(() => _historyLoaded = true);
    }
  }

  Future<void> _markRead() async {
    try {
      await messages_api.markAsRead(tradeId: widget.orderId);
      ref.read(chatRoomsNotifierProvider.notifier).markRead(widget.orderId);
    } catch (e) {
      debugPrint('[chat] markAsRead failed: $e');
    }
  }

  Future<void> _onSend(String text) async {
    if (text.trim().isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      final sent = await messages_api.sendMessage(
        tradeId: widget.orderId,
        content: text.trim(),
      );
      if (!mounted) return;
      setState(() => _messages.add(sent));
      _scrollToBottom();
      ref.read(chatRoomsNotifierProvider.notifier).upsertRoom(
            _buildRoomPreview(lastMsg: sent),
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _onAttach() async {
    setState(() => _isAttaching = true);
    // File attachment via send_file is wired in Rust; UI hook deferred.
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _isAttaching = false);
  }

  // ── Incoming stream ───────────────────────────────────────────────────────

  void _onIncomingMessage(rust_types.ChatMessage msg) {
    if (_messages.any((m) => m.id == msg.id)) return; // deduplicate
    setState(() => _messages.add(msg));
    _scrollToBottom();
    _markRead();
    ref.read(chatRoomsNotifierProvider.notifier).upsertRoom(
          _buildRoomPreview(lastMsg: msg),
        );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _scrollToBottom() {
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

  void _toggleTradeInfo() => setState(() {
        _showTradeInfo = !_showTradeInfo;
        if (_showTradeInfo) _showUserInfo = false;
      });

  void _toggleUserInfo() => setState(() {
        _showUserInfo = !_showUserInfo;
        if (_showUserInfo) _showTradeInfo = false;
      });

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

  ChatRoomState _buildRoomPreview({required rust_types.ChatMessage lastMsg}) {
    final room = _resolveRoom();
    final unread = _messages.where((m) => !m.isRead && !m.isMine).length;
    return room.copyWith(
      lastMessage: lastMsg.content,
      lastMessageIsOwn: lastMsg.isMine,
      lastMessageAt: lastMsg.createdAt.toInt(),
      unreadCount: unread,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.orderId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: const Center(child: Text('Invalid trade ID')),
        bottomNavigationBar: const BottomNavBar(),
      );
    }

    // Wire the incoming message stream.
    ref.listen<AsyncValue<rust_types.ChatMessage>>(
      incomingMessageProvider(widget.orderId),
      (_, next) => next.whenData(_onIncomingMessage),
    );

    final room = _resolveRoom();
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) {
      throw StateError('AppColors theme extension must be registered');
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final showSidePanel = screenWidth >= AppBreakpoints.tablet;

    // Side panel (tablet / desktop)
    Widget? sidePanel;
    if (showSidePanel) {
      sidePanel = SizedBox(
        width: 300,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
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
                  : Container(
                      key: const ValueKey('none'),
                      color: colors.backgroundCard,
                      child: Center(
                        child: Text(
                          'Select \u2139 or \u{1F464}\nfor details',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textSubtle),
                        ),
                      ),
                    ),
        ),
      );
    }

    // Chat column
    final chatColumn = Column(
      children: [
        // Info panels (mobile only)
        if (!showSidePanel)
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
          child: !_historyLoaded
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          'No messages yet.\nSay hello to ${room.peerHandle}!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textSubtle),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return MessageBubble(
                          // Adapt the FRB-generated ChatMessage to the
                          // Dart-side ChatMessage used by MessageBubble.
                          message: ChatMessage(
                            id: msg.id,
                            tradeId: msg.tradeId,
                            content: msg.content,
                            isMine: msg.isMine,
                            isRead: msg.isRead,
                            hasAttachment: msg.hasAttachment,
                            createdAt: msg.createdAt.toInt(),
                            messageType: _msgTypeStr(msg.messageType),
                          ),
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
            bottom:
                MediaQuery.of(context).viewInsets.bottom + AppSpacing.sm,
            top: AppSpacing.xs,
          ),
          child: MessageInput(
            onSendText: _onSend,
            onAttachFile: _onAttach,
            isAttaching: _isAttaching || _isSending,
          ),
        ),
      ],
    );

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
      body: showSidePanel && sidePanel != null
          ? Row(
              children: [
                Expanded(child: chatColumn),
                const VerticalDivider(width: 1),
                sidePanel,
              ],
            )
          : chatColumn,
      bottomNavigationBar: const BottomNavBar(),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _msgTypeStr(rust_types.MessageType t) => switch (t) {
      rust_types.MessageType.peer => 'peer',
      rust_types.MessageType.admin => 'admin',
      rust_types.MessageType.system => 'system',
    };

// ── AppBar title widget ───────────────────────────────────────────────────────

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.room});

  final ChatRoomState room;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) {
      throw StateError('AppColors theme extension must be registered');
    }
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
