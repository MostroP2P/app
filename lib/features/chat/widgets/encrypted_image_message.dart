import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';

/// Placeholder widget for encrypted image attachments.
///
/// Tapping shows a SnackBar stub until download_attachment() + decrypt_file()
/// are wired via the Rust bridge (Phase 10+).
class EncryptedImageMessage extends StatelessWidget {
  const EncryptedImageMessage({
    super.key,
    required this.messageId,
    required this.fileName,
  });

  final String messageId;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    assert(colors != null, 'AppColors theme extension must be registered');
    if (colors == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        width: 200,
        height: 150,
        decoration: BoxDecoration(
          color: colors.backgroundCard,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Stack(
          children: [
            // Main placeholder icon
            Center(
              child: Icon(
                Icons.image,
                size: 48,
                color: colors.textSubtle,
              ),
            ),

            // "Tap to download" hint
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 52), // below icon
                  Text(
                    'Tap to download',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSubtle,
                    ),
                  ),
                ],
              ),
            ),

            // File name at bottom
            Positioned(
              bottom: AppSpacing.sm,
              left: AppSpacing.sm,
              right: AppSpacing.sm,
              child: Text(
                fileName,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onTap(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Image download wired in Phase 10+'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
