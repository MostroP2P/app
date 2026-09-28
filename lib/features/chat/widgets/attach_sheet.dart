import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/attachments/attachment_picker.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// Asks where the file comes from. Resolves to null when dismissed.
///
/// The camera row is offered only where there is one ([showCamera]).
/// [note] says who can open the file; the P2P chat's by default.
Future<AttachmentSource?> showAttachSheet(
  BuildContext context, {
  required bool showCamera,
  String? note,
}) {
  return showMostroSheet<AttachmentSource>(
    context: context,
    builder: (sheetContext) {
      final l10n = AppLocalizations.of(sheetContext);
      return MostroSheet(
        title: l10n.attachSheetTitle,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SourceRow(
              icon: Icons.photo_library_outlined,
              label: l10n.attachSourcePhoto,
              source: AttachmentSource.photo,
            ),
            if (showCamera)
              _SourceRow(
                icon: Icons.photo_camera_outlined,
                label: l10n.attachSourceCamera,
                source: AttachmentSource.camera,
              ),
            _SourceRow(
              icon: Icons.picture_as_pdf_outlined,
              label: l10n.attachSourcePdf,
              source: AttachmentSource.pdf,
            ),
            const SizedBox(height: 10),
            _Note(text: note ?? l10n.attachSheetBody),
          ],
        ),
      );
    },
  );
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.label,
    required this.source,
  });

  final IconData icon;
  final String label;
  final AttachmentSource source;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: book.limeIcon),
      title: Text(label, style: TextStyle(color: book.textPrimary)),
      onTap: () => Navigator.of(context).pop(source),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, size: 14, color: book.textTertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: book.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
