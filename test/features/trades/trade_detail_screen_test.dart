import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart'
    show disputeLookupProvider;
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/rate/providers/rating_providers.dart';
import 'package:mostro/features/rate/screens/rate_counterpart_screen.dart';
import 'package:mostro/features/rate/widgets/star_rating.dart';
import 'package:mostro/features/trades/providers/release_pending_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/features/trades/screens/trade_detail_screen.dart';
import 'package:mostro/features/trades/widgets/cancel_request_notice.dart';
import 'package:mostro/features/trades/widgets/trade_chat_card.dart';
import 'package:mostro/features/chat/models/chat_list_rules.dart';
import 'package:mostro/features/chat/providers/chat_list_provider.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/trades/widgets/trade_completed_card.dart';
import 'package:mostro/features/trades/widgets/trade_step_block.dart';
import 'package:mostro/features/trades/widgets/trade_timeline.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../support/fake_orders.dart';
import '../../support/fake_trades.dart';
import '../../support/provider_harness.dart';

/// Pumps [TradeDetailScreen] for [orderId] with the role and live order
/// status overridden, matching this repo's Riverpod-override testing
/// convention (see `test/support/order_book_harness.dart`).
///
/// The order book itself is overridden to an empty stream — the screen's own
/// `_loadExpiresAt`/Rust-bridge calls fail silently without `RustLib.init()`
/// (the same as `test/widget_test.dart`'s smoke test), which is fine since
/// none of the assertions here depend on live order details.
///
/// Returns the container so a test can drive a provider after the first
/// frame — what [ratingFetch] is for: it is re-read on every refresh, so a
/// test can change what the rating lookup answers and invalidate it.
Future<ProviderContainer> _pumpTradeDetail(
  WidgetTester tester, {
  required String orderId,
  required bool isBuyer,
  required OrderStatus status,
  Stream<OrderStatus>? statusUpdates,
  Future<void> Function(String)? releaseOrder,
  bool ratingRoute = false,
  RatingInfo? rating,
  bool ratingUnresolved = false,
  Future<RatingInfo?> Function()? ratingFetch,
  Locale locale = const Locale('en'),
  List<TradeInfo>? trades,
  List<OrderItem> book = const [],
  bool roleKnown = true,
  bool privacyMode = false,
  NotificationsNotifier? notifications,
  ChatRowState? chatState,
  List<Override> extraOverrides = const [],
}) async {
  final container = createContainer(
    overrides: [
      ...extraOverrides,
      if (chatState != null)
        chatRowStateProvider(orderId).overrideWithValue(chatState),
      if (notifications != null)
        notificationsProvider.overrideWith((_) => notifications),
      if (privacyMode)
        privacyModeProvider.overrideWith(
          (ref) => PrivacyModeNotifier(initialValue: true),
        ),
      if (releaseOrder != null)
        releaseOrderActionProvider.overrideWithValue(releaseOrder),
      if (trades != null) rawTradesProvider.overrideWith((ref) async => trades),
      tradeRoleProvider.overrideWith(
        (ref) => roleKnown ? {orderId: isBuyer} : <String, bool>{},
      ),
      if (!roleKnown)
        tradeRoleFromDbProvider(orderId).overrideWith((ref) async => null),
      tradeStatusProvider(
        orderId,
      ).overrideWith((ref) => statusUpdates ?? Stream.value(status)),
      orderBookProvider.overrideWith((ref) => Stream.value(book)),
      // A waiting step draws its countdown from the step deadline, which
      // without a bridge resolves to "unknown" — and then the screen draws
      // none (#270). The 8a cases below assert the countdown's label, so the
      // harness stands in for the daemon message that opened the step.
      invoiceDeadlineProvider(orderId).overrideWith(
        (ref) async => DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600,
      ),
      tradeRatingProvider(orderId).overrideWith((ref) {
        // A pending Completer future keeps the rating lookup in its first
        // loading state, pinning the no-CTA-flash guard.
        if (ratingUnresolved) return Completer<RatingInfo?>().future;
        return ratingFetch != null ? ratingFetch() : Future.value(rating);
      }),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home:
            ratingRoute
                ? RateCounterpartScreen(orderId: orderId)
                : TradeDetailScreen(orderId: orderId),
      ),
    ),
  );

  await _settle(tester);
  return container;
}

