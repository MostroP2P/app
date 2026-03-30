import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';

/// Placeholder widget for encrypted file attachments (non-image).
///
/// Simulates a download progress bar for 1.5 s, then shows a stub SnackBar
/// until the Rust bridge download_attachment() + decrypt_file() are wired
/// (Phase 10+).
class EncryptedFileMessage extends StatefulWidget {
  const EncryptedFileMessage({
    super.key,
    required this.messageId,
    required this.fileName,
    required this.mimeType,
    required this.fileSizeBytes,
  });

  final String messageId;
  final String fileName;
  final String mimeType;
  final int fileSizeBytes;

  @override
  State<EncryptedFileMessage> createState() => _EncryptedFileMessageState();
}

class _EncryptedFileMessageState extends State<EncryptedFileMessage> {
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    assert(colors != null, 'AppColors theme extension must be registered');
    if (colors == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;

    final icon = _iconForMime(widget.mimeType);
    final sizeLabel = _formatSize(widget.fileSizeBytes);
    final typeLabel = _typeLabel(widget.mimeType);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // File type icon
                Icon(icon, color: colors.mostroGreen, size: 32),
                const SizedBox(width: AppSpacing.md),

                // File details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.fileName,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            sizeLabel,
                            style: textTheme.bodySmall
                                ?.copyWith(color: colors.textSubtle),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _TypeChip(label: typeLabel, colors: colors),
                        ],
                      ),
                    ],
                  ),
                ),

                // Download button
                IconButton(
                  icon: Icon(Icons.download, color: colors.textSecondary),
                  tooltip: 'Download',
                  onPressed: _downloading ? null : () => _startDownload(context),
                ),
              ],
            ),

            // Progress bar (visible while simulating download)
            if (_downloading) ...[
              const SizedBox(height: AppSpacing.xs),
              LinearProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(colors.mostroGreen),
                backgroundColor: colors.backgroundInput,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _startDownload(BuildContext context) async {
    setState(() => _downloading = true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _downloading = false);
    // Use this.context (State.context) which is guarded by the mounted check above.
    ScaffoldMessenger.of(this.context).showSnackBar(
      const SnackBar(
        content: Text('File download wired in Phase 10+'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ── Static helpers ───────────────────────────────────────────────────────

  IconData _iconForMime(String mime) {
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('video')) return Icons.video_file;
    return Icons.description;
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      return '$mb MB';
    }
    final kb = (bytes / 1024).ceil();
    return '$kb KB';
  }

  String _typeLabel(String mime) {
    if (mime.contains('pdf')) return 'PDF';
    if (mime.contains('video')) return 'Video';
    if (mime.contains('image')) return 'Image';
    if (mime.contains('zip') || mime.contains('tar')) return 'Archive';
    return 'File';
  }
}

// ── Private chip widget ───────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.colors});

  final String label;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.backgroundInput,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textSubtle,
              fontSize: 10,
            ),
      ),
    );
  }
}
