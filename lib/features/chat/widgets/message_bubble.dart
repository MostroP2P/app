import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mostro/core/app_theme.dart';

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

  /// Unix timestamp (seconds) when the message was created.
  final int createdAt;

  /// Message type: 'peer', 'admin', or 'system'.
  final String messageType;

  bool get isSystem => messageType == 'system';
}

// ── MessageBubble widget ──────────────────────────────────────────────────────

/// Renders a single chat message as a styled bubble.
///
/// - Own messages → right-aligned, purple background, top-right square corner.
/// - Peer messages → left-aligned, dark hue background, top-left square corner.
/// - System messages → centered italic text, no bubble background.
/// - Long-press → copies content to clipboard and shows a SnackBar.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.peerColorHue,
  });

  final ChatMessage message;

  /// HSV hue (0–359) used to tint peer message bubbles.
  final int peerColorHue;

  static const _ownBubbleColor = Color(0xFF7856AF);

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return _SystemMessage(message: message);
    }

    final colors = Theme.of(context).extension<AppColors>()!;
    final textTheme = Theme.of(context).textTheme;

    final isMine = message.isMine;
    final alignment = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final mainAxisAlignment =
        isMine ? MainAxisAlignment.end : MainAxisAlignment.start;

    final bubbleColor = isMine
        ? _ownBubbleColor
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

    return GestureDetector(
      onLongPress: () => _copyToClipboard(context, message.content),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisAlignment: mainAxisAlignment,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: alignment,
                children: [
                  // Bubble
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72,
                    ),
                    padding: const EdgeInsets.symmetric(
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
                        Text(
                          message.content,
                          style: textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        if (message.hasAttachment) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '[Attachment]',
                            style: textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _formatTime(int unixSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── System message ────────────────────────────────────────────────────────────

class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
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
