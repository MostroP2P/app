import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/escrow_mode_provider.dart';
import 'package:mostro/features/settings/widgets/escrow_mode_dev_card.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/provider_harness.dart';

EscrowModeInfo _info({String? mintOverride}) => EscrowModeInfo(
      mode: 'lightning',
      mintUrl: null,
      escrowLocktimeDays: null,
      settlementMarginDays: null,
      isOverridden: false,
      isCashuAvailable: false,
      forceCashuOverride: false,
      mintUrlOverride: mintOverride,
    );

Future<void> _pump(WidgetTester tester, Stream<EscrowModeInfo> stream) async {
  final container = createContainer(overrides: [
    escrowModeProvider.overrideWith((ref) => stream),
  ]);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: EscrowModeDevCard()),
      ),
    ),
  );
}

void main() {
  group('EscrowModeDevCard', () {
    testWidgets('seeds the mint field from the stored override', (tester) async {
      final controller = StreamController<EscrowModeInfo>();
      addTearDown(controller.close);

      await _pump(tester, controller.stream);
      controller.add(_info(mintOverride: 'http://localhost:3338'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'http://localhost:3338');
    });

    testWidgets('the newest override wins over an earlier one', (tester) async {
      // Guards the seeding path against applying a stale value: the seed is
      // read when the post-frame callback runs, not captured during the build
      // that scheduled it.
      final controller = StreamController<EscrowModeInfo>();
      addTearDown(controller.close);

      await _pump(tester, controller.stream);
      controller.add(_info(mintOverride: 'http://old.example'));
      await tester.pumpAndSettle();
      controller.add(_info(mintOverride: 'http://new.example'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'http://new.example');
    });

    testWidgets('typing survives an event that did not change the override',
        (tester) async {
      // A node switch or a capability re-fetch emits without touching the
      // override; wiping the field on those would eat what the user is typing.
      final controller = StreamController<EscrowModeInfo>();
      addTearDown(controller.close);

      await _pump(tester, controller.stream);
      controller.add(_info(mintOverride: 'http://localhost:3338'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'http://typing');
      controller.add(_info(mintOverride: 'http://localhost:3338'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'http://typing');
    });
  });
}
