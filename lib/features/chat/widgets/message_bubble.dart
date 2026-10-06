import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/models/reaction_rules.dart';
import 'package:mostro/features/chat/widgets/encrypted_file_message.dart';
import 'package:mostro/features/chat/widgets/encrypted_image_message.dart';
import 'package:mostro/features/chat/widgets/message_actions_menu.dart';
import 'package:mostro/features/chat/widgets/reaction_picker.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

// ── ChatMessage model ─────────────────────────────────────────────────────────

/// Lightweight Dart-side chat message model.
///
/// Will be replaced / augmented by the Rust-bridge type once the FFI layer
/// is wired (Phase 10+).
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.tradeId,
    required this.content,
    required this.isMine,
    required this.isRead,
    required this.hasAttachment,
    required this.createdAt,
    this.messageType = 'peer',
    this.attachment,
    this.reaction,
  });

  /// Unique message identifier.
  final String id;

  /// The trade / order that this message belongs to.
  final String tradeId;

  /// Text content of the message.
  final String content;

  /// Whether this message was sent by the local user.
  final bool isMine;

  /// Whether the local user has read this message.
  final bool isRead;

  /// Whether an encrypted file attachment accompanies this message.
  final bool hasAttachment;

  /// The attachment itself (#589). [content] then holds its file name.
  final rust_types.AttachmentInfo? attachment;

  /// Unix timestamp (seconds) when the message was created.
  final int createdAt;

  /// Message type: 'peer', 'admin', or 'system'.
  final String messageType;

  /// The reaction this message carries, if any. Only the party who did not
  /// write it can react (protocol chat.md, "Reactions"): on the
  /// counterpart's message it is the user's, on the user's the
  /// counterpart's.
  final String? reaction;

  bool get isSystem => messageType == 'system';
}

// ── MessageBubble widget ──────────────────────────────────────────────────────

