import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/invoice_widgets.dart';

/// Whether [text] sits inside a live region, which screen readers announce
/// when it changes (DS-A11Y-2).
Finder _inLiveRegion(String text) => find.ancestor(
  of: find.textContaining(text),
  matching: find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.liveRegion == true,
  ),
);

const _elapsed = 'Time is up.';

Widget _band(Duration remaining) => MaterialApp(
  theme: buildDarkTheme(),
  home: Scaffold(
    body: InvoiceTimeBand(
      remaining: remaining,
      window: const Duration(minutes: 15),
      sentence: (time) => 'You have $time to send it',
      hours: (hours, minutes) => '$hours h $minutes',
      elapsed: _elapsed,
    ),
  ),
);

/// The band's 00:00 notice appears while the user watches the countdown, so
/// it is announced; the ticking figure before it is not, or a screen reader
/// would read it every second.
void main() {
  testWidgets('the ticking countdown is not a live region', (tester) async {
    await tester.pumpWidget(_band(const Duration(seconds: 30)));
    expect(find.textContaining('to send it'), findsOneWidget);
    expect(_inLiveRegion('to send it'), findsNothing);
  });

  testWidgets('the notice that replaces it at 00:00 is announced', (
    tester,
  ) async {
    await tester.pumpWidget(_band(const Duration(seconds: 1)));
    expect(find.text(_elapsed), findsNothing);

    await tester.pumpWidget(_band(Duration.zero));
    expect(find.text(_elapsed), findsOneWidget);
    expect(_inLiveRegion(_elapsed), findsWidgets);
  });
}
