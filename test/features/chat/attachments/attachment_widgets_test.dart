import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/attachments/attachment_gateway.dart';
import 'package:mostro/features/chat/attachments/attachment_launcher.dart';
import 'package:mostro/features/chat/attachments/attachment_saver.dart';
import 'package:mostro/features/chat/attachments/upload_controller.dart';
import 'package:mostro/features/chat/screens/attachment_viewer_screen.dart';
import 'package:mostro/features/chat/widgets/encrypted_file_message.dart';
import 'package:mostro/features/chat/widgets/encrypted_image_message.dart';
import 'package:mostro/features/chat/widgets/message_bubble.dart';
import 'package:mostro/features/chat/widgets/upload_bubble.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/messages.dart' as messages_api;
import 'package:mostro/src/rust/api/types.dart' as rust_types;

import '../../../support/attachment_fixtures.dart';
import '../../../support/provider_harness.dart';

/// A real PNG, so `Image.memory` decodes rather than failing.
Future<Uint8List> _png(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 8, 6),
      Paint()..color = const Color(0xFF3A7BD5),
    );
    final image = await recorder.endRecording().toImage(8, 6);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }))!;
}

/// Lets `Image.memory` finish decoding, which happens outside fake time.
Future<void> _decodeImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      final image = element.widget as Image;
      await precacheImage(image.image, element);
    }
  });
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required FakeAttachmentGateway gateway,
  FakeAttachmentSaver? saver,
  FakeAttachmentLauncher? launcher,
}) async {
  final container = createContainer(
    overrides: [
      attachmentGatewayProvider.overrideWithValue(gateway),
      if (saver != null) attachmentSaverProvider.overrideWithValue(saver),
      attachmentLauncherProvider.overrideWithValue(
        launcher ?? FakeAttachmentLauncher(),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  group('EncryptedImageMessage', () {
    testWidgets('downloads on arrival and shows a spinner meanwhile', (
      tester,
    ) async {
      final pending = Completer<messages_api.AttachmentData>();
      final gateway = FakeAttachmentGateway(
        downloadResult: (_) => pending.future,
      );

      await _pump(
        tester,
        EncryptedImageMessage(messageId: 'm1', attachment: imageInfo()),
        gateway: gateway,
      );
      await tester.pump();

      expect(gateway.downloads, ['m1']);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.completeError(Exception('DownloadFailed: late'));
      await tester.pump();
    });

    testWidgets('keeps the sender\'s shape before the image decrypts', (
      tester,
    ) async {
      final gateway = FakeAttachmentGateway(
        downloadResult: (_) => Completer<messages_api.AttachmentData>().future,
      );

      await _pump(
        tester,
        EncryptedImageMessage(
          messageId: 'm1',
          attachment: imageInfo(width: 1000, height: 2000),
        ),
        gateway: gateway,
      );

      final size = tester.getSize(find.byType(AspectRatio));
      expect(size.width, kImageBubbleMaxWidth);
      expect(size.height, kImageBubbleMaxWidth * 2);
    });

    testWidgets('shows the image and opens it full screen', (tester) async {
      final png = await _png(tester);
      final gateway = FakeAttachmentGateway(
        downloadResult: (_) async => attachmentData(png, mimeType: 'image/png'),
      );

      await _pump(
        tester,
        EncryptedImageMessage(messageId: 'm1', attachment: imageInfo()),
        gateway: gateway,
      );
      await tester.pump();
      await _decodeImages(tester);

      expect(find.byType(Image), findsOneWidget);
      expect(find.bySemanticsLabel('Image: receipt.jpg'), findsOneWidget);

      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      expect(find.byType(AttachmentViewerScreen), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byTooltip('Share'), findsOneWidget);
      expect(find.byTooltip('Open with…'), findsOneWidget);
      expect(find.byTooltip('Save'), findsOneWidget);
      // Served from memory: the viewer does not decrypt it again.
      expect(gateway.downloads, ['m1']);
    });

    testWidgets('a failed download offers a retry that downloads again', (
      tester,
    ) async {
      var calls = 0;
      final png = await _png(tester);
      final gateway = FakeAttachmentGateway(
        downloadResult: (_) async {
          if (calls++ == 0) throw Exception('DownloadFailed: 503');
          return attachmentData(png);
        },
      );

      await _pump(
        tester,
        EncryptedImageMessage(messageId: 'm1', attachment: imageInfo()),
        gateway: gateway,
      );
      await tester.pump();

      expect(find.text('The file could not be downloaded.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      await _decodeImages(tester);

      expect(gateway.downloads, ['m1', 'm1']);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('a file that does not decrypt offers no retry', (tester) async {
      final gateway = FakeAttachmentGateway(
        downloadResult: (_) async => throw Exception('DecryptionFailed: tag'),
      );

      await _pump(
        tester,
        EncryptedImageMessage(messageId: 'm1', attachment: imageInfo()),
        gateway: gateway,
      );
      await tester.pump();

      expect(find.text('This file could not be decrypted.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('EncryptedFileMessage', () {
    testWidgets('shows name, size and type, and downloads nothing', (
      tester,
    ) async {
      final gateway = FakeAttachmentGateway();

      await _pump(
        tester,
        EncryptedFileMessage(messageId: 'm2', attachment: pdfInfo()),
        gateway: gateway,
      );

      expect(find.text('transfer.pdf'), findsOneWidget);
      expect(find.text('1.4 MB · PDF'), findsOneWidget);
      expect(gateway.downloads, isEmpty);
    });

    FakeAttachmentGateway pdfGateway({String mimeType = 'application/pdf'}) =>
        FakeAttachmentGateway(
          downloadResult:
              (_) async => attachmentData(
                [37, 80, 68, 70],
                fileName: 'transfer.pdf',
                mimeType: mimeType,
              ),
        );

    Future<void> pickFromMenu(WidgetTester tester, String item) async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping the card opens it in another app', (tester) async {
      final gateway = pdfGateway();
      final launcher = FakeAttachmentLauncher();

      await _pump(
        tester,
        EncryptedFileMessage(messageId: 'm2', attachment: pdfInfo()),
        gateway: gateway,
        launcher: launcher,
      );
      await tester.tap(find.text('transfer.pdf'));
      await tester.pumpAndSettle();

      expect(gateway.downloads, ['m2']);
      expect(launcher.opened, ['transfer.pdf']);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('says so when no app can open it', (tester) async {
      await _pump(
        tester,
        EncryptedFileMessage(messageId: 'm2', attachment: pdfInfo()),
        gateway: pdfGateway(),
        launcher: FakeAttachmentLauncher(openOutcome: LaunchOutcome.noApp),
      );
      await tester.tap(find.text('transfer.pdf'));
      await tester.pumpAndSettle();

      expect(
        find.text('No app on this device can open this file.'),
        findsOneWidget,
      );
    });

    testWidgets('the menu offers open, share and save', (tester) async {
      final launcher = FakeAttachmentLauncher();
      final saver = FakeAttachmentSaver();
      await _pump(
        tester,
        EncryptedFileMessage(messageId: 'm2', attachment: pdfInfo()),
        gateway: pdfGateway(),
        saver: saver,
        launcher: launcher,
      );

      await pickFromMenu(tester, 'Share');
      await pickFromMenu(tester, 'Save');

      expect(launcher.shared, ['transfer.pdf']);
      expect(saver.saved, ['transfer.pdf']);
      expect(find.text('File saved'), findsOneWidget);
    });

    testWidgets('no Share where the share sheet takes no files', (
      tester,
    ) async {
      await _pump(
        tester,
        EncryptedFileMessage(messageId: 'm2', attachment: pdfInfo()),
        gateway: pdfGateway(),
        launcher: FakeAttachmentLauncher(canShare: false),
      );
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      expect(find.text('Open with…'), findsOneWidget);
      expect(find.text('Share'), findsNothing);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('a type it will not hand off can only be saved', (
      tester,
    ) async {
      final saver = FakeAttachmentSaver();
      final launcher = FakeAttachmentLauncher();
      final apk = rust_types.AttachmentInfo(
        fileName: 'update.apk',
        mimeType: 'application/vnd.android.package-archive',
        fileSize: BigInt.from(2048),
        fileType: rust_types.FileType.document,
        downloadStatus: rust_types.DownloadStatus.pending,
        blossomUrl: 'https://blossom.example/$kSha',
        sha256: kSha,
        encryptedSize: BigInt.from(2076),
      );
      await _pump(
        tester,
        EncryptedFileMessage(messageId: 'm2', attachment: apk),
        gateway: pdfGateway(
          mimeType: 'application/vnd.android.package-archive',
        ),
        saver: saver,
        launcher: launcher,
      );

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Open with…'), findsNothing);
      expect(find.text('Share'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // Tapping the card saves too, rather than opening.
      await tester.tap(find.text('update.apk'));
      await tester.pumpAndSettle();

      expect(launcher.opened, isEmpty);
      expect(saver.saved, ['transfer.pdf', 'transfer.pdf']);
    });

    testWidgets('declared a PDF, turned out otherwise: save only', (
      tester,
    ) async {
      final launcher = FakeAttachmentLauncher();
      await _pump(
        tester,
        EncryptedFileMessage(messageId: 'm2', attachment: pdfInfo()),
        // Rust reports what the bytes are, not what the sender said.
        gateway: pdfGateway(mimeType: 'application/octet-stream'),
        launcher: launcher,
      );
      await tester.tap(find.text('transfer.pdf'));
      await tester.pumpAndSettle();

      expect(launcher.opened, isEmpty);
      expect(find.text('This type of file can only be saved.'), findsOneWidget);
    });

    testWidgets('a closed save dialog says nothing', (tester) async {
      await _pump(
        tester,
        EncryptedFileMessage(messageId: 'm2', attachment: pdfInfo()),
        gateway: pdfGateway(),
        saver: FakeAttachmentSaver(result: false),
      );
      await pickFromMenu(tester, 'Save');

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed download is reported, not opened', (tester) async {
      final launcher = FakeAttachmentLauncher();
      await _pump(
        tester,
        EncryptedFileMessage(messageId: 'm2', attachment: pdfInfo()),
        gateway: FakeAttachmentGateway(
          downloadResult: (_) async => throw Exception('DownloadFailed: 404'),
        ),
        launcher: launcher,
      );
      await tester.tap(find.text('transfer.pdf'));
      await tester.pumpAndSettle();

      expect(launcher.opened, isEmpty);
      expect(find.text('The file could not be downloaded.'), findsOneWidget);
    });

    testWidgets('DOC and DOCX from v1 are labelled by format', (tester) async {
      rust_types.AttachmentInfo doc(String name, String mime) =>
          rust_types.AttachmentInfo(
            fileName: name,
            mimeType: mime,
            fileSize: BigInt.from(1024),
            fileType: rust_types.FileType.document,
            downloadStatus: rust_types.DownloadStatus.pending,
            blossomUrl: 'https://blossom.example/$kSha',
            sha256: kSha,
            encryptedSize: BigInt.from(1052),
          );
      await _pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EncryptedFileMessage(
              messageId: 'a',
              attachment: doc('a.doc', 'application/msword'),
            ),
            EncryptedFileMessage(
              messageId: 'b',
              attachment: doc(
                'b.docx',
                'application/vnd.openxmlformats-officedocument.'
                    'wordprocessingml.document',
              ),
            ),
            EncryptedFileMessage(
              messageId: 'c',
              attachment: doc('c.mp4', 'video/mp4'),
            ),
          ],
        ),
        gateway: FakeAttachmentGateway(),
      );

      expect(find.text('1 KB · DOC'), findsOneWidget);
      expect(find.text('1 KB · DOCX'), findsOneWidget);
      expect(find.text('1 KB · Video'), findsOneWidget);
    });
  });

  group('UploadBubble', () {
    PendingUpload upload({
      UploadStatus status = UploadStatus.uploading,
      Object? error,
    }) => PendingUpload(
      id: 'u1',
      fileName: 'receipt.png',
      bytes: Uint8List(2048),
      progress: 0.3,
      status: status,
      error: error,
    );

    testWidgets('shows progress while uploading, and no actions', (
      tester,
    ) async {
      await _pump(
        tester,
        UploadBubble(upload: upload(), onRetry: () {}, onDiscard: () {}),
        gateway: FakeAttachmentGateway(),
      );

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.3);
      expect(find.text('Sending… 2 KB'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Discard'), findsNothing);
    });

    testWidgets('a failed upload says why and offers retry and discard', (
      tester,
    ) async {
      var retried = 0;
      var discarded = 0;
      await _pump(
        tester,
        UploadBubble(
          upload: upload(
            status: UploadStatus.failed,
            error: Exception('UploadFailed: none'),
          ),
          onRetry: () => retried++,
          onDiscard: () => discarded++,
        ),
        gateway: FakeAttachmentGateway(),
      );

      expect(
        find.text('The upload failed. Check your connection and try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Discard'));
      expect((retried, discarded), (1, 1));
    });

    testWidgets('a file Rust refused offers only discard', (tester) async {
      await _pump(
        tester,
        UploadBubble(
          upload: upload(
            status: UploadStatus.failed,
            error: Exception('UnsupportedFileType: image/heic'),
          ),
          onRetry: () {},
          onDiscard: () {},
        ),
        gateway: FakeAttachmentGateway(),
      );

      expect(
        find.text('Only JPEG, PNG and PDF files can be sent.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Discard'), findsOneWidget);
    });
  });

  group('MessageBubble', () {
    ChatMessage bubbleMessage(dynamic attachment) => ChatMessage(
      id: 'm3',
      tradeId: 'order-chat',
      content: 'transfer.pdf',
      isMine: false,
      isRead: true,
      hasAttachment: true,
      createdAt: 1000,
      attachment: attachment,
    );

    testWidgets('draws an image attachment as an image bubble', (tester) async {
      await _pump(
        tester,
        MessageBubble(message: bubbleMessage(imageInfo()), peerColorHue: 200),
        gateway: FakeAttachmentGateway(
          downloadResult:
              (_) => Completer<messages_api.AttachmentData>().future,
        ),
      );

      expect(find.byType(EncryptedImageMessage), findsOneWidget);
      expect(find.byType(EncryptedFileMessage), findsNothing);
    });

    testWidgets('draws a document as a file card, not as its name', (
      tester,
    ) async {
      await _pump(
        tester,
        MessageBubble(message: bubbleMessage(pdfInfo()), peerColorHue: 200),
        gateway: FakeAttachmentGateway(),
      );

      expect(find.byType(EncryptedFileMessage), findsOneWidget);
      // The name appears once, in the card — not also as message text.
      expect(find.text('transfer.pdf'), findsOneWidget);
    });
  });
}
