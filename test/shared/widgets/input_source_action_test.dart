import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/shared/widgets/input_source_action.dart';

Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback? onTap,
  String? tooltip,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 160,
            child: InputSourceAction(
              icon: Icons.content_paste_outlined,
              label: 'Paste',
              onTap: onTap,
              tooltip: tooltip,
              accent: true,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('InputSourceAction', () {
    // DS-CMP-6: a 13 sp label and its padding came to 46 dp on their own.
    testWidgets('an enabled action is a 48 dp tap target', (tester) async {
      await _pump(tester, onTap: () {});

      expect(
        tester.getSize(find.byType(InkWell)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('a disabled action keeps the same height', (tester) async {
      await _pump(tester, onTap: null);

      expect(
        tester.getSize(find.byType(InkWell)).height,
        greaterThanOrEqualTo(48),
      );
    });

    // DS-A11Y-1: a screen reader hears one button named by its label, not
    // a node whose name is whatever text happens to sit inside it.
    testWidgets('is announced as a button named by its label', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, onTap: () {});

      // One node carries the label: it is not read twice.
      final node = find.semantics.byLabel('Paste').evaluate().single;
      expect(
        node,
        isSemantics(
          label: 'Paste',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('a disabled one is announced as such', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, onTap: null);

      // One node carries the label: it is not read twice.
      final node = find.semantics.byLabel('Paste').evaluate().single;
      expect(
        node,
        isSemantics(
          label: 'Paste',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      semantics.dispose();
    });

    // The reason a disabled action gives on hover joins the same node: one
    // announcement, the label and then why it cannot be used.
    testWidgets('a disabled one with a reason is still one node', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, onTap: null, tooltip: 'Not available on this device');

      // One node carries the label: it is not read twice.
      final node = find.semantics.byLabel('Paste').evaluate().single;
      expect(
        node,
        isSemantics(
          label: 'Paste',
          tooltip: 'Not available on this device',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      semantics.dispose();
    });
  });
}