/// Pumps [TradeDetailScreen] for the buyer under a router, so leaving for
/// home is observable, with the trades list and the order book under test
/// control. [loadTrades] answers the trades list; [book] is the order book;
/// [cancelOrder] stands in for publishing the cancel.
Future<void> _pumpRoutedTradeDetail(
  WidgetTester tester, {
  required String orderId,
  required OrderStatus status,
  required Future<List<TradeInfo>> Function() loadTrades,
  List<OrderItem> book = const [],
  Future<void> Function(String)? cancelOrder,
  Stream<OrderStatus>? statusUpdates,
  Stream<List<OrderItem>>? bookUpdates,
  Future<Dispute?> Function(String tradeId)? disputeLookup,
}) async {
  final container = createContainer(
    overrides: [
      if (disputeLookup != null)
        disputeLookupProvider.overrideWithValue(disputeLookup),
      if (cancelOrder != null)
        cancelOrderActionProvider.overrideWithValue(cancelOrder),
      tradeRoleProvider.overrideWith((ref) => {orderId: true}),
      tradeStatusProvider(
        orderId,
      ).overrideWith((ref) => statusUpdates ?? Stream.value(status)),
      orderBookProvider.overrideWith(
        (ref) => bookUpdates ?? Stream.value(book),
      ),
      rawTradesProvider.overrideWith((ref) => loadTrades()),
    ],
  );
  final router = GoRouter(
    initialLocation: AppRoute.tradeDetailPath(orderId),
    routes: [
      // A Scaffold, as the real home is: the snackbar the screen leaves with
      // shows on whichever Scaffold is current.
      GoRoute(
        path: AppRoute.home,
        builder: (_, __) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: AppRoute.tradeDetail,
        builder:
            (_, state) =>
                TradeDetailScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: AppRoute.disputeDetails,
        builder:
            (_, state) => Scaffold(
              body: Text('dispute ${state.pathParameters['disputeId']}'),
            ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  // See `_pumpTradeDetail`: frames, never `pumpAndSettle()`.
  await tester.pump();
  await tester.pump();
}

/// Lets a navigation the screen started run its page transition out, so the
/// route it left is gone from the tree. A fixed step, never `pumpAndSettle()`
/// (see `_pumpTradeDetail`).
Future<void> _finishPageTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// The secondary Cancel, by its automation id: its label is "Cancel trade"
/// alone in the row and "Cancel" next to the dispute.
Finder _cancelButton() => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.identifier == AutomationIds.tradeCancel,
);

/// Taps the secondary Cancel and confirms the dialog.
Future<void> _cancelFromTradeDetail(WidgetTester tester) async {
  final l10n = AppLocalizationsEn();
  await tester.tap(_cancelButton());
  await tester.pump();
  await tester.tap(find.text(l10n.yesCancelButtonLabel));
  await tester.pump();
  await tester.pump();
}

/// One frame for the build, one to flush the fire-and-forget
/// `_loadExpiresAt` future and the stream-provider emissions, then the
/// 200 ms crossfade a status change plays on the step block and timeline.
///
/// Deliberately not `pumpAndSettle()`: the screen keeps a real countdown
/// timer scheduling frames for the whole 15-minute default window, so it
/// would never report "settled".
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

/// Builds the rating the Rust store would hand back for a trade.
///
/// [isMine] is the field under test: `true` is the local user rating their
/// counterpart, `false` the counterpart rating them.
RatingInfo _rating({required bool isMine, int score = 5}) => RatingInfo(
  tradeId: 'trade',
  score: score,
  isMine: isMine,
  createdAt: intToPlatformInt64(1000),
);

/// Matches an outlined secondary button by its visible label text.
Finder _outlinedButtonWithText(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(OutlinedButton));

/// Matches the primary (lime) action by its visible label text.
///
/// Matched by predicate, not `byType`: the label alone can also appear in
/// the timeline, and `FilledButton.icon` builds a private subclass.
Finder _filledButtonWithText(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is FilledButton),
);

/// Matches any `PopupMenuButton`, regardless of its generic type argument.
Finder _anyPopupMenuButton() =>
    find.byWidgetPredicate((widget) => widget is PopupMenuButton);

/// Matches any `PopupMenuItem`, regardless of its generic type argument.
Finder _anyPopupMenuItem() =>
    find.byWidgetPredicate((widget) => widget is PopupMenuItem);

final _en = AppLocalizationsEn();

void main() {
  testWidgets('opening the trade reads its notices, not its chat card (#610)', (
    tester,
  ) async {
    // Arrange
    final notifications = NotificationsNotifier();
    final chatCardId = NotificationModel.chatCardId(
      'order-610',
      fromSolver: false,
    );
    for (final n in [
      NotificationModel.tradeStatus(
        orderId: 'order-610',
        status: 'active',
        at: DateTime.utc(2026),
      ),
      NotificationModel.chatMessages(
        tradeId: 'order-610',
        fromSolver: false,
        count: 1,
        at: DateTime.utc(2026),
      ),
      NotificationModel.tradeStatus(
        orderId: 'other-order',
        status: 'active',
        at: DateTime.utc(2026),
      ),
    ]) {
      await notifications.add(n);
    }

    // Act
    await _pumpTradeDetail(
      tester,
      orderId: 'order-610',
      isBuyer: true,
      status: OrderStatus.active,
      notifications: notifications,
    );

    // Assert
    final read = {for (final n in notifications.state) n.id: n.isRead};
    expect(read, {
      'trade-order-610-active': true,
      chatCardId: false,
      'trade-other-order-active': false,
    });
  });

  group('8a · waiting for the counterpart to lock the sats', () {
    testWidgets(
      'buyer: amber chip, no chat, lock note, Cancel trade alone, no dispute',
      (tester) async {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-8a',
          isBuyer: true,
          status: OrderStatus.waitingPayment,
          // A buy order: the seller who owes the payment took it, so expiry
          // puts the order back in the book.
          trades: [
            fakeTrade(
              id: 'order-8a',
              orderId: 'order-8a',
              status: OrderStatus.waitingPayment,
              kind: OrderKind.buy,
            ),
          ],
        );

        expect(find.text(_en.tradeScreenTitle), findsOneWidget);
        expect(find.text(_en.stepIndicator(2, 5)), findsOneWidget);
        expect(find.text(_en.tradeChipWaiting), findsOneWidget);
        expect(find.text(_en.tradeHeadlineWaitingPaymentBuyer), findsOneWidget);
        expect(find.byType(TradeChatLockedLine), findsOneWidget);
        expect(find.byType(TradeChatCard), findsNothing);
        expect(find.text(_en.tradeTimerTheyHave), findsOneWidget);
        expect(find.text(_en.tradeTimerExpiryBackToBook), findsOneWidget);
        expect(_outlinedButtonWithText(_en.cancelTradeButton), findsOneWidget);
        expect(_outlinedButtonWithText(_en.openDisputeButton), findsNothing);
        expect(
          find.byWidgetPredicate((w) => w is FilledButton),
          findsNothing,
          reason: 'when the user only waits there is no lime button',
        );
      },
    );

    testWidgets('the seller who must pay the hold invoice gets the action', (
      tester,
    ) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-8a-seller',
        isBuyer: false,
        status: OrderStatus.waitingPayment,
      );

      expect(find.text(_en.tradeChipYourTurn), findsOneWidget);
      expect(_filledButtonWithText(_en.payHoldInvoiceButton), findsOneWidget);
      expect(find.text(_en.tradeTimerYouHave), findsOneWidget);
    });
  });

  group('8b / 8c · active', () {
    testWidgets('seller: lime chip, chat card, no primary, Cancel + Dispute', (
      tester,
    ) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-8b',
        isBuyer: false,
        status: OrderStatus.active,
      );

      expect(find.text(_en.stepIndicator(3, 5)), findsOneWidget);
      expect(find.text(_en.tradeChipActive), findsOneWidget);
      expect(find.byType(TradeChatCard), findsOneWidget);
      expect(find.byType(TradeChatLockedLine), findsNothing);
      expect(find.byWidgetPredicate((w) => w is FilledButton), findsNothing);
      expect(_outlinedButtonWithText(_en.cancel), findsOneWidget);
      expect(_outlinedButtonWithText(_en.openDisputeButton), findsOneWidget);
      expect(find.text(_en.tradeTimerTheyHave), findsOneWidget);
      expect(find.text(_en.tradeTimerNoteCoordinate), findsOneWidget);
      expect(_anyPopupMenuButton(), findsOneWidget);
    });

    testWidgets('buyer: your-turn chip and the fiat-sent action', (
      tester,
    ) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-8c',
        isBuyer: true,
        status: OrderStatus.active,
      );

      expect(find.text(_en.tradeChipYourTurn), findsOneWidget);
      expect(_filledButtonWithText(_en.tradeFiatSentAction), findsOneWidget);
      expect(_outlinedButtonWithText(_en.cancel), findsOneWidget);
      expect(_outlinedButtonWithText(_en.openDisputeButton), findsOneWidget);
      expect(_outlinedButtonWithText(_en.releaseSatsButton), findsNothing);
      expect(find.text(_en.tradeTimerYouHave), findsOneWidget);
    });
  });

  group('a cooperative cancel request is pending', () {
    testWidgets('asked by me: the notice, no second Cancel, dispute stays', (
      tester,
    ) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-coop-me',
        isBuyer: true,
        status: OrderStatus.active,
        trades: [
          fakeTrade(
            id: 'coop-me',
            cooperativeCancelState: CooperativeCancelState.requestedByMe,
          ),
        ],
      );

      expect(find.byType(CancelRequestNotice), findsOneWidget);
      expect(find.text(_en.tradeCancelRequestedByMeNotice), findsOneWidget);
      expect(_outlinedButtonWithText(_en.cancel), findsNothing);
      expect(_outlinedButtonWithText(_en.openDisputeButton), findsOneWidget);
      // The trade goes on: the buyer can still mark the fiat as sent.
      expect(_filledButtonWithText(_en.tradeFiatSentAction), findsOneWidget);
    });

    testWidgets('asked by the peer: the notice and Cancel reads Accept', (
      tester,
    ) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-coop-peer',
        isBuyer: false,
        status: OrderStatus.fiatSent,
        trades: [
          fakeTrade(
            id: 'coop-peer',
            status: OrderStatus.fiatSent,
            cooperativeCancelState: CooperativeCancelState.requestedByPeer,
          ),
        ],
      );

      expect(find.text(_en.tradeCancelRequestedByPeerNotice), findsOneWidget);
      expect(_outlinedButtonWithText(_en.acceptCancelButton), findsOneWidget);
      expect(_outlinedButtonWithText(_en.cancel), findsNothing);
      // The trade goes on: the seller can still release.
      expect(
        _filledButtonWithText(_en.confirmReleaseSatsButton),
        findsOneWidget,
      );

      await tester.tap(_outlinedButtonWithText(_en.acceptCancelButton));
      await _settle(tester);
      // The dialog says what accepting does, not what a first request does.
      expect(find.text(_en.cancelTradeDialogContentAccept), findsOneWidget);
      expect(find.text(_en.cancelTradeDialogContent), findsNothing);
    });

    testWidgets('a dispute keeps the request: the buyer can accept it', (
      tester,
    ) async {
      // mostrod leaves the request in place when a dispute opens; the
      // counterparty's cancel then ends the trade and closes the dispute.
      await _pumpTradeDetail(
        tester,
        orderId: 'order-coop-dispute',
        isBuyer: true,
        status: OrderStatus.dispute,
        trades: [
          fakeTrade(
            id: 'coop-dispute',
            status: OrderStatus.dispute,
            cooperativeCancelState: CooperativeCancelState.requestedByPeer,
          ),
        ],
      );

      expect(find.text(_en.tradeCancelRequestedByPeerNotice), findsOneWidget);
      expect(_filledButtonWithText(_en.viewDisputeButton), findsOneWidget);
      expect(_outlinedButtonWithText(_en.acceptCancelButton), findsOneWidget);

      await tester.tap(_outlinedButtonWithText(_en.acceptCancelButton));
      await _settle(tester);
      expect(find.text(_en.cancelTradeDialogContentAccept), findsOneWidget);
    });

    testWidgets('a settled trade shows no stale request', (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-coop-done',
        isBuyer: true,
        status: OrderStatus.cooperativelyCanceled,
        trades: [
          fakeTrade(
            id: 'coop-done',
            status: OrderStatus.cooperativelyCanceled,
            cooperativeCancelState: CooperativeCancelState.requestedByPeer,
          ),
        ],
      );

      expect(find.text(_en.tradeCancelRequestedByPeerNotice), findsNothing);
      expect(find.text(_en.tradeCancelRequestedByMeNotice), findsNothing);
    });
  });

  group('8d · fiat sent', () {
    testWidgets(
      'seller: release action with the irreversibility warning, Cancel + Dispute',
      (tester) async {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-8d',
          isBuyer: false,
          status: OrderStatus.fiatSent,
        );

        expect(find.text(_en.stepIndicator(4, 5)), findsOneWidget);
        expect(find.text(_en.tradeChipYourTurn), findsOneWidget);
        expect(find.text(_en.tradeReleaseIrreversible), findsOneWidget);
        expect(
          _filledButtonWithText(_en.confirmReleaseSatsButton),
          findsOneWidget,
        );
        expect(_outlinedButtonWithText(_en.cancel), findsOneWidget);
        expect(_outlinedButtonWithText(_en.openDisputeButton), findsOneWidget);
        expect(_outlinedButtonWithText(_en.releaseSatsButton), findsNothing);
      },
    );

    testWidgets('buyer waits: amber chip, no warning, no primary', (
      tester,
    ) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-8d-buyer',
        isBuyer: true,
        status: OrderStatus.fiatSent,
      );

      expect(find.text(_en.tradeChipWaiting), findsOneWidget);
      expect(find.text(_en.tradeReleaseIrreversible), findsNothing);
      expect(find.byWidgetPredicate((w) => w is FilledButton), findsNothing);
      expect(_outlinedButtonWithText(_en.cancel), findsOneWidget);
      expect(_outlinedButtonWithText(_en.openDisputeButton), findsOneWidget);
    });

    /// Releasing is the one action of the screen that asks first: the sheet
    /// must be confirmed before the release provider is called.
    testWidgets('publishing release keeps the seller on the trade screen', (
      tester,
    ) async {
      final released = <String>[];
      await _pumpTradeDetail(
        tester,
        orderId: 'order-release-ack',
        isBuyer: false,
        status: OrderStatus.fiatSent,
        releaseOrder: (id) async {
          released.add(id);
        },
      );
      await tester.tap(find.text(_en.confirmReleaseSatsButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text(_en.releaseSheetTitle), findsOneWidget);
      expect(released, isEmpty);

      await tester.tap(find.text(_en.releaseSheetConfirm));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(released, ['order-release-ack']);
      expect(find.byType(TradeDetailScreen), findsOneWidget);
      expect(find.text(_en.releaseFailed), findsNothing);
      expect(find.text(_en.tradeCompletedTitle), findsNothing);
      // Drain the button's success indication and the release's wait for
      // the node before disposing the screen.
      await tester.pump(kReleaseConfirmationTimeout);
    });

    /// Confirms Release on the sheet and lets the publish land.
    Future<void> confirmRelease(WidgetTester tester) async {
      await tester.tap(find.text(_en.confirmReleaseSatsButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text(_en.releaseSheetConfirm));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    FilledButton filledButton(WidgetTester tester, String label) =>
        tester.widget<FilledButton>(_filledButtonWithText(label));

    // A seller pressed Release three times: the node took ~30 s to settle
    // the hold invoice, and the button came back after the first publish.
    testWidgets('a published release is not offered again while it waits', (
      tester,
    ) async {
      // Arrange
      final released = <String>[];
      await _pumpTradeDetail(
        tester,
        orderId: 'order-release-wait',
        isBuyer: false,
        status: OrderStatus.fiatSent,
        releaseOrder: (id) async => released.add(id),
      );

      // Act
      await confirmRelease(tester);
      await tester.pump(const Duration(seconds: 5));

      // Assert
      expect(released, ['order-release-wait']);
      expect(find.text(_en.releaseSentNotice), findsOneWidget);
      expect(find.text(_en.confirmReleaseSatsButton), findsNothing);
      expect(filledButton(tester, _en.releasePendingLabel).onPressed, isNull);
      await tester.pump(kReleaseConfirmationTimeout);
    });

    testWidgets('a release that lands after the seller left still waits', (
      tester,
    ) async {
      // Codex / ermeme on #604: the wait was recorded only while the screen
      // was mounted. Leaving mid-publication dropped it, and reopening the
      // unchanged fiat-sent trade offered Release again.
      // Arrange — a publication that is still in flight.
      final publication = Completer<void>();
      final container = await _pumpTradeDetail(
        tester,
        orderId: 'order-release-left',
        isBuyer: false,
        status: OrderStatus.fiatSent,
        releaseOrder: (_) => publication.future,
      );
      await confirmRelease(tester);

      // Act — the seller leaves, then the publication succeeds.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SizedBox.shrink(),
        ),
      );
      publication.complete();
      await tester.pump();

      // Assert — the wait is recorded, so a reopened screen will not offer
      // Release while the node settles.
      expect(
        container.read(releasePendingProvider)['order-release-left'],
        ReleaseWait.waiting,
      );
      await tester.pump(kReleaseConfirmationTimeout);
    });

    testWidgets('the wait ends as soon as the order moves', (tester) async {
      // Arrange: broadcast, because the release re-reads the status and
      // the screen subscribes again.
      final updates = StreamController<OrderStatus>.broadcast();
      addTearDown(() => unawaited(updates.close()));
      final container = await _pumpTradeDetail(
        tester,
        orderId: 'order-release-moves',
        isBuyer: false,
        status: OrderStatus.fiatSent,
        statusUpdates: updates.stream,
        releaseOrder: (_) async {},
      );
      updates.add(OrderStatus.fiatSent);
      await _settle(tester);
      await confirmRelease(tester);
      expect(
        container.read(releasePendingProvider)['order-release-moves'],
        ReleaseWait.waiting,
      );

      // Act: the node settled the hold invoice.
      updates.add(OrderStatus.settledHoldInvoice);
      await _settle(tester);

      // Assert
      expect(
        container.read(releasePendingProvider),
        isNot(contains('order-release-moves')),
      );
      expect(find.text(_en.releasePendingLabel), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Release comes back when the node never confirms', (
      tester,
    ) async {
      // Arrange
      final released = <String>[];
      await _pumpTradeDetail(
        tester,
        orderId: 'order-release-overdue',
        isBuyer: false,
        status: OrderStatus.fiatSent,
        releaseOrder: (id) async => released.add(id),
      );
      await confirmRelease(tester);

      // Act
      await tester.pump(kReleaseConfirmationTimeout);
      // Frames for the earlier snackbar to leave and this one to come in.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      // Assert
      expect(find.text(_en.releaseUnconfirmedNotice), findsOneWidget);
      expect(
        filledButton(tester, _en.confirmReleaseSatsButton).onPressed,
        isNotNull,
      );
      expect(released, hasLength(1));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Back on the release sheet releases nothing', (tester) async {
      final released = <String>[];
      await _pumpTradeDetail(
        tester,
        orderId: 'order-release-back',
        isBuyer: false,
        status: OrderStatus.fiatSent,
        releaseOrder: (id) async {
          released.add(id);
        },
      );
      await tester.tap(find.text(_en.confirmReleaseSatsButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text(_en.releaseSheetBack));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(released, isEmpty);
      expect(find.text(_en.releaseSheetTitle), findsNothing);
      expect(
        _filledButtonWithText(_en.confirmReleaseSatsButton),
        findsOneWidget,
      );
    });
  });

  group('payout pending', () {
    testWidgets('the buyer waits for the payout after the release', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-payout-pending',
          isBuyer: true,
          status: OrderStatus.settledHoldInvoice,
        );
        expect(find.bySemanticsLabel('payout-pending'), findsOneWidget);
        expect(find.text(_en.tradeHeadlinePayoutPending), findsOneWidget);
        expect(find.text(_en.tradeCompletedTitle), findsNothing);
        expect(find.byType(TradeCompletedCard), findsNothing);
        expect(find.byWidgetPredicate((w) => w is FilledButton), findsNothing);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('a successful payout replaces the pending state with rating', (
      tester,
    ) async {
      final updates = StreamController<OrderStatus>();
      addTearDown(() => unawaited(updates.close()));
      updates.add(OrderStatus.settledHoldInvoice);
      await _pumpTradeDetail(
        tester,
        orderId: 'order-payout-transition',
        isBuyer: true,
        status: OrderStatus.settledHoldInvoice,
        statusUpdates: updates.stream,
      );
      expect(find.text(_en.tradeHeadlinePayoutPending), findsOneWidget);
      expect(find.byType(TradeCompletedCard), findsNothing);

      updates.add(OrderStatus.success);
      await _settle(tester);

      expect(find.text(_en.tradeHeadlinePayoutPending), findsNothing);
      expect(find.byType(TradeCompletedCard), findsOneWidget);
      expect(find.text(_en.tradeCompletedTitle), findsOneWidget);
      expect(_filledButtonWithText(_en.tradeSendRatingAction), findsOneWidget);
    });

    testWidgets('a rating notification cannot show the buyer success early', (
      tester,
    ) async {
      final updates = StreamController<OrderStatus>();
      addTearDown(() => unawaited(updates.close()));
      updates.add(OrderStatus.settledHoldInvoice);
      await _pumpTradeDetail(
        tester,
        orderId: 'order-early-rating',
        isBuyer: true,
        status: OrderStatus.settledHoldInvoice,
        statusUpdates: updates.stream,
        ratingRoute: true,
      );
      // The daemon refuses the buyer's rating until the payout completes.
      expect(find.text(_en.successfulOrder), findsNothing);
      expect(find.byType(StarRating), findsNothing);
      expect(find.text(_en.tradeHeadlinePayoutPending), findsOneWidget);

      updates.add(OrderStatus.success);
      await _settle(tester);

      expect(find.text(_en.successfulOrder), findsOneWidget);
      expect(find.byType(StarRating), findsOneWidget);
    });
  });

  /// Once released, the seller's part is over: getting the sats to the buyer
  /// is Mostro's job, and mostrod asks the seller to rate right away — it
  /// sends `rate` with the release and accepts the seller's rating at
  /// `settled-hold-invoice` (#586).
  group('the seller after the release', () {
    testWidgets('is asked to rate, not told to wait for the payout', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-seller-released',
          isBuyer: false,
          status: OrderStatus.settledHoldInvoice,
        );
        expect(find.bySemanticsLabel('pending-rating'), findsOneWidget);
        expect(find.text(_en.tradeHeadlinePayoutPending), findsNothing);
        expect(find.byType(TradeCompletedCard), findsOneWidget);
        expect(
          _filledButtonWithText(_en.tradeSendRatingAction),
          findsOneWidget,
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('reaches the rating screen without waiting for success', (
      tester,
    ) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-seller-rates',
        isBuyer: false,
        status: OrderStatus.settledHoldInvoice,
        ratingRoute: true,
      );
      expect(find.text(_en.successfulOrder), findsOneWidget);
      expect(find.byType(StarRating), findsOneWidget);
      expect(find.text(_en.tradeHeadlinePayoutPending), findsNothing);
    });

    // DS-CMP-20: skipping the rating undoes nothing, so it is a neutral
    // link, not an outlined button as heavy as sending the rating.
    testWidgets('skipping the rating is a neutral link', (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-seller-skips',
        isBuyer: false,
        status: OrderStatus.settledHoldInvoice,
        ratingRoute: true,
      );
      expect(
        find.widgetWithText(OutlinedButton, _en.closeRatingButton),
        findsNothing,
      );
      final link = find.widgetWithText(TextButton, _en.closeRatingButton);
      expect(link, findsOneWidget);
      final label = tester.widget<RichText>(
        find.descendant(of: link, matching: find.byType(RichText)),
      );
      expect(label.text.style?.color, OrderBookPalette.dark.textSecondary);
    });

    testWidgets('who already rated is not offered the form again', (
      tester,
    ) async {
      // Codex on #587: a seller back on `/rate_user/:id` (say, from the
      // rating notification) while the payout still retries must see their
      // rating, not a form whose submit meets `AlreadyRated`.
      await _pumpTradeDetail(
        tester,
        orderId: 'order-seller-rated-route',
        isBuyer: false,
        status: OrderStatus.settledHoldInvoice,
        ratingRoute: true,
        rating: _rating(isMine: true),
      );
      expect(find.byType(StarRating), findsNothing);
      expect(find.text(_en.successfulOrder), findsNothing);
      expect(_filledButtonWithText(_en.tradeSendRatingAction), findsNothing);
    });

    testWidgets('in privacy mode gets no rating form on the rating route', (
      tester,
    ) async {
      // CodeRabbit on #587: the trade screen withholds the rating in privacy
      // mode (Rust refuses to send one); a direct route must not offer it.
      await _pumpTradeDetail(
        tester,
        orderId: 'order-seller-private',
        isBuyer: false,
        status: OrderStatus.settledHoldInvoice,
        ratingRoute: true,
        privacyMode: true,
      );
      expect(find.text(_en.successfulOrder), findsNothing);
      expect(_filledButtonWithText(_en.tradeSendRatingAction), findsNothing);
      expect(find.text(_en.submitUppercaseButton), findsNothing);
      expect(find.text(_en.rateScreenHeader), findsNothing);
    });

    testWidgets('once rated, is done — even before the payout completes', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-seller-rated',
          isBuyer: false,
          status: OrderStatus.settledHoldInvoice,
          rating: _rating(isMine: true),
        );
        expect(find.bySemanticsLabel('rated'), findsOneWidget);
        expect(find.text(_en.tradeHeadlinePayoutPending), findsNothing);
        expect(_filledButtonWithText(_en.tradeSendRatingAction), findsNothing);
      } finally {
        semantics.dispose();
      }
    });
  });

  /// The countdown ticks once a second under an hour for the whole life of
  /// the screen. If that tick went through `setState`, this build method —
  /// which lays out the chat, step, reputation, timeline and actions — would
  /// re-run every second.
  ///
  /// Widget identity is the observable: Flutter allocates fresh widget
  /// objects on every build, so an `AppBar` instance surviving a tick means
  /// the screen itself was not rebuilt.
  testWidgets('the countdown tick does not rebuild the screen', (tester) async {
    await _pumpTradeDetail(
      tester,
      orderId: 'countdown-order',
      isBuyer: true,
      status: OrderStatus.active,
    );

    final before = tester.widget(find.byType(AppBar));
    // No order reaches the screen here, so the countdown starts from the
    // 15-minute default — under an hour, so mm:ss.
    expect(find.text('15:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('14:59'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('14:58'), findsOneWidget);

    expect(
      identical(tester.widget(find.byType(AppBar)), before),
      isTrue,
      reason: 'the per-second tick must repaint the timer, not the screen',
    );
  });

  group('outside the happy path', () {
    /// `in-progress` is the public order book's coarse bucket: the order left
    /// the book, which says nothing about the escrow. Presenting it as an
    /// active trade offered a dispute and a fiat-sent the daemon rejects with
    /// CantDo (issue #203).
    testWidgets('buyer + inProgress: no dispute, no fiat-sent, cancel only', (
      tester,
    ) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-in-progress-buyer',
        isBuyer: true,
        status: OrderStatus.inProgress,
      );

      expect(find.text(_en.tradeHeadlineInProgress), findsOneWidget);
      expect(find.text(_en.tradeChipWaiting), findsOneWidget);
      expect(_filledButtonWithText(_en.tradeFiatSentAction), findsNothing);
      expect(_outlinedButtonWithText(_en.openDisputeButton), findsNothing);
      expect(_outlinedButtonWithText(_en.releaseSatsButton), findsNothing);
      // Cancel stays: the daemon accepts it in every pre-settlement state.
      expect(_outlinedButtonWithText(_en.cancelTradeButton), findsOneWidget);
    });

    testWidgets('seller + inProgress: no dispute and no release', (
      tester,
    ) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-in-progress-seller',
        isBuyer: false,
        status: OrderStatus.inProgress,
      );

      expect(_outlinedButtonWithText(_en.openDisputeButton), findsNothing);
      expect(_outlinedButtonWithText(_en.releaseSatsButton), findsNothing);
      expect(_outlinedButtonWithText(_en.cancelTradeButton), findsOneWidget);
    });

    testWidgets(
      'seller + disputed: View dispute, Release + Cancel, no Dispute, no timeline',
      (tester) async {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-5',
          isBuyer: false,
          status: OrderStatus.dispute,
        );

        expect(find.text(_en.tradeChipDispute), findsOneWidget);
        expect(_filledButtonWithText(_en.viewDisputeButton), findsOneWidget);
        expect(_outlinedButtonWithText(_en.releaseSatsButton), findsOneWidget);
        expect(_outlinedButtonWithText(_en.cancel), findsOneWidget);
        expect(_outlinedButtonWithText(_en.openDisputeButton), findsNothing);
        expect(find.byType(TradeTimeline), findsNothing);
        expect(find.byType(TradeChatCard), findsOneWidget);
      },
    );

    testWidgets('buyer + disputed: View dispute and Cancel, no Release', (
      tester,
    ) async {
      // mostrod accepts a cooperative cancel from either party in `dispute`.
      await _pumpTradeDetail(
        tester,
        orderId: 'order-6',
        isBuyer: true,
        status: OrderStatus.dispute,
      );

      expect(_filledButtonWithText(_en.viewDisputeButton), findsOneWidget);
      expect(_outlinedButtonWithText(_en.cancelTradeButton), findsOneWidget);
      expect(_outlinedButtonWithText(_en.releaseSatsButton), findsNothing);
      expect(_outlinedButtonWithText(_en.openDisputeButton), findsNothing);
    });

    testWidgets('cancelled: the reason, Close, no chat, no timeline', (
      tester,
    ) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-cancelled',
        isBuyer: true,
        status: OrderStatus.canceled,
      );

      expect(find.text(_en.tradeHeadlineCancelled), findsOneWidget);
      expect(find.text(_en.tradeInstructionCancelled), findsOneWidget);
      expect(_filledButtonWithText(_en.tradeCloseAction), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TradeChatCard), findsNothing);
      expect(find.byType(TradeChatLockedLine), findsNothing);
      expect(find.byType(TradeTimeline), findsNothing);
    });
  });

  group('overflow menu (Share order)', () {
    testWidgets(
      'contains only Share order; tapping it shows the coming-soon SnackBar',
      (tester) async {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-7',
          isBuyer: true,
          status: OrderStatus.active,
        );

        // The bar has its own Cancel/Dispute — the menu must not repeat them.
        expect(_outlinedButtonWithText(_en.cancel), findsOneWidget);
        expect(_outlinedButtonWithText(_en.openDisputeButton), findsOneWidget);
        expect(_anyPopupMenuItem(), findsNothing);

        await tester.tap(find.byIcon(Icons.more_vert));
        // The popup route animates in; two pumps let it finish so the tap
        // below lands on the item and not mid-transition.
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 350));

        expect(_anyPopupMenuItem(), findsOneWidget);
        expect(find.text(_en.shareOrderButton), findsOneWidget);

        await tester.tap(_anyPopupMenuItem());
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.text(_en.comingSoonMessage), findsOneWidget);
      },
    );
  });

  group('action failures propagate to the button', () {
    // No RustLib.init() in this harness (see _pumpTradeDetail's doc comment),
    // so every orders_api / disputes_api call below fails for real —
    // exercising the actual rethrow path instead of a mocked one.
    testWidgets(
      'cancel: bridge failure shows the SnackBar and does not crash',
      (tester) async {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-9',
          isBuyer: true,
          status: OrderStatus.active,
        );

        await tester.tap(_outlinedButtonWithText(_en.cancel));
        await tester.pump();

        expect(find.text(_en.yesCancelButtonLabel), findsOneWidget);
        await tester.tap(find.text(_en.yesCancelButtonLabel));
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text(_en.cancelRequestFailed), findsOneWidget);

        // Flush the button's own 4s error cooldown timer.
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'open dispute: bridge failure shows the SnackBar and does not crash',
      (tester) async {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-10',
          isBuyer: true,
          status: OrderStatus.active,
        );

        await tester.tap(_outlinedButtonWithText(_en.openDisputeButton));
        await tester.pump();
        await tester.pump();

        // #280: opening a dispute confirms first.
        expect(find.text(_en.yesButtonLabel), findsOneWidget);
        await tester.tap(find.text(_en.yesButtonLabel));
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text(_en.openDisputeFailed), findsOneWidget);

        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'release: bridge failure shows the SnackBar and does not crash',
      (tester) async {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-11',
          isBuyer: false,
          status: OrderStatus.fiatSent,
        );

        await tester.tap(find.text(_en.confirmReleaseSatsButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.text(_en.releaseSheetConfirm), findsOneWidget);
        await tester.tap(find.text(_en.releaseSheetConfirm));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(tester.takeException(), isNull);
        expect(find.text(_en.releaseFailed), findsOneWidget);

        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'send rating: bridge failure shows the SnackBar and does not crash',
      (tester) async {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-rate-fail',
          isBuyer: true,
          status: OrderStatus.success,
          rating: null,
        );

        await tester.tap(find.bySemanticsLabel(_en.selectStarTooltip(4)));
        await tester.pump();
        await tester.tap(find.text(_en.tradeSendRatingAction));
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text(_en.ratingFailed), findsOneWidget);

        await tester.pump(const Duration(seconds: 4));
      },
    );
  });

  /// #327: the daemon never reports a "rated" order status — a successful
  /// trade stays successful once the rating is sent — so the screen resolves
  /// the rate prompt by overlaying the locally held rating.
  group('8e · completed', () {
    testWidgets(
      'not rated yet: five stars, Send rating disabled until one is picked, Close link',
      (tester) async {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-rate-1',
          isBuyer: false,
          status: OrderStatus.success,
          rating: null,
        );

        expect(find.byType(TradeCompletedCard), findsOneWidget);
        expect(find.byType(TradeChatCard), findsNothing);
        expect(find.byType(TradeStepBlock), findsNothing);
        for (var star = 1; star <= 5; star++) {
          expect(
            find.bySemanticsLabel(_en.selectStarTooltip(star)),
            findsOneWidget,
          );
        }
        final send = tester.widget<FilledButton>(
          _filledButtonWithText(_en.tradeSendRatingAction),
        );
        expect(send.onPressed, isNull);
        expect(
          find.ancestor(
            of: find.text(_en.tradeCloseAction),
            matching: find.byType(TextButton),
          ),
          findsOneWidget,
        );

        await tester.tap(find.bySemanticsLabel(_en.selectStarTooltip(3)));
        await tester.pump();

        expect(
          tester
              .widget<FilledButton>(
                _filledButtonWithText(_en.tradeSendRatingAction),
              )
              .onPressed,
          isNotNull,
        );
        expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
      },
    );

    testWidgets('rated by me: the rating row and a full-width Close', (
      tester,
    ) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-rate-2',
        isBuyer: true,
        status: OrderStatus.success,
        rating: _rating(isMine: true, score: 5),
      );

      expect(find.text(_en.tradeCompletedTitle), findsOneWidget);
      expect(
        find.textContaining(
          _en.tradeRatedCounterpart(_en.unknownPeerHandle, '5'),
        ),
        findsOneWidget,
      );
      expect(_filledButtonWithText(_en.tradeSendRatingAction), findsNothing);
      expect(_filledButtonWithText(_en.tradeCloseAction), findsOneWidget);
      expect(find.bySemanticsLabel(_en.selectStarTooltip(1)), findsNothing);
    });

    /// The store falls back to the counterpart's rating when the local user
    /// has not submitted one, so a rating alone must not resolve the prompt —
    /// being rated is not the same as having rated.
    testWidgets('rated by the counterpart only: the stars stay', (
      tester,
    ) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-rate-3',
        isBuyer: false,
        status: OrderStatus.success,
        rating: _rating(isMine: false),
      );

      expect(_filledButtonWithText(_en.tradeSendRatingAction), findsOneWidget);
      expect(find.bySemanticsLabel(_en.selectStarTooltip(1)), findsOneWidget);
      expect(_filledButtonWithText(_en.tradeCloseAction), findsNothing);
    });

    /// The screen holds `loading` while the first rating lookup is in
    /// flight, for the same reason it does while the order status is
    /// unresolved: never flash an action that may change on the next frame.
    testWidgets('rating lookup unresolved: no action at all', (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-rate-4',
        isBuyer: false,
        status: OrderStatus.success,
        ratingUnresolved: true,
      );

      expect(find.byType(TradeCompletedCard), findsNothing);
      expect(find.byWidgetPredicate((w) => w is FilledButton), findsNothing);
    });

    /// The post-submission link: once the daemon accepts a rating the screen
    /// invalidates `tradeRatingProvider` and must re-read and resolve the
    /// prompt without being rebuilt from scratch.
    ///
    /// The invalidation is driven directly rather than by tapping Send
    /// rating: `submitRating` calls the bridge with no injectable seam, and
    /// this harness runs without `RustLib.init()`.
    testWidgets('a rating submitted while mounted resolves the prompt', (
      tester,
    ) async {
      const orderId = 'order-rate-5';
      final refresh = Completer<RatingInfo?>();
      var first = true;

      final container = await _pumpTradeDetail(
        tester,
        orderId: orderId,
        isBuyer: false,
        status: OrderStatus.success,
        ratingFetch: () {
          if (first) {
            first = false;
            return Future<RatingInfo?>.value(null);
          }
          return refresh.future;
        },
      );

      expect(_filledButtonWithText(_en.tradeSendRatingAction), findsOneWidget);

      container.invalidate(tradeRatingProvider(orderId));
      container.read(tradeRatingProvider(orderId));
      await tester.pump();

      // Mid-refresh the previous answer still stands, so the prompt holds
      // its ground: only the *first* lookup may hide the card.
      expect(_filledButtonWithText(_en.tradeSendRatingAction), findsOneWidget);

      refresh.complete(_rating(isMine: true, score: 4));
      await _settle(tester);

      expect(
        find.textContaining(
          _en.tradeRatedCounterpart(_en.unknownPeerHandle, '4'),
        ),
        findsOneWidget,
      );
      expect(_filledButtonWithText(_en.tradeSendRatingAction), findsNothing);
      expect(_filledButtonWithText(_en.tradeCloseAction), findsOneWidget);
    });
  });

  group('automation readouts', () {
    testWidgets('order.status and order.id are exposed by machine name', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpTradeDetail(
          tester,
          orderId: 'a-very-long-order-identifier-0123',
          isBuyer: true,
          status: OrderStatus.active,
        );

        expect(
          tester.getSemantics(find.bySemanticsLabel('active')),
          isSemantics(identifier: AutomationIds.orderStatus, label: 'active'),
        );
        // The id row is the last row of the scroll, below the fold of the
        // test window — hence `skipOffstage: false`.
        expect(
          tester.getSemantics(
            find.bySemanticsLabel(
              'a-very-long-order-identifier-0123',
              skipOffstage: false,
            ),
          ),
          isSemantics(
            identifier: AutomationIds.orderId,
            label: 'a-very-long-order-identifier-0123',
          ),
        );
        // The visible id is shortened around an ellipsis.
        expect(find.text('a-very-l…0123', skipOffstage: false), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('the completed card keeps the stars addressable', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-rate-ids',
          isBuyer: true,
          status: OrderStatus.success,
          rating: null,
        );

        expect(find.bySemanticsLabel('pending-rating'), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel(_en.selectStarTooltip(2))),
          isSemantics(identifier: AutomationIds.tradeRateStar(2)),
        );
      } finally {
        semantics.dispose();
      }
    });
  });

  group('layout', () {
    for (final status in [
      OrderStatus.waitingPayment,
      OrderStatus.active,
      OrderStatus.fiatSent,
      OrderStatus.success,
    ]) {
      testWidgets('German labels on a 360dp width do not overflow ($status)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpTradeDetail(
          tester,
          orderId: 'order-de-$status',
          isBuyer: status != OrderStatus.fiatSent,
          status: status,
          locale: const Locale('de'),
        );
        expect(tester.takeException(), isNull);
      });
    }

    // DS-A11Y-4: 320 dp, 2× text, German. The id row (label, shortened id,
    // copy icon and, with the order in the book, its creation date) is the
    // one this screen's own code lays out; the step block header has its own
    // debt, so these statuses are the ones whose header fits.
    for (final status in [OrderStatus.waitingPayment, OrderStatus.success]) {
      for (final inBook in [false, true]) {
        testWidgets('the id row fits 320 dp at 2× text in German '
            '($status, ${inBook ? 'with' : 'without'} the creation date)', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(320, 760);
          tester.view.devicePixelRatio = 1.0;
          tester.platformDispatcher.textScaleFactorTestValue = 2.0;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await _pumpTradeDetail(
            tester,
            orderId: 'order-de-narrow',
            isBuyer: true,
            status: status,
            locale: const Locale('de'),
            book: inBook ? [fakeOrder(id: 'order-de-narrow')] : const [],
          );
          // The row closes the scroll: bring it on screen so its last
          // layout is the one checked, with the date when the order is in
          // the book.
          await tester.scrollUntilVisible(find.text('ID'), 200);
          if (inBook) {
            expect(find.textContaining('erstellt'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }

    // DS-A11Y-4: the disputed bar gained the buyer's Cancel; the seller's
    // carries Release and Cancel side by side under View dispute.
    for (final isBuyer in [true, false]) {
      testWidgets('the disputed bar in German, 320dp, 2x text '
          '(isBuyer: $isBuyer)', (tester) async {
        tester.view.physicalSize = const Size(320, 760);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await _pumpTradeDetail(
          tester,
          orderId: 'order-de-dispute-$isBuyer',
          isBuyer: isBuyer,
          status: OrderStatus.dispute,
          locale: const Locale('de'),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(OutlinedButton), findsNWidgets(isBuyer ? 1 : 2));
      });
    }
  });

  group('the cancel dialog says what the cancel does', () {
    final l10n = AppLocalizationsEn();
    final texts = [
      l10n.cancelTradeDialogContentNotStarted,
      l10n.cancelTradeDialogContentMaybeStarted,
      l10n.cancelTradeDialogContent,
    ];
    for (final (status, kind, expected) in [
      // Before `active` mostrod cancels at once: the dialog used to announce
      // a cooperative request the counterparty had to accept.
      (
        OrderStatus.waitingPayment,
        'immediate',
        l10n.cancelTradeDialogContentNotStarted,
      ),
      (
        OrderStatus.waitingBuyerInvoice,
        'immediate',
        l10n.cancelTradeDialogContentNotStarted,
      ),
      // Taken, real state unknown (#203): either may happen.
      (
        OrderStatus.inProgress,
        'either',
        l10n.cancelTradeDialogContentMaybeStarted,
      ),
      (OrderStatus.active, 'cooperative', l10n.cancelTradeDialogContent),
      (OrderStatus.fiatSent, 'cooperative', l10n.cancelTradeDialogContent),
      // mostrod cancels from `dispute` as from `active`.
      (OrderStatus.dispute, 'cooperative', l10n.cancelTradeDialogContent),
    ]) {
      testWidgets('${status.name}: the $kind cancel', (tester) async {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-cancel-copy',
          isBuyer: true,
          status: status,
        );
        await tester.tap(_cancelButton());
        await tester.pump();

        for (final text in texts) {
          expect(
            find.text(text),
            text == expected ? findsOneWidget : findsNothing,
          );
        }
      });
    }
  });

  group('a trade that is no longer the user\'s', () {
    const orderId = 'order-lost';

    testWidgets('a lost take whose order is public again leaves for home', (
      tester,
    ) async {
      // The take was wiped in Rust and the order handed back to the book,
      // where it reads `pending`: without leaving, the screen showed the
      // ex-taker the maker's "your order is published" view, cancel
      // button included.
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.pending,
        loadTrades: () async => const [],
        book: [fakeOrder(id: orderId)],
      );
      await _finishPageTransition(tester);

      expect(find.byType(TradeDetailScreen), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(
        find.text(AppLocalizationsEn().tradeNoLongerYours),
        findsOneWidget,
      );
    });

    testWidgets('the maker stays on an order of theirs without a trade row', (
      tester,
    ) async {
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.pending,
        loadTrades: () async => const [],
        book: [fakeOrder(id: orderId, isMine: true)],
      );
      await _finishPageTransition(tester);

      expect(find.byType(TradeDetailScreen), findsOneWidget);
      expect(find.text(AppLocalizationsEn().tradeNoLongerYours), findsNothing);
    });

    testWidgets('a take is not judged before its trade row has loaded', (
      tester,
    ) async {
      final trades = Completer<List<TradeInfo>>();
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.waitingBuyerInvoice,
        loadTrades: () => trades.future,
      );
      await _finishPageTransition(tester);
      expect(
        find.byType(TradeDetailScreen),
        findsOneWidget,
        reason: 'no answer yet is not an absent row',
      );

      trades.complete([fakeTrade(id: 'lost')]);
      await _finishPageTransition(tester);
      expect(find.byType(TradeDetailScreen), findsOneWidget);
    });

    testWidgets('cancelling a trade that never went active leaves for home', (
      tester,
    ) async {
      final cancelled = <String>[];
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.waitingPayment,
        loadTrades: () async => [fakeTrade(id: 'lost')],
        cancelOrder: (id) async => cancelled.add(id),
      );

      await _cancelFromTradeDetail(tester);
      await _finishPageTransition(tester);

      expect(cancelled, [orderId]);
      expect(find.byType(TradeDetailScreen), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(find.text(AppLocalizationsEn().cancelRequestSent), findsOneWidget);
      // Drain the button's success indication, which outlives the screen.
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('cancelling an active trade stays on the screen', (
      tester,
    ) async {
      // From `active` on a cancel is a cooperative request: the trade goes on
      // until the counterparty agrees.
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.active,
        loadTrades:
            () async => [fakeTrade(id: 'lost', status: OrderStatus.active)],
        cancelOrder: (_) async {},
      );

      await _cancelFromTradeDetail(tester);
      await _finishPageTransition(tester);

      expect(find.byType(TradeDetailScreen), findsOneWidget);
      expect(find.text(AppLocalizationsEn().cancelRequestSent), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a trade that goes active while the cancel dialog is open '
        'stays open', (tester) async {
      // The seller's payment can land while the buyer hesitates. The cancel
      // then goes out as a cooperative request, and leaving would strand an
      // active trade behind a "cancel sent" snackbar.
      final l10n = AppLocalizationsEn();
      final status = StreamController<OrderStatus>();
      addTearDown(() => unawaited(status.close()));
      status.add(OrderStatus.waitingPayment);
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.waitingPayment,
        statusUpdates: status.stream,
        loadTrades:
            () async => [
              fakeTrade(id: 'lost', status: OrderStatus.waitingPayment),
            ],
        cancelOrder: (_) async {},
      );
      await tester.tap(_cancelButton());
      await tester.pump();
      expect(
        find.text(l10n.cancelTradeDialogContentNotStarted),
        findsOneWidget,
      );

      status.add(OrderStatus.active);
      await tester.pump();
      await tester.pump();
      expect(
        find.text(l10n.cancelTradeDialogContent),
        findsOneWidget,
        reason: 'the copy the user confirms follows the live status',
      );
      expect(find.text(l10n.cancelTradeDialogContentNotStarted), findsNothing);

      await tester.tap(find.text(l10n.yesCancelButtonLabel));
      await tester.pump();
      await tester.pump();
      await _finishPageTransition(tester);

      expect(find.byType(TradeDetailScreen), findsOneWidget);
      expect(find.text(l10n.cancelRequestSent), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('an absent row is not judged before the order book loads', (
      tester,
    ) async {
      // A cold start can resolve the trades list before the book's first
      // emission. Until the book answers, a missing order is not a
      // stranger's one.
      final book = StreamController<List<OrderItem>>();
      addTearDown(() => unawaited(book.close()));
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.pending,
        loadTrades: () async => const [],
        bookUpdates: book.stream,
      );
      await _finishPageTransition(tester);
      expect(
        find.byType(TradeDetailScreen),
        findsOneWidget,
        reason: 'the book has not answered yet',
      );

      book.add([fakeOrder(id: orderId, isMine: true)]);
      await _finishPageTransition(tester);
      expect(
        find.byType(TradeDetailScreen),
        findsOneWidget,
        reason: "the maker's own order arrived",
      );
    });
  });

  group('the trade row outranks what the book says about the order', () {
    const orderId = 'order-row';

    testWidgets('a take left Canceled reads cancelled over a public pending', (
      tester,
    ) async {
      // Older builds marked a take Canceled as soon as its cancel went out;
      // the daemon then put the order back in the book, where it reads
      // `pending`. Shown as is, that was the user's own order with a Cancel
      // the daemon refuses (IsNotYourOrder).
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.pending,
        loadTrades:
            () async => [fakeTrade(id: 'row', status: OrderStatus.canceled)],
        book: [fakeOrder(id: orderId)],
      );
      await _finishPageTransition(tester);

      expect(find.byType(TradeDetailScreen), findsOneWidget);
      expect(find.text(_en.tradeHeadlineCancelled), findsOneWidget);
      expect(find.text(_en.tradeHeadlinePending), findsNothing);
      expect(_cancelButton(), findsNothing);
    });

    testWidgets('a public pending waits for the row before it is shown', (
      tester,
    ) async {
      // The row is a full trades read, while the role comes from an indexed
      // lookup, so opening a leftover take cold (a notification, the chat
      // header, a restart) resolves the role first. Shown as is, the book's
      // `pending` offered the maker's view with a Cancel the daemon refuses.
      final trades = Completer<List<TradeInfo>>();
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.pending,
        loadTrades: () => trades.future,
        book: [fakeOrder(id: orderId)],
      );
      await _finishPageTransition(tester);

      expect(find.text(_en.tradeHeadlinePending), findsNothing);
      expect(_cancelButton(), findsNothing);

      trades.complete([fakeTrade(id: 'row', status: OrderStatus.canceled)]);
      await _finishPageTransition(tester);

      expect(find.text(_en.tradeHeadlineCancelled), findsOneWidget);
      expect(_cancelButton(), findsNothing);
    });

    testWidgets('no nudge either while the row is still loading', (
      tester,
    ) async {
      final nudges = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') nudges.add('$call');
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final book = StreamController<OrderStatus>();
      addTearDown(() => unawaited(book.close()));
      book.add(OrderStatus.pending);
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.pending,
        statusUpdates: book.stream,
        loadTrades: () => Completer<List<TradeInfo>>().future,
      );
      await _finishPageTransition(tester);

      book.add(OrderStatus.inProgress);
      await tester.pump();
      await tester.pump();

      expect(nudges, isEmpty);
    });

    testWidgets('an ended take stays ended when someone else completes it', (
      tester,
    ) async {
      // The same leftover row, its order since taken and completed by
      // someone else: the book's `success` is not this user's trade. The
      // My Trades list reads it the same way.
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.success,
        loadTrades:
            () async => [fakeTrade(id: 'row', status: OrderStatus.canceled)],
      );
      await _finishPageTransition(tester);

      expect(find.text(_en.tradeHeadlineCancelled), findsOneWidget);
      expect(find.byType(TradeCompletedCard), findsNothing);
    });

    testWidgets('an open take keeps its own step over a public pending', (
      tester,
    ) async {
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.pending,
        loadTrades:
            () async => [
              fakeTrade(id: 'row', status: OrderStatus.waitingPayment),
            ],
        book: [fakeOrder(id: orderId)],
      );
      await _finishPageTransition(tester);

      expect(find.text(_en.tradeHeadlineWaitingPaymentBuyer), findsOneWidget);
      expect(find.text(_en.tradeHeadlinePending), findsNothing);
    });

    testWidgets("a maker's order still reads pending from the book", (
      tester,
    ) async {
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.pending,
        loadTrades:
            () async => [
              fakeTrade(
                id: 'row',
                status: OrderStatus.waitingPayment,
                isMine: true,
              ),
            ],
        book: [fakeOrder(id: orderId, isMine: true)],
      );
      await _finishPageTransition(tester);

      expect(find.text(_en.tradeHeadlinePending), findsOneWidget);
    });

    testWidgets('a book change the row outranks is not a step: no nudge', (
      tester,
    ) async {
      final nudges = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') nudges.add('$call');
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final book = StreamController<OrderStatus>();
      addTearDown(() => unawaited(book.close()));
      book.add(OrderStatus.pending);
      await _pumpRoutedTradeDetail(
        tester,
        orderId: orderId,
        status: OrderStatus.pending,
        statusUpdates: book.stream,
        loadTrades:
            () async => [fakeTrade(id: 'row', status: OrderStatus.canceled)],
      );
      await _finishPageTransition(tester);

      // Someone else takes the order: the book moves, this trade does not.
      book.add(OrderStatus.inProgress);
      await tester.pump();
      await tester.pump();

      expect(nudges, isEmpty);
      expect(find.text(_en.tradeHeadlineCancelled), findsOneWidget);
    });
  });

  group('a range order taken for one amount inside it', () {
    // The book keeps the range; the trade row holds the slice the take
    // priced (MostroP2P/app#620).
    TradeInfo takenRange(OrderStatus status) => fakeTrade(
      id: 'range',
      status: status,
      role: TradeRole.seller,
      fiatCode: 'ARS',
      paymentMethod: 'Mercado Pago',
      isMine: true,
      fiatAmount: 219500,
      fiatAmountMin: 10000,
      fiatAmountMax: 1000000,
      amountSats: BigInt.from(163069),
    );
    final rangeInBook = fakeOrder(
      id: 'order-range',
      fiatAmountMin: 10000,
      fiatAmountMax: 1000000,
      fiatCode: 'ARS',
      paymentMethod: 'Mercado Pago',
      isMine: true,
    );

    testWidgets('the step card says what was sold, in fiat and sats', (
      tester,
    ) async {
      // Arrange + Act
      await _pumpTradeDetail(
        tester,
        orderId: 'order-range',
        isBuyer: false,
        status: OrderStatus.waitingPayment,
        trades: [takenRange(OrderStatus.waitingPayment)],
        book: [rangeInBook],
      );

      // Assert
      expect(
        find.text('${_en.tradesDirectionSell} · 219,500 ARS · 163,069 sats'),
        findsOneWidget,
      );
      expect(find.textContaining('10,000'), findsNothing);
    });

    testWidgets('the side comes from the row while the role is unknown', (
      tester,
    ) async {
      // Arrange + Act: the role lookup has no answer; the row says seller.
      await _pumpTradeDetail(
        tester,
        orderId: 'order-range',
        isBuyer: true,
        roleKnown: false,
        status: OrderStatus.waitingPayment,
        trades: [takenRange(OrderStatus.waitingPayment)],
        book: [rangeInBook],
      );

      // Assert
      expect(
        find.text('${_en.tradesDirectionSell} · 219,500 ARS · 163,069 sats'),
        findsOneWidget,
      );
      expect(find.textContaining(_en.tradesDirectionBuy), findsNothing);
    });

    testWidgets('the headline names the slice, not the range', (tester) async {
      // Arrange + Act
      await _pumpTradeDetail(
        tester,
        orderId: 'order-range',
        isBuyer: false,
        status: OrderStatus.active,
        trades: [takenRange(OrderStatus.active)],
        book: [rangeInBook],
      );

      // Assert
      expect(
        find.text(_en.tradeHeadlineActiveSeller('219,500 ARS')),
        findsOneWidget,
      );
      expect(find.textContaining('1000000'), findsNothing);
    });
  });

  group('View dispute on a dispute the counterparty opened', () {
    // The list is only hydrated on resume or when this side opens the
    // dispute, so the peer's is missing from it; the bridge holds it.
    testWidgets('asks the bridge and opens the dispute', (tester) async {
      // Arrange
      final asked = <String>[];
      await _pumpRoutedTradeDetail(
        tester,
        orderId: 'order-peer-dispute',
        status: OrderStatus.dispute,
        loadTrades:
            () async => [
              fakeTrade(
                id: 'peer-dispute',
                status: OrderStatus.dispute,
                role: TradeRole.buyer,
              ),
            ],
        disputeLookup: (tradeId) async {
          asked.add(tradeId);
          return Dispute(
            id: 'dispute-9',
            tradeId: tradeId,
            status: DisputeStatus.open,
            initiatedByMe: false,
            openedAt: intToPlatformInt64(1000),
            isRead: false,
            chatKeyShared: false,
          );
        },
      );

      // Act
      await tester.tap(_filledButtonWithText(_en.viewDisputeButton));
      await _finishPageTransition(tester);

      // Assert
      expect(asked, ['order-peer-dispute']);
      expect(find.text(_en.disputeNotFoundForOrder), findsNothing);
      expect(find.text('dispute dispute-9'), findsOneWidget);
      // Let the button's and the snackbar's timers run out.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('says so when the bridge has none either', (tester) async {
      // Arrange
      await _pumpRoutedTradeDetail(
        tester,
        orderId: 'order-no-dispute',
        status: OrderStatus.dispute,
        loadTrades:
            () async => [
              fakeTrade(
                id: 'no-dispute',
                status: OrderStatus.dispute,
                role: TradeRole.buyer,
              ),
            ],
        disputeLookup: (_) async => null,
      );

      // Act
      await tester.tap(_filledButtonWithText(_en.viewDisputeButton));
      await tester.pump();
      await tester.pump();

      // Assert
      expect(find.text(_en.disputeNotFoundForOrder), findsOneWidget);
      // Let the button's and the snackbar's timers run out.
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('the chat card stays pinned above the scroll', () {
    Finder inList(Type type) =>
        find.descendant(of: find.byType(ListView), matching: find.byType(type));

    testWidgets('scrolling to the bottom leaves it in place, tappable', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 560);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pumpTradeDetail(
        tester,
        orderId: 'order-pinned',
        isBuyer: true,
        status: OrderStatus.active,
      );
      expect(inList(TradeChatCard), findsNothing);
      final before = tester.getTopLeft(find.byType(TradeChatCard));

      await tester.scrollUntilVisible(
        find.text(_en.tradeIdLabel),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await _settle(tester);

      expect(tester.getTopLeft(find.byType(TradeChatCard)), before);
      expect(find.byType(TradeChatCard).hitTestable(), findsOneWidget);
    });

    testWidgets('the lock note before the trade is active scrolls with the '
        'content', (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-locked',
        isBuyer: true,
        status: OrderStatus.waitingPayment,
      );
      expect(inList(TradeChatLockedLine), findsOneWidget);
      expect(find.byType(TradeChatCard), findsNothing);
    });

    const room = ChatRoomState(
      orderId: 'order-done',
      peerPubkey: 'peer',
      peerHandle: 'bright-fox-41',
      peerIconIndex: 3,
      peerColorHue: 120,
      isSelling: false,
    );

    for (final (name, chatState, closed) in [
      (
        'keeps it open during its hour',
        const ChatRowState(
          group: ChatGroup.active,
          tone: ChatAvatarTone.waiting,
        ),
        false,
      ),
      (
        'keeps it, closed, once the hour is over',
        const ChatRowState(
          group: ChatGroup.closed,
          tone: ChatAvatarTone.closed,
        ),
        true,
      ),
    ]) {
      testWidgets('a completed trade $name (#642)', (tester) async {
        final container = await _pumpTradeDetail(
          tester,
          orderId: 'order-done',
          isBuyer: true,
          status: OrderStatus.success,
          chatState: chatState,
        );
        container.read(chatRoomsNotifierProvider.notifier).upsertRoom(room);
        await _settle(tester);

        expect(find.byType(TradeChatCard), findsOneWidget);
        expect(inList(TradeChatCard), findsNothing);
        expect(
          find.text(_en.tradeChatClosed),
          closed ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets('a trade cancelled after it was active keeps it, closed', (
      tester,
    ) async {
      final container = await _pumpTradeDetail(
        tester,
        orderId: 'order-done',
        isBuyer: true,
        status: OrderStatus.canceled,
        chatState: const ChatRowState(
          group: ChatGroup.closed,
          tone: ChatAvatarTone.closed,
        ),
      );
      container
          .read(chatRoomsNotifierProvider.notifier)
          .upsertRoom(room.copyWith(unreadCount: 3));
      await _settle(tester);

      expect(find.text(_en.tradeChatClosed), findsOneWidget);
      // Unread until the room is opened, as the chat list and the Chat tab
      // count them: closing the conversation does not read its messages.
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('a trade cancelled before it was active has no card', (
      tester,
    ) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-never-active',
        isBuyer: true,
        status: OrderStatus.canceled,
      );
      expect(find.byType(TradeChatCard), findsNothing);
    });

    testWidgets('the card turns closed when the conversation ends on screen', (
      tester,
    ) async {
      final chatState = StateProvider(
        (_) => const ChatRowState(
          group: ChatGroup.active,
          tone: ChatAvatarTone.waiting,
        ),
      );
      final container = await _pumpTradeDetail(
        tester,
        orderId: 'order-done',
        isBuyer: true,
        status: OrderStatus.success,
        extraOverrides: [
          chatRowStateProvider(
            'order-done',
          ).overrideWith((ref) => ref.watch(chatState)),
        ],
      );
      container.read(chatRoomsNotifierProvider.notifier).upsertRoom(room);
      await _settle(tester);
      expect(find.text(_en.tradeChatEncrypted), findsOneWidget);

      container.read(chatState.notifier).state = const ChatRowState(
        group: ChatGroup.closed,
        tone: ChatAvatarTone.closed,
      );
      await _settle(tester);
      expect(find.text(_en.tradeChatClosed), findsOneWidget);
    });

    testWidgets('the end of the conversation is announced once, on screen', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final chatState = StateProvider(
        (_) => const ChatRowState(
          group: ChatGroup.active,
          tone: ChatAvatarTone.waiting,
        ),
      );
      final container = await _pumpTradeDetail(
        tester,
        orderId: 'order-done',
        isBuyer: true,
        status: OrderStatus.success,
        extraOverrides: [
          chatRowStateProvider(
            'order-done',
          ).overrideWith((ref) => ref.watch(chatState)),
        ],
      );
      container.read(chatRoomsNotifierProvider.notifier).upsertRoom(room);
      await _settle(tester);
      expect(tester.takeAnnouncements(), isEmpty);

      container.read(chatState.notifier).state = const ChatRowState(
        group: ChatGroup.closed,
        tone: ChatAvatarTone.closed,
      );
      await _settle(tester);
      // A rebuild with the conversation still closed says nothing more.
      container
          .read(chatRoomsNotifierProvider.notifier)
          .upsertRoom(room.copyWith(unreadCount: 1));
      await _settle(tester);

      expect(
        [for (final a in tester.takeAnnouncements()) a.message],
        [_en.tradeChatClosedAnnouncement],
      );
      semantics.dispose();
    });

    testWidgets('a conversation already closed when the screen opens is not '
        'announced', (tester) async {
      final semantics = tester.ensureSemantics();
      final container = await _pumpTradeDetail(
        tester,
        orderId: 'order-done',
        isBuyer: true,
        status: OrderStatus.canceled,
        chatState: const ChatRowState(
          group: ChatGroup.closed,
          tone: ChatAvatarTone.closed,
        ),
      );
      container.read(chatRoomsNotifierProvider.notifier).upsertRoom(room);
      await _settle(tester);

      expect(tester.takeAnnouncements(), isEmpty);
      semantics.dispose();
    });

    testWidgets('turning active, the lock note never fades over the step '
        'block, which crossfades', (tester) async {
      final updates = StreamController<OrderStatus>();
      addTearDown(() => unawaited(updates.close()));
      updates.add(OrderStatus.waitingPayment);
      await _pumpTradeDetail(
        tester,
        orderId: 'order-turns-active',
        isBuyer: true,
        status: OrderStatus.waitingPayment,
        statusUpdates: updates.stream,
      );
      expect(inList(TradeChatLockedLine), findsOneWidget);

      updates.add(OrderStatus.active);
      await tester.pump();
      var crossfaded = false;
      for (var frame = 0; frame < 15; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        final blocks = find.byType(TradeStepBlock);
        crossfaded |= blocks.evaluate().length == 2;
        for (final note in find.byType(TradeChatLockedLine).evaluate()) {
          final noteRect = tester.getRect(find.byWidget(note.widget));
          for (final block in blocks.evaluate()) {
            expect(
              noteRect.overlaps(tester.getRect(find.byWidget(block.widget))),
              isFalse,
              reason: 'frame $frame: the lock note is drawn over a step block',
            );
          }
        }
      }
      expect(crossfaded, isTrue, reason: 'the step block did not crossfade');
      expect(find.byType(TradeChatLockedLine), findsNothing);
      expect(find.byType(TradeChatCard), findsOneWidget);
    });

    testWidgets('with animations off, the card takes the top at once', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final updates = StreamController<OrderStatus>();
      addTearDown(() => unawaited(updates.close()));
      updates.add(OrderStatus.waitingPayment);
      await _pumpTradeDetail(
        tester,
        orderId: 'order-no-motion',
        isBuyer: true,
        status: OrderStatus.waitingPayment,
        statusUpdates: updates.stream,
      );

      updates.add(OrderStatus.active);
      await tester.pump();
      await tester.pump();

      expect(find.byType(TradeChatLockedLine), findsNothing);
      final fades = tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.byType(TradeChatCard),
          matching: find.byType(FadeTransition),
        ),
      );
      expect([for (final f in fades) f.opacity.value], everyElement(1.0));
      final slides = tester.widgetList<SlideTransition>(
        find.ancestor(
          of: find.byType(TradeChatCard),
          matching: find.byType(SlideTransition),
        ),
      );
      expect([
        for (final s in slides) s.position.value,
      ], everyElement(Offset.zero));
    });

    testWidgets('the line under the card goes once nothing scrolls beneath '
        'it', (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final updates = StreamController<OrderStatus>.broadcast();
      addTearDown(() => unawaited(updates.close()));
      final container = await _pumpTradeDetail(
        tester,
        orderId: 'order-done',
        isBuyer: false,
        status: OrderStatus.fiatSent,
        statusUpdates: updates.stream,
        chatState: const ChatRowState(
          group: ChatGroup.active,
          tone: ChatAvatarTone.waiting,
        ),
      );
      container.read(chatRoomsNotifierProvider.notifier).upsertRoom(room);
      updates.add(OrderStatus.fiatSent);
      await _settle(tester);
      final book = OrderBookPalette.of(
        tester.element(find.byType(TradeChatCard)),
      );
      Color chatLine() {
        final box = tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.byType(TradeChatCard),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is DecoratedBox &&
                      w.decoration is BoxDecoration &&
                      (w.decoration as BoxDecoration).border is Border,
                ),
              )
              .first,
        );
        return ((box.decoration as BoxDecoration).border! as Border)
            .bottom
            .color;
      }

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await _settle(tester);
      expect(chatLine(), book.navBorder);

      updates.add(OrderStatus.success);
      await _settle(tester);

      expect(find.byType(TradeChatCard), findsOneWidget);
      expect(chatLine(), Colors.transparent);
    });

    // DS-A11Y-4: the pinned card leaves the rest reachable at 320 dp, 2x text,
    // in German.
    for (final status in [
      OrderStatus.active,
      OrderStatus.fiatSent,
      OrderStatus.dispute,
    ]) {
      testWidgets('German, 320dp, 2x text: the content still scrolls under it '
          '($status)', (tester) async {
        tester.view.physicalSize = const Size(320, 760);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await _pumpTradeDetail(
          tester,
          orderId: 'order-pinned-de-$status',
          // The buyer's active step header still overflows here (its chip,
          // #712); the seller's does not, and the card is the same.
          isBuyer: status != OrderStatus.active,
          status: status,
          locale: const Locale('de'),
        );
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(
          find.text(lookupAppLocalizations(const Locale('de')).tradeIdLabel),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(TradeChatCard).hitTestable(), findsOneWidget);
      });
    }
  });

  // Issue #724, DS-CMP-22: the trade's id row reads the same short form as
  // every other screen (8 + 4, not 5 + 4), beside the copy icon of 16.
  testWidgets('the id row reads the short id with the copy icon', (
    tester,
  ) async {
    const id = '09150348-1a2b-4c3d-8e9f-0a1b2c3d99b5';
    await _pumpTradeDetail(
      tester,
      orderId: id,
      isBuyer: true,
      status: OrderStatus.active,
    );

    expect(find.text('09150348…99b5', skipOffstage: false), findsOneWidget);
    final icon = tester.widget<Icon>(
      find.byIcon(Icons.copy_rounded, skipOffstage: false),
    );
    expect(icon.size, 16);
  });

  // DS-CMP-22: the id row sits in a card of the screen, not bare on the
  // scroll after the timeline.
  testWidgets('the id row sits in a card', (tester) async {
    const id = '09150348-1a2b-4c3d-8e9f-0a1b2c3d99b5';
    await _pumpTradeDetail(
      tester,
      orderId: id,
      isBuyer: true,
      status: OrderStatus.active,
    );

    final card = find.ancestor(
      of: find.text('09150348…99b5', skipOffstage: false),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).border != null &&
            (w.decoration! as BoxDecoration).borderRadius ==
                BorderRadius.circular(18),
        skipOffstage: false,
      ),
    );
    expect(card, findsOneWidget);
  });

  // DS-CMP-6 and DS-A11Y-1: the id card is a copy button at least 48 high.
  testWidgets('the id row is a button of at least 48 dp', (tester) async {
    const id = '09150348-1a2b-4c3d-8e9f-0a1b2c3d99b5';
    final semantics = tester.ensureSemantics();
    await _pumpTradeDetail(
      tester,
      orderId: id,
      isBuyer: true,
      status: OrderStatus.active,
    );

    final row = find.ancestor(
      of: find.text('09150348…99b5', skipOffstage: false),
      matching: find.byType(InkWell, skipOffstage: false),
    );
    expect(row, findsOneWidget);
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSemantics(row),
      isSemantics(isButton: true, hasTapAction: true),
    );
    semantics.dispose();
  });
}
