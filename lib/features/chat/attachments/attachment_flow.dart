import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/chat/attachments/attachment_gateway.dart';
import 'package:mostro/features/chat/attachments/attachment_picker.dart';
import 'package:mostro/features/chat/widgets/attach_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// A file the user picked and confirmed, read into memory.
typedef AttachmentToSend = ({String name, Uint8List bytes});

/// The paperclip's steps before an upload, shared by the P2P chat and the
/// dispute chat (#589): the source sheet, the pick, the size check, the
/// confirmation and the read.
///
/// Resolves to null when the user backed out or the file cannot be sent —
/// then the user was already told why. [onBusy] brackets the pick and the
/// read, which can take a while for a large file; it is not called when the
/// user dismisses the sheet. [sheetNote] tells who can open the file (see
/// [showAttachSheet]).
Future<AttachmentToSend?> pickAttachmentToSend(
  BuildContext context,
  WidgetRef ref, {
  required ValueChanged<bool> onBusy,
  String? sheetNote,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final picker = ref.read(attachmentPickerProvider);
  final source = await showAttachSheet(
    context,
    showCamera: picker.supportsCamera,
    note: sheetNote,
  );
  if (source == null || !context.mounted) return null;
  onBusy(true);
  try {
    final outcome = await picker.pick(source);
    if (!context.mounted) return null;
    switch (outcome) {
      case PickCancelled():
        return null;
      case PickTooLarge():
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.attachmentTooLarge)),
        );
        return null;
      case Picked(:final file):
        if (!await _confirmSend(context, file)) return null;
        return (name: file.name, bytes: await file.read());
    }
  } catch (e) {
    // A denied camera permission or an unreadable file.
    debugPrint('[chat] pick attachment failed: $e');
    messenger.showSnackBar(SnackBar(content: Text(l10n.attachmentReadFailed)));
    return null;
  } finally {
    if (context.mounted) onBusy(false);
  }
}

Future<bool> _confirmSend(BuildContext context, PickedAttachment file) async {
  final confirmed = await showMostroDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return MostroDialog(
        title: l10n.attachConfirmTitle,
        body: l10n.attachConfirmBody(
          file.name,
          formatAttachmentSize(file.size),
        ),
        primary: ModalAction(
          label: l10n.disputeSend,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
        secondary: ModalAction(
          label: l10n.cancel,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
      );
    },
  );
  return confirmed ?? false;
}
