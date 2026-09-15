import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/features/trades/widgets/bond_slashed_notice.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';

BondInfo _bond(BondState state) => BondInfo(
  role: BondRole.taker,
  amountSats: BigInt.from(1648),
  invoice: 'lnbc16480n1bond',
  state: state,
  requestedAt: intToPlatformInt64(1000),
  expiresAt: null,
  lockedAt: null,
);

/// A notifier with [notices] and no store, so nothing touches disk.
NotificationsNotifier _notifier(List<NotificationModel> notices) {
  final notifier = NotificationsNotifier();
  for (final n in notices) {
    notifier.state = [...notifier.state, n];
  }
  return notifier;
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  TradeInfo trade, {
  List<NotificationModel> notices = const [],
  TradeInfo Function()? tradeNow,
}) async {
  final container = ProviderContainer(
    overrides: [
      rawTradesProvider.overrideWith((ref) async => const []),
      tradeInfoProvider.overrideWith((ref, id) async {
        // Re-read on the trades refresh, as the real provider does.
        ref.watch(rawTradesProvider);
        return tradeNow == null ? trade : tradeNow();
      }),
      notificationsProvider.overrideWith((ref) => _notifier(notices)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: BondSlashedNotice(orderId: 'order-1')),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return container;
}

Finder _byId(String id) =>
    find.byWidgetPredicate((w) => w is AutomationId && w.id == id);

void main() {
  testWidgets('nothing unless the bond was slashed', (tester) async {
    await _pump(tester, fakeTrade(bond: _bond(BondState.locked)));
    expect(_byId(AutomationIds.tradeBondSlashed), findsNothing);
  });

  testWidgets('a dispute-cause slash names the dispute', (tester) async {
    await _pump(
      tester,
      fakeTrade(
        status: OrderStatus.settledByAdmin,
        bond: _bond(BondState.slashed),
      ),
    );
    expect(
      find.text('The node slashed your 1648-sat bond in this dispute.'),
      findsOneWidget,
    );
    expect(
      tester.widget<AutomationId>(_byId(AutomationIds.tradeBondSlashed)).label,
      'dispute',
    );
  });

  testWidgets('a timeout slash names the timeout', (tester) async {
    await _pump(
      tester,
      fakeTrade(status: OrderStatus.canceled, bond: _bond(BondState.slashed)),
    );
    expect(find.textContaining('after a step timed out'), findsOneWidget);
    expect(
      tester.widget<AutomationId>(_byId(AutomationIds.tradeBondSlashed)).label,
      'timeout',
    );
  });

  testWidgets('the released-to-slashed transition shows up on the refresh', (
    tester,
  ) async {
    // The resolution left the bond provisionally Released; the slash notice
    // then rewrites the row and the bootstrap refreshes the trades.
    var state = BondState.released;
    final container = await _pump(
      tester,
      fakeTrade(
        status: OrderStatus.settledByAdmin,
        bond: _bond(BondState.released),
      ),
      tradeNow:
          () =>
              fakeTrade(status: OrderStatus.settledByAdmin, bond: _bond(state)),
    );
    expect(_byId(AutomationIds.tradeBondSlashed), findsNothing);

    state = BondState.slashed;
    container.invalidate(rawTradesProvider);
    await tester.pumpAndSettle();
    expect(_byId(AutomationIds.tradeBondSlashed), findsOneWidget);
  });

  testWidgets('the amount is the slice the notice reported, not the bond', (
    tester,
  ) async {
    await _pump(
      tester,
      fakeTrade(
        id: 'order-1',
        status: OrderStatus.settledByAdmin,
        bond: _bond(BondState.slashed),
      ),
      notices: [
        NotificationModel.bondSlashed(
          id: 'evt-1',
          orderId: 'order-1',
          amountSats: 412,
          disputeCause: true,
        ),
      ],
    );
    expect(find.textContaining('your 412-sat bond'), findsOneWidget);
    expect(find.textContaining('1648'), findsNothing);
  });
}
