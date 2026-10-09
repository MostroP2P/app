import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/disputes/providers/dispute_chat_provider.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/disputes/screens/dispute_chat_screen.dart';
import 'package:mostro/features/disputes/widgets/dispute_info_card.dart';
import 'package:mostro/features/disputes/widgets/dispute_message_input.dart';
import 'package:mostro/features/disputes/widgets/dispute_messages_list.dart';
import 'package:mostro/features/disputes/widgets/dispute_title_row.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/features/trades/widgets/trade_list_chip.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_de.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

import '../../support/fake_trades.dart';
import '../../support/load_app_fonts.dart';
import '../../support/provider_harness.dart';

// Full-length ids: the card must show them whole, never shortened.
const _trade = '7f2c9d4e-1a3b-4c5d-8e9f-0a1b2c3d4e5f';
const _disputeId = 'b81e6a52-93cd-4f07-a2e4-5c6d7e8f9a0b';
const _solver = 'solver-pubkey';
const _peer = 'sovereign-crusader';

final _en = AppLocalizationsEn();

DisputeItem _dispute({
  DisputeStatus status = DisputeStatus.inReview,
  String? adminPubkey = _solver,
  bool initiatedByMe = true,
  DisputeResolution? resolution,
}) => DisputeItem(
  id: _disputeId,
  tradeId: _trade,
  status: status,
  initiatedByMe: initiatedByMe,
  openedAt: 100,
  adminPubkey: adminPubkey,
  resolution: resolution,
);

class _QuietGateway extends DisputeChatGateway {
  @override
  Future<rust_types.ChatMessage> sendText({
    required String tradeId,
    required String text,
  }) => Completer<rust_types.ChatMessage>().future;

  @override
  Future<rust_types.Dispute?> getDispute(String tradeId) => Future.value();

  @override
  Future<rust_types.SolverRole> solverRole(
    String tradeId,
    String solverPubkey,
  ) async => rust_types.SolverRole.human;
}

rust_types.ChatMessage _solverMessage(String content, {int createdAt = 1000}) =>
    rust_types.ChatMessage(
      id: 'm-$content',
      tradeId: _trade,
      senderPubkey: _solver,
      content: content,
      messageType: rust_types.MessageType.admin,
      isMine: false,
      isRead: true,
      hasAttachment: false,
      createdAt: intToPlatformInt64(createdAt),
      reactions: const [],
    );

/// Pumps the dispute chat with the trade row the card resolves its role and
/// counterparty from. A null [role] leaves the trade unknown.
Future<void> _pump(
  WidgetTester tester, {
  required DisputeItem dispute,
  rust_types.TradeRole? role = rust_types.TradeRole.buyer,
  Locale locale = const Locale('en'),
  Size size = const Size(400, 800),
  double textScale = 1,
  List<rust_types.ChatMessage> history = const [],
  bool advanceTime = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final container = createContainer(
    overrides: [
      disputeChatProvider(
        _trade,
      ).overrideWith((ref) => DisputeChatNotifier(() async => history)),
      disputeUpdatesProvider(
        _trade,
      ).overrideWith((ref) => const Stream<rust_types.Dispute>.empty()),
      disputeChatGatewayProvider.overrideWithValue(_QuietGateway()),
      notificationsProvider.overrideWith((ref) => NotificationsNotifier()),
      rawTradesProvider.overrideWith(
        (ref) async => [
          if (role != null)
            fakeTrade(
              orderId: _trade,
              role: role,
              status: rust_types.OrderStatus.dispute,
            ),
        ],
      ),
      nymLookupProvider.overrideWithValue(
        (pubkey) async => const rust_types.NymIdentity(
          pseudonym: _peer,
          iconIndex: 3,
          colorHue: 120,
        ),
      ),
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
        home: const DisputeChatScreen(disputeId: _disputeId),
      ),
    ),
  );
  // Trade row, pseudonym and history resolve, then the list scrolls.
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
  if (advanceTime) await tester.pump(const Duration(milliseconds: 300));
}

