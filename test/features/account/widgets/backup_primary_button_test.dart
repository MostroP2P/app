import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/widgets/backup_widgets.dart';

void main() {
  testWidgets('keeps its label for assistive technology while loading', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: BackupPrimaryButton(
            label: 'Confirm',
            onPressed: () {},
            loading: true,
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
    expect(find.bySemanticsLabel('Confirm'), findsOneWidget);
    semantics.dispose();
  });
}
