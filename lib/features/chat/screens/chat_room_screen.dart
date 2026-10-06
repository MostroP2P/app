import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/attachments/attachment_flow.dart';
import 'package:mostro/features/chat/attachments/upload_controller.dart';
import 'package:mostro/features/chat/models/chat_list_rules.dart';
import 'package:mostro/features/chat/models/reaction_rules.dart';
import 'package:mostro/features/chat/providers/chat_list_provider.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/chat/widgets/info_panels.dart';
import 'package:mostro/features/chat/widgets/message_bubble.dart';
import 'package:mostro/features/chat/widgets/message_input.dart';
import 'package:mostro/features/chat/widgets/trade_state_header.dart';
import 'package:mostro/features/chat/widgets/upload_bubble.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart';
import 'package:mostro/shared/widgets/nym_avatar.dart';
import 'package:mostro/src/rust/api/messages.dart' as messages_api;
import 'package:mostro/src/rust/api/types.dart' as rust_types;

/// How close to the end of the list still counts as "following along".
///
/// Roughly one message bubble, so a reader who has scrolled up by even one
/// message is left where they are.
const double kFollowThresholdPixels = 80;

/// How long a burst of incoming messages may stay quiet before the room is
/// marked read once, instead of once per message.
const Duration kMarkReadDebounce = Duration(milliseconds: 400);

/// How much of the conversation an open info panel always leaves visible
/// under it: about one message bubble, as [kFollowThresholdPixels].
const double kMinVisibleMessagesHeight = kFollowThresholdPixels;

/// The tallest an info panel may be when the panel and the messages share
/// [available] height: whatever keeps [kMinVisibleMessagesHeight] of the
/// conversation in view. The panel scrolls inside when its content is taller.
double infoPanelMaxHeight(double available) =>
    math.max(0, available - kMinVisibleMessagesHeight);

/// Whether an arriving message should scroll the list.
///
/// Pinning is the reason this is a decision at all: auto-scrolling
/// unconditionally yanks a reader away from older messages every time the
/// counterparty types, and a history burst starts one animation per message.
bool isPinnedToBottom({
  required double offset,
  required double maxScrollExtent,
}) => maxScrollExtent - offset <= kFollowThresholdPixels;

