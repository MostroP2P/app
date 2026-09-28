import 'package:mostro/l10n/app_localizations.dart';

/// Maps the markers `send_file`, `send_dispute_file` and
/// `download_attachment` fail with to a
/// localized message. Rust does not translate (CLAUDE.md, *Translations*).
///
/// Matched by substring, like `localizedDaemonError`: anyhow wraps the marker
/// in context of its own.
String attachmentErrorMessage(AppLocalizations l10n, Object error) {
  final raw = error.toString();
  if (raw.contains('FileTooLarge')) return l10n.attachmentTooLarge;
  if (raw.contains('UnsupportedFileType')) return l10n.attachmentUnsupported;
  if (raw.contains('InvalidImage')) return l10n.attachmentInvalidImage;
  // Nobody has taken the order yet: there is no one to share a key with.
  if (raw.contains('PeerUnknown')) return l10n.attachmentPeerUnknown;
  // The dispute chat: no solver took the dispute yet, or it is over.
  if (raw.contains('AdminNotAssigned')) return l10n.disputeSolverNotAssigned;
  if (raw.contains('NoOpenDispute')) return l10n.disputeChatClosed;
  if (raw.contains('UploadFailed')) return l10n.attachmentUploadFailed;
  if (raw.contains('DecryptionFailed')) return l10n.attachmentDecryptFailed;
  if (raw.contains('DownloadFailed') || raw.contains('AttachmentNotFound')) {
    return l10n.attachmentDownloadFailed;
  }
  return l10n.attachmentSendFailed;
}

/// Whether retrying [error] can succeed. A file of the wrong type or size
/// fails the same way every time; a network or relay failure may not.
bool isRetryableAttachmentError(Object error) {
  final raw = error.toString();
  return !raw.contains('FileTooLarge') &&
      !raw.contains('UnsupportedFileType') &&
      !raw.contains('InvalidImage') &&
      !raw.contains('DecryptionFailed') &&
      // A resolved dispute stays resolved.
      !raw.contains('NoOpenDispute');
}
