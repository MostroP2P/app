import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/disputes.dart' as disputes_api;
import 'package:mostro/src/rust/api/messages.dart' as messages_api;
import 'package:mostro/src/rust/api/types.dart' as rust_types;

/// The largest file the chat sends, as `MAX_ATTACHMENT_BYTES` in
/// `rust/src/attachments/mod.rs`.
///
/// Checked before a picked file is read, so a 2 GB video is refused without
/// loading it into memory. Rust checks it again on what it receives.
const int kMaxAttachmentBytes = 25 * 1024 * 1024;

/// `512 KB`, `1.4 MB`: a file size as the chat shows it.
String formatAttachmentSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).ceil()} KB';
}

/// The Rust calls behind chat attachments (#589), in one place a test can
/// replace.
///
/// Rust decides everything that matters — the type, the metadata stripped,
/// the key, the upload, the hash check. Dart hands over bytes and gets
/// bytes back, decrypted in memory; nothing here writes them to disk.
class AttachmentGateway {
  const AttachmentGateway();

  /// Encrypts, uploads and sends [bytes] in the P2P chat of [tradeId].
  ///
  /// [uploadId] names the upload for [progress]. Fails with the markers of
  /// `send_file` (see `attachmentErrorMessage`).
  Future<rust_types.ChatMessage> send({
    required String tradeId,
    required Uint8List bytes,
    required String fileName,
    required String uploadId,
  }) => messages_api.sendFile(
    tradeId: tradeId,
    fileBytes: bytes,
    fileName: fileName,
    uploadId: uploadId,
  );

  /// Encrypts, uploads and sends [bytes] to the solver of [tradeId]'s
  /// dispute (#589 phase 3), keyed to the solver instead of the peer.
  ///
  /// Fails with the markers of `send_dispute_file`.
  Future<rust_types.ChatMessage> sendToSolver({
    required String tradeId,
    required Uint8List bytes,
    required String fileName,
    required String uploadId,
  }) => disputes_api.sendDisputeFile(
    tradeId: tradeId,
    fileBytes: bytes,
    fileName: fileName,
    uploadId: uploadId,
  );

  /// The decrypted attachment of [messageId]: from the encrypted cache, or
  /// downloaded from Blossom and checked against the hash in its URL.
  Future<messages_api.AttachmentData> download(String messageId) =>
      messages_api.downloadAttachment(messageId: messageId);

  /// Progress of the upload [uploadId], from 0 to 1.
  ///
  /// Ends at 1.0. The Rust stream never closes on its own and a pending
  /// `next()` cannot be cancelled from Dart, so a failed upload leaves one
  /// idle receiver behind. It is a broadcast receiver: it takes no event from
  /// a retry's own stream, and the retry's first event ends it (its `yield`
  /// lands on a cancelled subscription).
  Stream<double> progress(String uploadId) async* {
    final stream = await messages_api.onAttachmentProgress(messageId: uploadId);
    while (true) {
      final value = await stream.next();
      if (value == null) return;
      yield value;
      if (value >= 1.0) return;
    }
  }
}

final attachmentGatewayProvider = Provider<AttachmentGateway>(
  (ref) => const AttachmentGateway(),
);
