import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:mostro/features/chat/attachments/attachment_gateway.dart';

/// Where the user takes a file from, one per row of the attach sheet.
enum AttachmentSource { photo, camera, pdf }

/// A file the user chose, not read yet.
@immutable
class PickedAttachment {
  const PickedAttachment({
    required this.name,
    required this.size,
    required this.read,
  });

  /// The name the platform gave it. Rust sanitizes it before it is sent.
  final String name;

  final int size;

  /// Loads the bytes. Called only after the size check and the user's
  /// confirmation, so a refused file is never read into memory.
  final Future<Uint8List> Function() read;
}

/// What came back from a pick.
sealed class PickOutcome {
  const PickOutcome();
}

/// The user closed the picker.
class PickCancelled extends PickOutcome {
  const PickCancelled();
}

/// Over [kMaxAttachmentBytes]; refused before reading it.
class PickTooLarge extends PickOutcome {
  const PickTooLarge(this.name, this.size);

  final String name;
  final int size;
}

class Picked extends PickOutcome {
  const Picked(this.file);

  final PickedAttachment file;
}

/// Checks the size before anything is read.
PickOutcome checkPicked(PickedAttachment file) =>
    file.size > kMaxAttachmentBytes
        ? PickTooLarge(file.name, file.size)
        : Picked(file);

/// The platform pickers behind the attach sheet.
///
/// Photos and the camera go through `image_picker` (the system photo picker
/// on mobile, a file dialog on desktop); PDFs through `file_picker`. What is
/// sent is decided by Rust from the bytes, not from anything said here.
class AttachmentPicker {
  AttachmentPicker({ImagePicker? imagePicker})
    : _images = imagePicker ?? ImagePicker();

  final ImagePicker _images;

  /// Whether this device has a camera the picker can open. False on desktop
  /// and the web.
  bool get supportsCamera =>
      !kIsWeb && _images.supportsImageSource(ImageSource.camera);

  Future<PickOutcome> pick(AttachmentSource source) => switch (source) {
    AttachmentSource.photo => _pickImage(ImageSource.gallery),
    AttachmentSource.camera => _pickImage(ImageSource.camera),
    AttachmentSource.pdf => _pickPdf(),
  };

  Future<PickOutcome> _pickImage(ImageSource source) async {
    // Full metadata would ask iOS for photo-library access; Rust strips the
    // metadata anyway.
    final file = await _images.pickImage(
      source: source,
      requestFullMetadata: false,
    );
    if (file == null) return const PickCancelled();
    return checkPicked(
      PickedAttachment(
        name: file.name,
        size: await file.length(),
        read: file.readAsBytes,
      ),
    );
  }

  Future<PickOutcome> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      // Read later, and only if the size passes. The web has no path to
      // read from later: it hands over a stream of the browser's File, read
      // in slices only when it is listened to.
      withData: false,
      withReadStream: kIsWeb,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return const PickCancelled();
    final stream = file.readStream;
    return checkPicked(
      PickedAttachment(
        name: file.name,
        size: file.size,
        read:
            stream != null
                ? () => collectBytes(stream)
                : file.xFile.readAsBytes,
      ),
    );
  }
}

/// Every chunk of [stream] in one buffer.
@visibleForTesting
Future<Uint8List> collectBytes(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

final attachmentPickerProvider = Provider<AttachmentPicker>(
  (ref) => AttachmentPicker(),
);
