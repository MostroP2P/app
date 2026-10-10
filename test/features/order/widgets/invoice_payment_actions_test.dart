import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/invoice_widgets.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../../support/load_app_fonts.dart';
import '../../../support/text_scale.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Locale locale,
  required double textScale,
  required bool copyLeads,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      builder: textScaleBuilder(textScale),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: kInvoiceGutter),
          child: InvoicePaymentActions(
            copyLeads: copyLeads,
            copied: false,
            onCopy: () {},
            onOpenWallet: () {},
            onShare: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // The labels are measured: the real font, not the test one.
  setUpAll(loadAppFonts);

  // DS-A11Y-4: the action bar of the hold invoice (13b) and the bond (14) fits
  // at 320 dp wide in every language, at 1x and 2x text, whichever action
  // leads: nothing overflows, no label runs past two lines and no word is
  // broken across them. The screens' own overflow at this size is #712.
  for (final locale in AppLocalizations.supportedLocales) {
    for (final textScale in [1.0, 2.0]) {
      for (final copyLeads in [false, true]) {
        testWidgets(
          'fits at 320 dp, ${textScale}x text, ${locale.languageCode}, '
          '${copyLeads ? 'Copy' : 'the wallet'} leads',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(320, 640);
            addTearDown(tester.view.reset);

            await _pump(
              tester,
              locale: locale,
              textScale: textScale,
              copyLeads: copyLeads,
            );

            expect(tester.takeException(), isNull);
            final l10n = lookupAppLocalizations(locale);
            for (final label in [
              l10n.copyButtonLabel,
              l10n.shareButtonLabel,
              l10n.invoiceOpenWallet,
            ]) {
              final paragraph = tester.renderObject<RenderParagraph>(
                find.text(label),
              );
              expect(paragraph.didExceedMaxLines, isFalse, reason: label);
              expect(breaksAWord(paragraph), isFalse, reason: label);
            }
          },
        );
      }
    }
  }

  testWidgets('the secondaries share a row while both labels fit', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);

    await _pump(
      tester,
      locale: const Locale('en'),
      textScale: 1,
      copyLeads: false,
    );

    final copy = tester.getRect(
      find.widgetWithText(InvoiceSecondaryButton, 'Copy'),
    );
    final share = tester.getRect(
      find.widgetWithText(InvoiceSecondaryButton, 'Share'),
    );
    expect(copy.top, share.top);
    expect(copy.height, share.height);
  });

  testWidgets('the secondaries stack once a word has no room beside', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    // "Compartir" at 2x does not fit half of 320 dp.
    await _pump(
      tester,
      locale: const Locale('es'),
      textScale: 2,
      copyLeads: false,
    );

    final copy = tester.getRect(
      find.widgetWithText(InvoiceSecondaryButton, 'Copiar'),
    );
    final share = tester.getRect(
      find.widgetWithText(InvoiceSecondaryButton, 'Compartir'),
    );
    expect(share.top, greaterThan(copy.bottom));
    expect(copy.width, share.width);
  });
}
