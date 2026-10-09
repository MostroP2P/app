import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_detail_palette.dart';
import 'package:mostro/features/about/models/mostro_instance.dart' as instance;
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/take_order_screen.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';

import '../../../support/fake_orders.dart';
import '../../../support/explanatory_note_finders.dart';
import '../../../support/fake_trades.dart';
import '../../../support/provider_harness.dart';

const _id = '09150348-1a2b-4c3d-8e9f-0a1b2c3d99b5';
const _dark = OrderDetailPalette.dark;
const _book = OrderBookPalette.dark;

/// Pumps the take-order screen over a book fed by [books], with the node's
/// rate stubbed and the user's trade rows being [trades] (none by default),
/// or whatever [readTrades] answers — the screen reads them through the real
/// `tradeRoleLookupProvider`. 1 000 ARS is 1 000 sats at the stubbed rate, so
/// the estimates are easy to read.
typedef _Take =
    Future<TradeInfo> Function({
      required String orderId,
      required TradeRole role,
      double? fiatAmount,
    });

Future<StreamController<List<OrderItem>>> _pump(
  WidgetTester tester, {
  required OrderItem order,
  bool isBuying = true,
  double? rate = 100000000,
  _Take? take,
  List<TradeInfo> trades = const [],
  Future<List<TradeInfo>> Function()? readTrades,
  instance.MostroInstance? node,
  int? bondEstimate,
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
      tradeListReaderProvider.overrideWithValue(
        readTrades ?? () async => trades,
      ),
      if (take != null) takeOrderActionProvider.overrideWithValue(take),
      exchangeRateProvider.overrideWith((ref, code) async => rate),
      mostroNodeProvider.overrideWith((ref) async => node),
      bondEstimateProvider.overrideWith((ref, sats) async => bondEstimate),
      fiatCurrenciesProvider.overrideWith(
        (ref) async => const [
          FiatCurrency(code: 'ARS', name: 'Argentine Peso', flag: '🇦🇷'),
        ],
      ),
    ],
  );
  // Under a router, so where the screen sends the user is observable: each
  // destination lands on a stand-in reading its own name.
  final router = GoRouter(
    initialLocation:
        isBuying ? AppRoute.takeSellPath(_id) : AppRoute.takeBuyPath(_id),
    routes: [
      GoRoute(
        path: isBuying ? AppRoute.takeSell : AppRoute.takeBuy,
        builder: (_, __) => TakeOrderScreen(orderId: _id, isBuying: isBuying),
      ),
      GoRoute(
        path: AppRoute.tradeDetail,
        builder: (_, __) => const Scaffold(body: Text('trade')),
      ),
      GoRoute(
        path: AppRoute.payInvoice,
        builder: (_, __) => const Scaffold(body: Text('pay')),
      ),
      GoRoute(
        path: AppRoute.addInvoice,
        builder: (_, __) => const Scaffold(body: Text('add invoice')),
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
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
  OrderStatus status = OrderStatus.pending,
  double rating = 4.8,
  int tradeCount = 16,
  int daysActive = 219,
  Duration expiresIn = const Duration(hours: 23, minutes: 12),
  int minutesAgo = 3,
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
  status: status,
  rating: rating,
  tradeCount: tradeCount,
  daysActive: daysActive,
  minutesAgo: minutesAgo,
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
  // DS-CMP-21 (#723): a time left says what runs out and sits in the body,
  // never as a bare clock in the app bar, and hours never read as `23:12`.
  group('TakeOrderScreen countdown', () {
    testWidgets('announces turning urgent once, not every tick', (
      tester,
    ) async {
      var now = kFakeNow;
      await withClock(Clock(() => now), () async {
        // Created 3 minutes ago: a short window, urgent under a minute.
        await _pump(
          tester,
          order: _order(expiresIn: const Duration(minutes: 1, seconds: 2)),
        );
        tester.takeAnnouncements();

        for (var i = 0; i < 8; i++) {
          now = now.add(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
        }

        expect(
          [for (final a in tester.takeAnnouncements()) a.message],
          ['Expires in 00:59'],
        );
      });
    });

    testWidgets('is a labeled row of the data card, not an app-bar clock', (
      tester,
    ) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(tester, order: _order());

        final row = find.ancestor(
          of: find.text('Expires in'),
          matching: find.byType(OrderDataRow),
        );
        expect(row, findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.text('23 h 12')),
          findsOneWidget,
        );
        expect(find.text('23:12'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(Icons.schedule_rounded),
          ),
          findsNothing,
        );
      });
    });

    testWidgets('names the end in the same row once the order is gone', (
      tester,
    ) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(expiresIn: const Duration(seconds: -1)),
        );

        final row = find.ancestor(
          of: find.text('Closed'),
          matching: find.byType(OrderDataRow),
        );
        expect(row, findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.text('Status')),
          findsOneWidget,
        );
      });
    });
  });

  group('TakeOrderScreen buying BTC', () {
    testWidgets('shows what is paid, received, and who sells', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(tester, order: _order());

        expect(find.text('Buy BTC'), findsOneWidget);
        expect(find.text('23 h 12'), findsOneWidget);
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
        expect(
          find.textContaining('the seller locks the sats'),
          findsOneWidget,
        );
        expect(find.text('Take order'), findsOneWidget);
        expect(find.text('Close'), findsNothing);
      });
    });

    testWidgets('explains the escrow in a body note led by the lock', (
      tester,
    ) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(tester, order: _order());
        expectExplanatoryNote(
          tester,
          find.textContaining('the seller locks the sats'),
          notInside: find.byType(OrderDetailActionBar),
        );
        expect(find.byIcon(Icons.shield_outlined), findsNothing);
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

    // DS-CMP-23: one hero, left-aligned, its unit on the figure's baseline.
    testWidgets(
      'the hero states the currency beside the figure, not in a chip',
      (tester) async {
        await withClock(Clock.fixed(kFakeNow), () async {
          await _pump(tester, order: _order());

          expect(find.byType(OrderCurrencyChip), findsNothing);
          final label = tester.widget<Text>(find.text('You pay'));
          expect(label.style?.fontSize, 12);
          expect(label.style?.color, _book.textSecondary);
          final figure = tester.widget<Text>(find.text('1,000'));
          expect(figure.style?.fontSize, 38);
          expect(figure.style?.fontWeight, FontWeight.w700);
          final unit = tester.widget<Text>(find.text('ARS'));
          expect(unit.style?.fontSize, 15);
          expect(unit.style?.color, _book.textSecondary);
          // Left-aligned: the label and the figure share their start edge,
          // and the unit follows the figure on its line.
          final figureBox = tester.getRect(find.text('1,000'));
          expect(tester.getTopLeft(find.text('You pay')).dx, figureBox.left);
          final unitBox = tester.getRect(find.text('ARS'));
          expect(unitBox.left, greaterThan(figureBox.right));
          expect(unitBox.bottom, lessThanOrEqualTo(figureBox.bottom));
          expect(unitBox.top, greaterThan(figureBox.top));
        });
      },
    );

    testWidgets(
      'the amount received stacks under the one paid, in lime at 19',
      (tester) async {
        await withClock(Clock.fixed(kFakeNow), () async {
          await _pump(tester, order: _order());

          final line = tester.widget<Text>(find.text('≈ 1,000 sats'));
          final figure = (line.textSpan! as TextSpan).children![1] as TextSpan;
          expect(figure.text, '≈ 1,000');
          expect(figure.style?.fontSize, 19);
          expect(figure.style?.color, _book.limeInk);
          final receive = tester.getRect(find.text('You receive'));
          expect(receive.left, tester.getTopLeft(find.text('1,000')).dx);
          expect(
            tester.getTopLeft(find.text('≈ 1,000 sats')).dy,
            greaterThanOrEqualTo(receive.bottom),
          );
        });
      },
    );

    testWidgets('a range too wide for 38 drops to 26 rather than truncate', (
      tester,
    ) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(
            fiatAmount: null,
            fiatAmountMin: 100000,
            fiatAmountMax: 2500000,
          ),
        );

        final figure = tester.widget<Text>(find.text('100,000 – 2,500,000'));
        expect(figure.style?.fontSize, 26);
        expect(figure.overflow, isNot(TextOverflow.ellipsis));
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
        // A day-long order: under DS-CMP-21 only a window of 15 minutes or
        // less waits for the last minute.
        await _pump(
          tester,
          order: _order(
            expiresIn: const Duration(minutes: 4, seconds: 59),
            minutesAgo: 24 * 60 - 5,
          ),
        );
        expect(_colorOf(tester, '04:59'), _dark.danger);
      });
    });
  });

  group('TakeOrderScreen selling BTC', () {
    testWidgets('names the buyer and what the taker hands over', (
      tester,
    ) async {
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

  group('TakeOrderScreen taking', () {
    final en = AppLocalizationsEn();

    testWidgets('shows Taking… on a lime tint while the relay answers', (
      tester,
    ) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        final reply = Completer<TradeInfo>();
        await _pump(
          tester,
          order: _order(),
          take: ({required orderId, required role, fiatAmount}) => reply.future,
        );

        await tester.tap(find.text('Take order'));
        await tester.pump();
        await tester.pump();

        expect(find.text('Taking…'), findsOneWidget);
        expect(find.text('Take order'), findsNothing);
        expect(_colorOf(tester, 'Taking…'), _dark.ctaLoadingInk);
        // Left unanswered on purpose: the screen is torn down while loading.
      });
    });

    testWidgets('keeps Taking… while its own take moves the order on', (
      tester,
    ) async {
      // Rust updates the order's book entry as soon as the daemon confirms
      // the take, before `take_order` returns: that is this user's take, not
      // the order going away (#454).
      await withClock(Clock.fixed(kFakeNow), () async {
        final reply = Completer<TradeInfo>();
        final books = await _pump(
          tester,
          order: _order(),
          take: ({required orderId, required role, fiatAmount}) => reply.future,
        );

        await tester.tap(find.text('Take order'));
        await tester.pump();
        books.add([
          fakeOrder(id: _id, status: OrderStatus.waitingBuyerInvoice),
        ]);
        await tester.pump();
        await tester.pump();

        expect(find.text('Taking…'), findsOneWidget);
        expect(find.text('No longer available'), findsNothing);
        // Left unanswered on purpose: the screen is torn down while loading.
      });
    });

    testWidgets('a failed take over an order that moved on reads unavailable', (
      tester,
    ) async {
      // The in-flight hold lasts only as long as the take: once it fails,
      // the book decides again, and here the order is gone from `pending`.
      await withClock(Clock.fixed(kFakeNow), () async {
        final reply = Completer<TradeInfo>();
        final books = await _pump(
          tester,
          order: _order(),
          take: ({required orderId, required role, fiatAmount}) => reply.future,
        );

        await tester.tap(find.text('Take order'));
        await tester.pump();
        books.add([fakeOrder(id: _id, status: OrderStatus.inProgress)]);
        await tester.pump();
        reply.completeError(Exception('AnyhowException(NoDaemonResponse)'));
        await tester.pumpAndSettle();

        expect(find.text('Taking…'), findsNothing);
        expect(find.text('No longer available'), findsOneWidget);
      });
    });

    for (final (side, isBuying, lands) in [
      ('seller', false, 'pay'),
      ('buyer', true, 'trade'),
    ]) {
      testWidgets('a $side take that succeeds never reads unavailable on the '
          'way out', (tester) async {
        // `context.go` leaves this screen mounted while the next route
        // animates in, so the frames after a successful take are the screen's
        // too, and its own take is already in the book by then (#454).
        //
        // The buyer path reads the default Lightning address before it
        // navigates, and that bridge call throws in a widget test — which is
        // the unreadable-settings path itself: the take stands, the error
        // never reaches `_showTakeError`, and the trade screen is where the
        // user lands, offering the invoice step it owns.
        await withClock(Clock.fixed(kFakeNow), () async {
          final reply = Completer<TradeInfo>();
          final books = await _pump(
            tester,
            order: _order(kind: isBuying ? 'sell' : 'buy'),
            isBuying: isBuying,
            take:
                ({required orderId, required role, fiatAmount}) => reply.future,
          );

          await tester.tap(find.text('Take order'));
          await tester.pump();
          // The daemon's answer reaches the book first, as it does in Rust.
          books.add([
            _order(
              kind: isBuying ? 'sell' : 'buy',
              status:
                  isBuying
                      ? OrderStatus.waitingBuyerInvoice
                      : OrderStatus.waitingPayment,
            ),
          ]);
          await tester.pump();
          reply.complete(
            fakeTrade(
              id: 'taken',
              status:
                  isBuying
                      ? OrderStatus.waitingBuyerInvoice
                      : OrderStatus.waitingPayment,
            ),
          );

          for (var frame = 0; frame < 60; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (find.byType(TakeOrderScreen).evaluate().isEmpty) continue;
            expect(
              find.text('No longer available'),
              findsNothing,
              reason: '$side, frame $frame, with the screen still mounted',
            );
          }
          expect(find.text(lands), findsOneWidget);
          // A take that stands is never reported as a failure, and an
          // unreadable setting does not send the buyer to a step the daemon
          // may not be waiting for.
          expect(find.byType(SnackBar), findsNothing);
          if (isBuying) expect(find.text('add invoice'), findsNothing);
        });
      });
    }

    testWidgets('an order expiring mid-take keeps Taking…', (tester) async {
      var now = kFakeNow;
      await withClock(Clock(() => now), () async {
        await _pump(
          tester,
          order: _order(expiresIn: const Duration(seconds: 2)),
          take:
              ({required orderId, required role, fiatAmount}) =>
                  Completer<TradeInfo>().future,
        );

        await tester.tap(find.text('Take order'));
        await tester.pump();
        now = kFakeNow.add(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 3));

        expect(find.text('Taking…'), findsOneWidget);
        expect(find.text('No longer available'), findsNothing);
      });
    });

    testWidgets('an order that expired mid-take dies once the take fails', (
      tester,
    ) async {
      // The countdown held its fire for the take, so the expiry it saw is
      // applied when the take comes back empty-handed: the book still calls
      // the order pending until the daemon publishes its end.
      var now = kFakeNow;
      await withClock(Clock(() => now), () async {
        final reply = Completer<TradeInfo>();
        await _pump(
          tester,
          order: _order(expiresIn: const Duration(seconds: 2)),
          take: ({required orderId, required role, fiatAmount}) => reply.future,
        );

        await tester.tap(find.text('Take order'));
        await tester.pump();
        now = kFakeNow.add(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 3));
        reply.completeError(Exception('AnyhowException(NoDaemonResponse)'));
        await tester.pumpAndSettle();

        expect(find.text('No longer available'), findsOneWidget);
        expect(find.text('Take order'), findsNothing);
      });
    });

    testWidgets('dies in place when the daemon says it was already taken', (
      tester,
    ) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(),
          take:
              ({required orderId, required role, fiatAmount}) async =>
                  throw Exception('AnyhowException(OrderAlreadyTaken)'),
        );

        await tester.tap(find.text('Take order'));
        await tester.pumpAndSettle();

        expect(find.byType(TakeOrderScreen), findsOneWidget);
        expect(find.text('No longer available'), findsOneWidget);
        expect(find.text(en.orderAlreadyTaken), findsOneWidget);
      });
    });

    testWidgets('dies in place when the daemon says the order moved on', (
      tester,
    ) async {
      // `CantDo(InvalidOrderStatus)`: the order is no longer pending, so
      // it cannot be taken again, whoever moved it (#719).
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(),
          take:
              ({required orderId, required role, fiatAmount}) async =>
                  throw Exception('AnyhowException(CantDo:InvalidOrderStatus)'),
        );

        await tester.tap(find.text('Take order'));
        await tester.pumpAndSettle();

        expect(find.text('No longer available'), findsOneWidget);
        expect(find.text(en.orderNoLongerActive), findsOneWidget);
        expect(find.textContaining('InvalidOrderStatus'), findsNothing);
      });
    });

    testWidgets('never shows the raw text of an error it cannot map', (
      tester,
    ) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(),
          take:
              ({required orderId, required role, fiatAmount}) async =>
                  throw Exception('AnyhowException(CantDo:SomeNewReason)'),
        );

        await tester.tap(find.text('Take order'));
        await tester.pumpAndSettle();

        expect(
          find.text('Could not take the order. Please try again.'),
          findsOneWidget,
        );
        expect(find.textContaining('SomeNewReason'), findsNothing);
        expect(find.text('Take order'), findsOneWidget);
      });
    });

    testWidgets('warns about the deposit on a node that bonds takers', (
      tester,
    ) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(),
          node: const instance.MostroInstance(
            pubKey: 'node',
            bondPolicy: instance.BondPolicy.enabled,
            bondApplyTo: instance.BondApplyTo.take,
          ),
          bondEstimate: 1500,
        );
        expect(
          find.textContaining(en.takeOrderBondNoticeEstimate('1,500')),
          findsOneWidget,
        );
        expect(find.text('Take order'), findsOneWidget);
      });
    });

    testWidgets('puts the deposit in the same body note as the escrow', (
      tester,
    ) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(),
          node: const instance.MostroInstance(
            pubKey: 'node',
            bondPolicy: instance.BondPolicy.enabled,
            bondApplyTo: instance.BondApplyTo.take,
          ),
          bondEstimate: 1500,
        );
        expectExplanatoryNote(
          tester,
          find.textContaining(en.takeOrderBondNoticeEstimate('1,500')),
          notInside: find.byType(OrderDetailActionBar),
        );
      });
    });

    testWidgets('names the deposit without a figure when none is estimable', (
      tester,
    ) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(),
          node: const instance.MostroInstance(
            pubKey: 'node',
            bondPolicy: instance.BondPolicy.enabled,
            bondApplyTo: instance.BondApplyTo.both,
          ),
        );
        expect(find.textContaining(en.takeOrderBondNotice), findsOneWidget);
      });
    });

    testWidgets(
      'says nothing about a deposit when the node bonds makers only',
      (tester) async {
        await withClock(Clock.fixed(kFakeNow), () async {
          await _pump(
            tester,
            order: _order(),
            node: const instance.MostroInstance(
              pubKey: 'node',
              bondPolicy: instance.BondPolicy.enabled,
              bondApplyTo: instance.BondApplyTo.make,
            ),
            bondEstimate: 1500,
          );
          expect(find.textContaining('deposit'), findsNothing);
        });
      },
    );

    testWidgets('maps a daemon timeout through the shared error table', (
      tester,
    ) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(),
          take:
              ({required orderId, required role, fiatAmount}) async =>
                  throw Exception('AnyhowException(NoDaemonResponse)'),
        );

        await tester.tap(find.text('Take order'));
        await tester.pumpAndSettle();

        expect(find.text(en.sessionTimeoutMessage), findsOneWidget);
        expect(find.text('Take order'), findsOneWidget);
      });
    });

    testWidgets('a second tap while the first is still checking takes once', (
      tester,
    ) async {
      // The button stays on Take order until the role lookup (and, on a
      // range order, the amount modal) is done: a tap in that window must not
      // start a second take (#551).
      await withClock(Clock.fixed(kFakeNow), () async {
        final rows = Completer<List<TradeInfo>>();
        final taken = <String>[];
        await _pump(
          tester,
          order: _order(),
          readTrades: () => rows.future,
          take: ({required orderId, required role, fiatAmount}) {
            taken.add(orderId);
            // Left unanswered: only the dispatch is under test.
            return Completer<TradeInfo>().future;
          },
        );

        await tester.tap(find.text('Take order'));
        await tester.pump();
        await tester.tap(find.text('Take order'));
        await tester.pump();
        rows.complete(const []);
        await tester.pump();
        await tester.pump();

        expect(taken, [_id]);
        expect(find.text('Taking…'), findsOneWidget);
      });
    });

    testWidgets('a take that failed can be tried again', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        var attempts = 0;
        await _pump(
          tester,
          order: _order(),
          take: ({required orderId, required role, fiatAmount}) async {
            attempts++;
            throw Exception('AnyhowException(NoDaemonResponse)');
          },
        );

        await tester.tap(find.text('Take order'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Take order'));
        await tester.pumpAndSettle();

        expect(attempts, 2);
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

  group('TakeOrderScreen and a trade the user already has on the order', () {
    testWidgets('a take still open on the order lands on its trade', (
      tester,
    ) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(),
          trades: [
            fakeTrade(
              id: 'open',
              orderId: _id,
              status: OrderStatus.waitingBuyerInvoice,
            ),
          ],
        );

        expect(find.byType(TakeOrderScreen), findsNothing);
        expect(find.text('trade'), findsOneWidget);
      });
    });

    testWidgets('a take that already ended leaves the order takeable', (
      tester,
    ) async {
      // What older builds left behind: a take cancelled before it went
      // active, marked Canceled, its order since back in the book. Sent to
      // that dead trade, the user could never take the order again (#434).
      await withClock(Clock.fixed(kFakeNow), () async {
        final taken = <String>[];
        await _pump(
          tester,
          order: _order(),
          trades: [
            fakeTrade(id: 'ended', orderId: _id, status: OrderStatus.canceled),
          ],
          take: ({required orderId, required role, fiatAmount}) {
            taken.add(orderId);
            // Left unanswered: only the dispatch is under test.
            return Completer<TradeInfo>().future;
          },
        );
        expect(find.byType(TakeOrderScreen), findsOneWidget);

        await tester.tap(find.text('Take order'));
        await tester.pump();
        await tester.pump();

        expect(taken, [_id]);
        expect(find.text('trade'), findsNothing);
      });
    });

    testWidgets('an unreadable trade store still lets the take go out', (
      tester,
    ) async {
      // Reading the rows can fail where the bridge call it replaced could
      // not: unawaited in initState, and before the button leaves idle. An
      // unreadable store is no proof of participation, and a take the user
      // does hold is refused by the daemon and reported.
      await withClock(Clock.fixed(kFakeNow), () async {
        final taken = <String>[];
        await _pump(
          tester,
          order: _order(),
          readTrades: () async => throw Exception('storage is unreadable'),
          take: ({required orderId, required role, fiatAmount}) {
            taken.add(orderId);
            return Completer<TradeInfo>().future;
          },
        );
        expect(find.byType(TakeOrderScreen), findsOneWidget);

        await tester.tap(find.text('Take order'));
        await tester.pump();
        await tester.pump();

        expect(taken, [_id]);
        expect(find.text('Taking…'), findsOneWidget);
      });
    });
  });
}
