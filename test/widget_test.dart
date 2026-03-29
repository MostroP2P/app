import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/main.dart';

void main() {
  testWidgets('Mostro app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MostroApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
