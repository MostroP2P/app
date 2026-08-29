import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/trades/widgets/dispute_confirmation_dialog.dart';
import 'package:mostro/l10n/app_localizations.dart';

Widget _host() {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDisputeConfirmationDialog(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

Future<bool?> _openAndTap(WidgetTester tester, String buttonText) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDisputeConfirmationDialog(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(buttonText));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('renders title, body and Yes/No buttons', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Open dispute'), findsOneWidget);
    expect(
      find.textContaining('escalates the trade to an admin'),
      findsOneWidget,
    );
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
  });

  testWidgets('tapping Yes resolves with true', (tester) async {
    expect(await _openAndTap(tester, 'Yes'), isTrue);
  });

  testWidgets('tapping No resolves with false', (tester) async {
    expect(await _openAndTap(tester, 'No'), isFalse);
  });
}
