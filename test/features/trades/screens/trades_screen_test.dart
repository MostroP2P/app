import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/activity_palette.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/features/trades/screens/trades_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/provider_harness.dart';
import '../../../support/trades_list_fixtures.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<TradeInfo>? trades,
}) async {
  tester.view.physicalSize = const Size(360, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = createContainer(
    overrides: tradesListOverrides(trades ?? kHandoffTrades),
  );
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, __) => const TradesScreen())],
    // Every destination a card can open lands here, so a test reads where
    // the tap went without building that screen.
    errorBuilder: (_, state) => Scaffold(body: Text('route ${state.uri}')),
  );
  addTearDown(router.dispose);

  await withClock(Clock.fixed(kTradesNow), () async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: buildDarkTheme(),
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  });
  return container;
}

Finder _card(String orderId) =>
    find.bySemanticsIdentifier(AutomationIds.tradesItem(orderId));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('groups by what each trade asks, each with its count', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('REQUIEREN TU ACCIÓN'), findsOneWidget);
    expect(find.text('EN CURSO'), findsOneWidget);
    expect(find.text('CERRADAS'), findsOneWidget);

    final action = tester.getTopLeft(find.text('REQUIEREN TU ACCIÓN')).dy;
    final progress = tester.getTopLeft(find.text('EN CURSO')).dy;
    final closed = tester.getTopLeft(find.text('CERRADAS')).dy;
    expect(action < progress && progress < closed, isTrue);

    // Two need the user, one waits, two are closed.
    expect(find.text('2'), findsNWidgets(2));
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a trade that needs the user names the step and is lime', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Liberar sats'), findsOneWidget);
    expect(find.text('Enviar pago'), findsOneWidget);
    expect(find.text('TE TOCA'), findsNWidgets(2));
    expect(find.text('ESPERANDO PAGO'), findsOneWidget);

    final shape =
        tester
                .widget<Material>(
                  find
                      .descendant(
                        of: _card('release'),
                        matching: find.byType(Material),
                      )
                      .first,
                )
                .shape!
            as RoundedRectangleBorder;
    expect(shape.side.color, ActivityPalette.dark.borderAction);
  });

  testWidgets('the card says who the counterparty is and what it is worth', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Vendes a used-jaguar', findRichText: true), findsOne);
    expect(find.text('Mercado Pago +2'), findsOneWidget);
    // Fixed by the daemon: no `≈`.
    expect(find.text('6.900 sats'), findsOneWidget);
    // A cancelled trade moved no sats.
    expect(find.text('—'), findsOneWidget);
    expect(find.text('hace 1 h'), findsOneWidget);
    expect(find.text('ayer'), findsOneWidget);
  });

  testWidgets('the role chip is gone', (tester) async {
    await _pump(tester);

    expect(find.textContaining('Creada por ti'), findsNothing);
    expect(find.textContaining('Tomada por ti'), findsNothing);
  });

  testWidgets('the verb opens its step directly', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Liberar sats'));
    await tester.pumpAndSettle();

    expect(find.text('route /trade_detail/release'), findsOneWidget);
  });

  testWidgets('filtering keeps only the matching group, and remembers it', (
    tester,
  ) async {
    final container = await _pump(tester);

    await tester.tap(find.text('Todas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canceladas'));
    await tester.pumpAndSettle();

    expect(find.text('REQUIEREN TU ACCIÓN'), findsNothing);
    expect(find.text('CERRADAS'), findsOneWidget);
    expect(_card('cancelled'), findsOneWidget);
    expect(_card('done'), findsNothing);
    expect(container.read(tradeListFilterProvider), TradeListFilter.cancelled);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kTradeListFilterKey), 'cancelled');
  });

  testWidgets('with no trades it says so instead of drawing empty groups', (
    tester,
  ) async {
    await _pump(tester, trades: const []);

    expect(find.text('REQUIEREN TU ACCIÓN'), findsNothing);
    expect(find.text('CERRADAS'), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });
}
