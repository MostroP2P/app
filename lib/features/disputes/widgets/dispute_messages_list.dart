import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/attachments/upload_controller.dart';
import 'package:mostro/features/chat/widgets/encrypted_file_message.dart';
import 'package:mostro/features/chat/widgets/encrypted_image_message.dart';
import 'package:mostro/features/chat/widgets/upload_bubble.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/disputes/widgets/dispute_info_card.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

// ── DisputeMessagesList ───────────────────────────────────────────────────────

/// Who a solver pubkey is (#637); `null` for a message without a sender.
typedef SolverRoleOf = rust_types.SolverRole Function(String? solverPubkey);

/// Where the "a resolver took over" line goes among [sorted] messages
/// (#637): before the first message of the person who took the dispute over
/// from Serbero, or last when they have not written yet. `null` while
/// Serbero still holds it ([current]), or when Serbero never spoke.
@visibleForTesting
int? takeoverLineIndex(
  List<DisputeMessage> sorted,
  SolverRoleOf roleOf,
  rust_types.SolverRole current,
) {
  if (current != rust_types.SolverRole.human) return null;
  bool from(DisputeMessage m, rust_types.SolverRole role) =>
      !m.isMine && m.isAdmin && roleOf(m.senderPubkey) == role;
  final lastAssistant = sorted.lastIndexWhere(
    (m) => from(m, rust_types.SolverRole.assistant),
  );
  if (lastAssistant < 0) return null;
  final firstPerson = sorted.indexWhere(
    (m) => from(m, rust_types.SolverRole.human),
    lastAssistant + 1,
  );
  return firstPerson < 0 ? sorted.length : firstPerson;
}

/// Scrollable list of dispute messages with info card and optional banners.
///
/// Slot order (always shown in this sequence):
///   1. [DisputeInfoCard] — always first, then [outcome] once resolved
///   2. "Solver assigned" banner — shown when status is `inReview` and no
///      messages yet; it names Serbero while Serbero holds the dispute
///   3. [DisputeMessageBubble] entries — sorted by `createdAt`, deduped by
///      `nostrEventId` if present, with a "resolver took over" line where a
///      person took the dispute over from Serbero (#637)
///   4. [UploadBubble]s — files still on their way to the solver
///   5. "Chat closed" lock banner — shown when status is resolved/closed
///
/// Auto-scrolls to bottom when new messages arrive.
class DisputeMessagesList extends StatefulWidget {
  const DisputeMessagesList({
    super.key,
    required this.dispute,
    required this.messages,
    this.uploads = const [],
    this.onRetryUpload,
    this.onDiscardUpload,
    this.roleOf = _unknownIsAPerson,
    this.outcome,
  });

  final DisputeItem dispute;
  final List<DisputeMessage> messages;
  final List<PendingUpload> uploads;
  final ValueChanged<String>? onRetryUpload;
  final ValueChanged<String>? onDiscardUpload;

  /// Who a solver pubkey is, as Rust decided it (#637).
  final SolverRoleOf roleOf;

  /// The resolved dispute's outcome, under the info card. It scrolls with
  /// the card, as v1's resolution box inside its card does, so a tall one
  /// never squeezes the conversation.
  final Widget? outcome;

  static rust_types.SolverRole _unknownIsAPerson(String? _) =>
      rust_types.SolverRole.human;

  @override
  State<DisputeMessagesList> createState() => _DisputeMessagesListState();
}

/// How many frames [_DisputeMessagesListState._jumpToLatest] corrects its
/// jump for before it gives up.
const _maxJumpPasses = 4;

class _DisputeMessagesListState extends State<DisputeMessagesList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.messages.isNotEmpty) _jumpToLatest();
  }

  @override
  void didUpdateWidget(DisputeMessagesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != oldWidget.messages.length ||
        widget.uploads.length != oldWidget.uploads.length) {
      // The history arriving lands on the latest message at once, as in v1:
      // the info card above it can fill the screen (#680).
      if (oldWidget.messages.isEmpty && oldWidget.uploads.isEmpty) {
        _jumpToLatest();
      } else {
        _scrollToBottom();
      }
    }
  }

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

  /// Jumps to the end once laid out, then again after each frame until the
  /// end stays put: the list only estimates the length of messages it has
  /// not laid out, and laying them out can move the end either way. A jump
  /// past a shorter real end would otherwise spring back on screen.
  void _jumpToLatest([int passesLeft = _maxJumpPasses]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.pixels == position.maxScrollExtent && !position.outOfRange) {
        return;
      }
      position.jumpTo(position.maxScrollExtent);
      if (passesLeft > 1) _jumpToLatest(passesLeft - 1);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) throw StateError('AppColors theme extension must be registered');

    // Deduplicate by nostrEventId where present.
    final seen = <String>{};
    final deduped = widget.messages.where((m) {
      final key = m.nostrEventId ?? m.id;
      return seen.add(key);
    }).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final isResolved = widget.dispute.status == DisputeStatus.resolved;
    final isInReview = widget.dispute.status == DisputeStatus.inReview;
    final currentRole = widget.roleOf(widget.dispute.adminPubkey);
    final takeoverAt = takeoverLineIndex(deduped, widget.roleOf, currentRole);
    final entries = [...deduped];
    if (takeoverAt != null) {
      entries.insert(
        takeoverAt,
        DisputeMessage(
          id: 'solver-took-over',
          content: AppLocalizations.of(context).disputeSolverTookOver,
          isMine: false,
          isAdmin: false,
          createdAt: 0,
        ),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // 1. Info card (always first)
        SliverToBoxAdapter(child: DisputeInfoCard(dispute: widget.dispute)),
        if (widget.outcome case final outcome?)
          SliverToBoxAdapter(child: outcome),

        // 2. "Solver assigned" banner (inReview + no messages)
        if (isInReview && deduped.isEmpty)
          SliverToBoxAdapter(
            child: _SolverAssignedBanner(
              isAssistant: currentRole == rust_types.SolverRole.assistant,
            ),
          ),

        // 3. Message bubbles, and the takeover line among them
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => DisputeMessageBubble(
              message: entries[index],
              colors: colors,
              solverRole: widget.roleOf(entries[index].senderPubkey),
            ),
            childCount: entries.length,
          ),
        ),

        // 4. Files on their way out follow the history.
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final upload = widget.uploads[index];
              return UploadBubble(
                key: ValueKey(upload.id),
                upload: upload,
                onRetry: () => widget.onRetryUpload?.call(upload.id),
                onDiscard: () => widget.onDiscardUpload?.call(upload.id),
              );
            },
            childCount: widget.uploads.length,
          ),
        ),

        // 5. "Chat closed" lock banner (resolved state)
        if (isResolved)
          SliverToBoxAdapter(
            child: _ChatClosedBanner(colors: colors),
          ),

        // Bottom padding
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }
}

