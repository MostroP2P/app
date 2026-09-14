import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/screens/chat_rooms_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/chat_list_fixtures.dart';
import '../../support/provider_harness.dart';
import '../../support/trades_list_fixtures.dart';

/// Goldens of the chat tab redesign (`design_handoff_operaciones_chat`,
/// 11b): two open conversations, one closed. 360 × 760, `es`, dark and light.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (mode, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    testWidgets('11b_chat · $mode', (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await withClock(Clock.fixed(kTradesNow), () async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: createContainer(
              overrides: chatListOverrides(disputes: [kHandoffDispute]),
            ),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme:
                  brightness == Brightness.dark
                      ? buildDarkTheme()
                      : buildLightTheme(),
              locale: const Locale('es'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const ChatRoomsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });

      await expectLater(
        find.byType(ChatRoomsScreen),
        matchesGoldenFile('goldens/chat_11b_$mode.png'),
      );
    });
  }
}
