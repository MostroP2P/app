import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

import '../../support/load_app_fonts.dart';

/// One image of the standard modals, the way `chip_gallery` shows the chips.
///
/// The per-variant goldens next door are the regression contract; this one is
/// for people — it is what a UI pull request shows a reviewer, so the shape of
/// the change can be seen without checking the branch out (#534).
Widget _gallery(Brightness brightness) {
  final book =
      brightness == Brightness.dark
          ? OrderBookPalette.dark
          : OrderBookPalette.light;

  Widget caption(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 4),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: book.textMuted,
      ),
    ),
  );

  return Container(
    key: const ValueKey('modal-gallery'),
    // 360 for the phone, plus this container's own padding.
    width: 392,
    color: book.bg,
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        caption('CONFIRM — accent answer on the right'),
        const _Framed(
          MostroDialog(
            title: 'Refresh your data?',
            body: 'The app reloads the order book from the relays.',
            primary: ModalAction(label: 'Refresh', onPressed: _noop),
            secondary: ModalAction(label: 'Cancel', onPressed: _noop),
          ),
        ),
        const SizedBox(height: 18),
        caption('DESTRUCTIVE — cancel, dispute, delete'),
        const _Framed(
          MostroDialog(
            title: 'Cancel this trade?',
            body: 'The order goes back to the book and no sats change hands.',
            icon: Icons.gavel,
            iconTone: ModalTone.destructive,
            primary: ModalAction(
              label: 'Yes, cancel',
              onPressed: _noop,
              tone: ModalTone.destructive,
            ),
            secondary: ModalAction(label: 'No', onPressed: _noop),
          ),
        ),
        const SizedBox(height: 18),
        caption('LINKS — somewhere to read, not an answer'),
        const _Framed(
          MostroDialog(
            title: 'Bond slashed',
            body: 'Your bond was forfeited when the trade was abandoned.',
            primary: ModalAction(label: 'Close', onPressed: _noop),
            links: [
              ModalLink(label: 'View policy', onPressed: _noop),
              ModalLink(label: 'View trade', onPressed: _noop),
            ],
          ),
        ),
        const SizedBox(height: 18),
        caption('PICKER — the answer is the row, so there is no footer'),
        _Framed(
          MostroDialog(
            title: 'Sort orders by',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PickerRow('Newest first', book, selected: true),
                _PickerRow('Best premium', book),
                _PickerRow('Best reputation', book),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        caption('SHEET — the same footer, from the bottom edge'),
        _Framed(
          Container(
            decoration: BoxDecoration(
              color: book.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.modal),
              ),
            ),
            child: const MostroSheet(
              title: 'Release the sats?',
              body: 'The buyer receives the payment. This cannot be undone.',
              primary: ModalAction(label: 'Release', onPressed: _noop),
              secondary: ModalAction(label: 'Cancel', onPressed: _noop),
            ),
          ),
        ),
      ],
    ),
  );
}

/// One row of the picker above: the shape the sort, language, theme and
/// currency pickers take inside a standard modal.
class _PickerRow extends StatelessWidget {
  const _PickerRow(this.label, this.book, {this.selected = false});

  final String label;
  final OrderBookPalette book;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? book.limeInk : book.textBody,
            ),
          ),
        ),
        if (selected)
          Icon(Icons.check_rounded, size: 20, color: book.limeText),
      ],
    ),
  );
}

/// Gives a modal the width it has on a 360 px phone, so the gallery shows the
/// real line breaks and the real footer layout.
///
/// That is the width of the *phone*, not of the card: `Dialog` takes its own
/// 24 px inset off each side, so framing it at the card's 312 would render a
/// 264 px card and break its lines earlier than the app does.
class _Framed extends StatelessWidget {
  const _Framed(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Center(child: SizedBox(width: 360, child: child));
}

void main() {
  setUpAll(loadAppFonts);

  for (final (mode, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    testWidgets('modal gallery · $mode', (tester) async {
      tester.view.physicalSize = const Size(420, 1760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme:
              brightness == Brightness.dark
                  ? buildDarkTheme()
                  : buildLightTheme(),
          home: Scaffold(body: Center(child: _gallery(brightness))),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const ValueKey('modal-gallery')),
        matchesGoldenFile('goldens/modal_gallery_$mode.png'),
      );
    });
  }
}

void _noop() {}
