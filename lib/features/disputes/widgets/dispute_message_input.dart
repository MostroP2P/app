import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Message composition bar for dispute/admin chat.
///
/// Same layout as the P2P [MessageInput] — attach + text field + send button.
/// Only rendered when the dispute is still `in-progress`; hidden for
/// resolved or closed disputes.
///
/// Text and files both go to the solver, keyed to the solver's pubkey
/// (#143, #589 phase 3).
class DisputeMessageInput extends StatefulWidget {
  const DisputeMessageInput({
    super.key,
    required this.onSendText,
    required this.onAttachFile,
    this.isAttaching = false,
    this.isSending = false,
  });

  /// Called with the composed text when the user taps send. Resolves to
  /// whether it was sent: the field is cleared only then, so a failed send
  /// keeps what the user wrote.
  final Future<bool> Function(String text) onSendText;

  /// Called when the user taps the attachment button.
  final VoidCallback onAttachFile;

  /// When true, replaces the attachment icon with a progress indicator.
  final bool isAttaching;

  /// When true, a message is on its way and the send button is disabled.
  final bool isSending;

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

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isSending) return;
    final sent = await widget.onSendText(text);
    // Only what was sent: text typed while it was on its way stays.
    if (sent && mounted && _controller.text.trim() == text) {
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) throw StateError('AppColors theme extension must be registered');
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
              onPressed: widget.isSending ? null : _handleSend,
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
