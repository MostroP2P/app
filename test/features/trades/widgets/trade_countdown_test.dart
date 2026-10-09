import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/trades/widgets/trade_countdown.dart';
import 'package:mostro/l10n/app_localizations.dart';

// The clock's format, tone and cadence are tested with the shared countdown
// module (`test/shared/utils/countdown_test.dart`); this file keeps what is
// the trade countdown's own.
void main() {
  // The note under the bar changes while the user watches: at 00:00 it says
  // what mostrod is about to do (#569). That change is announced; the figure
  // that ticks every second is not (DS-A11Y-2).
  group('TradeCountdown announces its note', () {
    Finder inLiveRegion(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      ),
    );

    Widget countdown(Duration remaining, String note) => MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TradeCountdown(
          remaining: remaining,
          total: const Duration(seconds: 60),
          label: 'You have',
          isWaiting: false,
          note: note,
        ),
      ),
    );

    testWidgets('the note that changes at 00:00 is a live region', (
      tester,
    ) async {
      await tester.pumpWidget(
        countdown(
          const Duration(seconds: 1),
          'If it expires, the order is cancelled.',
        ),
      );
      await tester.pumpWidget(countdown(Duration.zero, 'Time is up.'));
      expect(find.text('Time is up.'), findsOneWidget);
      expect(inLiveRegion('Time is up.'), findsWidgets);
    });

    testWidgets('the ticking figure is not', (tester) async {
      await tester.pumpWidget(
        countdown(
          const Duration(seconds: 30),
          'If it expires, the order is cancelled.',
        ),
      );
      expect(find.text('00:30'), findsOneWidget);
      expect(inLiveRegion('00:30'), findsNothing);
    });
  });
}
