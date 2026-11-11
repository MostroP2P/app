import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/widgets/notification_group_card.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart';

/// #845: a trade card speaks to the user, so a seller who took a buy order
/// is asked to lock the sats, not told to wait for "the seller".

final _en = AppLocalizationsEn();
const _orderId = 'd5f425ca-1111-4c3d-8e9f-0a1b2c3d99b5';

TradeRow _row({required bool isSelling}) => TradeRow(
  orderId: _orderId,
  status: OrderStatus.waitingPayment,
  rowStatus: OrderStatus.waitingPayment,
  state: TradeRowState.of(
    status: OrderStatus.waitingPayment,
    isBuyer: !isSelling,
    ratedByMe: false,
    canRate: false,
  ),
  isSelling: isSelling,
  isMaker: false,
  fiatAmount: 200000,
  fiatAmountMin: null,
  fiatAmountMax: null,
  fiatCode: 'ARS',
  premium: 0,
  amountSats: 169109,
  paymentMethod: 'Bank transfer',
  startedAt: 0,
  peerHandle: null,
  node: null,
);

void main() {
  Future<void> pump(WidgetTester tester, {required bool isSelling}) async {
    final row = _row(isSelling: isSelling);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tradeRowsProvider.overrideWithValue(AsyncValue.data([row])),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: NotificationGroupCard(
                notifications: [
                  NotificationModel.tradeStatus(
                    orderId: _orderId,
                    status: 'waitingPayment',
                    at: DateTime.utc(2026, 1, 1, 1),
                  ),
                ],
                tradeRow: row,
                onTapNotification: (_) {},
                onGoToTrade: () {},
                onOtherNode: (_, _, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a seller who owes the payment is asked to lock the sats', (
    tester,
  ) async {
    await pump(tester, isSelling: true);

    expect(find.text(_en.tradeCardWaitingPaymentSellerTitle), findsOneWidget);
    expect(find.text(_en.tradeCardWaitingPaymentSellerMessage), findsOneWidget);
    expect(find.text(_en.tradeCardWaitingPaymentTitle), findsNothing);
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsNothing);
  });

  testWidgets('the buyer still waits for the seller', (tester) async {
    await pump(tester, isSelling: false);

    expect(find.text(_en.tradeCardWaitingPaymentTitle), findsOneWidget);
    expect(find.text(_en.tradeCardWaitingPaymentMessage), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
  });
}
