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

    testWidgets('a newer override arriving mid-frame is not overwritten',
        (tester) async {
      // The race the seeding path has to survive: the widget schedules its seed
      // callback during build, and a newer override lands before that callback
      // runs. Capturing the value at build time would restore the stale one.
      //
      // Reproducing it needs two things: a *synchronous* controller, so the
      // listener fires inside the frame rather than in a later microtask; and a
      // post-frame callback registered *before* the widget's, so the newer
      // value is emitted while the widget's callback is still queued behind it.
      final controller = StreamController<EscrowModeInfo>.broadcast(sync: true);
      addTearDown(controller.close);

      await _pump(tester, controller.stream);
      controller.add(_info(mintOverride: 'http://old.example'));

      // Runs ahead of the seed callback the next build will schedule.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.add(_info(mintOverride: 'http://new.example'));
      });

      await tester.pump();
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.controller?.text,
        'http://new.example',
        reason: 'the seed callback must read the current value, not a copy '
            'captured during build',
      );
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
