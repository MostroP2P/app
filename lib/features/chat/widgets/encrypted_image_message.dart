import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/attachments/attachment_errors.dart';
import 'package:mostro/features/chat/attachments/attachment_providers.dart';
import 'package:mostro/features/chat/screens/attachment_viewer_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

/// Widest an image is drawn inside a bubble.
const double kImageBubbleMaxWidth = 240;

/// The shape the bubble keeps before the image is decrypted: the sender's
/// `width`/`height`, clamped so a peer-declared 1 × 10000 cannot draw a
/// sliver or a tower. 4:3 when the sender gave none.
double imageBubbleAspectRatio(int? width, int? height) {
  if (width == null || height == null || width <= 0 || height <= 0) {
    return 4 / 3;
  }
  return (width / height).clamp(0.5, 2.0);
}

/// An encrypted image in the chat, downloaded and decrypted on arrival, as v1
/// does. Tapping it opens [AttachmentViewerScreen].
///
/// The plaintext stays in memory ([decryptedAttachmentCacheProvider]).
class EncryptedImageMessage extends ConsumerWidget {
  const EncryptedImageMessage({
    super.key,
    required this.messageId,
    required this.attachment,
  });

  final String messageId;
  final rust_types.AttachmentInfo attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final data = ref.watch(attachmentDataProvider(messageId));
    final aspect = imageBubbleAspectRatio(attachment.width, attachment.height);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kImageBubbleMaxWidth),
      child: AspectRatio(
        aspectRatio: aspect,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.bubble - 4),
          child: ColoredBox(
            color: Colors.black26,
            child: data.when(
              loading:
                  () => const Center(
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
                  ),
              error:
                  (error, _) => _ImageError(
                    message: attachmentErrorMessage(l10n, error),
                    onRetry:
                        isRetryableAttachmentError(error)
                            ? () => ref.invalidate(
                              attachmentDataProvider(messageId),
                            )
                            : null,
                  ),
              data:
                  (file) => Semantics(
                    label: l10n.attachmentImageSemantics(attachment.fileName),
                    image: true,
                    button: true,
                    onTapHint: l10n.attachmentOpenImage,
                    child: GestureDetector(
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder:
                                  (_) => AttachmentViewerScreen(
                                    messageId: messageId,
                                    fileName: attachment.fileName,
                                  ),
                            ),
                          ),
                      child: LayoutBuilder(
                        builder:
                            (context, constraints) => Image.memory(
                              file.bytes,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              // Decode at the size drawn, not the photo's 4000 px.
                              cacheWidth: _decodeWidth(
                                context,
                                constraints.maxWidth,
                              ),
                              excludeFromSemantics: true,
                              errorBuilder:
                                  (_, _, _) => _ImageError(
                                    message: l10n.attachmentInvalidImage,
                                  ),
                            ),
                      ),
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }

  static int? _decodeWidth(BuildContext context, double logicalWidth) {
    if (!logicalWidth.isFinite) return null;
    return (logicalWidth * MediaQuery.devicePixelRatioOf(context)).ceil();
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image_outlined, color: Colors.white70),
          const SizedBox(height: AppSpacing.xs),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(l10n.retry),
            ),
        ],
      ),
    );
  }
}
