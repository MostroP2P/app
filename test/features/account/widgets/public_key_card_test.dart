import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/account/widgets/public_key_card.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// The card is the only place the active account is identifiable without
/// revealing the secret words, and its readout is what Mortsom reads to know
/// which identity it is driving. Both are asserted here; loading the key over
/// the Rust bridge is the account screen's job and is not covered.
void main() {
  const key =
      '8171eb680049f62ce8747d203f57c3f71de6eea308af6f995363896a1e47cc51';

  Future<void> pump(WidgetTester tester, String? publicKey) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: PublicKeyCard(publicKey: publicKey)),
      ),
    );
  }

  testWidgets('shows the placeholder when no identity is stored',
      (tester) async {
    await pump(tester, null);

    expect(find.text(PublicKeyCard.placeholder), findsOneWidget);
    // An empty readout is how the harness knows to generate an identity;
    // the placeholder must not leak into it as if it were a key.
    expect(
      tester.getSemantics(find.byType(PublicKeyCard)),
      containsSemantics(identifier: AutomationIds.keysPublicKey, label: ''),
    );
  });

  testWidgets('shows the key and exposes it whole', (tester) async {
    await pump(tester, key);

    expect(find.text(key), findsOneWidget);
    // The visible text ellipsizes at the card's width; the readout does not.
    expect(
      tester.getSemantics(find.byType(PublicKeyCard)),
      containsSemantics(identifier: AutomationIds.keysPublicKey, label: key),
    );
  });

  testWidgets('follows the key when the identity is replaced', (tester) async {
    const replacement =
        '0000000000000000000000000000000000000000000000000000000000000001';
    await pump(tester, key);
    await pump(tester, replacement);

    expect(find.text(key), findsNothing);
    expect(
      tester.getSemantics(find.byType(PublicKeyCard)),
      containsSemantics(
        identifier: AutomationIds.keysPublicKey,
        label: replacement,
      ),
    );
  });
}