// ── DisputeMessageBubble ──────────────────────────────────────────────────────

/// Single message bubble in the dispute chat.
///
/// - Own → right-aligned, purple (`colors.purpleButton`)
/// - Admin → left-aligned, dark gray
/// - System → centered italic
///
/// An image or a file shows the chat's own attachment widgets, which
/// download and decrypt it with the solver's key (#589 phase 3).
class DisputeMessageBubble extends StatelessWidget {
  const DisputeMessageBubble({
    super.key,
    required this.message,
    required this.colors,
    this.solverRole = rust_types.SolverRole.human,
  });

  final DisputeMessage message;
  final AppColors colors;

  /// Who wrote a solver's message: it is labelled Serbero or as a person.
  final rust_types.SolverRole solverRole;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.xl,
        ),
        child: Center(
          child: Text(
            message.content,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: colors.systemMessage,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    final isMine = message.isMine;
    final attachment = message.attachment;
    final isImage = attachment?.fileType == rust_types.FileType.image;
    final bubbleColor = isMine
        ? colors.purpleButton
        : const Color(0xFF2D3142); // admin/peer dark gray

    final borderRadius = isMine
        ? const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.bubble),
            topRight: Radius.zero,
            bottomLeft: Radius.circular(AppRadius.bubble),
            bottomRight: Radius.circular(AppRadius.bubble),
          )
        : const BorderRadius.only(
            topLeft: Radius.zero,
            topRight: Radius.circular(AppRadius.bubble),
            bottomLeft: Radius.circular(AppRadius.bubble),
            bottomRight: Radius.circular(AppRadius.bubble),
          );

    return GestureDetector(
      // An attachment's content is its file name: nothing worth copying.
      onLongPress: attachment != null
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: message.content));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context).messageCopied),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
      child: Padding(
        padding: EdgeInsets.only(
          left: isMine ? AppSpacing.xl : AppSpacing.lg,
          right: isMine ? AppSpacing.lg : AppSpacing.xl,
          top: AppSpacing.xs,
          bottom: AppSpacing.xs,
        ),
        child: Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            // An image fills its bubble; a thin frame keeps the colour.
            padding: isImage
                ? const EdgeInsets.all(4)
                : const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: borderRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.isAdmin && !message.isMine)
                  Text(
                    solverRole == rust_types.SolverRole.assistant
                        ? AppLocalizations.of(context).serberoLabel
                        : AppLocalizations.of(context).solverLabel,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.tealAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                switch (attachment) {
                  null => Text(
                      message.content,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: Colors.white),
                    ),
                  _ when isImage => EncryptedImageMessage(
                      messageId: message.id,
                      attachment: attachment,
                    ),
                  _ => EncryptedFileMessage(
                      messageId: message.id,
                      attachment: attachment,
                    ),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Banners ───────────────────────────────────────────────────────────────────

class _SolverAssignedBanner extends StatelessWidget {
  const _SolverAssignedBanner({required this.isAssistant});

  /// Serbero holds the dispute, not a person.
  final bool isAssistant;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.statusActive.$1,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Icon(Icons.support_agent, color: AppColors.statusActive.$2, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              isAssistant
                  ? AppLocalizations.of(context).disputeSerberoAssigned
                  : AppLocalizations.of(context).disputeSolverAssigned,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.statusActive.$2,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatClosedBanner extends StatelessWidget {
  const _ChatClosedBanner({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 14, color: colors.textSubtle),
          const SizedBox(width: AppSpacing.xs),
          // Wraps on a narrow phone instead of overflowing (PR #596).
          Flexible(
            child: Text(
              AppLocalizations.of(context).disputeChatClosed,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSubtle,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
