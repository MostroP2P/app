import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/rate/providers/rating_providers.dart';
import 'package:mostro/features/trades/screens/trade_detail_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart';

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
  RatingInfo? rating,
  bool ratingUnresolved = false,
  Future<RatingInfo?> Function()? ratingFetch,
  Locale locale = const Locale('en'),
}) async {
  final container = createContainer(overrides: [
    tradeRoleProvider.overrideWith((ref) => {orderId: isBuyer}),
    tradeStatusProvider(orderId).overrideWith((ref) => Stream.value(status)),
    orderBookProvider.overrideWith((ref) => Stream.value(const [])),
    tradeRatingProvider(orderId).overrideWith((ref) {
      // A pending Completer future keeps the rating lookup in its first
      // loading state, pinning the no-CTA-flash guard.
      if (ratingUnresolved) return Completer<RatingInfo?>().future;
      return ratingFetch != null ? ratingFetch() : Future.value(rating);
    }),
  ]);

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
        home: TradeDetailScreen(orderId: orderId),
      ),
    ),
  );

  // One frame for the initial build, then a frame to flush the
  // fire-and-forget `_loadExpiresAt` future and the stream-provider
  // emissions above. Deliberately not `pumpAndSettle()`: the screen starts a
  // real 1s-period countdown `Timer.periodic` that keeps scheduling frames
  // for the full 15-minute default duration, which would make
  // `pumpAndSettle()` time out.
  await tester.pump();
  await tester.pump();

  return container;
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

/// Matches an outlined secondary-row button by its visible label text.
Finder _outlinedButtonWithText(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(OutlinedButton),
    );

/// Matches the primary CTA by its visible label text.
///
/// The label alone is ambiguous: the timeline repeats it as the step name.
/// Matched by predicate, not `byType`: `FilledButton.icon` builds a private
/// subclass, which `find.byType(FilledButton)` does not accept.
Finder _filledButtonWithText(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );

/// Matches any `PopupMenuButton`, regardless of its generic type argument.
///
/// The AppBar overflow menu is unconditional (Share order only — see
/// `_buildOverflowMenu`), so it is always present regardless of trade status.
Finder _anyPopupMenuButton() =>
    find.byWidgetPredicate((widget) => widget is PopupMenuButton);

/// Matches any `PopupMenuItem`, regardless of its generic type argument —
/// used to assert the restored overflow menu contains exactly one entry.
Finder _anyPopupMenuItem() =>
    find.byWidgetPredicate((widget) => widget is PopupMenuItem);

