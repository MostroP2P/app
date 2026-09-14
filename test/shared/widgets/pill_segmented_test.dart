import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/shared/widgets/pill_segmented.dart';

Future<void> _pump(
  WidgetTester tester, {
  required String selected,
  required ValueChanged<String> onSelected,
  bool secondEnabled = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Center(
          child: PillSegmented<String>(
            size: PillSegmentedSize.small,
            selected: selected,
            segments: [
              const PillSegment(value: 'a', label: 'Market'),
              PillSegment(value: 'b', label: 'Fixed', enabled: secondEnabled),
            ],
            onSelected: onSelected,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows every option and reports the tapped one', (tester) async {
    // Arrange
    final taps = <String>[];
    await _pump(tester, selected: 'a', onSelected: taps.add);
    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Fixed'), findsOneWidget);

    // Act
    await tester.tap(find.text('Fixed'));
    await tester.pumpAndSettle();

    // Assert
    expect(taps, ['b']);
  });

  testWidgets('a disabled segment ignores taps', (tester) async {
    final taps = <String>[];
    await _pump(
      tester,
      selected: 'a',
      onSelected: taps.add,
      secondEnabled: false,
    );

    await tester.tap(find.text('Fixed'));
    await tester.pumpAndSettle();

    expect(taps, isEmpty);
  });

  testWidgets('marks the selected segment for assistive tech', (tester) async {
    await _pump(tester, selected: 'b', onSelected: (_) {});

    // Read the Semantics widget itself rather than the flags API, which
    // changed shape between the CI and local Flutter versions.
    bool selectedOf(String label) => tester
        .widgetList<Semantics>(
          find.ancestor(of: find.text(label), matching: find.byType(Semantics)),
        )
        .firstWhere((s) => s.properties.selected != null)
        .properties
        .selected!;
    expect(selectedOf('Fixed'), isTrue);
    expect(selectedOf('Market'), isFalse);
  });
}
