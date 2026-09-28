import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:mostro/features/chat/attachments/attachment_gateway.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

enum UploadStatus { uploading, failed }

/// The conversation of a trade an upload goes to.
enum ChatThread {
  /// Buyer and seller.
  peer,

  /// Us and the solver of the trade's dispute.
  dispute,
}

/// A file on its way out, shown as our own bubble until Rust returns the
/// message it sent.
@immutable
class PendingUpload {
  const PendingUpload({
    required this.id,
    required this.fileName,
    required this.bytes,
    this.progress = 0,
    this.status = UploadStatus.uploading,
    this.error,
  });

  /// Also the id `on_attachment_progress` reports under.
  final String id;
  final String fileName;

  /// Kept, in memory, for a retry.
  final Uint8List bytes;

  /// 0 to 1: prepared, encrypted, uploaded, sent (`send_file`).
  final double progress;
  final UploadStatus status;

  /// Why it failed, a Rust error carrying its marker.
  final Object? error;

  PendingUpload copyWith({
    double? progress,
    UploadStatus? status,
    Object? error,
  }) => PendingUpload(
    id: id,
    fileName: fileName,
    bytes: bytes,
    progress: progress ?? this.progress,
    status: status ?? this.status,
    error: error,
  );
}

/// The uploads in flight in one conversation of a trade: the P2P chat, or
/// the dispute chat with the solver ([thread]).
///
/// Scoped to the open room: leaving it drops the failed ones, whose bytes
/// were only ever in memory. One still uploading finishes in Rust and shows
/// up in the history.
class ChatUploadsNotifier extends StateNotifier<List<PendingUpload>> {
  ChatUploadsNotifier(
    this._gateway,
    this._tradeId, {
    this.thread = ChatThread.peer,
  }) : super(const []);

  final AttachmentGateway _gateway;
  final String _tradeId;
  final ChatThread thread;

  /// Starts sending [bytes]. Resolves to the sent message, or null when it
  /// failed — the bubble then offers a retry.
  Future<rust_types.ChatMessage?> send(String fileName, Uint8List bytes) {
    final upload = PendingUpload(
      id: const Uuid().v4(),
      fileName: fileName,
      bytes: bytes,
    );
    state = [...state, upload];
    return _run(upload);
  }

  Future<rust_types.ChatMessage?> retry(String id) {
    final upload = _find(id);
    if (upload == null || upload.status != UploadStatus.failed) {
      return Future.value();
    }
    final restarted = upload.copyWith(
      progress: 0,
      status: UploadStatus.uploading,
    );
    _replace(restarted);
    return _run(restarted);
  }

  void discard(String id) {
    state = [
      for (final u in state)
        if (u.id != id) u,
    ];
  }

  Future<rust_types.ChatMessage?> _run(PendingUpload upload) async {
    final progress = _gateway.progress(upload.id).listen(
      (value) {
        final current = _find(upload.id);
        if (current != null && value > current.progress) {
          _replace(current.copyWith(progress: value));
        }
      },
      // A progress stream that fails leaves the bar where it was; the send
      // itself decides the outcome.
      onError: (Object e) => debugPrint('[chat] upload progress: $e'),
    );
    try {
      final send = switch (thread) {
        ChatThread.peer => _gateway.send,
        ChatThread.dispute => _gateway.sendToSolver,
      };
      final sent = await send(
        tradeId: _tradeId,
        bytes: upload.bytes,
        fileName: upload.fileName,
        uploadId: upload.id,
      );
      if (mounted) discard(upload.id);
      return sent;
    } catch (e) {
      debugPrint('[chat] ${thread.name} attachment send failed: $e');
      final current = _find(upload.id);
      if (current != null) {
        _replace(current.copyWith(status: UploadStatus.failed, error: e));
      }
      return null;
    } finally {
      unawaited(progress.cancel());
    }
  }

  PendingUpload? _find(String id) {
    if (!mounted) return null;
    for (final u in state) {
      if (u.id == id) return u;
    }
    return null;
  }

  void _replace(PendingUpload upload) {
    if (!mounted) return;
    state = [for (final u in state) u.id == upload.id ? upload : u];
  }
}

final chatUploadsProvider = StateNotifierProvider.autoDispose
    .family<ChatUploadsNotifier, List<PendingUpload>, String>(
      (ref, tradeId) =>
          ChatUploadsNotifier(ref.watch(attachmentGatewayProvider), tradeId),
    );

/// The uploads on their way to the solver of a trade's dispute.
final disputeUploadsProvider = StateNotifierProvider.autoDispose
    .family<ChatUploadsNotifier, List<PendingUpload>, String>(
      (ref, tradeId) => ChatUploadsNotifier(
        ref.watch(attachmentGatewayProvider),
        tradeId,
        thread: ChatThread.dispute,
      ),
    );
