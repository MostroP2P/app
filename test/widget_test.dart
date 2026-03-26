import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/app.dart';

void main() {
  testWidgets('App smoke test — renders without crashing',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MostroApp()),
    );
    // App redirects to /onboarding (no identity) — welcome placeholder renders.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
