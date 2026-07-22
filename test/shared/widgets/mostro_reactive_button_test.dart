import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/shared/widgets/mostro_reactive_button.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Future<void> Function() onPressed,
  MostroButtonVariant variant = MostroButtonVariant.primary,
  bool outlined = false,
  void Function(Object error)? onError,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: MostroReactiveButton(
          label: 'Do it',
          variant: variant,
          outlined: outlined,
          onPressed: onPressed,
          onError: onError,
        ),
      ),
    ),
  );
}

void main() {
  group('MostroReactiveButton', () {
    testWidgets('idle renders the label', (tester) async {
      await _pump(tester, onPressed: () async {});
      expect(find.text('Do it'), findsOneWidget);
    });

    testWidgets('outlined: false renders a FilledButton', (tester) async {
      await _pump(tester, onPressed: () async {});
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('outlined: true renders an OutlinedButton', (tester) async {
      await _pump(tester, onPressed: () async {}, outlined: true);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('tap shows a spinner, then success, then the label again',
        (tester) async {
      final completer = Completer<void>();
      await _pump(tester, onPressed: () => completer.future);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete();
      await tester.pump();
      expect(find.byIcon(Icons.check), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('Do it'), findsOneWidget);
    });

    testWidgets('disabled while pending, so a second tap does not re-enter',
        (tester) async {
      var callCount = 0;
      final completer = Completer<void>();
      await _pump(
        tester,
        onPressed: () {
          callCount++;
          return completer.future;
        },
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(callCount, 1);

      completer.complete();
      await tester.pump(const Duration(milliseconds: 1500));
    });

    testWidgets(
        'on failure: reports onError, shows no error icon or color, '
        'stays disabled for 4s', (tester) async {
      Object? reportedError;
      await _pump(
        tester,
        onPressed: () async => throw Exception('boom'),
        onError: (e) => reportedError = e,
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(reportedError, isNotNull);
      expect(find.text('Do it'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);

      final duringCooldown =
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(duringCooldown.onPressed, isNull);

      await tester.pump(const Duration(seconds: 4));
      final afterCooldown =
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(afterCooldown.onPressed, isNotNull);
    });

    testWidgets(
        'destructive variant renders outlined with the destructive accent, '
        'not the primary green', (tester) async {
      await _pump(
        tester,
        onPressed: () async {},
        variant: MostroButtonVariant.destructive,
        outlined: true,
      );

      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);

      final button =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      final accent = button.style?.side?.resolve(<WidgetState>{})?.color;
      final green = buildDarkTheme().extension<AppColors>()!.mostroGreen;

      expect(accent, isNotNull);
      expect(accent, isNot(equals(green)));
    });

    testWidgets(
        'on MostroActionAborted: no success checkmark, no error report, '
        'button immediately re-enabled', (tester) async {
      Object? reportedError;
      await _pump(
        tester,
        onPressed: () async => throw const MostroActionAborted(),
        onError: (e) => reportedError = e,
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(reportedError, isNull);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.text('Do it'), findsOneWidget);

      final afterAbort =
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(afterAbort.onPressed, isNotNull);
    });
  });
}
