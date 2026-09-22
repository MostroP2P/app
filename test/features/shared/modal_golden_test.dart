import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

import '../../support/load_app_fonts.dart';

/// The standard modals, one screenshot per variant and theme.
///
/// This is the contract the 29 migrated modals render against (#534): change
/// a radius, a button height or the accent and these move, in review, before
/// the app does.
Widget _app(Brightness brightness, Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: brightness == Brightness.dark ? buildDarkTheme() : buildLightTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  // These goldens carry real text, and the footer measures its labels to
  // decide whether the pair fits one row — both need the real fonts.
  setUpAll(loadAppFonts);

  const confirm = ModalAction(label: 'Confirm', onPressed: _noop);
  const cancel = ModalAction(label: 'Cancel', onPressed: _noop);

  for (final (mode, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    for (final (name, widget) in <(String, Widget)>[
      (
        'dialog_pair',
        const MostroDialog(
          title: 'Cancel this trade?',
          body: 'The order goes back to the book and no sats change hands.',
          primary: confirm,
          secondary: cancel,
        ),
      ),
      (
        'dialog_destructive',
        const MostroDialog(
          title: 'Open a dispute?',
          body: 'An admin takes over the trade. This cannot be undone.',
          icon: Icons.gavel,
          iconTone: ModalTone.destructive,
          primary: ModalAction(
            label: 'Yes, open it',
            onPressed: _noop,
            tone: ModalTone.destructive,
          ),
          secondary: cancel,
        ),
      ),
      (
        'dialog_single',
        const MostroDialog(
          title: 'Price types',
          body: 'A fixed price is set once; a market price follows the rate.',
          primary: ModalAction(label: 'OK', onPressed: _noop),
        ),
      ),
      (
        'dialog_links',
        const MostroDialog(
          title: 'Bond slashed',
          body: 'Your bond was forfeited when the trade was abandoned.',
          primary: ModalAction(label: 'Close', onPressed: _noop),
          links: [
            ModalLink(label: 'View policy', onPressed: _noop),
            ModalLink(label: 'View trade', onPressed: _noop),
          ],
        ),
      ),
      (
        'dialog_busy',
        const MostroDialog(
          title: 'Add your node',
          body: 'Contacting the node…',
          primary: ModalAction(label: 'Add', onPressed: _noop, busy: true),
          secondary: cancel,
        ),
      ),
      (
        'dialog_disabled',
        const MostroDialog(
          title: 'Add your node',
          body: 'Enter a pubkey to continue.',
          primary: ModalAction(label: 'Add', onPressed: null),
          secondary: cancel,
        ),
      ),
    ]) {
      testWidgets('$name · $mode', (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app(brightness, widget));
        // A busy action paints a CircularProgressIndicator, which never
        // settles — one frame is what these variants need anyway.
        await tester.pump(const Duration(milliseconds: 16));

        await expectLater(
          find.byType(MostroDialog),
          matchesGoldenFile('goldens/modal_${name}_$mode.png'),
        );
      });
    }

    testWidgets('sheet_pair · $mode', (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Opened through the route, not dropped on a Scaffold: the sheet's
      // surface and its rounded top come from `bottomSheetTheme`, which only
      // `showModalBottomSheet` applies.
      await tester.pumpWidget(_app(brightness, const _OpenSheetButton()));
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(BottomSheet),
        matchesGoldenFile('goldens/modal_sheet_pair_$mode.png'),
      );
    });
  }

  testWidgets('a label too long for half a row stacks the pair', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        Brightness.dark,
        const SizedBox(
          width: 300,
          child: ModalFooter(
            primary: ModalAction(
              label: 'Ja, diesen Handel abbrechen',
              onPressed: _noop,
            ),
            secondary: cancel,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Stacked: the answer sits above the way out, both full width.
    final primary = tester.getRect(find.byType(FilledButton));
    final secondary = tester.getRect(find.byType(OutlinedButton));
    expect(primary.top, lessThan(secondary.top));
    expect(primary.left, closeTo(secondary.left, 0.5));
    expect(primary.width, closeTo(secondary.width, 0.5));
  });

  testWidgets('a short pair on a 360 px phone stays on one row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        Brightness.dark,
        const MostroDialog(
          title: 'Cancel this trade?',
          body: 'The order goes back to the book.',
          primary: confirm,
          secondary: cancel,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(FilledButton)).top,
      closeTo(tester.getRect(find.byType(OutlinedButton)).top, 0.5),
    );
  });

  testWidgets('a wide footer puts the answer on the right', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        Brightness.dark,
        const SizedBox(
          width: 340,
          child: ModalFooter(primary: confirm, secondary: cancel),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final primary = tester.getRect(find.byType(FilledButton));
    final secondary = tester.getRect(find.byType(OutlinedButton));
    expect(primary.center.dx, greaterThan(secondary.center.dx));
    expect(primary.top, closeTo(secondary.top, 0.5));
  });

  testWidgets('a long body at a large text scale keeps the answer on screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: MostroDialog(
                title: 'Cancel this trade?',
                body:
                    'The order goes back to the book and no sats change '
                    'hands. If the counterparty already sent the fiat you '
                    'must not cancel: open a dispute instead, so an admin '
                    'can take the trade over. This cannot be undone once '
                    'the daemon applies it.',
                primary: confirm,
                secondary: cancel,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Both buttons are inside the viewport, so the dialog can be answered.
    final viewport = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    for (final finder in [
      find.byType(FilledButton),
      find.byType(OutlinedButton),
    ]) {
      expect(tester.getRect(finder).bottom, lessThanOrEqualTo(viewport));
    }
  });

  testWidgets('an open keyboard does not cover the sheet actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The sheet route sits above any MediaQuery this test could wrap the app
    // in, so the keyboard has to come from the view itself.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);

    await tester.pumpWidget(_app(Brightness.dark, const _OpenSheetButton()));
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(FilledButton)).bottom,
      lessThanOrEqualTo(640 - 300),
    );
  });

  testWidgets('a picker spends no room on a footer it has no actions for', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A picker answers by tapping one of its rows (sort, language, theme),
    // so it passes no action at all.
    await tester.pumpWidget(
      _app(
        Brightness.dark,
        const MostroDialog(
          title: 'Sort orders by',
          content: SizedBox(key: ValueKey('rows'), height: 120),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    // Only the card's own 16 px bottom padding is left under the rows: an
    // empty footer must not leave a 20 px hole where the buttons would be.
    final rows = tester.getRect(find.byKey(const ValueKey('rows')));
    final card = tester.getRect(
      find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first,
    );
    expect(card.bottom - rows.bottom, closeTo(16, 0.5));
  });

  testWidgets('a busy action cannot be pressed', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _app(
        Brightness.dark,
        MostroDialog(
          title: 'Add your node',
          primary: ModalAction(
            label: 'Add',
            onPressed: () => pressed++,
            busy: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(pressed, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

void _noop() {}

/// Opens the release sheet the way the app does.
class _OpenSheetButton extends StatelessWidget {
  const _OpenSheetButton();

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed:
          () => showMostroSheet<bool>(
            context: context,
            builder:
                (_) => const MostroSheet(
                  title: 'Release the sats?',
                  body:
                      'The buyer receives the payment. This cannot be undone.',
                  primary: ModalAction(label: 'Release', onPressed: _noop),
                  secondary: ModalAction(label: 'Cancel', onPressed: _noop),
                ),
          ),
      child: const Text('open'),
    ),
  );
}
