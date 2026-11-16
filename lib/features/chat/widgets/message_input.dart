import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/composer_emoji_button.dart';

/// Bottom message composition bar.
///
/// Pill-shaped row containing an attach button, an emoji button, a text field
/// that grows to five lines, and a send button.
/// The field takes the cursor as it appears, so a chat opens ready to type.
class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.onSendText,
    this.onAttachFile,
    this.isAttaching = false,
  });

  /// Called with the composed text when the user taps send (or presses the
  /// keyboard action). The field is cleared automatically after the callback.
  final void Function(String text) onSendText;

  /// Called when the user taps the attachment button. Null hides it, where
  /// attachments cannot be sent (the web, until #150).
  final VoidCallback? onAttachFile;

  /// When true, replaces the attachment icon with a small progress indicator.
  final bool isAttaching;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendText(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    // design-check: ignore DS-COL-11 — the v1 composer colours (§14), unchanged; the chat has no palette yet
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) throw StateError('AppColors theme extension must be registered');
    final l10n = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        // design-check: ignore DS-SHP-1 — the v1 composer pill (§14), unchanged; the chat has no palette yet
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        // The buttons stay by the last line as the field grows.
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attachment button / progress
          if (widget.onAttachFile != null)
            SizedBox(
              width: 36,
              height: 36,
              child: widget.isAttaching
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colors.textSubtle,
                        ),
                      ),
                    )
                  : IconButton(
                      icon: Icon(Icons.attach_file, color: colors.textSubtle),
                      onPressed: widget.onAttachFile,
                      tooltip: l10n.disputeAttachFile,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
            ),

          ComposerEmojiButton(
            controller: _controller,
            focusNode: _focusNode,
            color: colors.textSubtle,
          ),

          // Text field
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              // Wraps up to five lines, then scrolls. The keyboard keeps
              // Send rather than a new-line key, so sending is unchanged.
              keyboardType: TextInputType.text,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
              decoration: InputDecoration(
                hintText: l10n.disputeWriteMessageHint,
                hintStyle: TextStyle(color: colors.textSubtle),
                filled: true,
                fillColor: colors.backgroundInput,
                border: OutlineInputBorder(
                  // design-check: ignore DS-SHP-4 — the v1 composer field (§14), unchanged; the chat has no palette yet
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  // design-check: ignore DS-SHP-4 — the v1 composer field (§14), unchanged; the chat has no palette yet
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  // design-check: ignore DS-SHP-4 — the v1 composer field (§14), unchanged; the chat has no palette yet
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                isDense: true,
              ),
            ),
          ),

          // Send button
          const SizedBox(width: AppSpacing.xs),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              icon: Icon(Icons.send, color: colors.mostroGreen),
              onPressed: _handleSend,
              tooltip: l10n.disputeSend,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }
}
