import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  testWidgets(
    'manual invoice amount follows the daemon amount without inventing a value',
    (tester) async {
      final amounts = StreamController<BigInt?>();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              isWalletConnectedProvider.overrideWithValue(false),
              tradeAmountProvider.overrideWith(
                (ref, orderId) => amounts.stream,
              ),
              tradeUpdatesProvider.overrideWith(
                (ref) => const Stream<TradeUpdate>.empty(),
              ),
              tradeInfoProvider.overrideWith((ref, orderId) async => null),
            ],
            child: MaterialApp(
              theme: buildDarkTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const AddLightningInvoiceScreen(orderId: 'order-1'),
            ),
          ),
        );
        await tester.pump();
        final readout = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.identifier == 'invoice.amount',
        );
        expect(readout, findsNothing);
        final order = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.identifier == 'invoice.order_id',
        );
        expect(tester.getSemantics(order).getSemanticsData().label, 'order-1');
        expect(find.text('Order order-1'), findsOneWidget);
        amounts.add(BigInt.from(999));
        await tester.pump();
        await tester.pump();
        expect(readout, findsOneWidget);
        expect(tester.getSemantics(readout).getSemanticsData().label, '999');
        expect(find.text('Amount to receive: 999 sats'), findsOneWidget);
        amounts.add(BigInt.from(998));
        await tester.pump();
        await tester.pump();
        expect(tester.getSemantics(readout).getSemanticsData().label, '998');
        expect(find.text('Amount to receive: 998 sats'), findsOneWidget);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        unawaited(amounts.close());
      }
    },
  );
}
