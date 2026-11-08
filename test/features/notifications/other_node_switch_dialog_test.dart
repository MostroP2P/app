import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/notifications/widgets/other_node_switch_dialog.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_de.dart';
import 'package:mostro/l10n/app_localizations_en.dart';

/// #811: opening a notification of another node's trade asks to switch.

final _en = AppLocalizationsEn();
final _de = AppLocalizationsDe();

void main() {
  late List<bool?> results;
  late int switches;

  /// Opens the dialog from a button; [onSwitch] answers each switch.
  Future<void> pump(
    WidgetTester tester, {
    Future<bool> Function()? onSwitch,
    Locale locale = const Locale('en'),
  }) async {
    results = [];
    switches = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () async {
                    results.add(
                      await showOtherNodeSwitchDialog(
                        context,
                        nodeName: 'Node A',
                        onSwitch: () {
                          switches++;
                          return (onSwitch ?? () async => true)();
                        },
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('it asks to switch to the node, by name', (tester) async {
    await pump(tester);

    expect(find.text(_en.otherNodeCardDialogTitle), findsOneWidget);
    expect(find.text(_en.otherNodeCardSwitchPrompt('Node A')), findsOneWidget);
    expect(find.text(_en.nodeSwitchConfirmAction), findsOneWidget);
    expect(find.text(_en.cancel), findsOneWidget);
  });

  testWidgets('Cancel switches nothing', (tester) async {
    await pump(tester);

    await tester.tap(find.text(_en.cancel));
    await tester.pumpAndSettle();

    expect(switches, 0);
    expect(results, [null]);
    expect(find.text(_en.otherNodeCardDialogTitle), findsNothing);
  });

  testWidgets('the switch runs with the dialog open, which nothing closes '
      'meanwhile', (tester) async {
    final gate = Completer<bool>();
    await pump(tester, onSwitch: () => gate.future);

    await tester.tap(find.text(_en.nodeSwitchConfirmAction));
    await tester.pump();

    expect(switches, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.text(_en.otherNodeCardDialogTitle), findsOneWidget);
    expect(results, isEmpty);

    gate.complete(true);
    await tester.pumpAndSettle();

    expect(results, [true]);
    expect(find.text(_en.otherNodeCardDialogTitle), findsNothing);
  });

  testWidgets('a failed switch closes it and says so to the caller', (
    tester,
  ) async {
    await pump(tester, onSwitch: () async => false);

    await tester.tap(find.text(_en.nodeSwitchConfirmAction));
    await tester.pumpAndSettle();

    expect(results, [false]);
  });

  testWidgets('a switch that throws closes it as a failed one', (
    tester,
  ) async {
    await pump(tester, onSwitch: () async => throw StateError('boom'));

    await tester.tap(find.text(_en.nodeSwitchConfirmAction));
    await tester.pumpAndSettle();

    expect(results, [false]);
    expect(find.text(_en.otherNodeCardDialogTitle), findsNothing);
  });

  // DS-A11Y-4: the dialog at 320 dp, 2× text, German.
  testWidgets('it fits 320 dp at 2× text in German', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pump(tester, locale: const Locale('de'));

    expect(find.text(_de.otherNodeCardSwitchPrompt('Node A')), findsOneWidget);
    expect(find.text(_de.nodeSwitchConfirmAction), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
