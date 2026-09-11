import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/add_order_button.dart';

Future<void> _pump(WidgetTester tester) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder:
            (_, __) => const Scaffold(
              body: Center(child: Text('BOOK')),
              floatingActionButton: AddOrderButton(),
              bottomNavigationBar: SizedBox(
                height: 68,
                child: Center(child: Text('NAV')),
              ),
            ),
      ),
      GoRoute(
        path: AppRoute.addOrder,
        builder: (_, state) => Text('add ${state.uri.queryParameters['type']}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      theme: buildDarkTheme(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

Finder get _scrim => find.byWidgetPredicate(
  (w) => w is ColoredBox && w.color == OrderBookPalette.dark.scrim,
);

Finder _buttonWith(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

void main() {
  testWidgets('opens a full-screen scrim over the bottom bar', (tester) async {
    await _pump(tester);
    expect(_scrim, findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getSize(_scrim), screen);
    expect(
      tester.getRect(_scrim).contains(tester.getCenter(find.text('NAV'))),
      isTrue,
    );
    expect(find.text('Tap outside to close'), findsOneWidget);
  });

  testWidgets('shows Buy and Sell as equal full-width buttons', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    final buy = tester.getRect(_buttonWith('Buy BTC'));
    final sell = tester.getRect(_buttonWith('Sell BTC'));
    expect(buy.size, sell.size);
    expect(buy.height, greaterThanOrEqualTo(52));
    expect(buy.left, 18);
    expect(buy.width, tester.getSize(_scrim).width - 36);
  });

  testWidgets('tapping the scrim closes it', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();

    expect(_scrim, findsNothing);
    expect(find.text('Buy BTC'), findsNothing);
  });

  testWidgets('the close button in the open state collapses it', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(_scrim, findsNothing);
  });

  testWidgets('closes when the screen changes size while open', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();

    expect(_scrim, findsNothing);
    expect(find.text('Buy BTC'), findsNothing);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('hides what is behind the scrim from screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    // Semantics finders search the live semantics tree, where blocked nodes
    // are actually gone.
    expect(find.semantics.byLabel('NAV'), findsOne);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.semantics.byLabel('NAV'), findsNothing);
    expect(find.semantics.byLabel(RegExp('Buy BTC')), findsOne);
    semantics.dispose();
  });

  testWidgets('keeps keyboard focus inside the open menu', (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    final visited = <FocusNode>{};
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus!;
      expect(focus.enclosingScope?.debugLabel, 'Create-order menu');
      visited.add(focus);
    }

    // Twice round the three controls: Buy, Sell and Close, nothing else.
    expect(visited, hasLength(3));
  });

  for (final (label, type) in [('Buy BTC', 'buy'), ('Sell BTC', 'sell')]) {
    testWidgets('$label closes and opens the create-order form', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(find.text('add $type'), findsOneWidget);
      expect(_scrim, findsNothing);
    });
  }
}