/// The chat's scroll position.
ScrollPosition _chatPosition(WidgetTester tester) =>
    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(DisputeMessagesList),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;

Finder _inCard(Finder matching) =>
    find.descendant(of: find.byType(DisputeInfoCard), matching: matching);

/// The chip's caption, as it renders: upper case.
Finder _chip(String caption) => find.descendant(
  of: find.byType(TradeListChip),
  matching: find.text(caption.toUpperCase()),
);

void main() {
  group('DisputeInfoCard', () {
    testWidgets('opens the chat: title with role and counterparty, chip', (
      tester,
    ) async {
      await _pump(tester, dispute: _dispute());

      expect(find.byType(DisputeInfoCard), findsOneWidget);
      // A buyer's dispute is with the seller.
      expect(
        _inCard(find.text(_en.disputeWith(_en.seller, _peer))),
        findsOneWidget,
      );
      expect(_inCard(_chip(_en.disputeStatusInProgress)), findsOneWidget);
      // Said once: the app bar no longer repeats the card's title.
      expect(find.text(_en.disputeWith(_en.seller, _peer)), findsOneWidget);
    });

    testWidgets('a short chip leaves the title more than half the row', (
      tester,
    ) async {
      await _pump(tester, dispute: _dispute());

      final title = _inCard(find.text(_en.disputeWith(_en.seller, _peer)));
      final row = _inCard(find.byType(DisputeTitleRow));
      expect(
        tester.getSize(title).width,
        greaterThan(tester.getSize(row).width / 2),
      );
    });

    testWidgets('a seller\'s dispute is with the buyer', (tester) async {
      await _pump(
        tester,
        dispute: _dispute(),
        role: rust_types.TradeRole.seller,
      );

      expect(
        _inCard(find.text(_en.disputeWith(_en.buyer, _peer))),
        findsOneWidget,
      );
    });

    testWidgets('an unknown counterparty is named as such', (tester) async {
      await _pump(tester, dispute: _dispute(), role: null);

      expect(
        _inCard(find.text(_en.disputeWith(_en.seller, _en.unknownPeerHandle))),
        findsOneWidget,
      );
    });

    testWidgets('shows both full ids under their labels, in monospace', (
      tester,
    ) async {
      await _pump(tester, dispute: _dispute());

      for (final (label, id) in [
        (_en.orderIdLabel, _trade),
        (_en.disputeIdLabel, _disputeId),
      ]) {
        expect(_inCard(find.text(label)), findsOneWidget);
        final value = _inCard(find.text(id));
        expect(value, findsOneWidget);
        final text = tester.widget<Text>(value);
        expect(text.style?.fontFamily, 'monospace');
        expect(text.maxLines, isNull);
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        // The label sits above its id.
        expect(
          tester.getTopLeft(_inCard(find.text(label))).dy,
          lessThan(tester.getTopLeft(value).dy),
        );
      }
      // Order id first, then the dispute id.
      expect(
        tester.getTopLeft(_inCard(find.text(_trade))).dy,
        lessThan(tester.getTopLeft(_inCard(find.text(_disputeId))).dy),
      );
    });

    testWidgets('tapping an id copies it whole', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(tester, dispute: _dispute());

      await tester.tap(_inCard(find.text(_trade)));
      await tester.pump();
      await tester.tap(_inCard(find.text(_disputeId)));
      await tester.pump();

      expect(copied, [_trade, _disputeId]);
    });

    testWidgets('in progress: status text and the three instructions, '
        'no shared-key bullet', (tester) async {
      await _pump(tester, dispute: _dispute());

      final status = _inCard(find.text(_en.disputeInProgress));
      expect(status, findsOneWidget);
      expect(tester.widget<Text>(status).style?.fontWeight, FontWeight.w600);
      for (final bullet in [
        _en.disputeInstruction1,
        _en.disputeInstruction2,
        _en.disputeInstruction3,
      ]) {
        expect(_inCard(find.text(bullet)), findsOneWidget);
      }
      // v1's fourth bullet points to a shared key v2 no longer shows (#415).
      expect(find.textContaining('shared key'), findsNothing);
      // Status first, then the bullets in order.
      final ys =
          [
            _en.disputeInProgress,
            _en.disputeInstruction1,
            _en.disputeInstruction2,
            _en.disputeInstruction3,
          ].map((t) => tester.getTopLeft(_inCard(find.text(t))).dy).toList();
      expect(ys, orderedEquals([...ys]..sort()));
    });

    group('per status', () {
      testWidgets('opened by the buyer, no solver yet', (tester) async {
        await _pump(
          tester,
          dispute: _dispute(status: DisputeStatus.open, adminPubkey: null),
        );

        expect(_inCard(_chip(_en.disputeStatusInitiated)), findsOneWidget);
        expect(
          _inCard(find.text(_en.disputeOpenedByYouAgainstSeller(_peer))),
          findsOneWidget,
        );
        expect(_inCard(find.text(_en.disputeInstruction1)), findsOneWidget);
      });

      testWidgets('opened by the seller, no solver yet', (tester) async {
        await _pump(
          tester,
          dispute: _dispute(status: DisputeStatus.open, adminPubkey: null),
          role: rust_types.TradeRole.seller,
        );

        expect(
          _inCard(find.text(_en.disputeOpenedByYouAgainstBuyer(_peer))),
          findsOneWidget,
        );
      });

      testWidgets('opened by the peer, no solver yet', (tester) async {
        await _pump(
          tester,
          dispute: _dispute(
            status: DisputeStatus.open,
            adminPubkey: null,
            initiatedByMe: false,
          ),
        );

        expect(_inCard(_chip(_en.disputeStatusInitiated)), findsOneWidget);
        expect(_inCard(find.text(_en.disputeWaitingForAdmin)), findsOneWidget);
        expect(_inCard(find.text(_en.disputeInstruction3)), findsOneWidget);
      });

      testWidgets('initiated but a solver already took it', (tester) async {
        await _pump(tester, dispute: _dispute(status: DisputeStatus.open));

        // v1: the chip follows the status, the text the solver.
        expect(_inCard(_chip(_en.disputeStatusInitiated)), findsOneWidget);
        expect(_inCard(find.text(_en.disputeInProgress)), findsOneWidget);
      });

      for (final (resolution, caption) in [
        (DisputeResolution.fundsToBuyer, _en.disputeStatusResolved),
        (DisputeResolution.fundsToSeller, _en.disputeStatusResolved),
        (DisputeResolution.cooperativeCancel, _en.disputeStatusClosed),
        (null, _en.disputeStatusClosed),
      ]) {
        testWidgets('resolved ($resolution): chip, ids, no instructions', (
          tester,
        ) async {
          await _pump(
            tester,
            dispute: _dispute(
              status: DisputeStatus.resolved,
              resolution: resolution,
            ),
          );

          expect(_inCard(_chip(caption)), findsOneWidget);
          expect(_inCard(find.text(_trade)), findsOneWidget);
          expect(_inCard(find.text(_disputeId)), findsOneWidget);
          // The outcome is the resolved banner's; the card asks for nothing.
          expect(_inCard(find.text(_en.disputeInProgress)), findsNothing);
          expect(_inCard(find.text(_en.disputeInstruction1)), findsNothing);
          expect(_inCard(find.text(_en.disputeInstruction2)), findsNothing);
          expect(_inCard(find.text(_en.disputeInstruction3)), findsNothing);
        });
      }
    });

    testWidgets('sits above the messages and scrolls with them', (
      tester,
    ) async {
      await _pump(
        tester,
        dispute: _dispute(),
        history: [_solverMessage('Please send the receipt')],
      );

      final card = find.byType(DisputeInfoCard);
      final message = find.text('Please send the receipt');
      expect(message, findsOneWidget);
      expect(
        tester.getBottomLeft(card).dy,
        lessThanOrEqualTo(tester.getTopLeft(message).dy),
      );
      expect(
        find.ancestor(of: card, matching: find.byType(Scrollable)),
        findsOneWidget,
      );
    });

    testWidgets('a long opener then short replies land on the latest '
        'message, with no spring-back', (tester) async {
      // The first messages laid out are taller than the rest, so the list's
      // first estimate of its length is too long.
      final opener = List.filled(150, 'evidence').join(' ');
      await _pump(
        tester,
        dispute: _dispute(),
        advanceTime: false,
        history: [
          _solverMessage(opener, createdAt: 1),
          for (var i = 1; i <= 40; i++)
            _solverMessage('ok $i', createdAt: 1 + i),
        ],
      );

      // The first settled frame, before any time passes.
      final position = _chatPosition(tester);
      expect(position.outOfRange, isFalse);
      expect(position.pixels, position.maxScrollExtent);
      expect(position.isScrollingNotifier.value, isFalse);
      final last = tester.getRect(find.text('ok 40'));
      final input = tester.getRect(find.byType(DisputeMessageInput));
      expect(last.bottom, lessThanOrEqualTo(input.top));
      expect(last.top, greaterThanOrEqualTo(0));
    });

    group('320 dp, German, text at 2x', () {
      final de = AppLocalizationsDe();

      for (final dispute in [
        _dispute(),
        _dispute(status: DisputeStatus.open, adminPubkey: null),
        _dispute(
          status: DisputeStatus.resolved,
          resolution: DisputeResolution.fundsToSeller,
        ),
      ]) {
        testWidgets('${dispute.status}: no overflow, ids whole', (
          tester,
        ) async {
          await _pump(
            tester,
            dispute: dispute,
            locale: const Locale('de'),
            size: const Size(320, 640),
            textScale: 2,
          );

          expect(tester.takeException(), isNull);
          expect(_inCard(find.text(de.orderIdLabel)), findsOneWidget);
          expect(_inCard(find.text(_trade)), findsOneWidget);
        });
      }

      testWidgets('the input bar stays on screen and the latest message is '
          'reachable', (tester) async {
        await _pump(
          tester,
          dispute: _dispute(),
          locale: const Locale('de'),
          size: const Size(320, 640),
          textScale: 2,
          history: [_solverMessage('Please send the receipt')],
        );

        expect(tester.takeException(), isNull);
        final input = find.byType(DisputeMessageInput);
        expect(input, findsOneWidget);
        final rect = tester.getRect(input);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(640));
        // The card is taller than the chat area here; the history's arrival
        // scrolls to the latest message, above the input bar.
        final message = tester.getRect(find.text('Please send the receipt'));
        expect(message.bottom, lessThanOrEqualTo(rect.top));
        expect(message.top, greaterThanOrEqualTo(0));
      });
    });
  });

  // The outcome is told from the user's side of the trade, the side the
  // card names; DisputeItem.isSelling is never set (#680 review).
  group('resolved banner', () {
    for (final (role, resolution, won, lostText) in [
      (rust_types.TradeRole.buyer, DisputeResolution.fundsToBuyer, true, null),
      (
        rust_types.TradeRole.seller,
        DisputeResolution.fundsToBuyer,
        false,
        _en.disputeLostFundsToBuyer,
      ),
      (
        rust_types.TradeRole.seller,
        DisputeResolution.fundsToSeller,
        true,
        null,
      ),
      (
        rust_types.TradeRole.buyer,
        DisputeResolution.fundsToSeller,
        false,
        _en.disputeLostFundsToSeller,
      ),
    ]) {
      testWidgets('${role.name}, ${resolution.name}: '
          '${won ? 'won' : 'lost'}', (tester) async {
        await _pump(
          tester,
          dispute: _dispute(
            status: DisputeStatus.resolved,
            resolution: resolution,
          ),
          role: role,
        );

        expect(
          find.text(_en.disputeSuccessfullyCompleted),
          won ? findsOneWidget : findsNothing,
        );
        for (final text in [
          _en.disputeLostFundsToBuyer,
          _en.disputeLostFundsToSeller,
        ]) {
          expect(
            find.text(text),
            text == lostText ? findsOneWidget : findsNothing,
          );
        }
      });
    }

    for (final (resolution, neutral) in [
      (DisputeResolution.fundsToBuyer, _en.disputeDescResolvedBuyerFavour),
      (DisputeResolution.fundsToSeller, _en.disputeDescResolvedSellerFavour),
    ]) {
      testWidgets('unknown role, ${resolution.name}: a neutral outcome', (
        tester,
      ) async {
        await _pump(
          tester,
          dispute: _dispute(
            status: DisputeStatus.resolved,
            resolution: resolution,
          ),
          role: null,
        );

        expect(find.text(neutral), findsOneWidget);
        expect(find.text(_en.disputeSuccessfullyCompleted), findsNothing);
        expect(find.text(_en.disputeLostFundsToBuyer), findsNothing);
        expect(find.text(_en.disputeLostFundsToSeller), findsNothing);
      });
    }
  });

  // Measured with the app's fonts: the test engine's em squares would put
  // every break somewhere else.
  group('title wraps between words', () {
    setUpAll(loadAppFonts);

    /// Where the title's lines start, by the caret moving down a line.
    List<int> lineStarts(RenderParagraph paragraph, String text) {
      final starts = <int>[];
      var lastY =
          paragraph
              .getOffsetForCaret(const TextPosition(offset: 0), Rect.zero)
              .dy;
      for (var i = 1; i < text.length; i++) {
        final y =
            paragraph.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dy;
        if (y > lastY) starts.add(i);
        lastY = y;
      }
      return starts;
    }

    bool breaksBetweenWords(String text, int at) {
      final before = text[at - 1];
      return before == ' ' || before == '-' || text[at] == ' ';
    }

    for (final locale in AppLocalizations.supportedLocales) {
      for (final role in [
        rust_types.TradeRole.buyer,
        rust_types.TradeRole.seller,
      ]) {
        testWidgets('320 dp, 2x, ${locale.languageCode}, ${role.name}', (
          tester,
        ) async {
          await _pump(
            tester,
            dispute: _dispute(),
            role: role,
            locale: locale,
            size: const Size(320, 640),
            textScale: 2,
          );
          final l10n = lookupAppLocalizations(locale);
          final title = l10n.disputeWith(
            role == rust_types.TradeRole.buyer ? l10n.seller : l10n.buyer,
            _peer,
          );

          expect(tester.takeException(), isNull);
          final paragraph = tester.renderObject<RenderParagraph>(
            _inCard(find.text(title)),
          );
          for (final at in lineStarts(paragraph, title)) {
            expect(
              breaksBetweenWords(title, at),
              isTrue,
              reason:
                  '"${title.substring(0, at)}|${title.substring(at)}" '
                  'breaks a word',
            );
          }
        });
      }
    }

    testWidgets('393 dp, 1x: title and chip side by side', (tester) async {
      await _pump(tester, dispute: _dispute(), size: const Size(393, 800));

      final title = _inCard(find.text(_en.disputeWith(_en.seller, _peer)));
      final chip = _inCard(find.byType(TradeListChip));
      expect(tester.getTopLeft(chip).dy, tester.getTopLeft(title).dy);
      expect(
        tester.getTopLeft(chip).dx,
        greaterThanOrEqualTo(tester.getTopRight(title).dx),
      );
    });
  });
}
