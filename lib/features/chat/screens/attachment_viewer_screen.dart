import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/chat/attachments/attachment_errors.dart';
import 'package:mostro/features/chat/attachments/attachment_launcher.dart';
import 'package:mostro/features/chat/attachments/attachment_providers.dart';
import 'package:mostro/features/chat/attachments/attachment_saver.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// A chat image, full screen, with pinch-zoom, Share, "open with…" and Save.
///
/// Reads the decrypted bytes from memory — the bubble that opened it already
/// decrypted them. Share and "open with…" write a temporary copy that
/// [AttachmentLauncher.sweep] deletes; Save writes where the user chooses.
class AttachmentViewerScreen extends ConsumerWidget {
  const AttachmentViewerScreen({
    super.key,
    required this.messageId,
    required this.fileName,
  });

  final String messageId;
  final String fileName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final data = ref.watch(attachmentDataProvider(messageId));
    final file = data.valueOrNull;
    final launcher = ref.watch(attachmentLauncherProvider);
    final canHandOff = file != null && launcher.canHandOff(file);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(fileName, overflow: TextOverflow.ellipsis),
        actions: [
          if (canHandOff && launcher.supportsShare)
            // Its own context, so the share popover anchors on the button.
            Builder(
              builder:
                  (buttonContext) => IconButton(
                    tooltip: l10n.attachmentShare,
                    icon: const Icon(Icons.share_outlined),
                    onPressed:
                        () => shareAttachmentWithFeedback(
                          buttonContext,
                          ref,
                          file,
                        ),
                  ),
            ),
          if (canHandOff)
            IconButton(
              tooltip: l10n.attachmentOpenWith,
              icon: const Icon(Icons.open_in_new),
              onPressed: () => openAttachmentWithFeedback(context, ref, file),
            ),
          IconButton(
            tooltip: l10n.attachmentSave,
            icon: const Icon(Icons.download_outlined),
            onPressed:
                file == null
                    ? null
                    : () => saveAttachmentWithFeedback(context, ref, file),
          ),
        ],
      ),
      body: data.when(
        loading:
            () => const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
        error:
            (error, _) => Center(
              child: Text(
                attachmentErrorMessage(l10n, error),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
        data:
            (file) => InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: Image.memory(
                  file.bytes,
                  fit: BoxFit.contain,
                  semanticLabel: l10n.attachmentImageSemantics(fileName),
                  errorBuilder:
                      (_, _, _) => Text(
                        l10n.attachmentInvalidImage,
                        style: const TextStyle(color: Colors.white70),
                      ),
                ),
              ),
            ),
      ),
    );
  }
}