/// Route: /chat_room/:orderId
///
/// Individual trade chat room screen with message history, info panels,
/// and a composition bar.
///
/// The Rust bridge is fully wired:
/// - [messages_api.getMessages] seeds message history on open.
/// - [messages_api.sendMessage] encrypts and publishes outbound messages as
///   a Mostro chat envelope (kind 14 signed with the shared key, NIP-44
///   inner kind 1 signed by the trade key), directed to the ECDH shared-key
///   pubkey per the Mostro P2P chat protocol.
/// - [incomingMessageProvider] delivers real-time incoming messages from the
///   Rust `subscribe_incoming_chat` background task.
/// - [messages_api.markAsRead] resets unread count when the room is entered.
class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({super.key, required this.orderId});

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

  /// Ids already in [_messages]. A replayed envelope is common, and scanning
  /// the list for every incoming message made dedup O(history) per message.
  final Set<String> _seenIds = {};

  /// Updates of messages not in the list yet: one can overtake its
  /// message's arrival on the other stream, or the history load. Applied
  /// as the message is added; bounded, oldest dropped first.
  final Map<String, rust_types.ChatMessage> _earlyUpdates = {};
  static const _maxEarlyUpdates = 256;

  /// Coalesces mark-read across a burst. A history replay would otherwise
  /// fire one bridge call per message.
  Timer? _markReadDebounce;

  /// Rooms notifier captured while the widget is live, so a pending
  /// mark-read can still be flushed from [dispose], where `ref` is unusable.
  ChatRoomsNotifier? _roomsNotifier;

  /// Follow animations still in flight (see [_scrollToBottom]). While one
  /// runs the list lags behind the extent it is heading for, so the position
  /// alone would misreport a reader who never left the bottom.
  int _followAnimations = 0;

  bool _historyLoaded = false;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // The ref.listen in build only fires on changes; when the provider is
    // already alive with data (pushed from a screen that watches the same
    // family member), there is no change coming — apply the current value.
    unawaited(
      _applyTradeIdentity(
        ref.read(tradeInfoProvider(widget.orderId)).valueOrNull,
      ),
    );
    _loadHistory();
    _markRead();
  }

  @override
  void dispose() {
    _flushMarkRead();
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
          // This room is the buyer<->seller conversation only: solver
          // messages from a dispute share the order key in the store but
          // must never surface here — replying would go to the counterparty,
          // not the solver (PR #254 review).
          if (msg.messageType != rust_types.MessageType.peer) continue;
          if (_seenIds.add(msg.id)) {
            _messages.add(_withEarlyUpdate(msg));
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
    final notifications = ref.read(notificationsProvider.notifier);
    // Record read intent before either storage call yields. The notifier can
    // mark the persisted card even while its initial load is still pending.
    final cardRead = notifications.markAsRead(
      NotificationModel.chatCardId(widget.orderId, fromSolver: false),
    );
    await _markReadWith(ref.read(chatRoomsNotifierProvider.notifier));
    await cardRead;
  }

  /// [rooms] is passed in rather than read from `ref` so [_flushMarkRead]
  /// can run it from [dispose].
  Future<void> _markReadWith(ChatRoomsNotifier? rooms) async {
    try {
      await messages_api.markAsRead(tradeId: widget.orderId);
      if (rooms != null && rooms.mounted) rooms.markRead(widget.orderId);
    } catch (e) {
      debugPrint('[chat] markAsRead failed: $e');
    }
  }

  /// Upserts this trade's room into [chatRoomsNotifierProvider] with the
  /// peer identity resolved from [trade].
  ///
  /// The chat-list screen is the only other place that hydrates the notifier,
  /// so reaching this screen directly (trade-detail chat chip, deep link)
  /// would otherwise leave [_resolveRoom] on its empty-handle placeholder and
  /// the header stuck on the localized "Unknown" fallback.
  ///
  /// Cheap while it cannot succeed: [tradeInfoToChatRoom] bails synchronously
  /// on an empty counterparty (a maker before the reveal), and once the room
  /// is resolved the guard below skips the rest — so no in-flight bookkeeping
  /// is needed however often the provider emits.
  Future<void> _applyTradeIdentity(rust_types.TradeInfo? trade) async {
    if (trade == null) return;
    final rooms = ref.read(chatRoomsNotifierProvider);
    final index = rooms.indexWhere((r) => r.orderId == widget.orderId);
    if (index >= 0 && rooms[index].peerPubkey.isNotEmpty) return;
    try {
      final room = await tradeInfoToChatRoom(trade);
      if (room == null || !mounted) return;
      ref
          .read(chatRoomsNotifierProvider.notifier)
          .upsertRoom(_withLivePreview(room));
    } catch (e) {
      debugPrint('[chat] applyTradeIdentity failed: $e');
    }
  }

  /// [tradeInfoToChatRoom] rebuilds the preview from the message store, which
  /// can lag the entry [_buildRoomPreview] upserted for a message arriving
  /// mid-hydration — and resurrect an unread count [_markRead] just zeroed.
  /// [ChatRoomsNotifier.upsertRoom] replaces the room wholesale, so when the
  /// live entry is at least as recent, keep its preview and take only the
  /// resolved identity.
  ChatRoomState _withLivePreview(ChatRoomState hydrated) {
    final rooms = ref.read(chatRoomsNotifierProvider);
    final index = rooms.indexWhere((r) => r.orderId == widget.orderId);
    if (index < 0) return hydrated;
    final live = rooms[index];
    if (live.lastMessageAt < hydrated.lastMessageAt) return hydrated;
    return hydrated.copyWith(
      lastMessage: live.lastMessage,
      lastMessageIsOwn: live.lastMessageIsOwn,
      lastMessageAt: live.lastMessageAt,
      unreadCount: live.unreadCount,
    );
  }

  Future<void> _onSend(String text) async {
    if (text.trim().isEmpty || _isSending) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _isSending = true);
    try {
      final sent = await messages_api.sendMessage(
        tradeId: widget.orderId,
        content: text.trim(),
      );
      if (!mounted) return;
      _addOwnMessage(sent);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.messageSendFailed),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Appends a message this device sent and moves the room preview to it.
  void _addOwnMessage(rust_types.ChatMessage sent) {
    // Every path that appends to [_messages] must go through [_seenIds], or
    // an echo of this send arriving on the stream would render it twice.
    if (_seenIds.add(sent.id)) {
      setState(() => _messages.add(_withEarlyUpdate(sent)));
    }
    _scrollToBottom();
    ref
        .read(chatRoomsNotifierProvider.notifier)
        .upsertRoom(
          _buildRoomPreview(
            lastMsg: sent,
            rooms: ref.read(chatRoomsNotifierProvider),
          ),
        );
  }

  /// Paperclip: pick, confirm, then send (#589). The spinner covers the
  /// pick and the read; the upload shows its own progress in the list.
  Future<void> _onAttach() async {
    if (_isAttaching) return;
    final picked = await pickAttachmentToSend(
      context,
      ref,
      onBusy: (busy) => setState(() => _isAttaching = busy),
    );
    if (picked == null || !mounted) return;
    _scrollToBottom();
    final sent = await ref
        .read(chatUploadsProvider(widget.orderId).notifier)
        .send(picked.name, picked.bytes);
    if (sent != null && mounted) _addOwnMessage(sent);
  }

  Future<void> _retryUpload(String uploadId) async {
    final sent = await ref
        .read(chatUploadsProvider(widget.orderId).notifier)
        .retry(uploadId);
    if (sent != null && mounted) _addOwnMessage(sent);
  }

  // ── Incoming stream ───────────────────────────────────────────────────────

  void _onIncomingMessage(rust_types.ChatMessage msg) {
    // Dispute-channel traffic never belongs in the peer room (see
    // _loadHistory).
    if (msg.messageType != rust_types.MessageType.peer) return;
    if (!_seenIds.add(msg.id)) return; // deduplicate
    // Decide from where the reader is *before* the message is added. The
    // extent only grows at the next layout, so reading here keeps the
    // decision about the list they were looking at, whenever that lands.
    final wasAtBottom = _isPinnedToBottom();
    setState(() => _messages.add(_withEarlyUpdate(msg)));
    // Only follow the conversation if the user was already at the bottom;
    // otherwise an arriving message yanks them away from what they were
    // reading, and a burst starts one animation per message. Nor while a
    // message's menu is open over the room: it follows its message a frame
    // late, so a scroll animation would leave it trailing.
    final menuOpen = !(ModalRoute.of(context)?.isCurrent ?? true);
    if (wasAtBottom && !menuOpen) _scrollToBottom();
    _scheduleMarkRead();
    ref
        .read(chatRoomsNotifierProvider.notifier)
        .upsertRoom(
          _buildRoomPreview(
            lastMsg: msg,
            rooms: ref.read(chatRoomsNotifierProvider),
          ),
        );
  }

  /// Replaces the copy of a message already in the list, unless it carries
  /// older reactions than the one shown (a send's reply landing after the
  /// update of a later send). One not shown yet waits in [_earlyUpdates]:
  /// adding stays with the history and the incoming stream.
  void _onMessageUpdated(rust_types.ChatMessage msg) {
    if (msg.messageType != rust_types.MessageType.peer) return;
    final index = _messages.indexWhere((m) => m.id == msg.id);
    if (index < 0) {
      final waiting = _earlyUpdates[msg.id];
      if (waiting != null && !reactionsNotOlder(msg, waiting)) return;
      _earlyUpdates.remove(msg.id);
      if (_earlyUpdates.length >= _maxEarlyUpdates) {
        _earlyUpdates.remove(_earlyUpdates.keys.first);
      }
      _earlyUpdates[msg.id] = msg;
      return;
    }
    if (!reactionsNotOlder(msg, _messages[index])) return;
    setState(() => _messages[index] = msg);
  }

  /// [msg], or the update of it that arrived first when that one is not
  /// older.
  rust_types.ChatMessage _withEarlyUpdate(rust_types.ChatMessage msg) {
    final update = _earlyUpdates.remove(msg.id);
    return update != null && reactionsNotOlder(update, msg) ? update : msg;
  }

  /// Sends the user's reaction to the counterpart's [msg]; an empty [emoji]
  /// withdraws it. Never a preview or an unread message.
  Future<void> _onReact(rust_types.ChatMessage msg, String emoji) async {
    final l10n = AppLocalizations.of(context);
    try {
      final updated = await messages_api.sendReaction(
        tradeId: widget.orderId,
        messageId: msg.id,
        emoji: emoji,
      );
      if (!mounted) return;
      _onMessageUpdated(updated);
    } catch (e) {
      debugPrint('[chat] sendReaction failed: $e');
      if (!mounted) return;
      showOrderDetailSnackBar(context, l10n.reactionSendFailed);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Whether the list is close enough to the end to keep following it.
  bool _isPinnedToBottom() {
    // A follow animation still in flight means the reader was at the bottom
    // and only the animation is behind; do not mistake that for scrolling up.
    if (_followAnimations > 0) return true;
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return isPinnedToBottom(
      offset: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
    );
  }

  /// Mark the room read once the burst settles, instead of once per message.
  void _scheduleMarkRead() {
    _roomsNotifier = ref.read(chatRoomsNotifierProvider.notifier);
    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(kMarkReadDebounce, () {
      if (mounted) _markRead();
    });
  }

  /// Runs a pending mark-read now instead of dropping it: the reader saw the
  /// burst, and leaving within the debounce window must not leave the room
  /// flagged unread until their next visit.
  void _flushMarkRead() {
    final pending = _markReadDebounce;
    _markReadDebounce = null;
    if (pending == null || !pending.isActive) return;
    pending.cancel();
    unawaited(_markReadWith(_roomsNotifier));
  }

  void _scrollToBottom() {
    // Counted from the request, not the frame, so a message arriving before
    // the post-frame callback runs already sees a follow in progress.
    _followAnimations++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        _followAnimations--;
        return;
      }
      // Interrupting an earlier animation (a newer follow, or the reader
      // dragging) completes its future, so the counter always drains.
      _scrollController
          .animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          )
          .whenComplete(() => _followAnimations--);
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

  ChatRoomState _resolveRoom(List<ChatRoomState> rooms) {
    return rooms.firstWhere(
      (r) => r.orderId == widget.orderId,
      orElse:
          () => ChatRoomState(
            orderId: widget.orderId,
            peerPubkey: '',
            // Locale-independent: the localized "Unknown" is resolved at render
            // time via ChatRoomState.displayHandle, never cached in the model.
            peerHandle: '',
            peerIconIndex: 0,
            peerColorHue: 180,
            isSelling: false,
          ),
    );
  }

  ChatRoomState _buildRoomPreview({
    required rust_types.ChatMessage lastMsg,
    required List<ChatRoomState> rooms,
  }) {
    final room = _resolveRoom(rooms);
    // Use the bridge-provided isRead / isMine flags rather than recomputing
    // from local _messages, which may not yet reflect the latest markAsRead
    // call (the bridge call is async and may still be in flight).
    //
    // Strategy: start from room.unreadCount (as last set by the bridge) and
    // increment by one only when the incoming message is unread and not ours.
    // _markRead will reset this to 0 once the async call completes.
    final unread =
        (lastMsg.isMine || lastMsg.isRead)
            ? room.unreadCount
            : room.unreadCount + 1;
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
        appBar: AppBar(title: Text(AppLocalizations.of(context).navChat)),
        body: Center(child: Text(AppLocalizations.of(context).invalidTradeId)),
        bottomNavigationBar: const BottomNavBar(),
      );
    }

    // Wire the incoming message stream.
    ref.listen<AsyncValue<rust_types.ChatMessage>>(
      incomingMessageProvider(widget.orderId),
      (_, next) => next.whenData(_onIncomingMessage),
    );
    // A message already shown that changed: a reaction to it.
    ref.listen<AsyncValue<rust_types.ChatMessage>>(
      messageUpdatesProvider(widget.orderId),
      (_, next) => next.whenData(_onMessageUpdated),
    );

    // Resolve the peer identity from the trade row, live. Listening (rather
    // than a one-shot read) keeps the autoDispose provider chain alive, and
    // rawTradesProvider refetches itself on every trade update — so the
    // daemon reveal that fills the counterparty (BuyerTookOrder /
    // HoldInvoicePaymentAccepted) lands here as a fresh emission even while
    // this screen is open, with no manual refresh or retry bookkeeping. A
    // one-shot read future would instead go stale (and never resolve) when
    // that update invalidates the provider mid-await.
    ref.listen<AsyncValue<rust_types.TradeInfo?>>(
      tradeInfoProvider(widget.orderId),
      (_, next) =>
          next.whenData((trade) => unawaited(_applyTradeIdentity(trade))),
    );

    final l10n = AppLocalizations.of(context);
    final room = _resolveRoom(ref.watch(chatRoomsNotifierProvider));
    final displayHandle = room.displayHandle(l10n);
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) {
      throw StateError('AppColors theme extension must be registered');
    }

    final uploads = ref.watch(chatUploadsProvider(widget.orderId));

    // A closed or still-resolving chat takes no reaction, as it takes no

    // message: offering one would only end in a failure.

    final canReact =
        ref.watch(chatRowStateProvider(widget.orderId)).canCompose;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final showSidePanel = screenWidth >= AppBreakpoints.tablet;

    // Side panel (tablet / desktop)
    Widget? sidePanel;
    if (showSidePanel) {
      sidePanel = SizedBox(
        width: 300,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child:
              _showTradeInfo
                  ? TradeInformationTab(
                    key: const ValueKey('trade'),
                    orderId: widget.orderId,
                  )
                  : _showUserInfo
                  ? UserInformationTab(key: const ValueKey('user'), room: room)
                  : Container(
                    key: const ValueKey('none'),
                    color: colors.backgroundCard,
                    child: Center(
                      child: Text(
                        l10n.selectForDetailsHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textSubtle),
                      ),
                    ),
                  ),
        ),
      );
    }

    // Chat column
    // Info panels (mobile only)
    final infoPanel = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child:
          _showTradeInfo
              ? TradeInformationTab(
                key: const ValueKey('trade'),
                orderId: widget.orderId,
              )
              : _showUserInfo
              ? UserInformationTab(key: const ValueKey('user'), room: room)
              : const SizedBox.shrink(key: ValueKey('none')),
    );

    final messageList =
        !_historyLoaded
            ? const Center(child: CircularProgressIndicator())
            : _messages.isEmpty && uploads.isEmpty
            ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  l10n.noMessagesYet(displayHandle),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSubtle),
                ),
              ),
            )
            : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: _messages.length + uploads.length,
              itemBuilder: (context, index) {
                // Files still on their way out follow the history.
                if (index >= _messages.length) {
                  final upload = uploads[index - _messages.length];
                  return UploadBubble(
                    key: ValueKey(upload.id),
                    upload: upload,
                    onRetry: () => _retryUpload(upload.id),
                    onDiscard:
                        () => ref
                            .read(chatUploadsProvider(widget.orderId).notifier)
                            .discard(upload.id),
                  );
                }
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
                    attachment: msg.attachment,
                    reaction: shownReaction(msg),
                  ),
                  peerColorHue: room.peerColorHue,
                  onReact:
                      msg.isMine || !canReact
                          ? null
                          : (emoji) => _onReact(msg, emoji),
                );
              },
            );

    final chatColumn = Column(
      children: [
        // Sticky trade-state header — pinned below the app bar, does not
        // scroll with messages. Hides itself when the order can't be resolved.
        TradeStateHeader(orderId: widget.orderId),

        // The info panel and the messages share what the header and the
        // composer leave. The panel gives way first (it scrolls inside), so
        // a short screen at large text still shows the conversation.
        Expanded(
          child:
              showSidePanel
                  ? messageList
                  : LayoutBuilder(
                    builder:
                        (context, box) => Column(
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: infoPanelMaxHeight(box.maxHeight),
                              ),
                              child: infoPanel,
                            ),
                            Expanded(child: messageList),
                          ],
                        ),
                  ),
        ),

        // Composition bar
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.sm,
            right: AppSpacing.sm,
            bottom: AppSpacing.sm,
            top: AppSpacing.xs,
          ),
          // A closed trade's conversation opens read-only (handoff 11b), and
          // nothing is offered until the trade says which it is.
          child: switch (ref.watch(chatRowStateProvider(widget.orderId))) {
            ChatRowState(isReadOnly: true) => const _ClosedNotice(),
            ChatRowState(canCompose: false) => const SizedBox.shrink(),
            _ => MessageInput(
              onSendText: _onSend,
              onAttachFile: _onAttach,
              isAttaching: _isAttaching || _isSending,
            ),
          },
        ),
      ],
    );

    return Scaffold(
      // The Scaffold owns keyboard avoidance: the body ends at the taller of
      // the keyboard and the BottomNavBar, never their sum, so the composer
      // must not add viewInsets itself.
      appBar: AppBar(
        leading: const BackButton(),
        title: _AppBarTitle(room: room),
        actions: [
          IconButton(
            tooltip: l10n.exchangeInfoTooltip,
            icon: Icon(
              Icons.info_outline,
              color: _showTradeInfo ? colors.mostroGreen : null,
            ),
            onPressed: _toggleTradeInfo,
          ),
          IconButton(
            tooltip: l10n.userInfoTooltip,
            icon: Icon(
              Icons.person_outline,
              color: _showUserInfo ? colors.mostroGreen : null,
            ),
            onPressed: _toggleUserInfo,
          ),
        ],
      ),
      body:
          showSidePanel && sidePanel != null
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

// ── Closed notice ─────────────────────────────────────────────────────────────

/// Stands in for the composer once the trade has ended: the conversation
/// stays readable, and says why nothing can be sent.
class _ClosedNotice extends StatelessWidget {
  const _ClosedNotice();

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: book.border),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: book.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).chatClosedNotice,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: book.textTertiary,
              ),
            ),
          ),
        ],
      ),
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
    if (colors == null) {
      throw StateError('AppColors theme extension must be registered');
    }
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final handle = room.displayHandle(l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NymAvatar(
              pseudonym: room.peerHandle,
              iconIndex: room.peerIconIndex,
              colorHue: room.peerColorHue,
              size: 28,
            ),
            const SizedBox(width: AppSpacing.sm),
            // The alias gives way to the app bar's icons rather than
            // pushing past them: a long one at large text ellipsizes (#679).
            Flexible(
              child: Text(
                handle,
                style: textTheme.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Text(
          l10n.chattingWith(handle),
          style: textTheme.bodySmall?.copyWith(color: colors.textSubtle),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
