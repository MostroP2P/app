import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_detail_palette.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/take_order_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';

import '../../../support/fake_orders.dart';
import '../../../support/provider_harness.dart';

const _id = '09150348-1a2b-4c3d-8e9f-0a1b2c3d99b5';
const _dark = OrderDetailPalette.dark;
const _book = OrderBookPalette.dark;

/// Pumps the take-order screen over a book fed by [books], with the node's
/// rate and the (absent) trade role stubbed. 1 000 ARS is 1 000 sats at
/// the stubbed rate, so the estimates are easy to read.
Future<StreamController<List<OrderItem>>> _pump(
  WidgetTester tester, {
  required OrderItem order,
  bool isBuying = true,
  double? rate = 100000000,
}) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final books = StreamController<List<OrderItem>>.broadcast();
  addTearDown(books.close);
  final container = createContainer(
    overrides: [
      orderBookProvider.overrideWith((ref) async* {
        yield [order];
        yield* books.stream;
      }),
      tradeRoleLookupProvider.overrideWithValue((_) async => null),
      exchangeRateProvider.overrideWith((ref, code) async => rate),
      fiatCurrenciesProvider.overrideWith(
        (ref) async => const [
          FiatCurrency(code: 'ARS', name: 'Argentine Peso', flag: '🇦🇷'),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TakeOrderScreen(orderId: _id, isBuying: isBuying),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return books;
}

OrderItem _order({
  String kind = 'sell',
  double? fiatAmount = 1000,
  double? fiatAmountMin,
  double? fiatAmountMax,
  double premium = 0,
  BigInt? amountSats,
  double rating = 4.8,
  int tradeCount = 16,
  int daysActive = 219,
  Duration expiresIn = const Duration(hours: 23, minutes: 12),
}) => fakeOrder(
  id: _id,
  kind: kind,
  fiatAmount: fiatAmount,
  fiatAmountMin: fiatAmountMin,
  fiatAmountMax: fiatAmountMax,
  fiatCode: 'ARS',
  paymentMethod: 'Mercado Pago',
  premium: premium,
  amountSats: amountSats,
  rating: rating,
  tradeCount: tradeCount,
  daysActive: daysActive,
  minutesAgo: 3,
  expiresAt: kFakeNow.add(expiresIn),
);

Finder _byId(String id) =>
    find.byWidgetPredicate((w) => w is AutomationId && w.id == id);

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

TextSpan _figureOf(WidgetTester tester, String prefix) {
  final line = tester.widget<Text>(find.textContaining(prefix));
  return (line.textSpan! as TextSpan).children![1] as TextSpan;
}

void main() {
  group('TakeOrderScreen buying BTC', () {
    testWidgets('shows what is paid, received, and who sells', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(tester, order: _order());

        expect(find.text('Buy BTC'), findsOneWidget);
        expect(find.text('23:12'), findsOneWidget);
        expect(find.text('You pay'), findsOneWidget);
        expect(find.text('1,000'), findsOneWidget);
        expect(find.text('You receive'), findsOneWidget);
        expect(find.text('≈ 1,000 sats'), findsOneWidget);
        expect(find.textContaining('The final figure is set'), findsOneWidget);
        expect(find.text('4.8'), findsOneWidget);
        expect(find.text('Seller'), findsOneWidget);
        expect(find.text('16 trades · 219 days on Mostro'), findsOneWidget);
        expect(find.text('You pay with'), findsOneWidget);
        expect(find.text('Mercado Pago'), findsOneWidget);
        expect(find.text('3m ago'), findsOneWidget);
        expect(find.text('09150348…99b5'), findsOneWidget);
        expect(find.textContaining('the seller locks the sats'), findsOneWidget);
        expect(find.text('Take order'), findsOneWidget);
        expect(find.text('Close'), findsNothing);
      });
    });

    testWidgets('colours the premium from the taker side', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        // Buying 2 % above market is against the taker.
        await _pump(tester, order: _order(premium: 2));

        final figure = _figureOf(tester, 'Market price · ');
        expect(figure.text, '+2.0%');
        expect(figure.style?.color, _book.yellowInk);
      });
    });

    testWidgets('prices a range on its minimum', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(
            fiatAmount: null,
            fiatAmountMin: 500,
            fiatAmountMax: 2500,
          ),
        );

        expect(find.text('500 – 2,500'), findsOneWidget);
        expect(find.text('from ≈ 500 sats'), findsOneWidget);
      });
    });

    testWidgets('shows the exact figure on a fixed-sats order', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(tester, order: _order(amountSats: BigInt.from(8420)));

        expect(find.text('8,420 sats'), findsOneWidget);
        expect(find.textContaining('the seller asks for'), findsOneWidget);
        expect(find.textContaining('The final figure is set'), findsNothing);
      });
    });

    testWidgets('shows a dash without a rate', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(tester, order: _order(), rate: null);

        expect(find.text('—'), findsOneWidget);
      });
    });

    testWidgets('introduces a maker nobody rated as new', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(rating: 0, tradeCount: 0, daysActive: 29),
        );

        expect(find.text('New'), findsOneWidget);
        expect(find.text('no trades · 29 days on Mostro'), findsOneWidget);
      });
    });

    testWidgets('warns under an hour', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(expiresIn: const Duration(minutes: 12, seconds: 40)),
        );
        expect(_colorOf(tester, '12:40'), _book.yellowInk);
      });
    });

    testWidgets('urges under five minutes', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(expiresIn: const Duration(minutes: 4, seconds: 59)),
        );
        expect(_colorOf(tester, '04:59'), _dark.danger);
      });
    });
  });

  group('TakeOrderScreen selling BTC', () {
    testWidgets('names the buyer and what the taker hands over',
        (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(tester, order: _order(kind: 'buy'), isBuying: false);

        expect(find.text('Sell BTC'), findsOneWidget);
        expect(find.text('You receive'), findsOneWidget);
        expect(find.text('You send'), findsOneWidget);
        expect(find.text('Buyer'), findsOneWidget);
        expect(find.text('You get paid with'), findsOneWidget);
        expect(find.textContaining('you lock the sats'), findsOneWidget);
      });
    });
  });

  group('TakeOrderScreen when the order goes away', () {
    testWidgets('dies in place when someone else takes it', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        final books = await _pump(tester, order: _order());

        books.add(const []);
        await tester.pumpAndSettle();

        expect(find.byType(TakeOrderScreen), findsOneWidget);
        expect(find.text('No longer available'), findsOneWidget);
        expect(find.text('Take order'), findsNothing);
        expect(find.text('Closed'), findsOneWidget);
        expect(find.text('1,000'), findsOneWidget);
        expect(
          tester.getSemantics(_byId(AutomationIds.orderTakeConfirm)),
          isNot(isSemantics(isEnabled: true)),
        );
      });
    });

    testWidgets('dies in place once it expires', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(expiresIn: const Duration(seconds: -1)),
        );

        expect(find.text('No longer available'), findsOneWidget);
        expect(find.text('Closed'), findsOneWidget);
      });
    });
  });
}
