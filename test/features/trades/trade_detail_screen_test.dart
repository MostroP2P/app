import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/screens/trade_detail_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';

import '../../support/provider_harness.dart';

/// Pumps [TradeDetailScreen] for [orderId] with the role and live order
/// status overridden, matching this repo's Riverpod-override testing
/// convention (see `test/support/order_book_harness.dart`).
///
/// The order book itself is overridden to an empty stream — the screen's own
/// `_loadExpiresAt`/Rust-bridge calls fail silently without `RustLib.init()`
/// (the same as `test/widget_test.dart`'s smoke test), which is fine since
/// none of the assertions here depend on live order details.
Future<void> _pumpTradeDetail(
  WidgetTester tester, {
  required String orderId,
  required bool isBuyer,
  required OrderStatus status,
  Locale locale = const Locale('en'),
}) async {
  final container = createContainer(overrides: [
    tradeRoleProvider.overrideWith((ref) => {orderId: isBuyer}),
    tradeStatusProvider(orderId).overrideWith((ref) => Stream.value(status)),
    orderBookProvider.overrideWith((ref) => Stream.value(const [])),
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
}

/// Matches an outlined secondary-row button by its visible label text.
Finder _outlinedButtonWithText(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(OutlinedButton),
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