/// Renders a single chat message as a styled bubble.
///
/// - Own messages → right-aligned, purple background, top-right square corner.
/// - Peer messages → left-aligned, dark hue background, top-left square corner.
/// - System messages → centered italic text, no bubble background.
/// - Tapped or held → the message's menu ([showMessageActionsMenu]): Copy
///   for a text message, and the reactions when [onReact] is set. A tap on
///   an attachment opens the file, so only holding it opens the menu, which
///   offers just the reactions; without [onReact] it has no menu.
/// - A reaction shows under the bubble.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.peerColorHue,
    this.onReact,
  });

  final ChatMessage message;

  /// HSV hue (0–359) used to tint peer message bubbles.
  final int peerColorHue;

  /// Sends the user's reaction to this message, an empty string withdrawing
  /// it. Null where the user cannot react: their own messages.
  final Future<void> Function(String emoji)? onReact;


  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return _SystemMessage(message: message);
    }

    // design-check: ignore DS-COL-11 — the v1 bubble colours (§14), unchanged; the chat has no palette yet
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) throw StateError('AppColors theme extension must be registered');
    final textTheme = Theme.of(context).textTheme;

    final isMine = message.isMine;
    final alignment = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final mainAxisAlignment =
        isMine ? MainAxisAlignment.end : MainAxisAlignment.start;

    final bubbleColor = isMine
        ? colors.purpleButton
        : HSVColor.fromAHSV(1.0, peerColorHue.toDouble(), 0.55, 0.40).toColor();

    // Tail: own message → top-right is squared; peer → top-left is squared.
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

    final timestamp = _formatTime(message.createdAt);
    final attachment = message.attachment;
    // An image fills its bubble; a thin frame keeps the bubble's colour.
    final isImage = attachment?.fileType == rust_types.FileType.image;

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
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
      child: switch (attachment) {
        null => Text(
            message.content,
            style: textTheme.bodyMedium?.copyWith(
              // design-check: ignore DS-COL-1 — unchanged ink of the v1 bubbles (§14), moved here; the chat has no palette yet
              color: Colors.white,
            ),
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
    );

    // An attachment's content is its file name: nothing worth copying. It
    // opens the menu only to react to it.
    final opensMenu = attachment == null || onReact != null;
    // The menu draws over the bubble alone, though the whole column takes
    // the gesture; set while the column builds, read when a gesture lands.
    BuildContext? bubbleContext;
    void openMenu({required bool held}) {
      final anchorContext = bubbleContext;
      if (anchorContext != null) _openMenu(anchorContext, bubble, held: held);
    }

    final column = Column(
      crossAxisAlignment: alignment,
      children: [
        if (opensMenu)
          Builder(
            builder: (context) {
              bubbleContext = context;
              return bubble;
            },
          )
        else
          bubble,
        if (message.reaction case final emoji?) _ReactionChip(emoji: emoji),
        const SizedBox(height: 2),
        // Timestamp
        Text(
          timestamp,
          style: textTheme.bodySmall?.copyWith(
            color: colors.textSubtle,
            fontSize: 10,
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisAlignment: mainAxisAlignment,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: !opensMenu
                ? column
                // The detector gives screen readers the gesture that opens
                // the menu; the hint says what it opens (DS-A11Y-1).
                : Semantics(
                    button: true,
                    enabled: true,
                    onTapHint: attachment == null
                        ? AppLocalizations.of(context).messageMenuHint
                        : null,
                    onLongPressHint: attachment == null
                        ? null
                        : AppLocalizations.of(context).messageMenuHint,
                    child: GestureDetector(
                      // The bubble, its reaction and its time take the
                      // gesture, at least 48 × 48 dp of it however short the
                      // message (DS-CMP-6); the extra width sits on the
                      // bubble's open side, so nothing visible moves.
                      behavior: HitTestBehavior.opaque,
                      // An attachment's own tap opens the file.
                      onTap: attachment == null
                          ? () => openMenu(held: false)
                          : null,
                      onLongPress: () => openMenu(held: true),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: _minTarget,
                          minHeight: _minTarget,
                        ),
                        child: column,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Tapped or held ([held]): the message's menu, drawn over the bubble
  /// that [bubbleContext] lays out.
  Future<void> _openMenu(
    BuildContext bubbleContext,
    Widget bubble, {
    required bool held,
  }) async {
    // Where the message is and what of it its list shows, or null once
    // nobody can see it: disposed, or scrolled out of its list while the
    // list keeps it built in its cache.
    MessagePlace? anchor() {
      if (!bubbleContext.mounted) return null;
      final box = bubbleContext.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) return null;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final viewport =
          Scrollable.maybeOf(bubbleContext)?.context.findRenderObject()
              as RenderBox?;
      if (viewport == null || !viewport.attached || !viewport.hasSize) {
        return (rect: rect, visible: rect);
      }
      final list = viewport.localToGlobal(Offset.zero) & viewport.size;
      if (!rect.overlaps(list)) return null;
      return (rect: rect, visible: rect.intersect(list));
    }

    if (anchor() == null) return;
    // Each gesture its own feedback: the long-press vibration and the
    // screen reader's long-press event on a tap would say the wrong thing.
    held
        ? Feedback.forLongPress(bubbleContext)
        : Feedback.forTap(bubbleContext);

    final react = onReact;
    final choice = await showMessageActionsMenu(
      context: bubbleContext,
      anchor: anchor,
      bubble: bubble,
      alignEnd: message.isMine,
      canReact: react != null,
      canCopy: message.attachment == null,
      currentReaction: message.reaction,
    );
    switch (choice) {
      case null:
        return;
      case CopyMessage():
        // Copied even if the chat closed meanwhile; only the confirmation
        // needs the screen.
        await Clipboard.setData(ClipboardData(text: message.content));
        if (!bubbleContext.mounted) return;
        showOrderDetailSnackBar(
          bubbleContext,
          AppLocalizations.of(bubbleContext).messageCopied,
        );
      case ReactWith(:final emoji):
        await react?.call(_toggled(emoji));
      case MoreReactions():
        if (!bubbleContext.mounted) return;
        final emoji = await showReactionPicker(bubbleContext);
        if (emoji != null) await react?.call(_toggled(emoji));
    }
  }

  /// What picking [emoji] sends: the reaction already there takes it back,
  /// as in Signal, whichever list it was picked from.
  String _toggled(String emoji) =>
      sameReaction(emoji, message.reaction) ? '' : emoji;

  String _formatTime(int unixSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    return DateFormat.Hm().format(dt);
  }
}

// ── Reaction ──────────────────────────────────────────────────────────────────

const _pill = BorderRadius.all(Radius.circular(999));

/// The smallest tap target a message gets, in dp (DS-CMP-6).
const double _minTarget = 48;

/// The reaction under a bubble, as a small pill.
class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Semantics(
      container: true,
      label: AppLocalizations.of(context).messageReactionLabel(emoji),
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: book.surface,
          borderRadius: _pill,
          border: Border.all(color: book.border),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

// ── System message ────────────────────────────────────────────────────────────

class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) throw StateError('AppColors theme extension must be registered');
    final textTheme = Theme.of(context).textTheme;

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
}
