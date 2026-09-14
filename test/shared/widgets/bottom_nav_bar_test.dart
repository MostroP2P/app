import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show orderBookNotificationCountProvider;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart';

Future<void> _pump(WidgetTester tester) async {
  GoRoute route(String path) => GoRoute(
    path: path,
    builder:
        (_, __) => Scaffold(
          body: Text('route $path'),
          bottomNavigationBar: const BottomNavBar(),
        ),
  );
  final router = GoRouter(
    routes: [
      route(AppRoute.home),
      route(AppRoute.orderBook),
      route(AppRoute.chatList),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        orderBookNotificationCountProvider.overrideWith((ref) => 0),
        chatNotificationCountProvider.overrideWith((ref) => 0),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the three short labels on a 68-tall bar', (tester) async {
    await _pump(tester);

    for (final label in ['Book', 'Trades', 'Chat']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.getSize(find.byType(BottomNavBar)).height, 68);
  });

  testWidgets('colours the active destination lime and the rest muted', (
    tester,
  ) async {
    await _pump(tester);

    Color? colorOf(String label) =>
        tester.widget<Text>(find.text(label)).style?.color;
    expect(colorOf('Book'), OrderBookPalette.dark.limeText);
    expect(colorOf('Trades'), OrderBookPalette.dark.textTertiary);
  });

  testWidgets('navigates to the tapped destination', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Trades'));
    await tester.pumpAndSettle();

    expect(find.text('route ${AppRoute.orderBook}'), findsOneWidget);
  });
}
