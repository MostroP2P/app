import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';

/// DS-CMP-24: a data row's icon and padding are on their scales — a 16-dp
/// icon (DS-ICO-3) and 14 above and below (DS-SPC-2).
void main() {
  testWidgets('a data row sits on the icon and spacing scales', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const Scaffold(
          body: OrderDataRow(
            icon: Icons.payments_outlined,
            label: 'Recibes',
            value: OrderDataValue('312 ARS', figures: true),
          ),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.payments_outlined));
    expect(icon.size, 16);

    final padding = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(OrderDataRow),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(padding.padding, const EdgeInsets.symmetric(vertical: 14));
  });

  testWidgets('a tappable data row is announced as a button (DS-A11Y-1)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Column(
            children: [
              OrderDataRow(
                icon: Icons.credit_card_outlined,
                label: 'Pagas con',
                value: const OrderDataValue('Mercado Pago +2'),
                onTap: () => taps++,
              ),
              const OrderDataRow(
                icon: Icons.calendar_today_outlined,
                label: 'Publicada',
                value: OrderDataValue('hace 2 h'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.text('Pagas con')),
      matchesSemantics(
        label: 'Pagas con\nMercado Pago +2',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Publicada')),
      isNot(matchesSemantics(isButton: true)),
    );

    await tester.tap(find.text('Pagas con'));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a long trailing note stays inside a narrow row', (tester) async {
    tester.view.physicalSize = const Size(320, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 200),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: OrderDataRow(
              icon: Icons.person_outline_rounded,
              label: 'Venditore',
              value: OrderDataValue(
                'bright-fox-41',
                trailing: 'nessuna operazione',
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('nessuna operazione'), findsOneWidget);
  });
}
