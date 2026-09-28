import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/attachments/attachment_gateway.dart';
import 'package:mostro/features/chat/attachments/attachment_picker.dart';
import 'package:mostro/features/chat/models/chat_list_rules.dart';
import 'package:mostro/features/chat/providers/chat_list_provider.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/chat/screens/chat_room_screen.dart';
import 'package:mostro/features/chat/widgets/encrypted_file_message.dart';
import 'package:mostro/features/chat/widgets/trade_state_header.dart';
import 'package:mostro/features/chat/widgets/upload_bubble.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

import '../../support/attachment_fixtures.dart';
import '../../support/provider_harness.dart';

const _orderId = 'order-chat';

/// Pumps [ChatRoomScreen] as `chat_room_screen_test.dart` does — without
/// `RustLib.init()`, so history and mark-read fail quietly — with the
/// picker and the attachment gateway replaced.
Future<void> _pumpRoom(
  WidgetTester tester, {
  required FakeAttachmentPicker picker,
  required FakeAttachmentGateway gateway,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = createContainer(
    overrides: [
      incomingMessageProvider(
        _orderId,
      ).overrideWith((ref) => const Stream<rust_types.ChatMessage>.empty()),
      chatTradeOrderProvider(_orderId).overrideWith((ref) async => null),
      orderBookNotificationCountProvider.overrideWith((ref) => 0),
      chatRowStateProvider(_orderId).overrideWithValue(
        const ChatRowState(
          group: ChatGroup.active,
          tone: ChatAvatarTone.yourTurn,
        ),
      ),
      attachmentPickerProvider.overrideWithValue(picker),
      attachmentGatewayProvider.overrideWithValue(gateway),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ChatRoomScreen(orderId: _orderId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _openSheetAndPick(WidgetTester tester, String row) async {
  await tester.tap(find.byTooltip('Attach file'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(row));
  await _settleDialog(tester);
}

/// The composer's spinner turns while the confirmation is open, so the tree
/// never settles: step past the route transitions instead.
Future<void> _settleDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('offers photo and PDF, and the camera only where there is one', (
    tester,
  ) async {
    await _pumpRoom(
      tester,
      picker: FakeAttachmentPicker((_) => const PickCancelled()),
      gateway: FakeAttachmentGateway(),
    );

    await tester.tap(find.byTooltip('Attach file'));
    await tester.pumpAndSettle();

    expect(find.text('Send a file'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('PDF document'), findsOneWidget);
    expect(find.text('Camera'), findsNothing);
  });

  testWidgets('confirm, upload, then the sent file joins the conversation', (
    tester,
  ) async {
    final done = Completer<rust_types.ChatMessage>();
    final gateway = FakeAttachmentGateway(sendResult: (_) => done.future);
    final picker = FakeAttachmentPicker(
      (_) => Picked(pickedFile(name: 'transfer.pdf', size: 2048)),
    );
    await _pumpRoom(tester, picker: picker, gateway: gateway);

    await _openSheetAndPick(tester, 'PDF document');

    expect(picker.picked, [AttachmentSource.pdf]);
    expect(find.text('Send this file?'), findsOneWidget);
    expect(find.text('transfer.pdf (2 KB)'), findsOneWidget);

    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump();

    expect(gateway.sends.single.fileName, 'transfer.pdf');
    expect(gateway.sends.single.bytes, 2048);
    expect(find.byType(UploadBubble), findsOneWidget);

    done.complete(
      attachmentMessage(id: 'evt-1', tradeId: _orderId, attachment: pdfInfo()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UploadBubble), findsNothing);
    expect(find.byType(EncryptedFileMessage), findsOneWidget);
  });

  testWidgets('cancelling the confirmation sends nothing', (tester) async {
    final gateway = FakeAttachmentGateway();
    await _pumpRoom(
      tester,
      picker: FakeAttachmentPicker((_) => Picked(pickedFile())),
      gateway: gateway,
    );

    await _openSheetAndPick(tester, 'Photo');
    await tester.tap(find.text('Cancel'));
    await _settleDialog(tester);
    await tester.pumpAndSettle();

    expect(gateway.sends, isEmpty);
    expect(find.byType(UploadBubble), findsNothing);
  });

  testWidgets('a file over 25 MB is refused before it is read', (tester) async {
    final gateway = FakeAttachmentGateway();
    await _pumpRoom(
      tester,
      picker: FakeAttachmentPicker(
        (_) => const PickTooLarge('video.pdf', kMaxAttachmentBytes + 1),
      ),
      gateway: gateway,
    );

    await _openSheetAndPick(tester, 'PDF document');

    expect(find.text('Files can be up to 25 MB.'), findsOneWidget);
    expect(find.text('Send this file?'), findsNothing);
    expect(gateway.sends, isEmpty);
  });

  testWidgets('a failed upload stays as a bubble that can be retried', (
    tester,
  ) async {
    var attempt = 0;
    final gateway = FakeAttachmentGateway(
      sendResult: (_) async {
        if (attempt++ == 0) throw Exception('UploadFailed: none');
        return attachmentMessage(
          id: 'evt-2',
          tradeId: _orderId,
          attachment: pdfInfo(),
        );
      },
    );
    await _pumpRoom(
      tester,
      picker: FakeAttachmentPicker(
        (_) => Picked(pickedFile(name: 'transfer.pdf')),
      ),
      gateway: gateway,
    );

    await _openSheetAndPick(tester, 'PDF document');
    await tester.tap(find.text('Send'));
    await _settleDialog(tester);
    await tester.pumpAndSettle();

    expect(find.byType(UploadBubble), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(gateway.sends, hasLength(2));
    expect(find.byType(UploadBubble), findsNothing);
    expect(find.byType(EncryptedFileMessage), findsOneWidget);
  });
}
