import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/settings/screens/nwc_wallet_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/input_source_action.dart';
import 'package:mostro/shared/widgets/platform_aware_qr_scanner.dart';

import '../../../support/provider_harness.dart';

class _NoWallet extends NwcNotifier {}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: createContainer(
        overrides: [nwcProvider.overrideWith((ref) => _NoWallet())],
      ),
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NwcWalletScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

InputSourceAction _scanAction(WidgetTester tester) =>
    tester.widget<InputSourceAction>(
      find.widgetWithText(InputSourceAction, 'Scan QR'),
    );

void main() {
  group('NwcWalletScreen Scan QR', () {
    // Same row and widget as the Cashu Receive dialog, so the same answer:
    // without a camera, scanning is off and says why, instead of opening a
    // second paste field over the one already on screen.
    testWidgets(
      'without a camera it is disabled and says why',
      (tester) async {
        await _pump(tester);

        final scan = _scanAction(tester);
        expect(scan.onTap, isNull);
        expect(scan.tooltip, 'Not available on this device');

        await tester.tap(find.text('Scan QR'));
        await tester.pumpAndSettle();
        expect(find.byType(PlatformAwareQrScanner), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'with a camera it is enabled',
      (tester) async {
        await _pump(tester);

        final scan = _scanAction(tester);
        expect(scan.onTap, isNotNull);
        expect(scan.tooltip, isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });
}
