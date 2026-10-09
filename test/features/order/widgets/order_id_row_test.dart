import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// DS-CMP-22: the reference id row reads `09150348…99b5` beside a copy icon
/// of 16 (DS-ICO-3), and the whole row copies.
void main() {
  testWidgets('the id row shows the short id and a 16 copy icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: OrderIdRow(orderId: '09150348-1a2b-4c3d-8e9f-0a1b2c3d99b5'),
        ),
      ),
    );

    expect(find.text('09150348…99b5'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.copy_rounded));
    expect(icon.size, 16);
  });
}
