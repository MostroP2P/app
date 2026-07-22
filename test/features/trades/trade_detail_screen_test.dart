import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/screens/trade_detail_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';

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
      expect(_outlinedButtonWithText('Cancel order'), findsOneWidget);
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

      expect(_outlinedButtonWithText('Cancel order'), findsOneWidget);
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

      expect(_outlinedButtonWithText('Cancel order'), findsOneWidget);
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
      expect(_outlinedButtonWithText('Cancel order'), findsOneWidget);
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
      expect(_outlinedButtonWithText('Cancel order'), findsOneWidget);
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
      expect(_outlinedButtonWithText('Cancel order'), findsNothing);
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
      expect(_outlinedButtonWithText('Cancel order'), findsOneWidget);
      expect(_outlinedButtonWithText('Open dispute'), findsOneWidget);
      expect(_anyPopupMenuItem(), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert));
      // The popup menu's opening route animates in — a zero-duration pump()
      // leaves it mid-transition. pumpAndSettle() is unsafe here: the screen's
      // 1s countdown Timer.periodic keeps scheduling frames for its full
      // 15-minute duration, so it never reports "settled".
      await tester.pump(const Duration(milliseconds: 350));

      expect(_anyPopupMenuItem(), findsOneWidget);
      expect(find.text('Share order'), findsOneWidget);

      // Selecting the item via a real tap gesture is timing-fragile in a
      // widget test (the popup's own closing-route animation delays when
      // `onSelected` actually fires). Invoke the already-wired callback
      // directly instead — this still exercises the real selection → SnackBar
      // logic without depending on that animation's exact timing.
      final popupButton =
          tester.widget<PopupMenuButton<int>>(find.byType(PopupMenuButton<int>));
      popupButton.onSelected!(0);
      await tester.pump();

      expect(find.text('Coming soon'), findsOneWidget);
    });
  });

  group('TradeDetailScreen secondary action row layout', () {
    testWidgets(
        'German labels on a 320dp width do not overflow the secondary row',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
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
