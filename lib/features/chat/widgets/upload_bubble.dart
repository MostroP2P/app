import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/attachments/attachment_errors.dart';
import 'package:mostro/features/chat/attachments/attachment_gateway.dart';
import 'package:mostro/features/chat/attachments/upload_controller.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Our own file on its way out: its progress, or why it failed and what can
/// be done about it.
///
/// Replaced by the real bubble once Rust returns the sent message. There is
/// no cancel: `send_file` cannot be stopped midway, and a bubble that said
/// "canceled" while the file still reached the peer would lie.
class UploadBubble extends StatelessWidget {
  const UploadBubble({
    super.key,
    required this.upload,
    required this.onRetry,
    required this.onDiscard,
  });

  final PendingUpload upload;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) {
      throw StateError('AppColors theme extension must be registered');
    }
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final failed = upload.status == UploadStatus.failed;
    final error = upload.error;
    final isPdf = upload.fileName.toLowerCase().endsWith('.pdf');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.72,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.purpleButton,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppRadius.bubble),
              bottomLeft: Radius.circular(AppRadius.bubble),
              bottomRight: Radius.circular(AppRadius.bubble),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    // A failure is told by its icon, not by fading the
                    // bubble: white text on a faded purple is unreadable in
                    // the light theme.
                    failed
                        ? Icons.error_outline_rounded
                        : isPdf
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                    color: Colors.white,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      upload.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                failed && error != null
                    ? attachmentErrorMessage(l10n, error)
                    : '${l10n.attachmentUploading} '
                        '${formatAttachmentSize(upload.bytes.length)}',
                style: textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
              if (!failed) ...[
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(
                    value: upload.progress > 0 ? upload.progress : null,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ] else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (error == null || isRetryableAttachmentError(error))
                      TextButton(
                        onPressed: onRetry,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: Text(l10n.retry),
                      ),
                    TextButton(
                      onPressed: onDiscard,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                      child: Text(l10n.attachmentDiscard),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
