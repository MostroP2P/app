import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/test_environment.dart';
import 'package:mostro/features/drawer/screens/drawer_menu.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart';
import 'package:mostro/shared/widgets/test_environment_banner.dart';

Finder semantic(String id) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == id,
);

void main() {
  setUp(() {
    TestEnvironment.disarm();
  });
  tearDown(() {
    TestEnvironment.disarm();
    debugDefaultTargetPlatformOverride = null;
  });

  test('unarmed Linux and other platforms retain their ordinary labels', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(automationSemanticLabel('order.status', 'active'), 'active');
    expect(automationSemanticLabel('trade.release', null), isNull);
    TestEnvironment.arm();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(automationSemanticLabel('order.status', 'active'), 'active');
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(
      automationSemanticLabel('order.status', 'active'),
      TestEnvironment.defineEnabled ? '[mortsom:order.status]active' : 'active',
    );
  });

  testWidgets(
    'production Linux keeps the merged visible button label',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ElevatedButton(
            onPressed: () {},
            child: const Text('Release'),
          ).withAutomationId(AutomationIds.tradeRelease),
        ),
      );
      expect(
        tester.getSemantics(find.byType(ElevatedButton)),
        containsSemantics(
          identifier: AutomationIds.tradeRelease,
          label: 'Release',
          hasTapAction: true,
        ),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'armed Linux preserves identifiers actions and exact readouts',
    (tester) async {
      TestEnvironment.arm();
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              ElevatedButton(
                onPressed: () => tapped = true,
                child: const Text('Release'),
              ).withAutomationId(AutomationIds.tradeRelease),
              const Text(
                'Localized state',
              ).withAutomationId(AutomationIds.orderStatus, label: 'active'),
            ],
          ),
        ),
      );
      final button = tester.getSemantics(find.byType(ElevatedButton));
      expect(
        button.getSemanticsData().label,
        startsWith('[mortsom:trade.release]'),
      );
      expect(button.getSemanticsData().label, contains('Release'));
      expect(
        button,
        containsSemantics(
          identifier: AutomationIds.tradeRelease,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester
            .getSemantics(semantic(AutomationIds.orderStatus))
            .getSemanticsData()
            .label,
        '[mortsom:order.status]active',
      );
      await tester.tap(find.byType(ElevatedButton));
      expect(tapped, isTrue);
    },
    skip: !TestEnvironment.defineEnabled,
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'armed Linux tab semantics preserve the identifier and tab action',
    (tester) async {
      TestEnvironment.arm();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: DefaultTabController(
              length: 2,
              child: Scaffold(
                appBar: AppBar(
                  bottom: TabBar(
                    tabs: [
                      Tab(
                        child: const Text(
                          'Buy BTC',
                        ).withAutomationId(AutomationIds.orderBookTabBuy),
                      ),
                      Tab(
                        child: const Text(
                          'Sell BTC',
                        ).withAutomationId(AutomationIds.orderBookTabSell),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final tab = tester.getSemantics(
          semantic(AutomationIds.orderBookTabSell),
        );
        expect(
          tab.getSemanticsData().label,
          'Tab 2 of 2\n[mortsom:order.book.tab.sell]\nSell BTC',
        );
        expect(
          tester
              .getSemantics(semantic(AutomationIds.orderBookTabBuy))
              .getSemanticsData()
              .label,
          'Tab 1 of 2\n[mortsom:order.book.tab.buy]\nBuy BTC',
        );
        expect(
          tab,
          containsSemantics(
            identifier: AutomationIds.orderBookTabSell,
            hasTapAction: true,
            isSelected: false,
          ),
        );
        tab.owner!.performAction(tab.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(semantic(AutomationIds.orderBookTabSell)),
          containsSemantics(isSelected: true),
        );
      } finally {
        semantics.dispose();
      }
    },
    skip: !TestEnvironment.defineEnabled,
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'armed Linux banner and sidebar expose IDs and route user taps',
    (tester) async {
      TestEnvironment.arm();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder:
                (_, state) => const Scaffold(
                  body: TestEnvironmentBanner(
                    child: DrawerMenu(persistent: true),
                  ),
                ),
          ),
          GoRoute(
            path: AppRoute.orderBook,
            builder: (_, state) => const Scaffold(body: Text('Trades route')),
          ),
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final id in [
        AutomationIds.envMarker,
        AutomationIds.navTrades,
        AutomationIds.drawerSettings,
      ]) {
        expect(
          tester.getSemantics(semantic(id)).label,
          startsWith('[mortsom:$id]'),
        );
      }
      expect(
        tester.getSemantics(semantic(AutomationIds.navTrades)),
        containsSemantics(hasTapAction: true),
      );
      await tester.tap(semantic(AutomationIds.navTrades));
      await tester.pumpAndSettle();
      expect(find.text('Trades route'), findsOneWidget);
    },
    skip: !TestEnvironment.defineEnabled,
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
