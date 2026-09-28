import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/attachments/attachment_gateway.dart';
import 'package:mostro/features/chat/attachments/attachment_picker.dart';
import 'package:mostro/features/chat/widgets/encrypted_file_message.dart';
import 'package:mostro/features/disputes/providers/dispute_chat_provider.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/disputes/screens/dispute_chat_screen.dart';
import 'package:mostro/features/disputes/widgets/dispute_message_input.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

import '../../support/attachment_fixtures.dart';
import '../../support/provider_harness.dart';

const _trade = 'order-dispute';
const _disputeId = 'dispute-1';
const _solver = 'solver-pubkey';

rust_types.ChatMessage _message({
  required String id,
  rust_types.MessageType type = rust_types.MessageType.admin,
  bool isMine = false,
  String content = 'hello',
  rust_types.AttachmentInfo? attachment,
  int createdAt = 1000,
}) => rust_types.ChatMessage(
  id: id,
  tradeId: _trade,
  senderPubkey: isMine ? 'me' : _solver,
  content: attachment?.fileName ?? content,
  messageType: type,
  isMine: isMine,
  isRead: true,
  hasAttachment: attachment != null,
  attachment: attachment,
  createdAt: intToPlatformInt64(createdAt),
);

DisputeItem _dispute({
  DisputeStatus status = DisputeStatus.inReview,
  String? adminPubkey = _solver,
}) => DisputeItem(
  id: _disputeId,
  tradeId: _trade,
  status: status,
  initiatedByMe: true,
  openedAt: 100,
  adminPubkey: adminPubkey,
);

/// Answers the dispute chat's text sends with what the test set.
class _FakeDisputeGateway extends DisputeChatGateway {
  _FakeDisputeGateway(this.onSend, {this.refresh});

  final Future<rust_types.ChatMessage> Function(String text) onSend;

  /// What `getDispute` answers; null when absent.
  final Future<rust_types.Dispute?> Function()? refresh;
  final texts = <String>[];

  @override
  Future<rust_types.ChatMessage> sendText({
    required String tradeId,
    required String text,
  }) {
    texts.add(text);
    return onSend(text);
  }

  @override
  Future<rust_types.Dispute?> getDispute(String tradeId) =>
      refresh?.call() ?? Future.value();
}

