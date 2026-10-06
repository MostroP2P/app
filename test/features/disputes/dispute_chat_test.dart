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
import 'package:mostro/features/disputes/widgets/share_chat_key_action.dart';
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
const _serbero = 'serbero-pubkey';

rust_types.ChatMessage _message({
  required String id,
  rust_types.MessageType type = rust_types.MessageType.admin,
  bool isMine = false,
  String content = 'hello',
  rust_types.AttachmentInfo? attachment,
  int createdAt = 1000,
  String sender = _solver,
}) => rust_types.ChatMessage(
  id: id,
  tradeId: _trade,
  senderPubkey: isMine ? 'me' : sender,
  content: attachment?.fileName ?? content,
  messageType: type,
  isMine: isMine,
  isRead: true,
  hasAttachment: attachment != null,
  attachment: attachment,
  createdAt: intToPlatformInt64(createdAt),
  reactions: const [],
);

DisputeItem _dispute({
  DisputeStatus status = DisputeStatus.inReview,
  String? adminPubkey = _solver,
  bool chatKeyShared = false,
}) => DisputeItem(
  id: _disputeId,
  tradeId: _trade,
  status: status,
  initiatedByMe: true,
  openedAt: 100,
  adminPubkey: adminPubkey,
  chatKeyShared: chatKeyShared,
);

/// Answers the dispute chat's text sends with what the test set.
class _FakeDisputeGateway extends DisputeChatGateway {
  _FakeDisputeGateway(
    this.onSend, {
    this.refresh,
    this.assistants = const {},
    this.onShareKey,
  });

  final Future<rust_types.ChatMessage> Function(String text) onSend;

  /// What sharing the chat key answers; never answers when absent.
  final Future<rust_types.ChatMessage> Function()? onShareKey;

  /// The trades whose chat key was sent.
  final keyShares = <String>[];

  /// The solver pubkeys a node announces as its Serbero.
  final Set<String> assistants;

  /// The trades whose solvers were asked about.
  final roleTrades = <String>{};

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
  Future<rust_types.ChatMessage> shareChatKey(String tradeId) {
    keyShares.add(tradeId);
    return onShareKey?.call() ?? Completer<rust_types.ChatMessage>().future;
  }

  @override
  Future<rust_types.Dispute?> getDispute(String tradeId) =>
      refresh?.call() ?? Future.value();

  @override
  Future<rust_types.SolverRole> solverRole(
    String tradeId,
    String solverPubkey,
  ) async {
    roleTrades.add(tradeId);
    return assistants.contains(solverPubkey)
        ? rust_types.SolverRole.assistant
        : rust_types.SolverRole.human;
  }
}

