import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/log_provider.dart';
import 'package:mostro/features/settings/screens/log_report_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/provider_harness.dart';

/// #947: the export on the log report screen is a single "Copy logs" action.
/// The old share sheet did nothing on Linux desktop, so the report must land
/// on the clipboard — the one channel that works on every platform.
void main() {
  LogEntry entry(int id, String message) => LogEntry(
    id: id,
    level: LogLevel.info,
    tag: 'relay',
    message: message,
    timestamp: intToPlatformInt64(0),
  );

  Future<void> pump(WidgetTester tester, List<LogEntry> entries) async {
    final container = createContainer(
      overrides: [
        logEntriesProvider.overrideWith((ref) => Stream.value(entries)),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LogReportScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Copy logs puts the redacted report on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pump(tester, [
      entry(2, 'connected token=s3cr3t'),
      entry(1, 'starting up'),
    ]);

    // One export action, and it is the copy one.
    expect(find.byIcon(Icons.ios_share), findsNothing);
    expect(find.byTooltip('Copy logs'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy logs'));
    await tester.pump();

    expect(copied, isNotNull);
    expect(copied, startsWith('Mostro log report\n'));
    expect(copied, contains('relay: starting up'));
    expect(copied, contains('relay: connected token='));
    // Redacted, exactly as the old share text was.
    expect(copied, isNot(contains('s3cr3t')));
    expect(find.text('Logs copied'), findsOneWidget);
  });

  testWidgets('Copy logs is disabled when there is nothing to copy', (
    tester,
  ) async {
    await pump(tester, const []);

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.copy),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(button.tooltip, 'No logs to share');
  });
}
