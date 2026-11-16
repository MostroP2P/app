import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/widgets/message_input.dart';
import 'package:mostro/l10n/app_localizations.dart';

void main() {
  late List<String> sent;

  Future<void> pump(WidgetTester tester) async {
    sent = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageInput(onSendText: sent.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  group('MessageInput emojis (#938)', () {
    testWidgets('the emoji button puts the picked emoji at the cursor', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'hi');

      await tester.tap(find.byTooltip('Insert emoji'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('😀').first);
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'hi😀');
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );

      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      expect(sent, ['hi😀']);
    });

    testWidgets('dismissing the emoji sheet leaves the text as it was', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'hi');

      await tester.tap(find.byTooltip('Insert emoji'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'hi');
    });

    testWidgets('the field grows to five lines and still sends', (
      tester,
    ) async {
      await pump(tester);

      expect(field(tester).minLines, 1);
      expect(field(tester).maxLines, 5);
      expect(field(tester).textInputAction, TextInputAction.send);
    });
  });
}
