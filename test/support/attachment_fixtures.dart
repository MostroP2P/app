import 'dart:async';
import 'dart:ui' show Rect;
import 'dart:typed_data';

import 'package:mostro/features/chat/attachments/attachment_gateway.dart';
import 'package:mostro/features/chat/attachments/attachment_launcher.dart';
import 'package:mostro/features/chat/attachments/attachment_picker.dart';
import 'package:mostro/features/chat/attachments/attachment_saver.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/messages.dart' as messages_api;
import 'package:mostro/src/rust/api/types.dart' as rust_types;

const kSha = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

rust_types.AttachmentInfo imageInfo({
  String fileName = 'receipt.jpg',
  int? width = 1200,
  int? height = 900,
}) => rust_types.AttachmentInfo(
  fileName: fileName,
  mimeType: 'image/jpeg',
  fileSize: BigInt.from(524288),
  fileType: rust_types.FileType.image,
  downloadStatus: rust_types.DownloadStatus.pending,
  blossomUrl: 'https://blossom.example/$kSha',
  sha256: kSha,
  encryptedSize: BigInt.from(524316),
  width: width,
  height: height,
);

rust_types.AttachmentInfo pdfInfo({String fileName = 'transfer.pdf'}) =>
    rust_types.AttachmentInfo(
      fileName: fileName,
      mimeType: 'application/pdf',
      fileSize: BigInt.from(1468006),
      fileType: rust_types.FileType.document,
      downloadStatus: rust_types.DownloadStatus.pending,
      blossomUrl: 'https://blossom.example/$kSha',
      sha256: kSha,
      encryptedSize: BigInt.from(1468034),
    );

rust_types.ChatMessage attachmentMessage({
  required String id,
  required rust_types.AttachmentInfo attachment,
  String tradeId = 'order-chat',
  bool isMine = true,
  int createdAt = 1000,
}) => rust_types.ChatMessage(
  id: id,
  tradeId: tradeId,
  senderPubkey: isMine ? 'me' : 'peer',
  content: attachment.fileName,
  messageType: rust_types.MessageType.peer,
  isMine: isMine,
  isRead: true,
  hasAttachment: true,
  attachment: attachment,
  createdAt: intToPlatformInt64(createdAt),
);

/// Records calls and answers with what the test set.
class FakeAttachmentGateway extends AttachmentGateway {
  FakeAttachmentGateway({this.downloadResult, this.sendResult});

  /// Return a [Completer] future to hold the call open.
  Future<messages_api.AttachmentData> Function(String id)? downloadResult;
  Future<rust_types.ChatMessage> Function(String uploadId)? sendResult;

  final downloads = <String>[];
  final sends = <({String tradeId, String fileName, int bytes, String id})>[];
  final progressControllers = <String, StreamController<double>>{};

  @override
  Future<rust_types.ChatMessage> send({
    required String tradeId,
    required Uint8List bytes,
    required String fileName,
    required String uploadId,
  }) {
    sends.add((
      tradeId: tradeId,
      fileName: fileName,
      bytes: bytes.length,
      id: uploadId,
    ));
    final result = sendResult;
    if (result == null) throw StateError('no send result');
    return result(uploadId);
  }

  /// Files sent to the solver, as [sends] records the peer's.
  final solverSends = <({String tradeId, String fileName, String id})>[];

  @override
  Future<rust_types.ChatMessage> sendToSolver({
    required String tradeId,
    required Uint8List bytes,
    required String fileName,
    required String uploadId,
  }) {
    solverSends.add((tradeId: tradeId, fileName: fileName, id: uploadId));
    final result = sendResult;
    if (result == null) throw StateError('no send result');
    return result(uploadId);
  }

  @override
  Future<messages_api.AttachmentData> download(String messageId) {
    downloads.add(messageId);
    final result = downloadResult;
    if (result == null) throw StateError('no download result');
    return result(messageId);
  }

  @override
  Stream<double> progress(String uploadId) =>
      (progressControllers[uploadId] = StreamController<double>()).stream;
}

/// Hands back [outcome] for whatever source is picked.
class FakeAttachmentPicker extends AttachmentPicker {
  FakeAttachmentPicker(this.outcome, {this.camera = false});

  PickOutcome Function(AttachmentSource source) outcome;
  final bool camera;
  final picked = <AttachmentSource>[];

  @override
  bool get supportsCamera => camera;

  @override
  Future<PickOutcome> pick(AttachmentSource source) async {
    picked.add(source);
    return outcome(source);
  }
}

class FakeAttachmentSaver extends AttachmentSaver {
  FakeAttachmentSaver({this.result = true});

  final bool result;
  final saved = <String>[];

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    saved.add(fileName);
    return result;
  }
}

messages_api.AttachmentData attachmentData(
  List<int> bytes, {
  String fileName = 'receipt.jpg',
  String mimeType = 'image/jpeg',
}) => messages_api.AttachmentData(
  bytes: Uint8List.fromList(bytes),
  fileName: fileName,
  mimeType: mimeType,
);

PickedAttachment pickedFile({String name = 'receipt.png', int size = 3}) =>
    PickedAttachment(
      name: name,
      size: size,
      read: () async => Uint8List.fromList(List.filled(size, 7)),
    );

/// Records what was handed off instead of launching anything.
class FakeAttachmentLauncher extends AttachmentLauncher {
  FakeAttachmentLauncher({
    this.openOutcome = LaunchOutcome.done,
    this.canShare = true,
  });

  final LaunchOutcome openOutcome;
  final bool canShare;
  final opened = <String>[];
  final shared = <String>[];

  @override
  bool get supportsShare => canShare;

  @override
  Future<LaunchOutcome> openWith(messages_api.AttachmentData data) async {
    opened.add(data.fileName);
    return openOutcome;
  }

  @override
  Future<void> share(messages_api.AttachmentData data, {Rect? origin}) async {
    shared.add(data.fileName);
  }
}
