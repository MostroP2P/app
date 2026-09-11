import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_detail_palette.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/my_order_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';

import '../../../support/fake_orders.dart';
import '../../../support/provider_harness.dart';

const _id = '09150348-1a2b-4c3d-8e9f-0a1b2c3d99b5';
const _dark = OrderDetailPalette.dark;
const _book = OrderBookPalette.dark;

/// Pumps the maker's own order with the book and the live status stubbed.
/// Pumped by frames, never settled: the waiting dot pulses forever.
Future<void> _pump(
  WidgetTester tester, {
  required OrderItem order,
  OrderStatus liveStatus = OrderStatus.pending,
}) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = createContainer(
    overrides: [
      orderBookProvider.overrideWith((ref) => Stream.value([order])),
      tradeStatusProvider.overrideWith((ref, id) => Stream.value(liveStatus)),
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
        home: const MyOrderScreen(orderId: _id),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

OrderItem _order({
  String kind = 'sell',
  double premium = 0,
  BigInt? amountSats,
  OrderStatus status = OrderStatus.pending,
  String paymentMethod = 'Mercado Pago',
}) => fakeOrder(
  id: _id,
  kind: kind,
  fiatAmount: 1000,
  fiatCode: 'ARS',
  paymentMethod: paymentMethod,
  premium: premium,
  amountSats: amountSats,
  status: status,
  isMine: true,
  minutesAgo: 3,
  expiresAt: kFakeNow.add(const Duration(hours: 23, minutes: 12)),
);

Finder _byId(String id) =>
    find.byWidgetPredicate((w) => w is AutomationId && w.id == id);

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  group('MyOrderScreen waiting for a taker', () {
    testWidgets('shows the three blocks and both actions', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(tester, order: _order());

        expect(find.text('Your sell order'), findsOneWidget);
        expect(find.text('SELLING BTC'), findsOneWidget);
        expect(find.text('ARS'), findsOneWidget);
        expect(find.text('1,000'), findsOneWidget);
        expect(find.text('Waiting for a taker'), findsOneWidget);
        expect(find.text('23:12'), findsOneWidget);
        expect(find.textContaining('Published 3m ago.'), findsOneWidget);
        expect(find.text('Mercado Pago'), findsOneWidget);
        expect(find.text('09150348…99b5'), findsOneWidget);
        expect(find.text('Close'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
      });
    });

    testWidgets('names the buy side on a buy order', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(tester, order: _order(kind: 'buy'));

        expect(find.text('Your buy order'), findsOneWidget);
        expect(find.text('BUYING BTC'), findsOneWidget);
      });
    });

    testWidgets('colours the premium from the maker side', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        // A seller gains from a positive premium.
        await _pump(tester, order: _order(kind: 'sell', premium: 2));
        final line = tester.widget<Text>(
          find.textContaining('Market price · '),
        );
        final spans = (line.textSpan! as TextSpan).children!;
        final figure = spans[1] as TextSpan;
        expect(figure.text, '+2.0%');
        expect(figure.style?.color, _book.limeText);
      });
    });

    testWidgets('shows the fixed sats when the maker fixed them',
        (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(tester, order: _order(amountSats: BigInt.from(4000)));

        expect(find.textContaining('Fixed amount · '), findsOneWidget);
        expect(find.textContaining('4,000 sats'), findsOneWidget);
      });
    });

    testWidgets('summarises more than two payment methods', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(paymentMethod: 'Mercado Pago, Brubank, Uala'),
        );

        expect(find.text('Mercado Pago +2'), findsOneWidget);

        await tester.tap(find.text('Mercado Pago +2'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Payment methods'), findsOneWidget);
        expect(find.text('Brubank'), findsOneWidget);
        expect(find.text('Uala'), findsOneWidget);
      });
    });

    testWidgets('copies the full id when the row is tapped', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await _pump(tester, order: _order());

        await tester.tap(find.text('ID'));
        await tester.pump();

        expect(copied, _id);
        expect(find.text('Order ID copied'), findsOneWidget);
      });
    });

    testWidgets('asks before cancelling and can back out', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(tester, order: _order());

        await tester.tap(_byId(AutomationIds.tradeCancel));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Cancel the order?'), findsOneWidget);
        expect(_byId(AutomationIds.tradeCancelConfirm), findsOneWidget);

        await tester.tap(find.text('Go back'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Cancel the order?'), findsNothing);
        expect(find.text('Waiting for a taker'), findsOneWidget);
      });
    });
  });

  group('MyOrderScreen after the order moved on', () {
    testWidgets('reads taken while the payment is pending, keeps Cancel',
        (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(),
          liveStatus: OrderStatus.waitingPayment,
        );

        expect(find.text('Taken · waiting for payment'), findsOneWidget);
        expect(
          _colorOf(tester, 'Taken · waiting for payment'),
          _dark.statusHoldText,
        );
        expect(find.text('23:12'), findsOneWidget);
        expect(find.textContaining('Published'), findsNothing);
        expect(find.text('Cancel'), findsOneWidget);
      });
    });

    testWidgets('reads expired without a Cancel button', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(status: OrderStatus.expired),
          liveStatus: OrderStatus.expired,
        );

        expect(find.text('Expired'), findsOneWidget);
        expect(_colorOf(tester, 'Expired'), _dark.statusDeadText);
        expect(find.text('Cancel'), findsNothing);
        expect(find.text('Close'), findsOneWidget);
      });
    });

    testWidgets('reads expired once the countdown runs out', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        final order = fakeOrder(
          id: _id,
          fiatAmount: 1000,
          fiatCode: 'ARS',
          isMine: true,
          expiresAt: kFakeNow.subtract(const Duration(minutes: 1)),
        );
        await _pump(tester, order: order);

        expect(find.text('Expired'), findsOneWidget);
        expect(find.text('Cancel'), findsNothing);
      });
    });

    testWidgets('reads cancelled in the coral family', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          order: _order(status: OrderStatus.canceled),
          liveStatus: OrderStatus.canceled,
        );

        expect(find.text('Cancelled'), findsOneWidget);
        expect(_colorOf(tester, 'Cancelled'), _dark.statusCancelText);
        expect(find.text('Cancel'), findsNothing);
      });
    });
  });
}
