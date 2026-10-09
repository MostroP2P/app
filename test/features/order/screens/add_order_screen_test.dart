import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/order_side_provider.dart';
import 'package:mostro/features/order/providers/payment_methods_provider.dart';
import 'package:mostro/features/order/screens/add_order_screen.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/features/order/widgets/payment_method_section.dart';
import 'package:mostro/features/order/widgets/price_section.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/providers/node_stats_provider.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import '../../../support/provider_harness.dart';

const _node = MostroInstance(
  pubKey: 'npub-test',
  minOrderAmount: 100,
  maxOrderAmount: 100000000,
  expirationHours: 24,
);

/// Pumps the screen with every Rust-backed provider stubbed: a node that
/// expires orders after 24 h, a USD rate of 100 000 and an ARS rate 1 000×
/// that (so 1 USD = 1 000 ARS), and a small currency and method catalogue.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String orderType = 'sell',
  Locale locale = const Locale('en'),
  MostroInstance node = _node,
  List<String> accepted = const [],
  Map<String, Completer<List<String>>>? acceptedByNode,
  List<String> Function()? cachedList,
  int? bondEstimate,
}) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = createContainer(
    overrides: [
      mostroNodeProvider.overrideWith((ref) async => node),
      activeNodeCurrenciesProvider.overrideWith(
        (ref) =>
            acceptedByNode?[ref.watch(activeMostroPubkeyProvider)]!.future ??
            Future.value(cachedList?.call() ?? accepted),
      ),
      bondEstimateProvider.overrideWith((ref, sats) async => bondEstimate),
      exchangeRateProvider.overrideWith(
        (ref, code) async => switch (code) {
          'USD' => 100000.0,
          'ARS' => 100000000.0,
          _ => null,
        },
      ),
      fiatCurrenciesProvider.overrideWith(
        (ref) async => const [
          FiatCurrency(code: 'USD', name: 'US Dollar', flag: '🇺🇸'),
          FiatCurrency(code: 'ARS', name: 'Argentine Peso', flag: '🇦🇷'),
        ],
      ),
      paymentMethodsDataProvider.overrideWith(
        (ref) async => {
          'USD': ['Zelle', 'Wire'],
          'ARS': ['Mercado Pago'],
        },
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: AddOrderScreen(orderType: orderType),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _amountField() => find.byType(TextField).first;

FilledButton _publishButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Publish order'));

String _previewText(WidgetTester tester) {
  final rich = tester.widget<Text>(
    find.descendant(
      of: find.byKey(const ValueKey('preview-sentence')),
      matching: find.byType(Text),
    ),
  );
  return rich.textSpan!.toPlainText();
}

void main() {
  group('AddOrderScreen', () {
    testWidgets('has no presets: the full form is the screen', (tester) async {
      await _pump(tester);
      expect(find.text('New order'), findsOneWidget);
      expect(find.text('Conservative'), findsNothing);
      expect(find.text('Custom'), findsNothing);
      expect(find.text('How much you sell'), findsOneWidget);
      expect(find.text('Payment methods'), findsOneWidget);
      expect(find.text('Price'), findsOneWidget);
    });

    testWidgets('seeds the side from the route and lets the user switch it',
        (tester) async {
      final container = await _pump(tester, orderType: 'buy');
      expect(container.read(orderSideProvider), OrderType.buy);
      expect(find.text('How much you buy'), findsOneWidget);

      await tester.tap(find.text('Sell BTC'));
      await tester.pumpAndSettle();

      expect(container.read(orderSideProvider), OrderType.sell);
      expect(find.text('How much you sell'), findsOneWidget);
    });

    testWidgets('publish stays disabled until amount and a method exist',
        (tester) async {
      final container = await _pump(tester);
      expect(_publishButton(tester).onPressed, isNull);
      expect(find.byKey(const ValueKey('preview-hint')), findsOneWidget);

      await tester.enterText(_amountField(), '5000');
      await tester.pumpAndSettle();
      expect(_publishButton(tester).onPressed, isNull);

      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.pumpAndSettle();
      expect(_publishButton(tester).onPressed, isNotNull);
    });

    testWidgets('a node that bonds makers says so and still publishes', (
      tester,
    ) async {
      // docs/ANTI_ABUSE_BOND.md §6.2: the deposit is asked before the tap;
      // Publish lands on the pay-bond screen.
      final container = await _pump(
        tester,
        node: const MostroInstance(
          pubKey: 'npub-test',
          minOrderAmount: 100,
          maxOrderAmount: 100000000,
          expirationHours: 24,
          bondPolicy: BondPolicy.enabled,
          bondApplyTo: BondApplyTo.both,
        ),
      );
      await tester.enterText(_amountField(), '5000');
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.pumpAndSettle();
      expect(_publishButton(tester).onPressed, isNotNull);
      expect(
        find.textContaining('lock a refundable deposit before the order'),
        findsOneWidget,
      );
    });

    testWidgets('names the estimated deposit once the amount is known',
        (tester) async {
      final container = await _pump(
        tester,
        node: const MostroInstance(
          pubKey: 'npub-test',
          minOrderAmount: 100,
          maxOrderAmount: 100000000,
          expirationHours: 24,
          bondPolicy: BondPolicy.enabled,
          bondApplyTo: BondApplyTo.make,
        ),
        bondEstimate: 1500,
      );
      await tester.enterText(_amountField(), '5000');
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.pumpAndSettle();
      expect(
        find.textContaining('refundable deposit of ≈ 1,500 sats'),
        findsOneWidget,
      );
    });

    testWidgets('a node that bonds takers only says nothing about a deposit',
        (tester) async {
      final container = await _pump(
        tester,
        node: const MostroInstance(
          pubKey: 'npub-test',
          minOrderAmount: 100,
          maxOrderAmount: 100000000,
          expirationHours: 24,
          bondPolicy: BondPolicy.enabled,
          bondApplyTo: BondApplyTo.take,
        ),
      );
      await tester.enterText(_amountField(), '5000');
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.pumpAndSettle();
      expect(_publishButton(tester).onPressed, isNotNull);
      expect(find.textContaining('refundable deposit'), findsNothing);
    });

    testWidgets('previews a market sell with premium and the node expiry',
        (tester) async {
      final container = await _pump(tester);
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      container.read(premiumValueProvider.notifier).state = 3;
      await tester.enterText(_amountField(), '5000');
      await tester.pumpAndSettle();

      expect(
        _previewText(tester),
        'You sell BTC for 5,000 USD at market price +3% · active 24 h',
      );
    });

    testWidgets('previews a fixed-price buy with the sats figure',
        (tester) async {
      final container = await _pump(tester, orderType: 'buy');
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.enterText(_amountField(), '100');
      await tester.tap(find.text('Fixed'));
      await tester.pumpAndSettle();
      container.read(fixedSatsProvider.notifier).state = '120000';
      await tester.pumpAndSettle();

      expect(
        _previewText(tester),
        'You buy 120,000 sats for 100 USD at a fixed price · active 24 h',
      );
    });

    testWidgets('groups thousands with the locale separator and previews it',
        (tester) async {
      final container = await _pump(tester, locale: const Locale('es'));
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.enterText(_amountField(), '25000');
      await tester.pumpAndSettle();

      expect(find.text('25.000'), findsOneWidget);
      expect(
        _previewText(tester),
        'Vendes BTC por 25.000 USD a precio de mercado · activa 24 h',
      );
    });

    testWidgets('switching to range keeps the amount as the minimum',
        (tester) async {
      final container = await _pump(tester);
      await tester.enterText(_amountField(), '5000');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Range'));
      await tester.pumpAndSettle();

      expect(container.read(isRangeOrderProvider), isTrue);
      expect(find.text('MINIMUM'), findsOneWidget);
      expect(find.text('MAXIMUM'), findsOneWidget);
      final min = tester.widget<TextField>(find.byType(TextField).at(0));
      expect(min.controller!.text, '5,000');

      // And back: the minimum is kept as the single amount.
      await tester.tap(find.text('Single'));
      await tester.pumpAndSettle();
      expect(container.read(isRangeOrderProvider), isFalse);
      final single = tester.widget<TextField>(_amountField());
      expect(single.controller!.text, '5,000');
    });

    testWidgets('a range order is priced at market and previews both ends',
        (tester) async {
      final container = await _pump(tester);
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.tap(find.text('Fixed'));
      await tester.pumpAndSettle();
      expect(container.read(isMarketPriceProvider), isFalse);

      await tester.tap(find.text('Range'));
      await tester.pumpAndSettle();
      expect(container.read(isMarketPriceProvider), isTrue);

      await tester.enterText(find.byType(TextField).at(0), '5000');
      await tester.enterText(find.byType(TextField).at(1), '25000');
      await tester.pumpAndSettle();

      expect(
        _previewText(tester),
        'You sell BTC for 5,000 – 25,000 USD at market price · active 24 h',
      );
      expect(_publishButton(tester).onPressed, isNotNull);
    });

    testWidgets('quick chips fill the amount field', (tester) async {
      await _pump(tester);
      // 1 USD = 1 USD, so the chips are the base amounts.
      expect(find.text('25'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);

      await tester.tap(find.text('25'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(_amountField()).controller!.text, '25');
    });

    testWidgets('opening the method picker releases the amount field focus', (
      tester,
    ) async {
      await _pump(tester);
      await tester.enterText(_amountField(), '5000');
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Flutter restores the route's last focus on pop: without the unfocus
      // the keyboard comes back over the publish button.
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isFalse,
      );
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('quick chips follow the chosen currency', (tester) async {
      final container = await _pump(tester);
      container.read(selectedFiatCodeProvider.notifier).state = 'ARS';
      await tester.pumpAndSettle();

      // 1 USD = 1 000 ARS → 10 000 / 25 000 / 50 000 / 100 000.
      expect(find.text('10,000'), findsOneWidget);
      expect(find.text('100,000'), findsOneWidget);
    });

    testWidgets('an out-of-range amount replaces the preview with the error',
        (tester) async {
      final container = await _pump(tester);
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      // 1 USD at 100 000 USD/BTC is 1 000 sats — above the node's max of
      // 100 000 000 sats only for absurd amounts, so go absurd.
      await tester.enterText(_amountField(), '999999999');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('preview-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-sentence')), findsNothing);
      expect(_publishButton(tester).onPressed, isNull);
    });

    testWidgets('the Sell tab uses the coral tint', (tester) async {
      await _pump(tester);
      final tab = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('Sell BTC'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(
        (tab.decoration! as BoxDecoration).color,
        CreateOrderPalette.dark.sellActiveBg,
      );
    });
  });

  group('currency picker', () {
    /// The codes the open picker lists, in order.
    List<String> pickerCodes(WidgetTester tester) => tester
        .widgetList<ListTile>(
          find.descendant(
            of: find.byType(MostroDialog),
            matching: find.byType(ListTile),
          ),
        )
        .map((tile) => (tile.title! as Text).data!)
        .toList();

    Future<void> openPicker(WidgetTester tester) async {
      await tester.tap(find.byType(CurrencyInlineSelector));
      await tester.pumpAndSettle();
    }

    testWidgets('offers only the currencies the node accepts', (tester) async {
      await _pump(
        tester,
        accepted: const ['ARS'],
      );
      await openPicker(tester);
      expect(pickerCodes(tester), ['ARS']);
    });

    testWidgets('offers the whole catalogue when the node sets no limit', (
      tester,
    ) async {
      await _pump(tester);
      await openPicker(tester);
      expect(pickerCodes(tester), ['USD', 'ARS']);
    });

    testWidgets('lists an accepted code the catalogue does not know', (
      tester,
    ) async {
      await _pump(
        tester,
        accepted: const ['CUP', 'ARS'],
      );
      await openPicker(tester);
      expect(pickerCodes(tester), ['ARS', 'CUP']);
      final cup = tester.widget<ListTile>(
        find.ancestor(of: find.text('CUP'), matching: find.byType(ListTile)),
      );
      expect(cup.subtitle, isNull);
    });

    testWidgets('rereads the list once the cache is written', (tester) async {
      var cached = const <String>[];
      final container = await _pump(tester, cachedList: () => cached);
      await openPicker(tester);
      expect(pickerCodes(tester), ['USD', 'ARS']);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      // What the startup warm-up and the node selector's fetch do once
      // they have written the node's kind 38385 event.
      cached = const ['ARS'];
      container.invalidate(activeNodeCurrenciesProvider);
      await tester.pumpAndSettle();

      expect(container.read(selectedFiatCodeProvider), 'ARS');
      await openPicker(tester);
      expect(pickerCodes(tester), ['ARS']);
    });

    testWidgets("a node switch drops the previous node's list", (
      tester,
    ) async {
      final nodeA = Completer<List<String>>()..complete(const ['ARS']);
      final nodeB = Completer<List<String>>();
      final container = await _pump(
        tester,
        acceptedByNode: {defaultMostroPubkey: nodeA, 'node-b': nodeB},
      );
      expect(container.read(acceptedFiatCodesProvider), ['ARS']);

      container.read(mostroPubkeyProvider.notifier).state = 'node-b';
      await tester.pump();
      expect(container.read(acceptedFiatCodesProvider), isNull);

      nodeB.complete(const ['USD']);
      await tester.pumpAndSettle();
      expect(container.read(acceptedFiatCodesProvider), ['USD']);
    });
  });

  group('selected currency', () {
    testWidgets("opens on the node's first currency when it lacks USD", (
      tester,
    ) async {
      final container = await _pump(
        tester,
        accepted: const ['ARS', 'EUR'],
      );
      expect(container.read(selectedFiatCodeProvider), 'ARS');
      // The form's currency only: the default in settings is not written.
      expect(container.read(settingsProvider).defaultFiatCode, isNull);
    });

    testWidgets('keeps the default when the node accepts it', (tester) async {
      final container = await _pump(
        tester,
        accepted: const ['ARS', 'USD'],
      );
      expect(container.read(selectedFiatCodeProvider), 'USD');
    });

    testWidgets("moves off USD when the node's list arrives late", (
      tester,
    ) async {
      final listArrives = Completer<List<String>>();
      final container = await _pump(
        tester,
        acceptedByNode: {defaultMostroPubkey: listArrives},
      );
      expect(container.read(selectedFiatCodeProvider), 'USD');

      listArrives.complete(const ['ARS']);
      await tester.pumpAndSettle();

      expect(container.read(selectedFiatCodeProvider), 'ARS');
    });

    testWidgets('a late list keeps what the user entered and refuses it', (
      tester,
    ) async {
      final listArrives = Completer<List<String>>();
      final container = await _pump(
        tester,
        acceptedByNode: {defaultMostroPubkey: listArrives},
      );
      await tester.enterText(_amountField(), '100');
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.pumpAndSettle();
      expect(_publishButton(tester).onPressed, isNotNull);

      listArrives.complete(const ['ARS']);
      await tester.pumpAndSettle();

      expect(container.read(selectedFiatCodeProvider), 'USD');
      expect(container.read(selectedPaymentMethodsProvider), ['Zelle']);
      expect(tester.widget<TextField>(_amountField()).controller!.text, '100');
      expect(
        find.text('This Mostro node does not accept USD. Pick another currency'),
        findsOneWidget,
      );
      expect(_publishButton(tester).onPressed, isNull);
    });

    testWidgets("a node switch moves an untouched form to the new node's list", (
      tester,
    ) async {
      final nodeA = Completer<List<String>>()..complete(const ['ARS', 'USD']);
      final nodeB = Completer<List<String>>()..complete(const ['ARS']);
      final container = await _pump(
        tester,
        acceptedByNode: {defaultMostroPubkey: nodeA, 'node-b': nodeB},
      );
      expect(container.read(selectedFiatCodeProvider), 'USD');

      container.read(mostroPubkeyProvider.notifier).state = 'node-b';
      await tester.pumpAndSettle();

      expect(container.read(selectedFiatCodeProvider), 'ARS');
    });

    testWidgets('a reread of the same node keeps a refused currency refused', (
      tester,
    ) async {
      final byNode = {defaultMostroPubkey: Completer<List<String>>()};
      final container = await _pump(tester, acceptedByNode: byNode);
      await tester.enterText(_amountField(), '100');
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      byNode[defaultMostroPubkey]!.complete(const ['ARS']);
      await tester.pumpAndSettle();
      expect(_publishButton(tester).onPressed, isNull);

      // The cache is written again and the local read is still pending.
      byNode[defaultMostroPubkey] = Completer<List<String>>();
      container.invalidate(activeNodeCurrenciesProvider);
      await tester.pump();
      await tester.pump();

      expect(container.read(acceptedFiatCodesProvider), ['ARS']);
      expect(_publishButton(tester).onPressed, isNull);

      byNode[defaultMostroPubkey]!.complete(const ['ARS']);
      await tester.pumpAndSettle();
    });

    testWidgets("rereads the node's list when its info event is fetched live", (
      tester,
    ) async {
      var cached = const <String>[];
      final container = await _pump(tester, cachedList: () => cached);
      expect(container.read(selectedFiatCodeProvider), 'USD');

      // The live fetch behind mostroNodeProvider writes the cache in Rust.
      cached = const ['ARS'];
      container.invalidate(mostroNodeProvider);
      await tester.pumpAndSettle();

      expect(container.read(selectedFiatCodeProvider), 'ARS');
    });

    testWidgets('a currency the user picked survives a late list', (
      tester,
    ) async {
      final listArrives = Completer<List<String>>();
      final container = await _pump(
        tester,
        acceptedByNode: {defaultMostroPubkey: listArrives},
      );
      await tester.tap(find.byType(CurrencyInlineSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ARS'));
      await tester.pumpAndSettle();

      listArrives.complete(const ['USD']);
      await tester.pumpAndSettle();

      expect(container.read(selectedFiatCodeProvider), 'ARS');
      expect(
        find.text('This Mostro node does not accept ARS. Pick another currency'),
        findsOneWidget,
      );
    });

    testWidgets('a pick survives the same list arriving again', (
      tester,
    ) async {
      final container = await _pump(tester, accepted: const ['USD', 'ARS']);
      await tester.tap(find.byType(CurrencyInlineSelector));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ARS'));
      await tester.pumpAndSettle();
      expect(container.read(selectedFiatCodeProvider), 'ARS');

      container.invalidate(activeNodeCurrenciesProvider);
      await tester.pumpAndSettle();

      expect(container.read(selectedFiatCodeProvider), 'ARS');
    });
  });
}
