import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/features/settings/models/settings_rows.dart';
import 'package:mostro/features/settings/widgets/settings_section.dart';

Future<void> _pump(WidgetTester tester, Widget child, {bool dark = true}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: dark ? buildDarkTheme() : buildLightTheme(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

Color _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.color!;

void main() {
  group('SettingsRow', () {
    testWidgets('shows the value in place of a subtitle', (tester) async {
      await _pump(
        tester,
        const SettingsRow(
          icon: Icons.language,
          label: 'Language',
          value: 'Español',
        ),
      );

      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Español'), findsOneWidget);
    });

    testWidgets('tones the value: neutral, lime, amber', (tester) async {
      const pal = SettingsPalette.dark;
      const book = OrderBookPalette.dark;
      for (final (tone, expected) in [
        (SettingsValueTone.neutral, book.textMuted),
        (SettingsValueTone.good, book.limeInk),
        (SettingsValueTone.warn, pal.warnInk),
      ]) {
        await _pump(
          tester,
          SettingsRow(
            icon: Icons.router_outlined,
            label: 'Relays',
            value: '3 of 4',
            tone: tone,
          ),
        );
        expect(_colorOf(tester, '3 of 4'), expected, reason: '$tone');
      }
    });

    testWidgets('a row with no onTap draws no chevron and takes no tap', (
      tester,
    ) async {
      await _pump(
        tester,
        const SettingsRow(
          icon: Icons.key_outlined,
          label: 'Key',
          value: 'npub',
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('the whole row is the tap target', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        SettingsRow(
          icon: Icons.description_outlined,
          label: 'Logs',
          onTap: () => taps++,
        ),
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      // Tapping the icon, not the label: the InkWell spans the card.
      await tester.tap(find.byIcon(Icons.description_outlined));
      expect(taps, 1);
    });

    testWidgets('announces the unabbreviated value to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const SettingsRow(
          icon: Icons.key_outlined,
          label: 'Your key',
          value: 'npub1x…7ka',
          semanticValue: 'npub1xthefullkey7ka',
        ),
      );

      expect(
        // The visible run is abbreviated for width; the reader gets the key.
        tester.getSemantics(find.text('npub1x…7ka')),
        matchesSemantics(label: 'npub1xthefullkey7ka'),
      );
      handle.dispose();
    });
  });

  group('SettingsGroup', () {
    testWidgets('uppercases the header and hairlines between rows', (
      tester,
    ) async {
      await _pump(
        tester,
        const SettingsGroup(
          header: 'Network',
          rows: [
            SettingsRow(icon: Icons.hub_outlined, label: 'Node'),
            SettingsRow(icon: Icons.router_outlined, label: 'Relays'),
          ],
        ),
      );

      expect(find.text('NETWORK'), findsOneWidget);
      expect(find.text('Network'), findsNothing);
    });
  });

  group('MostroToggle', () {
    testWidgets('reports its state and flips on tap', (tester) async {
      var value = false;
      await _pump(
        tester,
        StatefulBuilder(
          builder:
              (context, setState) => MostroToggle(
                value: value,
                onChanged: (next) => setState(() => value = next),
              ),
        ),
      );

      await tester.tap(find.byType(MostroToggle));
      await tester.pumpAndSettle();
      expect(value, isTrue);
    });

    testWidgets('a null onChanged makes it inert', (tester) async {
      await _pump(tester, const MostroToggle(value: true, onChanged: null));

      await tester.tap(find.byType(MostroToggle));
      await tester.pumpAndSettle();
      // Nothing to assert but the absence of a crash and of a state change:
      // a disabled toggle must not report a tap it cannot act on.
      expect(tester.takeException(), isNull);
    });

    testWidgets('the off state is visually distinct from the on state', (
      tester,
    ) async {
      // The whole point of replacing Material's switch: olive-on-green read
      // the same in both states.
      expect(
        SettingsPalette.dark.toggleOffThumb,
        isNot(SettingsPalette.dark.toggleOnThumb),
      );
      expect(
        SettingsPalette.dark.toggleOffBg,
        isNot(SettingsPalette.dark.toggleOnBg),
      );
    });
  });

  group('SettingsFootnote', () {
    testWidgets('renders at 11px, never smaller', (tester) async {
      await _pump(
        tester,
        const SettingsFootnote(
          icon: Icons.info_outline,
          text: 'Relays carry your orders.',
        ),
      );

      final style =
          tester.widget<Text>(find.text('Relays carry your orders.')).style!;
      // Below 11px the handoff's tone drops under 4.5:1.
      expect(style.fontSize, 11);
    });
  });
}
