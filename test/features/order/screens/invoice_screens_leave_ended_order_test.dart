import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/order/screens/pay_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';

const _orderId = 'order-1';

/// The two invoice screens stay open at 00:00 until the daemon closes the
/// step (#569), so they must leave on their own an order that ended while
/// they were closed — opened later from a notification, say. Such an order
/// sends them no TradeUpdate; its status is the only sign: cancelled, or
/// `pending` again when mostrod put it back in the book and wiped the trade.
void main() {
  final l10n = AppLocalizationsEn();

  /// [screen] under a router with a home route, the order reading [status]
  /// and the persisted trades reading [trades].
  Future<void> pump(
    WidgetTester tester, {
    required Widget Function(String orderId) screen,
    required String path,
    required OrderStatus status,
    List<TradeInfo> trades = const [],
  }) async {
    final router = GoRouter(
      initialLocation: path,
      routes: [
        GoRoute(
          path: AppRoute.home,
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: AppRoute.addInvoice,
          builder: (_, state) => screen(state.pathParameters['orderId']!),
        ),
        GoRoute(
          path: AppRoute.payInvoice,
          builder: (_, state) => screen(state.pathParameters['orderId']!),
        ),
        GoRoute(
          path: AppRoute.tradeDetail,
          builder: (_, __) => const Scaffold(body: Text('trade-detail')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isWalletConnectedProvider.overrideWithValue(false),
          tradeAmountProvider.overrideWith(
            (ref, id) => Stream.value(BigInt.from(1000)),
          ),
          tradeInfoStreamProvider.overrideWith(
            (ref, id) => Stream.value(
              fakeTrade(
                id: id,
                status: OrderStatus.waitingPayment,
                holdInvoice: 'lnbc1000n1holdinvoice',
                amountSats: BigInt.from(1000),
              ),
            ),
          ),
          tradeInfoProvider.overrideWith((ref, id) async => null),
          tradeStatusProvider.overrideWith((ref, id) => Stream.value(status)),
          tradeUpdatesProvider.overrideWith(
            (ref) => const Stream<TradeUpdate>.empty(),
          ),
          tradeListReaderProvider.overrideWithValue(() async => trades),
          invoiceDeadlineProvider.overrideWith((ref, id) async => null),
          mostroNodeProvider.overrideWith((ref) async => null),
          activeNodeNameProvider.overrideWithValue(null),
        ],
        child: MaterialApp.router(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  for (final (name, screen, path) in [
    (
      "the buyer's invoice screen",
      (String id) => AddLightningInvoiceScreen(orderId: id),
      AppRoute.addInvoicePath(_orderId),
    ),
    (
      "the seller's hold-invoice screen",
      (String id) => PayLightningInvoiceScreen(orderId: id),
      AppRoute.payInvoicePath(_orderId),
    ),
  ]) {
    group(name, () {
      for (final cancelled in const [
        OrderStatus.canceled,
        OrderStatus.cooperativelyCanceled,
        OrderStatus.canceledByAdmin,
        OrderStatus.expired,
      ]) {
        testWidgets('leaves an order whose status reads ${cancelled.name}', (
          tester,
        ) async {
          await pump(tester, screen: screen, path: path, status: cancelled);
          expect(find.text('home'), findsOneWidget);
          expect(find.text(l10n.orderNoLongerActive), findsOneWidget);
        });
      }

      testWidgets('leaves an order back in the book with no trade left', (
        tester,
      ) async {
        await pump(
          tester,
          screen: screen,
          path: path,
          status: OrderStatus.pending,
        );
        expect(find.text('home'), findsOneWidget);
        expect(find.text(l10n.orderNoLongerActive), findsOneWidget);
      });

      testWidgets('stays on a pending order the user still takes part in', (
        tester,
      ) async {
        await pump(
          tester,
          screen: screen,
          path: path,
          status: OrderStatus.pending,
          trades: [
            fakeTrade(
              orderId: _orderId,
              status: OrderStatus.pending,
              isMine: true,
            ),
          ],
        );
        expect(find.text('home'), findsNothing);
      });
    });
  }
}
