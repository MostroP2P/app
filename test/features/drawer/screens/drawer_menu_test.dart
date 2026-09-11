import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/about/screens/about_screen.dart'
    show appVersionProvider;
import 'package:mostro/features/drawer/screens/drawer_menu.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show orderBookNotificationCountProvider;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart'
    show chatNotificationCountProvider;

Future<void> _pumpDrawer(
  WidgetTester tester, {
  ThemeData? theme,
  bool persistent = false,
  VoidCallback? onClose,
  Future<String> Function()? version,
  double textScale = 1,
}) async {
  // Like the real hosts, remove the overlay drawer from the tree on close.
  var isOpen = true;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: AppRoute.home,
        builder:
            (_, __) => StatefulBuilder(
              builder:
                  (context, setState) => Scaffold(
                    body:
                        isOpen
                            ? DrawerMenu(
                              persistent: persistent,
                              onClose: () {
                                setState(() => isOpen = false);
                                onClose?.call();
                              },
                            )
                            : const SizedBox.shrink(),
                  ),
            ),
      ),
      for (final (path, name) in [
        (AppRoute.keyManagement, 'Account route'),
        (AppRoute.settings, 'Settings route'),
        (AppRoute.about, 'About route'),
      ])
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Text(name)),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appVersionProvider.overrideWith(
          (ref) => (version ?? () async => '2.0.0')(),
        ),
        orderBookNotificationCountProvider.overrideWith((ref) => 0),
        chatNotificationCountProvider.overrideWith((ref) => 0),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: theme ?? buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _semantic(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

void main() {
  group('DrawerMenu overlay', () {
    testWidgets('header shows wordmark, uppercase tagline and stage chip', (
      tester,
    ) async {
      await _pumpDrawer(tester);

      expect(find.text('Mostro'), findsOneWidget);
      expect(find.text('P2P EXCHANGE'), findsOneWidget);
      expect(find.text('ALPHA'), findsOneWidget);
    });

    testWidgets('footer shows the app version', (tester) async {
      await _pumpDrawer(tester);

      expect(find.text('Version 2.0.0'), findsOneWidget);
    });

    testWidgets('footer omits the version line when it cannot be read', (
      tester,
    ) async {
      await _pumpDrawer(
        tester,
        version: () async => throw StateError('bridge not loaded'),
      );

      expect(find.textContaining('Version'), findsNothing);
    });

    testWidgets('lists Account, Settings and About with none selected', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpDrawer(tester);

      for (final (id, label) in [
        (AutomationIds.drawerAccount, 'Account'),
        (AutomationIds.drawerSettings, 'Settings'),
        (AutomationIds.drawerAbout, 'About'),
      ]) {
        expect(find.text(label), findsOneWidget);
        expect(
          tester.getSemantics(_semantic(id)),
          containsSemantics(isButton: true, isSelected: false),
        );
      }
      semantics.dispose();
    });

    testWidgets('tapping an item closes the drawer and navigates', (
      tester,
    ) async {
      var closed = false;
      await _pumpDrawer(tester, onClose: () => closed = true);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(find.text('Settings route'), findsOneWidget);
    });

    testWidgets('tapping the scrim slides the panel out, then closes', (
      tester,
    ) async {
      var closed = false;
      await _pumpDrawer(tester, onClose: () => closed = true);

      await tester.tapAt(const Offset(780, 300));
      await tester.pump();
      expect(closed, isFalse, reason: 'closes only after the exit animation');

      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });

    for (final (mode, theme, palette) in [
      ('dark', buildDarkTheme(), DrawerPalette.dark),
      ('light', buildLightTheme(), DrawerPalette.light),
    ]) {
      testWidgets('uses the $mode palette under the $mode theme', (
        tester,
      ) async {
        await _pumpDrawer(tester, theme: theme);

        expect(
          find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == palette.scrim,
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('does not overflow on a small phone with large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _pumpDrawer(tester, textScale: 2);

      expect(tester.takeException(), isNull);
      expect(find.text('Account'), findsOneWidget);
    });
  });

  group('DrawerMenu persistent', () {
    testWidgets('highlights the active primary destination only', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpDrawer(tester, persistent: true);

      expect(
        tester.getSemantics(_semantic(AutomationIds.navOrderBook)),
        containsSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(_semantic(AutomationIds.drawerSettings)),
        containsSemantics(isSelected: false),
      );
      expect(find.text('ALPHA'), findsOneWidget);
      semantics.dispose();
    });
  });
}
