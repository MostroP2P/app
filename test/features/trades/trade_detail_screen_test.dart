import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/rate/providers/rating_providers.dart';
import 'package:mostro/features/rate/screens/rate_counterpart_screen.dart';
import 'package:mostro/features/rate/widgets/star_rating.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/features/trades/screens/trade_detail_screen.dart';
import 'package:mostro/features/trades/widgets/trade_chat_card.dart';
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
}) async {
  final container = createContainer(
    overrides: [
      if (releaseOrder != null)
        releaseOrderActionProvider.overrideWithValue(releaseOrder),
      tradeRoleProvider.overrideWith((ref) => {orderId: isBuyer}),
      tradeStatusProvider(
        orderId,
      ).overrideWith((ref) => statusUpdates ?? Stream.value(status)),
      orderBookProvider.overrideWith((ref) => Stream.value(const [])),
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
}) async {
  final container = createContainer(
    overrides: [
      if (cancelOrder != null)
        cancelOrderActionProvider.overrideWithValue(cancelOrder),
      tradeRoleProvider.overrideWith((ref) => {orderId: true}),
      tradeStatusProvider(orderId).overrideWith((ref) => Stream.value(status)),
      orderBookProvider.overrideWith((ref) => Stream.value(book)),
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
  group('8a · waiting for the counterpart to lock the sats', () {
    testWidgets(
      'buyer: amber chip, no chat, lock note, Cancel trade alone, no dispute',
      (tester) async {
        await _pumpTradeDetail(
          tester,
          orderId: 'order-8a',
          isBuyer: true,
          status: OrderStatus.waitingPayment,
        );

        expect(find.text(_en.tradeScreenTitle), findsOneWidget);
        expect(find.text(_en.stepIndicator(2, 5)), findsOneWidget);
        expect(find.text(_en.tradeChipWaiting), findsOneWidget);
        expect(find.text(_en.tradeHeadlineWaitingPaymentBuyer), findsOneWidget);
        expect(find.byType(TradeChatLockedLine), findsOneWidget);
        expect(find.byType(TradeChatCard), findsNothing);
        expect(find.text(_en.tradeTimerTheyHave), findsOneWidget);
        expect(
          find.text(_en.tradeTimerWaitingInvoiceConsequence),
          findsOneWidget,
        );
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
      // Drain the button's success indication before disposing its widget.
      await tester.pump(const Duration(seconds: 2));
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
    for (final isBuyer in [true, false]) {
      testWidgets(
        'escrow settlement stays pending for ${isBuyer ? "buyer" : "seller"}',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            await _pumpTradeDetail(
              tester,
              orderId: 'order-payout-pending',
              isBuyer: isBuyer,
              status: OrderStatus.settledHoldInvoice,
              rating: _rating(isMine: true),
            );
            expect(
              tradeStatusFromOrderStatus(
                OrderStatus.settledHoldInvoice,
              ).machineName,
              'payout-pending',
            );
            expect(find.bySemanticsLabel('payout-pending'), findsOneWidget);
            expect(find.text(_en.tradeHeadlinePayoutPending), findsOneWidget);
            expect(find.text(_en.tradeCompletedTitle), findsNothing);
            expect(find.byType(TradeCompletedCard), findsNothing);
            expect(
              find.byWidgetPredicate((w) => w is FilledButton),
              findsNothing,
            );
          } finally {
            semantics.dispose();
          }
        },
      );
    }

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

    testWidgets('a rating notification cannot show success before payout', (
      tester,
    ) async {
      final updates = StreamController<OrderStatus>();
      addTearDown(() => unawaited(updates.close()));
      updates.add(OrderStatus.settledHoldInvoice);
      await _pumpTradeDetail(
        tester,
        orderId: 'order-early-rating',
        isBuyer: false,
        status: OrderStatus.settledHoldInvoice,
        statusUpdates: updates.stream,
        ratingRoute: true,
      );
      expect(find.text(_en.successfulOrder), findsNothing);
      expect(find.byType(StarRating), findsNothing);
      expect(find.text(_en.tradeHeadlinePayoutPending), findsOneWidget);

      updates.add(OrderStatus.success);
      await _settle(tester);

      expect(find.text(_en.successfulOrder), findsOneWidget);
      expect(find.byType(StarRating), findsOneWidget);
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

    testWidgets('buyer + disputed: View dispute only', (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-6',
        isBuyer: true,
        status: OrderStatus.dispute,
      );

      expect(_filledButtonWithText(_en.viewDisputeButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
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
        expect(find.text('a-ver…0123', skipOffstage: false), findsOneWidget);
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
        find.text(AppLocalizationsEn().orderNoLongerActive),
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
      expect(find.text(AppLocalizationsEn().orderNoLongerActive), findsNothing);
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
  });
}
