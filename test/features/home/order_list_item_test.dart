import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';
import 'package:mostro/features/home/widgets/order_list_item.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../support/fake_orders.dart';

const _dark = OrderBookPalette.dark;

Future<void> _pumpCard(
  WidgetTester tester,
  OrderItem order, {
  OrderReason? reason,
  double width = 360,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await withClock(Clock.fixed(kFakeNow), () async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: OrderListItem(
              order: order,
              reason: reason,
              currencyFlags: const {'USD': '🇺🇸'},
            ),
          ),
        ),
      ),
    );
  });
}

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  group('OrderListItem premium', () {
    for (final (label, kind, premium, text, color) in [
      ('buying at a discount', 'sell', -1.5, '-1.5%', _dark.limeText),
      ('buying at market', 'sell', 0.0, '0.0%', _dark.limeText),
      ('buying up to 3% over', 'sell', 2.0, '+2.0%', _dark.premiumMid),
      ('buying more than 3% over', 'sell', 5.0, '+5.0%', _dark.premiumHigh),
      ('selling above market', 'buy', 2.0, '+2.0%', _dark.limeText),
      ('selling up to 3% under', 'buy', -3.0, '-3.0%', _dark.premiumMid),
      ('selling more than 3% under', 'buy', -4.0, '-4.0%', _dark.premiumHigh),
    ]) {
      testWidgets('is coloured for the taker when $label', (tester) async {
        await _pumpCard(tester, fakeOrder(kind: kind, premium: premium));

        expect(_colorOf(tester, text), color);
        expect(find.text('premium'), findsOneWidget);
      });
    }

    testWidgets('rounds a near-zero premium to an unsigned 0.0%', (
      tester,
    ) async {
      await _pumpCard(tester, fakeOrder(premium: 0.04));

      expect(_colorOf(tester, '0.0%'), _dark.limeText);
    });
  });

  group('OrderListItem amount', () {
    testWidgets('groups both ends of a range and never truncates it', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        fakeOrder(fiatAmount: null, fiatAmountMin: 832, fiatAmountMax: 5000),
      );

      final amount = tester.widget<Text>(find.text('832 – 5,000'));
      expect(amount.overflow, isNot(TextOverflow.ellipsis));
      expect(amount.maxLines, isNull);
    });

    testWidgets('market-price orders say so', (tester) async {
      await _pumpCard(tester, fakeOrder(amountSats: BigInt.zero));

      expect(find.text('Market price'), findsOneWidget);
      expect(find.textContaining('sats', findRichText: true), findsNothing);
    });

    testWidgets('fixed-sats orders show the sats figure instead', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        fakeOrder(fiatAmount: 25, amountSats: BigInt.from(4000)),
      );

      expect(
        find.text('Fixed amount · for 4,000 sats', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Market price'), findsNothing);
    });
  });

  group('OrderListItem rows', () {
    testWidgets('joins payment methods on one line, capped at two lines', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        fakeOrder(paymentMethod: 'SPEI,Retiro Cajero BBVA , Mercado Pago'),
      );

      final methods = tester.widget<Text>(
        find.text('SPEI, Retiro Cajero BBVA, Mercado Pago'),
      );
      expect(methods.maxLines, 2);
      expect(methods.overflow, TextOverflow.ellipsis);
    });

    testWidgets('shows rating, trades and days for a maker with history', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        fakeOrder(rating: 4.78, tradeCount: 16, daysActive: 219),
      );

      expect(find.text('4.78'), findsOneWidget);
      expect(find.text('16 trades', findRichText: true), findsOneWidget);
      expect(find.text('219 days', findRichText: true), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.star_rounded)).color,
        _dark.yellow,
      );
    });

    testWidgets('marks a maker without trades as new', (tester) async {
      await _pumpCard(
        tester,
        fakeOrder(rating: 0, tradeCount: 0, daysActive: 29),
      );

      expect(_colorOf(tester, 'New'), _dark.textNew);
      expect(find.text('no trades'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.star_rounded)).color,
        _dark.starEmpty,
      );
    });

    testWidgets('shows the currency chip with its flag', (tester) async {
      await _pumpCard(tester, fakeOrder(fiatCode: 'USD'));

      expect(find.text('USD'), findsOneWidget);
      expect(find.text('🇺🇸'), findsOneWidget);
    });

    testWidgets('keeps the own-order chip', (tester) async {
      await _pumpCard(tester, fakeOrder(kind: 'sell', isMine: true));

      expect(find.text('YOU ARE SELLING'), findsOneWidget);
    });
  });

  group('OrderListItem highlight', () {
    bool hasBorder(WidgetTester tester, Color color) => tester.any(
      find.byWidgetPredicate(
        (w) =>
            w is Material &&
            w.shape is RoundedRectangleBorder &&
            (w.shape! as RoundedRectangleBorder).side.color == color,
      ),
    );

    testWidgets('best premium gets its chip and the green border', (
      tester,
    ) async {
      await _pumpCard(tester, fakeOrder(), reason: OrderReason.bestPremium);

      expect(find.text('BEST PREMIUM'), findsOneWidget);
      expect(hasBorder(tester, _dark.borderHighlight), isTrue);
    });

    testWidgets('most reputable gets its chip but the plain border', (
      tester,
    ) async {
      await _pumpCard(tester, fakeOrder(), reason: OrderReason.mostReputable);

      expect(find.text('MOST REPUTABLE'), findsOneWidget);
      expect(hasBorder(tester, _dark.border), isTrue);
    });
  });

  testWidgets('does not overflow on a 320-wide phone with 2x text', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      fakeOrder(
        fiatAmount: null,
        fiatAmountMin: 100000,
        fiatAmountMax: 2500000,
        paymentMethod: 'SPEI, Retiro Cajero BBVA, Transferencia Banorte',
        rating: 4.78,
        tradeCount: 1600,
        daysActive: 2190,
        isMine: true,
      ),
      reason: OrderReason.mostReputable,
      width: 320,
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
  });
}
