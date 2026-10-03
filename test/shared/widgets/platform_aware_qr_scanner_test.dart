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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: PlatformAwareQrScanner(onDetected: onDetected)),
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
  });
}
