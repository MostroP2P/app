import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/attachments/attachment_gateway.dart';
import 'package:mostro/features/chat/attachments/upload_controller.dart';
import 'package:mostro/features/chat/widgets/message_bubble.dart';
import 'package:mostro/features/chat/widgets/upload_bubble.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../../support/attachment_fixtures.dart';
import '../../../support/load_app_fonts.dart';
import '../../../support/provider_harness.dart';

/// A stand-in for a transfer screenshot: a light card with a few bars.
Future<Uint8List> _receiptPng(WidgetTester tester) async {
  return (await tester.runAsync(() async {
    const w = 240.0, h = 180.0;
    final recorder = ui.PictureRecorder();
    final canvas =
        ui.Canvas(recorder)
          ..drawRect(
            const Rect.fromLTWH(0, 0, w, h),
            Paint()..color = const Color(0xFFF1F4F8),
          )
          ..drawRect(
            const Rect.fromLTWH(0, 0, w, 36),
            Paint()..color = const Color(0xFF2E6BD9),
          );
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(
        Rect.fromLTWH(16, 52 + i * 28.0, i.isEven ? 150 : 110, 12),
        Paint()..color = const Color(0xFFB7C0CC),
      );
    }
    final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }))!;
}

ChatMessage _bubble(String id, dynamic attachment, {required bool isMine}) =>
    ChatMessage(
      id: id,
      tradeId: 'order-chat',
      content: attachment.fileName as String,
      isMine: isMine,
      isRead: true,
      hasAttachment: true,
      // 10:24 UTC; CI renders goldens in UTC.
      createdAt: 1767954240,
      attachment: attachment,
    );

/// The attachment bubbles of #589 phase 2: a received image, a sent PDF,
/// and an upload in flight and failed. 360 wide, `en`, dark and light.
void main() {
  setUpAll(loadAppFonts);

  for (final (mode, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    testWidgets('attachment bubbles · $mode', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final png = await _receiptPng(tester);
      final gateway = FakeAttachmentGateway(
        downloadResult: (_) async => attachmentData(png, mimeType: 'image/png'),
      );
      final container = createContainer(
        overrides: [attachmentGatewayProvider.overrideWithValue(gateway)],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme:
                brightness == Brightness.dark
                    ? buildDarkTheme()
                    : buildLightTheme(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ListView(
                children: [
                  MessageBubble(
                    message: _bubble(
                      'm1',
                      imageInfo(width: 240, height: 180),
                      isMine: false,
                    ),
                    peerColorHue: 200,
                  ),
                  MessageBubble(
                    message: _bubble('m2', pdfInfo(), isMine: true),
                    peerColorHue: 200,
                  ),
                  UploadBubble(
                    upload: PendingUpload(
                      id: 'u1',
                      fileName: 'receipt.png',
                      bytes: Uint8List(524288),
                      progress: 0.3,
                    ),
                    onRetry: () {},
                    onDiscard: () {},
                  ),
                  UploadBubble(
                    upload: PendingUpload(
                      id: 'u2',
                      fileName: 'statement.pdf',
                      bytes: Uint8List(1468006),
                      status: UploadStatus.failed,
                      error: Exception('UploadFailed: every server refused'),
                    ),
                    onRetry: () {},
                    onDiscard: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/attachment_bubbles_$mode.png'),
      );
    });
  }
}