rust_types.Dispute _bridgeDispute({
  rust_types.DisputeStatus status = rust_types.DisputeStatus.inReview,
  rust_types.DisputeResolution? resolution,
  bool chatKeyShared = false,
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
  chatKeyShared: chatKeyShared,
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required DisputeItem dispute,
  List<rust_types.ChatMessage> history = const [],
  _FakeDisputeGateway? disputeGateway,
  FakeAttachmentGateway? attachments,
  FakeAttachmentPicker? picker,
  Stream<rust_types.Dispute>? updates,
  Size size = const Size(400, 800),
  Locale? locale,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
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
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
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

    test('takes whether the solver has the chat key', () {
      final notifier = DisputeNotifier()..upsert(_dispute());
      addTearDown(notifier.dispose);
      notifier.applyBridgeUpdate(_dispute(chatKeyShared: true));
      expect(notifier.state.single.chatKeyShared, isTrue);
      notifier.applyBridgeUpdate(_dispute());
      expect(notifier.state.single.chatKeyShared, isFalse);
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

  group('solver roles (#637)', () {
    final l10n = AppLocalizationsEn();
    _FakeDisputeGateway serberoNode() => _FakeDisputeGateway(
      (_) => Completer<Never>().future,
      assistants: {_serbero},
    );

    testWidgets('labels Serbero and the resolver who took the case over', (
      tester,
    ) async {
      // Arrange: Serbero talked first, then a person took the dispute.
      final gateway = serberoNode();
      await _pumpScreen(
        tester,
        dispute: _dispute(),
        disputeGateway: gateway,
        history: [
          _message(id: 's1', sender: _serbero, content: 'Hi, I am Serbero'),
          _message(id: 'm1', isMine: true, content: 'Hi', createdAt: 1100),
          _message(id: 'h1', content: 'Resolver here', createdAt: 1200),
        ],
      );
      await tester.pump();

      // Assert
      expect(find.text(l10n.serberoLabel), findsOneWidget);
      expect(find.text(l10n.solverLabel), findsOneWidget);
      final line = find.text(l10n.disputeSolverTookOver);
      expect(line, findsOneWidget);
      expect(
        tester.getTopLeft(line).dy,
        greaterThan(tester.getTopLeft(find.text('Hi')).dy),
        reason: 'the takeover line follows the conversation with Serbero',
      );
      expect(
        tester.getTopLeft(line).dy,
        lessThan(tester.getTopLeft(find.text('Resolver here')).dy),
        reason: 'and comes before the resolver speaks',
      );
      expect(
        gateway.roleTrades,
        {_trade},
        reason: "only the dispute's own node can vouch for its Serbero",
      );
    });

    testWidgets('marks a takeover the resolver has not spoken in yet', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        dispute: _dispute(),
        disputeGateway: serberoNode(),
        history: [
          _message(id: 's1', sender: _serbero, content: 'Hi, I am Serbero'),
        ],
      );
      await tester.pump();

      expect(find.text(l10n.disputeSolverTookOver), findsOneWidget);
    });

    testWidgets('while Serbero holds the dispute, it is named and no takeover '
        'is shown', (tester) async {
      await _pumpScreen(
        tester,
        dispute: _dispute(adminPubkey: _serbero),
        disputeGateway: serberoNode(),
      );
      await tester.pump();

      expect(find.text(l10n.disputeSerberoAssigned), findsOneWidget);
      expect(find.text(l10n.disputeSolverTookOver), findsNothing);
    });

    testWidgets('a dispute update reads the solver roles again', (
      tester,
    ) async {
      // Arrange: the history lands before the node's announcement.
      final assistants = <String>{};
      final updates = StreamController<rust_types.Dispute>();
      addTearDown(updates.close);
      await _pumpScreen(
        tester,
        dispute: _dispute(adminPubkey: _serbero),
        disputeGateway: _FakeDisputeGateway(
          (_) => Completer<Never>().future,
          assistants: assistants,
        ),
        updates: updates.stream,
        history: [_message(id: 's1', sender: _serbero, content: 'Hi')],
      );
      await tester.pump();
      expect(find.text(l10n.solverLabel), findsOneWidget);

      // Act: the announcement arrives, then an update of the dispute.
      assistants.add(_serbero);
      updates.add(_bridgeDispute());
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      // Assert
      expect(find.text(l10n.serberoLabel), findsOneWidget);
    });

    testWidgets('a node without Serbero shows every solver as a resolver', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        dispute: _dispute(),
        history: [_message(id: 'h1', content: 'Resolver here')],
      );
      await tester.pump();

      expect(find.text(l10n.solverLabel), findsOneWidget);
      expect(find.text(l10n.serberoLabel), findsNothing);
      expect(find.text(l10n.disputeSolverTookOver), findsNothing);
    });
  });

  group('chat key share (#415)', () {
    final l10n = AppLocalizationsEn();
    const keyText = 'Shared key: 0123abcd';

    testWidgets('is not offered until a solver takes the dispute', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        dispute: _dispute(status: DisputeStatus.open, adminPubkey: null),
      );
      expect(find.byTooltip(l10n.shareChatKeyAction), findsNothing);
      expect(find.byTooltip(l10n.chatKeySharedIndicator), findsNothing);
    });

    testWidgets('is not offered on a resolved dispute', (tester) async {
      await _pumpScreen(
        tester,
        dispute: _dispute(status: DisputeStatus.resolved),
      );
      expect(find.byTooltip(l10n.shareChatKeyAction), findsNothing);
    });

    testWidgets('once the solver has the key, says so and still offers it', (
      tester,
    ) async {
      // Arrange: shared already, perhaps with Serbero before a human took
      // over, or the user just wants to send it again.
      final gateway = _FakeDisputeGateway(
        (_) => Completer<Never>().future,
        onShareKey:
            () async => _message(id: 'key', isMine: true, content: keyText),
      );
      await _pumpScreen(
        tester,
        dispute: _dispute(chatKeyShared: true),
        disputeGateway: gateway,
      );
      expect(find.byTooltip(l10n.shareChatKeyAction), findsNothing);

      // Act
      await tester.tap(find.byTooltip(l10n.chatKeySharedIndicator));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.shareChatKeyConfirm));
      await tester.pumpAndSettle();

      // Assert
      expect(gateway.keyShares, [_trade]);
      expect(find.text(keyText), findsOneWidget);
    });

    testWidgets('cancelling sends nothing', (tester) async {
      final gateway = _FakeDisputeGateway((_) => Completer<Never>().future);
      await _pumpScreen(tester, dispute: _dispute(), disputeGateway: gateway);

      await tester.tap(find.byTooltip(l10n.shareChatKeyAction));
      await tester.pumpAndSettle();
      expect(find.text(l10n.shareChatKeyTitle), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();

      expect(gateway.keyShares, isEmpty);
      expect(find.text(l10n.shareChatKeyTitle), findsNothing);
    });

    testWidgets('confirming sends it, marks it shared and can send it again', (
      tester,
    ) async {
      // Arrange: the record reads shared once the key went.
      var sent = false;
      final gateway = _FakeDisputeGateway(
        (_) => Completer<Never>().future,
        onShareKey: () async {
          sent = true;
          return _message(id: 'key', isMine: true, content: keyText);
        },
        refresh: () async => _bridgeDispute(chatKeyShared: sent),
      );
      await _pumpScreen(tester, dispute: _dispute(), disputeGateway: gateway);

      // Act
      await tester.tap(find.byTooltip(l10n.shareChatKeyAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.shareChatKeyConfirm));
      await tester.pumpAndSettle();

      // Assert
      expect(gateway.keyShares, [_trade]);
      expect(find.text(l10n.shareChatKeyTitle), findsNothing);
      expect(find.text(keyText), findsOneWidget);
      expect(find.byTooltip(l10n.shareChatKeyAction), findsNothing);
      expect(find.byTooltip(l10n.chatKeySharedIndicator), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.chatKeySharedIndicator));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.shareChatKeyConfirm));
      await tester.pumpAndSettle();

      expect(gateway.keyShares, [_trade, _trade]);
    });

    testWidgets('a failure stays in the dialog, which can try again', (
      tester,
    ) async {
      var attempts = 0;
      final gateway = _FakeDisputeGateway(
        (_) => Completer<Never>().future,
        onShareKey: () async {
          attempts++;
          if (attempts == 1) throw Exception('NoSharedKey: peer unknown');
          return _message(id: 'key', isMine: true, content: keyText);
        },
      );
      await _pumpScreen(tester, dispute: _dispute(), disputeGateway: gateway);

      await tester.tap(find.byTooltip(l10n.shareChatKeyAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.shareChatKeyConfirm));
      await tester.pumpAndSettle();

      expect(find.text(l10n.shareChatKeyTitle), findsOneWidget);
      expect(find.text(l10n.shareChatKeyUnavailable), findsOneWidget);

      await tester.tap(find.text(l10n.shareChatKeyConfirm));
      await tester.pumpAndSettle();

      expect(gateway.keyShares, [_trade, _trade]);
      expect(find.text(l10n.shareChatKeyTitle), findsNothing);
      expect(find.text(keyText), findsOneWidget);
    });

    test('share errors map to their message', () {
      expect(
        shareChatKeyErrorMessage(l10n, Exception('AdminNotAssigned: none')),
        l10n.disputeSolverNotAssigned,
      );
      expect(
        shareChatKeyErrorMessage(l10n, Exception('NoOpenDispute: resolved')),
        l10n.disputeChatClosed,
      );
      expect(
        shareChatKeyErrorMessage(l10n, Exception('TradeNotFound: no key')),
        l10n.shareChatKeyUnavailable,
      );
      expect(
        shareChatKeyErrorMessage(l10n, Exception('SendFailed: no relay')),
        l10n.messageSendFailed,
      );
    });

    // DS-A11Y-4: the longest copy, at twice the text size, on a narrow phone.
    for (final shared in [false, true]) {
      testWidgets('the app bar fits in German at 2x text, 320 dp '
          '(shared: $shared)', (tester) async {
        await _pumpScreen(
          tester,
          dispute: _dispute(chatKeyShared: shared),
          size: const Size(320, 640),
          locale: const Locale('de'),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      });
    }

    for (final brightness in Brightness.values) {
      testWidgets('the dialog fits in German at 2x text, 320 dp '
          '(${brightness.name})', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme:
                brightness == Brightness.dark
                    ? buildDarkTheme()
                    : buildLightTheme(),
            locale: const Locale('de'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
            home: Scaffold(
              body: ShareChatKeyDialog(
                share: () async => throw Exception('NoSharedKey: unknown'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Teilen'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
