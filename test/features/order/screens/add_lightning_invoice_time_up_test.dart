import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart';

Finder _semantics(String identifier) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == identifier,
);

/// 13a has the same terminal state as 13b: once its countdown reaches 00:00
/// the form (and Send) goes, even though mostrod would still accept a late
/// invoice until its scheduler cancels the trade.
void main() {
  final l10n = AppLocalizationsEn();
  final now = DateTime.utc(2026, 9, 12, 12);
  final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;

  Future<void> pump(WidgetTester tester, {required int deadline}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isWalletConnectedProvider.overrideWithValue(false),
          tradeAmountProvider.overrideWith(
            (ref, id) => Stream.value(BigInt.from(250)),
          ),
          tradeInfoProvider.overrideWith((ref, id) async => null),
          tradeUpdatesProvider.overrideWith(
            (ref) => const Stream<TradeUpdate>.empty(),
          ),
          invoiceDeadlineProvider.overrideWith((ref, id) async => deadline),
          mostroNodeProvider.overrideWith((ref) async => null),
          activeNodeNameProvider.overrideWithValue(null),
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
    await tester.pump();
  }

  testWidgets('keeps the form while time is left', (tester) async {
    await withClock(Clock.fixed(now), () async {
      await pump(tester, deadline: nowSeconds + 90);
    });
    expect(_semantics('invoice.submit'), findsOneWidget);
    expect(find.text(l10n.invoiceTimeUpTitle), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('replaces the form with the time-up state at 00:00', (
    tester,
  ) async {
    await withClock(Clock.fixed(now), () async {
      await pump(tester, deadline: nowSeconds - 1);
    });
    expect(find.text(l10n.invoiceTimeUpTitle), findsOneWidget);
    expect(find.text(l10n.invoiceBackToBook), findsOneWidget);
    expect(_semantics('invoice.submit'), findsNothing);
    expect(_semantics('invoice.text'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
