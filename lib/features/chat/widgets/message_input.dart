import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';

/// Bottom message composition bar.
///
/// Pill-shaped row containing an attach button, a text field, and a send button.
class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.onSendText,
    required this.onAttachFile,
    this.isAttaching = false,
  });

  /// Called with the composed text when the user taps send (or presses the
  /// keyboard action). The field is cleared automatically after the callback.
  final void Function(String text) onSendText;

  /// Called when the user taps the attachment button.
  final VoidCallback onAttachFile;

  /// When true, replaces the attachment icon with a small progress indicator.
  final bool isAttaching;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
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
    final colors = Theme.of(context).extension<AppColors>()!;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundCard,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Attachment button / progress
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
                    tooltip: 'Attach file',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
          ),

          // Text field
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
              decoration: InputDecoration(
                hintText: 'Write a message...',
                hintStyle: TextStyle(color: colors.textSubtle),
                filled: true,
                fillColor: colors.backgroundInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
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
              tooltip: 'Send',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }
}
