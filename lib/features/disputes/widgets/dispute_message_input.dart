import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Message composition bar for dispute/admin chat.
///
/// Same layout as the P2P [MessageInput] — attach + text field + send button.
/// Only rendered when the dispute is still `in-progress`; hidden for
/// resolved or closed disputes.
///
/// File attachments use the admin shared key for encryption (wired Phase 12+).
class DisputeMessageInput extends StatefulWidget {
  const DisputeMessageInput({
    super.key,
    required this.onSendText,
    required this.onAttachFile,
    this.isAttaching = false,
  });

  /// Called with the composed text when the user taps send.
  final void Function(String text) onSendText;

  /// Called when the user taps the attachment button.
  final VoidCallback onAttachFile;

  /// When true, replaces the attachment icon with a progress indicator.
  final bool isAttaching;

  @override
  State<DisputeMessageInput> createState() => _DisputeMessageInputState();
}

class _DisputeMessageInputState extends State<DisputeMessageInput> {
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
    final colors = Theme.of(context).extension<AppColors>();
    assert(colors != null, 'AppColors theme extension must be registered');
    if (colors == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);

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
                    tooltip: l10n.disputeAttachFile,
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
                hintText: l10n.disputeWriteMessageHint,
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