void main() {
  group('TradeDetailScreen secondary action row', () {
    testWidgets('buyer + active: Fiat Sent CTA, Cancel + Dispute, no Release',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-1',
        isBuyer: true,
        status: OrderStatus.active,
      );

      expect(find.text('Mark fiat sent'), findsOneWidget);
      expect(_outlinedButtonWithText('Cancel trade'), findsOneWidget);
      expect(_outlinedButtonWithText('Open dispute'), findsOneWidget);
      expect(_outlinedButtonWithText('Release sats'), findsNothing);
      expect(_anyPopupMenuButton(), findsOneWidget);
    });

    /// `in-progress` is the public order book's coarse bucket: the order left
    /// the book, which says nothing about the escrow. Presenting it as an
    /// active trade offered a dispute and a fiat-sent the daemon rejects with
    /// CantDo (issue #203).
    testWidgets('buyer + inProgress: no Dispute and no Fiat Sent CTA',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-in-progress-buyer',
        isBuyer: true,
        status: OrderStatus.inProgress,
      );

      expect(find.text('Mark fiat sent'), findsNothing);
      expect(_outlinedButtonWithText('Open dispute'), findsNothing);
      expect(_outlinedButtonWithText('Release sats'), findsNothing);
      // Cancel stays: the daemon accepts it in every pre-settlement state.
      expect(_outlinedButtonWithText('Cancel trade'), findsOneWidget);
      expect(find.text('Setting up the trade…'), findsOneWidget);
    });

    testWidgets('seller + inProgress: no Dispute and no Release',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-in-progress-seller',
        isBuyer: false,
        status: OrderStatus.inProgress,
      );

      expect(_outlinedButtonWithText('Open dispute'), findsNothing);
      expect(_outlinedButtonWithText('Release sats'), findsNothing);
      expect(_outlinedButtonWithText('Cancel trade'), findsOneWidget);
    });

    testWidgets('buyer + fiatSent: Cancel + Dispute, no Release',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-2',
        isBuyer: true,
        status: OrderStatus.fiatSent,
      );

      expect(_outlinedButtonWithText('Cancel trade'), findsOneWidget);
      expect(_outlinedButtonWithText('Open dispute'), findsOneWidget);
      expect(_outlinedButtonWithText('Release sats'), findsNothing);
      expect(_anyPopupMenuButton(), findsOneWidget);
    });

    testWidgets('seller + active: Cancel + Dispute, no Release',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-3',
        isBuyer: false,
        status: OrderStatus.active,
      );

      expect(_outlinedButtonWithText('Cancel trade'), findsOneWidget);
      expect(_outlinedButtonWithText('Open dispute'), findsOneWidget);
      expect(_outlinedButtonWithText('Release sats'), findsNothing);
      expect(_anyPopupMenuButton(), findsOneWidget);
    });

    testWidgets(
        'seller + fiatSent: Confirm & release CTA, Cancel + Dispute, no secondary Release',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-4',
        isBuyer: false,
        status: OrderStatus.fiatSent,
      );

      expect(find.text('Confirm & release sats'), findsOneWidget);
      expect(_outlinedButtonWithText('Cancel trade'), findsOneWidget);
      expect(_outlinedButtonWithText('Open dispute'), findsOneWidget);
      expect(_outlinedButtonWithText('Release sats'), findsNothing);
      expect(_anyPopupMenuButton(), findsOneWidget);
    });

    testWidgets(
        'seller + disputed: View dispute CTA, Release + Cancel, no Dispute',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-5',
        isBuyer: false,
        status: OrderStatus.dispute,
      );

      expect(find.text('View dispute'), findsOneWidget);
      expect(_outlinedButtonWithText('Release sats'), findsOneWidget);
      expect(_outlinedButtonWithText('Cancel trade'), findsOneWidget);
      // canDispute is false once already disputed — no "Open dispute" button.
      expect(_outlinedButtonWithText('Open dispute'), findsNothing);
      expect(_anyPopupMenuButton(), findsOneWidget);
    });

    testWidgets('buyer + disputed: no secondary row at all', (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-6',
        isBuyer: true,
        status: OrderStatus.dispute,
      );

      expect(find.text('View dispute'), findsOneWidget);
      // Per the existing gating rules, canCancel/canDispute/canRelease are
      // all false for buyer + disputed — see gating logic in
      // trade_detail_screen.dart (`_buildSecondaryActionRow`).
      expect(_outlinedButtonWithText('Release sats'), findsNothing);
      expect(_outlinedButtonWithText('Cancel trade'), findsNothing);
      expect(_outlinedButtonWithText('Open dispute'), findsNothing);
      expect(_anyPopupMenuButton(), findsOneWidget);
    });
  });

  group('TradeDetailScreen overflow menu (Share order)', () {
    testWidgets(
        'contains only Share order; tapping it shows the coming-soon '
        'SnackBar; Cancel/Dispute/Release are not duplicated into it',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-7',
        isBuyer: true,
        status: OrderStatus.active,
      );

      // Secondary row is visible for this status/role, with its own
      // Cancel/Dispute buttons — the menu must not duplicate them.
      expect(_outlinedButtonWithText('Cancel trade'), findsOneWidget);
      expect(_outlinedButtonWithText('Open dispute'), findsOneWidget);
      expect(_anyPopupMenuItem(), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert));
      // The popup menu's opening route animates in — pumpAndSettle() is
      // unsafe here: the screen's 1s countdown Timer.periodic keeps
      // scheduling frames for its full 15-minute duration, so it never
      // reports "settled". Two pumps let the open transition fully finish;
      // tapping mid-transition hits the wrong on-screen position and misses
      // the item.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      expect(_anyPopupMenuItem(), findsOneWidget);
      expect(find.text('Share order'), findsOneWidget);

      // A real tap gesture exercises the actual value wired to onSelected,
      // catching a wrong PopupMenuItem value that a direct callback
      // invocation would not — `_OverflowAction` is private to the screen,
      // so the test cannot construct one to invoke onSelected directly
      // anyway. Two more pumps: one for the closing-route animation onSelected
      // waits on, one for the SnackBar's own entrance animation.
      await tester.tap(_anyPopupMenuItem());
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Coming soon'), findsOneWidget);
    });
  });

  group('TradeDetailScreen secondary action failures propagate to the button',
      () {
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

      await tester.tap(_outlinedButtonWithText('Cancel trade'));
      await tester.pump();

      expect(find.text('Yes, cancel'), findsOneWidget);
      await tester.tap(find.text('Yes, cancel'));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Failed to cancel. Please try again.'),
        findsOneWidget,
      );

      // Flush the button's own 4s error cooldown timer so it does not
      // outlive this test.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'open dispute: bridge failure shows the SnackBar and does not crash',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-10',
        isBuyer: true,
        status: OrderStatus.active,
      );

      await tester.tap(_outlinedButtonWithText('Open dispute'));
      await tester.pump();
      await tester.pump();

      // #280: opening a dispute now confirms first — tap Yes to reach
      // the bridge call, mirroring the release/cancel confirmation flow.
      final confirmLabel = AppLocalizationsEn().yesButtonLabel;
      expect(find.text(confirmLabel), findsOneWidget);
      await tester.tap(find.text(confirmLabel));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.text('Could not open dispute. Please try again.'),
        findsOneWidget,
      );

      // Flush the button's own 4s error cooldown timer so it does not
      // outlive this test.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'release: bridge failure shows the SnackBar and does not crash',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-11',
        isBuyer: false,
        status: OrderStatus.fiatSent,
      );

      await tester.tap(find.text('Confirm & release sats'));
      await tester.pump();

      final confirmLabel = AppLocalizationsEn().yesButtonLabel;
      expect(find.text(confirmLabel), findsOneWidget);
      await tester.tap(find.text(confirmLabel));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.text('Failed to release. Please try again.'),
        findsOneWidget,
      );

      // Flush the button's own 4s error cooldown timer so it does not
      // outlive this test.
      await tester.pump(const Duration(seconds: 4));
    });
  });

  /// #327: the daemon never reports a "rated" order status — a settled trade
  /// stays settled once the rating is sent — so the screen resolves the rate
  /// prompt by overlaying the locally held rating.
  group('TradeDetailScreen rated state', () {
    testWidgets('settled + not rated yet: the rate prompt is shown',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-rate-1',
        isBuyer: false,
        status: OrderStatus.settledHoldInvoice,
        rating: null,
      );

      expect(find.text('Rate'), findsOneWidget);
      expect(_filledButtonWithText('Rate your counterpart'), findsOneWidget);
      expect(find.text('Rated'), findsNothing);
    });

    testWidgets('settled + rated by me: the prompt is replaced by Close',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-rate-2',
        isBuyer: true,
        status: OrderStatus.success,
        rating: _rating(isMine: true),
      );

      expect(find.text('Rated'), findsOneWidget);
      expect(find.text('Thank you for your rating!'), findsOneWidget);
      expect(_filledButtonWithText('Rate your counterpart'), findsNothing);
      expect(_outlinedButtonWithText('CLOSE'), findsOneWidget);
    });

    /// The store falls back to the counterpart's rating when the local user
    /// has not submitted one, so a rating alone must not resolve the prompt —
    /// being rated is not the same as having rated.
    testWidgets('settled + rated by the counterpart only: prompt stays',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-rate-3',
        isBuyer: false,
        status: OrderStatus.settledHoldInvoice,
        rating: _rating(isMine: false),
      );

      expect(_filledButtonWithText('Rate your counterpart'), findsOneWidget);
      expect(find.text('Rated'), findsNothing);
    });

    /// The screen holds `loading` while the first rating lookup is in
    /// flight, for the same reason it does while the order status is
    /// unresolved: never flash a CTA that may change on the next frame.
    testWidgets('settled + rating lookup unresolved: neither CTA is shown',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        orderId: 'order-rate-4',
        isBuyer: false,
        status: OrderStatus.settledHoldInvoice,
        ratingUnresolved: true,
      );

      expect(_filledButtonWithText('Rate your counterpart'), findsNothing);
      expect(find.text('Rated'), findsNothing);
    });

    /// The post-submission link: RateCounterpartScreen invalidates
    /// `tradeRatingProvider` after a successful `submitRating`, and the
    /// detail screen underneath — still mounted, since the rate screen is
    /// pushed on top of it — must re-read and resolve the prompt without
    /// being rebuilt from scratch.
    ///
    /// The invalidation is driven directly rather than by tapping SUBMIT on
    /// the real screen: `submitRating` calls the bridge with no injectable
    /// seam, and this harness runs without `RustLib.init()`, so its success
    /// path is unreachable from a widget test.
    testWidgets('a rating submitted while mounted resolves the prompt',
        (tester) async {
      const orderId = 'order-rate-5';
      // The refetch the invalidation triggers, held open so the refreshing
      // frames are observable instead of racing to the result.
      final refresh = Completer<RatingInfo?>();
      var first = true;

      final container = await _pumpTradeDetail(
        tester,
        orderId: orderId,
        isBuyer: false,
        status: OrderStatus.settledHoldInvoice,
        ratingFetch: () {
          if (first) {
            first = false;
            return Future<RatingInfo?>.value(null);
          }
          return refresh.future;
        },
      );

      expect(_filledButtonWithText('Rate your counterpart'), findsOneWidget);
      expect(find.text('Rated'), findsNothing);

      // What _submit does once the daemon accepts the rating.
      container.invalidate(tradeRatingProvider(orderId));
      // Riverpod recomputes lazily, so read once to enter the refreshing
      // state before the frame — otherwise the pump below just re-renders
      // the pre-invalidation frame and asserts nothing.
      container.read(tradeRatingProvider(orderId));
      await tester.pump();

      // Mid-refresh the previous answer still stands, so the prompt holds
      // its ground: only the *first* lookup may show the spinner, or every
      // rating would bounce the screen through `loading`.
      expect(_filledButtonWithText('Rate your counterpart'), findsOneWidget);

      refresh.complete(_rating(isMine: true));
      await tester.pump();
      await tester.pump();

      expect(find.text('Rated'), findsOneWidget);
      expect(find.text('Thank you for your rating!'), findsOneWidget);
      expect(_filledButtonWithText('Rate your counterpart'), findsNothing);
    });
  });

  group('TradeDetailScreen secondary action row layout', () {
    testWidgets(
        'German labels on a 360dp width do not overflow the secondary row',
        (tester) async {
      // 360dp, not 320dp: at 320dp the unrelated step/status pill row
      // (trade_detail_screen.dart, around the _Pill row above the
      // instruction text) also overflows in German. That row has no
      // Expanded/Flexible protection and predates this PR; it is a
      // separate, pre-existing issue, not the secondary action row this
      // test targets. 360dp is still narrow enough to stress the
      // secondary row's wrapping while staying clear of that other bug.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpTradeDetail(
        tester,
        orderId: 'order-8',
        isBuyer: true,
        status: OrderStatus.active,
        locale: const Locale('de'),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
