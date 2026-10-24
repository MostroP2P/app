import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';
import 'package:mostro/features/home/widgets/order_list_item.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../support/catalogue_fixtures.dart';
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
      ProviderScope(
        overrides: [catalogueOverride()],
        child: MaterialApp(
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
              child: OrderListItem(order: order, reason: reason),
            ),
          ),
        ),
      ),
    );
    // The catalogue loads asynchronously; the mark lands a frame later.
    await tester.pump();
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

    testWidgets('fixed-sats orders show their price per BTC, not a premium', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        fakeOrder(
          fiatAmount: 100,
          fiatCode: 'EUR',
          amountSats: BigInt.from(163400),
        ),
      );

      expect(find.text('61.2k EUR/BTC'), findsOneWidget);
      expect(find.text('price'), findsOneWidget);
      expect(find.text('premium'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
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

    // DS-L10N-5: ratings counted as ratings, the age as the first trade's
    // month, as on every other screen.
    testWidgets('shows rating, ratings and first trade for a rated maker', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        fakeOrder(rating: 4.78, tradeCount: 16, daysActive: 219),
      );

      expect(find.text('4.78'), findsOneWidget);
      expect(find.text('16 ratings', findRichText: true), findsOneWidget);
      // 219 days before 2026-01-01.
      expect(find.text('since May 2025', findRichText: true), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.star_rounded)).color,
        _dark.yellow,
      );
    });

    testWidgets(
      'dates the maker\'s first trade from since, not the stale count',
      (tester) async {
        // The event's `days` (10) was frozen when the daemon published it;
        // `since` puts the first trade in March 2025.
        await _pumpCard(
          tester,
          fakeOrder(
            rating: 4.78,
            tradeCount: 16,
            daysActive: 10,
            makerSince: DateTime.utc(2025, 3, 7),
          ),
        );

        expect(find.text('since Mar 2025', findRichText: true), findsOneWidget);
        expect(find.text('since Dec 2025', findRichText: true), findsNothing);
      },
    );

    testWidgets('groups a large ratings count for the locale', (tester) async {
      await _pumpCard(tester, fakeOrder(rating: 4.97, tradeCount: 1323));

      expect(find.text('1,323 ratings', findRichText: true), findsOneWidget);
    });

    testWidgets('marks a maker without trades as new', (tester) async {
      await _pumpCard(
        tester,
        fakeOrder(rating: 0, tradeCount: 0, daysActive: 29),
      );

      expect(_colorOf(tester, 'New'), _dark.textNew);
      expect(find.text('no ratings', findRichText: true), findsOneWidget);
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

  for (final (fiatCode, fiatAmount, sats) in [
    ('EUR', 100.0, 163400),
    ('ARS', 1000000.0, 892857),
    ('LBP', 1000000.0, 10000),
  ]) {
    testWidgets('a fixed $fiatCode price per BTC does not overflow on a '
        '320-wide phone with 2x text', (tester) async {
      await _pumpCard(
        tester,
        fakeOrder(
          fiatAmount: fiatAmount,
          fiatCode: fiatCode,
          amountSats: BigInt.from(sats),
          paymentMethod: 'SPEI, Retiro Cajero BBVA, Transferencia Banorte',
          rating: 4.78,
          tradeCount: 1600,
          daysActive: 2190,
        ),
        width: 320,
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
    });
  }
}
