import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/widgets/mostro_node_selector.dart';
import 'package:mostro/l10n/app_localizations.dart';
import '../../../support/provider_harness.dart';

/// Pump the selector with the given bottom [keyboardInset] (viewInsets) and
/// [systemBarInset] (viewPadding). A tall surface keeps a large keyboard inset
/// from overflowing the test viewport.
Future<void> _pump(
  WidgetTester tester, {
  double keyboardInset = 0,
  double systemBarInset = 0,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = createContainer();
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
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(bottom: keyboardInset),
              viewPadding: EdgeInsets.only(bottom: systemBarInset),
              padding: EdgeInsets.only(bottom: systemBarInset),
            ),
            child: const Scaffold(
              resizeToAvoidBottomInset: false,
              body: MostroNodeSelector(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('MostroNodeSelector bottom inset', () {
    testWidgets('renders with the keyboard hidden', (tester) async {
      await _pump(tester, keyboardInset: 0, systemBarInset: 34);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('renders with the keyboard visible', (tester) async {
      await _pump(tester, keyboardInset: 300, systemBarInset: 34);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });
}
