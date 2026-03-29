import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app.dart';

void main() {
  testWidgets('Mostro app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MostroApp()));
    await tester.pumpAndSettle();
    // App renders without crashing.
  });
}