rust_types.Dispute _bridgeDispute({
  rust_types.DisputeStatus status = rust_types.DisputeStatus.inReview,
  rust_types.DisputeResolution? resolution,
}) => rust_types.Dispute(
  id: _disputeId,
  tradeId: _trade,
  status: status,
  initiatedByMe: true,
  adminPubkey: _solver,
  resolution: resolution,
  openedAt: intToPlatformInt64(100),
  resolvedAt: resolution == null ? null : intToPlatformInt64(200),
  isRead: true,
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required DisputeItem dispute,
  List<rust_types.ChatMessage> history = const [],
  _FakeDisputeGateway? disputeGateway,
  FakeAttachmentGateway? attachments,
  FakeAttachmentPicker? picker,
  Stream<rust_types.Dispute>? updates,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = createContainer(
    overrides: [
      disputeChatProvider(
        _trade,
      ).overrideWith((ref) => DisputeChatNotifier(() async => history)),
      disputeUpdatesProvider(_trade).overrideWith(
        (ref) => updates ?? const Stream<rust_types.Dispute>.empty(),
      ),
      disputeChatGatewayProvider.overrideWithValue(
        disputeGateway ?? _FakeDisputeGateway((_) => Completer<Never>().future),
      ),
      attachmentGatewayProvider.overrideWithValue(
        attachments ?? FakeAttachmentGateway(),
      ),
      attachmentPickerProvider.overrideWithValue(
        picker ?? FakeAttachmentPicker((_) => const PickCancelled()),
      ),
      // Memory-only: the sembast store does real I/O, which never completes
      // under the widget tester's fake clock.
      notificationsProvider.overrideWith((ref) => NotificationsNotifier()),
    ],
  );
  container.read(disputeNotifierProvider.notifier).upsert(dispute);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DisputeChatScreen(disputeId: _disputeId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('DisputeChatNotifier', () {
    test('keeps the solver conversation only, each message once', () async {
      final notifier = DisputeChatNotifier(
        () async => [
          _message(id: 'peer', type: rust_types.MessageType.peer),
          _message(id: 'a1'),
        ],
      );
      addTearDown(notifier.dispose);
      await pumpEventQueue();

      // The live stream repeats one history already had.
      notifier
        ..add(_message(id: 'a1'))
        ..add(_message(id: 'a2', isMine: true))
        ..add(_message(id: 'peer-2', type: rust_types.MessageType.peer));

      expect(notifier.state.map((m) => m.id), ['a1', 'a2']);
      expect(notifier.state.first.isAdmin, isTrue);
      expect(notifier.state.last.isMine, isTrue);
      expect(notifier.state.last.isAdmin, isFalse);
    });

    test('a failed history load leaves the live messages', () async {
      final notifier = DisputeChatNotifier(
        () async => throw Exception('bridge down'),
      );
      addTearDown(notifier.dispose);
      notifier.add(_message(id: 'a1'));
      await pumpEventQueue();

      expect(notifier.state.map((m) => m.id), ['a1']);
    });

    test('carries an attachment through', () {
      final msg = disputeMessageFromRust(
        _message(id: 'f', attachment: pdfInfo()),
      );
      expect(msg.attachment?.fileName, 'transfer.pdf');
      expect(msg.content, 'transfer.pdf');
    });
  });

  group('DisputeNotifier.applyBridgeUpdate', () {
    test("takes the bridge's state and keeps the UI's own fields", () {
      final notifier =
          DisputeNotifier()..upsert(
            _dispute(status: DisputeStatus.open, adminPubkey: null).copyWith(
              isRead: true,
              peerHandle: 'brave-otter',
              isSelling: true,
            ),
          );
      addTearDown(notifier.dispose);

      // The bridge may know the dispute under another id (a placeholder
      // minted before the daemon's): the trade is what matches.
      notifier.applyBridgeUpdate(
        const DisputeItem(
          id: 'daemon-id',
          tradeId: _trade,
          status: DisputeStatus.inReview,
          initiatedByMe: true,
          openedAt: 100,
          adminPubkey: _solver,
        ),
      );

      final item = notifier.state.single;
      expect(item.id, _disputeId);
      expect(item.status, DisputeStatus.inReview);
      expect(item.adminPubkey, _solver);
      expect(item.isRead, isTrue);
      expect(item.peerHandle, 'brave-otter');
      expect(item.isSelling, isTrue);
    });

    test('a field the bridge clears is cleared', () {
      final notifier = DisputeNotifier()..upsert(_dispute());
      addTearDown(notifier.dispose);
      notifier.applyBridgeUpdate(
        _dispute(status: DisputeStatus.open, adminPubkey: null),
      );
      expect(notifier.state.single.adminPubkey, isNull);
    });

    test('inserts a dispute the UI did not know', () {
      final notifier = DisputeNotifier();
      addTearDown(notifier.dispose);
      notifier.applyBridgeUpdate(_dispute());
      expect(notifier.state.single.id, _disputeId);
    });
  });

  test('send errors map to their message', () {
    final l10n = AppLocalizationsEn();
    expect(
      disputeSendErrorMessage(l10n, Exception('AdminNotAssigned: no admin')),
      l10n.disputeSolverNotAssigned,
    );
    expect(
      disputeSendErrorMessage(l10n, Exception('NoOpenDispute: resolved')),
      l10n.disputeChatClosed,
    );
    expect(
      disputeSendErrorMessage(l10n, Exception('SendFailed: relays')),
      l10n.messageSendFailed,
    );
  });

  group('DisputeChatScreen', () {
    testWidgets('a verdict arriving live closes the chat', (tester) async {
      final updates = StreamController<rust_types.Dispute>();
      addTearDown(updates.close);
      await _pumpScreen(tester, dispute: _dispute(), updates: updates.stream);
      expect(find.byType(DisputeMessageInput), findsOneWidget);

      updates.add(
        _bridgeDispute(
          status: rust_types.DisputeStatus.resolved,
          resolution: rust_types.DisputeResolution.fundsToBuyer,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(DisputeMessageInput), findsNothing);
    });

    testWidgets('a refresh a live update overtook is dropped', (tester) async {
      final refresh = Completer<rust_types.Dispute?>();
      final updates = StreamController<rust_types.Dispute>();
      addTearDown(updates.close);
      await _pumpScreen(
        tester,
        dispute: _dispute(),
        updates: updates.stream,
        disputeGateway: _FakeDisputeGateway(
          (_) => Completer<Never>().future,
          refresh: () => refresh.future,
        ),
      );

      // The verdict lands while the refresh on open is still out…
      updates.add(
        _bridgeDispute(
          status: rust_types.DisputeStatus.resolved,
          resolution: rust_types.DisputeResolution.fundsToSeller,
        ),
      );
      await tester.pump();
      // …which then answers with the record from before it.
      refresh.complete(_bridgeDispute());
      await tester.pump();
      await tester.pump();

      expect(find.byType(DisputeMessageInput), findsNothing);
    });

    testWidgets('has no composer until a solver takes the dispute', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        dispute: _dispute(status: DisputeStatus.open, adminPubkey: null),
      );
      expect(find.byType(DisputeMessageInput), findsNothing);
    });

    testWidgets('shows the history with the solver, attachments included', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        dispute: _dispute(),
        history: [
          _message(id: 'a1', content: 'Please send the receipt'),
          _message(
            id: 'p1',
            type: rust_types.MessageType.peer,
            content: 'peer only',
          ),
          _message(
            id: 'f1',
            isMine: true,
            attachment: pdfInfo(),
            createdAt: 1100,
          ),
        ],
      );

      expect(find.byType(DisputeMessageInput), findsOneWidget);
      expect(find.text('Please send the receipt'), findsOneWidget);
      expect(find.text('peer only'), findsNothing);
      expect(find.byType(EncryptedFileMessage), findsOneWidget);
    });

    testWidgets('sends text to the solver and shows it', (tester) async {
      final gateway = _FakeDisputeGateway(
        (text) async => _message(id: 'sent', isMine: true, content: text),
      );
      await _pumpScreen(tester, dispute: _dispute(), disputeGateway: gateway);

      await tester.enterText(find.byType(TextField), 'Here is my proof');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      expect(gateway.texts, ['Here is my proof']);
      expect(find.text('Here is my proof'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('keeps the text when the solver cannot be reached', (
      tester,
    ) async {
      final gateway = _FakeDisputeGateway(
        (_) async => throw Exception('AdminNotAssigned: no admin'),
      );
      await _pumpScreen(tester, dispute: _dispute(), disputeGateway: gateway);

      await tester.enterText(find.byType(TextField), 'Are you there?');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text(AppLocalizationsEn().disputeSolverNotAssigned),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Are you there?');
    });

    testWidgets('sends a picked file to the solver, not the peer', (
      tester,
    ) async {
      final done = Completer<rust_types.ChatMessage>();
      final attachments = FakeAttachmentGateway(sendResult: (_) => done.future);
      await _pumpScreen(
        tester,
        dispute: _dispute(),
        attachments: attachments,
        picker: FakeAttachmentPicker(
          (_) => Picked(pickedFile(name: 'receipt.pdf', size: 2048)),
        ),
      );

      await tester.tap(find.byTooltip('Attach file'));
      await tester.pumpAndSettle();
      // Only the solver can open it, and the sheet says so.
      expect(
        find.text(AppLocalizationsEn().attachSheetBodySolver),
        findsOneWidget,
      );
      await tester.tap(find.text('PDF document'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Send').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(attachments.solverSends.single.tradeId, _trade);
      expect(attachments.solverSends.single.fileName, 'receipt.pdf');
      expect(attachments.sends, isEmpty);

      done.complete(
        _message(
          id: 'f1',
          isMine: true,
          attachment: pdfInfo(fileName: 'receipt.pdf'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(EncryptedFileMessage), findsOneWidget);
    });
  });
}
