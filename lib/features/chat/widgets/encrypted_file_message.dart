import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/attachments/attachment_errors.dart';
import 'package:mostro/features/chat/attachments/attachment_gateway.dart';
import 'package:mostro/features/chat/attachments/attachment_launcher.dart';
import 'package:mostro/features/chat/attachments/attachment_providers.dart';
import 'package:mostro/features/chat/attachments/attachment_saver.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

enum _FileAction { open, share, save }

/// An encrypted file that is not an image — a PDF, or a DOC/DOCX/video sent
/// from v1 — drawn inside its chat bubble.
///
/// Nothing is downloaded until the user asks. Tapping the card opens it in
/// another app ("open with…") when its type is one the chat hands off
/// ([kOpenableTypes]); the menu adds Share and Save. Any other type can only
/// be saved.
class EncryptedFileMessage extends ConsumerStatefulWidget {
  const EncryptedFileMessage({
    super.key,
    required this.messageId,
    required this.attachment,
  });

  final String messageId;
  final rust_types.AttachmentInfo attachment;

  @override
  ConsumerState<EncryptedFileMessage> createState() =>
      _EncryptedFileMessageState();
}

class _EncryptedFileMessageState extends ConsumerState<EncryptedFileMessage> {
  bool _busy = false;

  /// Downloads and decrypts the file, then does [action] with it.
  Future<void> _run(_FileAction action) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final data = await loadAttachment(
        cache: ref.read(decryptedAttachmentCacheProvider),
        gateway: ref.read(attachmentGatewayProvider),
        messageId: widget.messageId,
      );
      if (!mounted) return;
      final launcher = ref.read(attachmentLauncherProvider);
      // The type offered was the one the sender declared; decide on the one
      // Rust found in the bytes.
      if (action != _FileAction.save && !launcher.canHandOff(data)) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.attachmentSaveOnly)),
        );
        return;
      }
      await switch (action) {
        _FileAction.open => openAttachmentWithFeedback(context, ref, data),
        _FileAction.share => shareAttachmentWithFeedback(context, ref, data),
        _FileAction.save => saveAttachmentWithFeedback(context, ref, data),
      };
    } catch (e) {
      debugPrint('[chat] download attachment failed: $e');
      messenger.showSnackBar(
        SnackBar(content: Text(attachmentErrorMessage(l10n, e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final attachment = widget.attachment;
    final launcher = ref.watch(attachmentLauncherProvider);
    final openable = launcher.canHandOffType(attachment.mimeType);
    final details =
        '${formatAttachmentSize(attachment.fileSize.toInt())} · '
        '${fileTypeLabel(attachment.mimeType, l10n)}';

    return Semantics(
      label: '${attachment.fileName}, $details',
      button: true,
      onTapHint: openable ? l10n.attachmentOpenWith : l10n.attachmentSave,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap:
            _busy
                ? null
                : () => _run(openable ? _FileAction.open : _FileAction.save),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              fileTypeIcon(attachment.mimeType),
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  ExcludeSemantics(
                    child: Text(
                      details,
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            SizedBox.square(
              dimension: 40,
              child:
                  _busy
                      ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      )
                      : PopupMenuButton<_FileAction>(
                        tooltip: l10n.attachmentMoreActions,
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        onSelected: _run,
                        itemBuilder:
                            (_) => [
                              if (openable)
                                PopupMenuItem(
                                  value: _FileAction.open,
                                  child: _MenuRow(
                                    icon: Icons.open_in_new,
                                    label: l10n.attachmentOpenWith,
                                  ),
                                ),
                              if (openable && launcher.supportsShare)
                                PopupMenuItem(
                                  value: _FileAction.share,
                                  child: _MenuRow(
                                    icon: Icons.share_outlined,
                                    label: l10n.attachmentShare,
                                  ),
                                ),
                              PopupMenuItem(
                                value: _FileAction.save,
                                child: _MenuRow(
                                  icon: Icons.download_outlined,
                                  label: l10n.attachmentSave,
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
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: AppSpacing.sm),
      Text(label),
    ],
  );
}

/// The icon for a file of [mime] type, as the sender declared it.
IconData fileTypeIcon(String mime) {
  if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
  if (mime.startsWith('video/')) return Icons.video_file_outlined;
  if (mime.startsWith('image/')) return Icons.image_outlined;
  return Icons.description_outlined;
}

/// The short type label shown next to the size. Format names (PDF, DOC)
/// are not translated.
String fileTypeLabel(String mime, AppLocalizations l10n) {
  if (mime.contains('pdf')) return 'PDF';
  if (mime == 'application/msword') return 'DOC';
  if (mime.contains('wordprocessingml')) return 'DOCX';
  if (mime.startsWith('video/')) return l10n.fileTypeVideo;
  if (mime.startsWith('image/')) return l10n.fileTypeImage;
  if (mime.contains('zip') || mime.contains('tar')) return l10n.fileTypeArchive;
  return l10n.fileTypeFile;
}
