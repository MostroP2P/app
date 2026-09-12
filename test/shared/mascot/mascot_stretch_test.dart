import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/mascot/mascot_stretch.dart';

/// The vertical scale the wrapper is applying right now.
double _scaleY(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(MascotStretch),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.getColumn(1)[1];
}

double _scaleX(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(MascotStretch),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.getColumn(0)[0];
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: Center(
          child: MascotStretch(
            height: 50,
            child: SizedBox(width: 35, height: 50),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('MascotStretch', () {
    testWidgets('sits at its natural size until it is pulled', (tester) async {
      await _pump(tester);

      expect(_scaleY(tester), 1);
      expect(_scaleX(tester), 1);
    });

    testWidgets('stretches while it is dragged down, and narrows with it',
        (tester) async {
      await _pump(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MascotStretch)),
      );
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();

      expect(_scaleY(tester), greaterThan(1));
      // Taffy keeps its volume.
      expect(_scaleX(tester), lessThan(1));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('ignores an upward drag', (tester) async {
      await _pump(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MascotStretch)),
      );
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();

      expect(_scaleY(tester), 1);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('springs back to its natural size when let go',
        (tester) async {
      await _pump(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MascotStretch)),
      );
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();
      expect(_scaleY(tester), greaterThan(1));

      await gesture.up();
      await tester.pumpAndSettle();

      expect(_scaleY(tester), closeTo(1, 0.001));
    });

    testWidgets('cannot be pulled past its limit', (tester) async {
      await _pump(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MascotStretch)),
      );
      await gesture.moveBy(const Offset(0, 5000));
      await tester.pump();

      expect(_scaleY(tester), closeTo(1 + MascotStretch.maxStretch, 0.001));

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
