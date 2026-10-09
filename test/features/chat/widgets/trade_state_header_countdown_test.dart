import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/trade_palette.dart';
import 'package:mostro/features/chat/widgets/trade_state_header.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

import '../../../support/fake_orders.dart';
import '../../../support/provider_harness.dart';

const _orderId = 'order-header-countdown';

Future<void> _pump(WidgetTester tester, {required Duration expiresIn}) async {
  final order = fakeOrder(
    id: _orderId,
    paymentMethod: 'Mercado Pago',
    status: OrderStatus.active,
    expiresAt: kFakeNow.add(expiresIn),
  );
  final container = createContainer(
    overrides: [
      chatTradeOrderProvider.overrideWith((ref, id) async => order),
      tradeStatusProvider.overrideWith(
        (ref, id) => Stream.value(OrderStatus.active),
      ),
      tradeRoleFromDbProvider.overrideWith((ref, id) async => true),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: TradeStateHeader(orderId: _orderId)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// The chat's countdown follows DS-CMP-21 (#723): the shared formatter (no
/// `H:MM:SS`) and the shared tones.
void main() {
  testWidgets('reads hours as h mm', (tester) async {
    await withClock(Clock.fixed(kFakeNow), () async {
      await _pump(tester, expiresIn: const Duration(hours: 2, minutes: 5));

      expect(find.text('2 h 05 left'), findsOneWidget);
      expect(find.textContaining('2:05:00'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('announces turning urgent once, not every tick', (tester) async {
    var now = kFakeNow;
    await withClock(Clock(() => now), () async {
      await _pump(tester, expiresIn: const Duration(minutes: 5, seconds: 2));
      tester.takeAnnouncements();

      for (var i = 0; i < 8; i++) {
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }

      expect(
        [for (final a in tester.takeAnnouncements()) a.message],
        ['04:59 left'],
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('turns coral under five minutes', (tester) async {
    await withClock(Clock.fixed(kFakeNow), () async {
      await _pump(tester, expiresIn: const Duration(minutes: 3));

      final text = tester.widget<Text>(find.text('03:00 left'));
      expect(text.style?.color, TradePalette.dark.timerUrgent);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
