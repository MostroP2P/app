import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/features/trades/widgets/bond_claim_banner.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart';

const _now = 1789300800;

BondClaim _claim(BondClaimPhase phase, {int deadlineAt = _now + 86400}) =>
    BondClaim(
      orderId: 'order-1',
      nodePubkey: 'node-a',
      amountSats: BigInt.from(1500),
      slashedAt: intToPlatformInt64(_now - 3600),
      deadlineAt: intToPlatformInt64(deadlineAt),
      phase: phase,
      submittedInvoice: null,
      fiatCode: 'USD',
      fiatAmount: 100,
      paymentMethod: 'Wire',
      updatedAt: intToPlatformInt64(_now - 60),
    );

Future<void> _pump(WidgetTester tester, BondClaim? claim) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bondClaimProvider.overrideWith((ref, id) async => claim),
        bondClaimUpdatesProvider.overrideWith(
          (ref) => const Stream<BondClaimUpdate>.empty(),
        ),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: ListView(children: const [BondClaimBanner(orderId: 'order-1')]),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Finder _byId(String id) =>
    find.byWidgetPredicate((w) => w is AutomationId && w.id == id);

void main() {
  final clockAt = Clock.fixed(
    DateTime.fromMillisecondsSinceEpoch(_now * 1000, isUtc: true),
  );

  testWidgets('nothing without a claim', (tester) async {
    await _pump(tester, null);
    expect(_byId(AutomationIds.tradeBondClaim), findsNothing);
  });

  testWidgets('a pending claim offers the payout invoice', (tester) async {
    await withClock(clockAt, () async {
      await _pump(tester, _claim(BondClaimPhase.pending));
      expect(find.textContaining('ready to come back to you'), findsOneWidget);
      expect(find.text('Add payout invoice'), findsOneWidget);
      expect(
        tester.widget<AutomationId>(_byId(AutomationIds.tradeBondClaim)).label,
        'pending',
      );
    });
  });

  testWidgets('an acknowledged claim reads in progress with a way to it', (
    tester,
  ) async {
    await withClock(clockAt, () async {
      await _pump(tester, _claim(BondClaimPhase.acknowledged));
      expect(find.text('Payout in progress'), findsOneWidget);
      expect(find.text('View claim'), findsOneWidget);
    });
  });

  testWidgets('a paid claim names the date and offers nothing', (tester) async {
    await withClock(clockAt, () async {
      await _pump(tester, _claim(BondClaimPhase.completed));
      expect(find.text('Payout received'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  testWidgets('a claim past its window is a muted line', (tester) async {
    await withClock(clockAt, () async {
      await _pump(tester, _claim(BondClaimPhase.pending, deadlineAt: _now - 1));
      expect(find.textContaining('closed on'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
