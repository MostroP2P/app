import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/platform_aware_qr_scanner.dart';

const _scannerMethods = MethodChannel(
  'dev.steenbakker.mobile_scanner/scanner/method',
);
const _scannerEvents = MethodChannel(
  'dev.steenbakker.mobile_scanner/scanner/event',
);
const _scannerOrientation = MethodChannel(
  'dev.steenbakker.mobile_scanner/scanner/deviceOrientation',
);

Future<void> _pump(
  WidgetTester tester, {
  required void Function(String) onDetected,
  Locale? locale,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      // As every caller hosts it: the body of a Scaffold under an app bar,
      // which the keyboard shrinks.
      home: Scaffold(
        appBar: AppBar(title: const Text('Scan')),
        body: PlatformAwareQrScanner(onDetected: onDetected),
      ),
    ),
  );
  await tester.pump();
}

/// Answers mobile_scanner's channels the way Android does when the user
/// refuses the camera permission: not yet granted, then refused.
void _denyCameraPermission(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_scannerMethods, (call) async {
    switch (call.method) {
      case 'state':
        return 2; // MobileScannerAuthorizationState.denied
      case 'request':
        return false;
    }
    return null;
  });
  messenger.setMockMethodCallHandler(_scannerEvents, (_) async => null);
  messenger.setMockMethodCallHandler(_scannerOrientation, (_) async => null);
  addTearDown(() {
    messenger.setMockMethodCallHandler(_scannerMethods, null);
    messenger.setMockMethodCallHandler(_scannerEvents, null);
    messenger.setMockMethodCallHandler(_scannerOrientation, null);
  });
}

void main() {
  group('qrInputFor', () {
    // mobile_scanner 7.4 implements Android, iOS, macOS and web. macOS is on
    // the paste side anyway: the sandboxed app lacks the camera entitlement
    // and NSCameraUsageDescription (#458).
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    ]) {
      test('$platform pastes: mobile_scanner has no camera there', () {
        expect(qrInputFor(false, platform), QrInput.paste);
      });
    }

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      test('$platform scans with the camera', () {
        expect(qrInputFor(false, platform), QrInput.camera);
      });
    }

    // On web `defaultTargetPlatform` is the browser's OS, so a phone browser
    // reports android — it must still get the paste field.
    for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
      test('web on $platform pastes', () {
        expect(qrInputFor(true, platform), QrInput.paste);
      });
    }
  });

  group('PlatformAwareQrScanner', () {
    testWidgets(
      'without a camera it shows the paste field, never mobile_scanner',
      (tester) async {
        final detected = <String>[];
        await _pump(tester, onDetected: detected.add);

        expect(find.byType(MobileScanner), findsNothing);
        expect(find.byType(TextField), findsOneWidget);

        await tester.enterText(find.byType(TextField), '  cashuBpasted  ');
        await tester.tap(find.text('Submit'));
        await tester.tap(find.text('Submit'));
        await tester.pump();

        expect(detected, ['cashuBpasted']);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'a refused camera permission falls back to the paste field',
      (tester) async {
        _denyCameraPermission(tester);
        final detected = <String>[];
        await _pump(tester, onDetected: detected.add);
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'lnbc1pasted');
        await tester.tap(find.text('Submit'));
        await tester.pump();

        expect(detected, ['lnbc1pasted']);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    // On desktop the value comes in with a paste shortcut, so Enter is the
    // keyboard's Submit, as in the Cashu Receive dialog. Also on a phone
    // whose camera was refused, where the same form stands in.
    testWidgets(
      'Enter submits the paste field once, trimmed',
      (tester) async {
        if (defaultTargetPlatform == TargetPlatform.android) {
          _denyCameraPermission(tester);
        }
        final detected = <String>[];
        await _pump(tester, onDetected: detected.add);
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '  lnbc1entered  ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(detected, ['lnbc1entered']);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.linux,
        TargetPlatform.android,
      }),
    );

    testWidgets(
      'Enter on an empty paste field says so and keeps the focus',
      (tester) async {
        if (defaultTargetPlatform == TargetPlatform.android) {
          _denyCameraPermission(tester);
        }
        final detected = <String>[];
        await _pump(tester, onDetected: detected.add);
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '   ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(detected, isEmpty);
        expect(find.text('Please enter a value'), findsOneWidget);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue,
        );
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.linux,
        TargetPlatform.android,
      }),
    );
  });
  // DS-A11Y-4: the longest translation, doubled, on the narrowest phone —
  // with the keyboard up as well, since typing into the paste field raises
  // it: on a phone browser, and on a phone whose camera was refused.
  group('PlatformAwareQrScanner paste form fits', () {
    for (final keyboard in [0.0, 280.0]) {
      testWidgets(
        'German at 2x on a 320 dp screen, keyboard inset $keyboard',
        (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1.0;
          tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
          tester.platformDispatcher.textScaleFactorTestValue = 2.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          if (defaultTargetPlatform == TargetPlatform.android) {
            _denyCameraPermission(tester);
          }

          await _pump(tester, onDetected: (_) {}, locale: const Locale('de'));
          await tester.pumpAndSettle();

          expect(find.byType(TextField), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        variant: const TargetPlatformVariant({
          TargetPlatform.linux,
          TargetPlatform.android,
        }),
      );
    }
  });
}
