import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/disputes/widgets/dispute_message_input.dart';
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
            child: DisputeMessageInput(
              onSendText: (text) async {
                sent.add(text);
                return true;
              },
              onAttachFile: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  group('DisputeMessageInput emojis (#938)', () {
    testWidgets('the emoji button puts the picked emoji at the cursor', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      await tester.tap(find.byTooltip('Insert emoji'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('😀').first);
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'hello😀');
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );

      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(sent, ['hello😀']);
    });

    testWidgets('the field grows to five lines and still sends', (
      tester,
    ) async {
      await pump(tester);

      expect(field(tester).minLines, 1);
      expect(field(tester).maxLines, 5);
      expect(field(tester).textInputAction, TextInputAction.send);
    });

    // The dispute screen drops the composer once the dispute resolves; the
    // emoji sheet, its own route, can still be open then (#940 review).
    testWidgets('an emoji picked after the composer is gone is dropped', (
      tester,
    ) async {
      final canWrite = ValueNotifier(true);
      addTearDown(canWrite.dispose);
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
            body: ValueListenableBuilder<bool>(
              valueListenable: canWrite,
              builder: (context, open, _) => open
                  ? DisputeMessageInput(
                      onSendText: (_) async => true,
                      onAttachFile: () {},
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Insert emoji'));
      await tester.pumpAndSettle();

      canWrite.value = false;
      await tester.pump();
      expect(find.byType(DisputeMessageInput), findsNothing);
      await tester.tap(find.text('😀').first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
