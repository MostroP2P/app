import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

Widget _footer(List<ModalLink> links) => MaterialApp(
  theme: buildDarkTheme(),
  home: Scaffold(body: ModalFooter(links: links)),
);

TextButton _button(WidgetTester tester, String label) => tester.widget(
  find.ancestor(of: find.text(label), matching: find.byType(TextButton)),
);

void main() {
  testWidgets('a disabled link takes the palette\'s faint ink', (tester) async {
    // Arrange
    await tester.pumpWidget(
      _footer(const [ModalLink(label: 'Scan QR', onPressed: null)]),
    );

    // Act
    final color = _button(
      tester,
      'Scan QR',
    ).style!.foregroundColor!.resolve({WidgetState.disabled});

    // Assert — left unset it is Material's default, the v1 theme's onSurface
    // at 38%: a link colors its label from the palette (DS-CMP-17).
    expect(color, OrderBookPalette.dark.textFaint);
  });

  testWidgets('a disabled link says why in its tooltip', (tester) async {
    // Arrange
    await tester.pumpWidget(
      _footer(const [
        ModalLink(
          label: 'Scan QR',
          onPressed: null,
          tooltip: 'Not available on this device',
        ),
      ]),
    );

    // Act
    await tester.longPress(find.text('Scan QR'));
    await tester.pumpAndSettle();

    // Assert
    expect(find.text('Not available on this device'), findsOneWidget);
  });

  testWidgets('a link without a tooltip gets none', (tester) async {
    // Arrange / Act
    await tester.pumpWidget(
      _footer([ModalLink(label: 'Paste', onPressed: () {})]),
    );

    // Assert
    expect(find.byType(Tooltip), findsNothing);
  });
}
