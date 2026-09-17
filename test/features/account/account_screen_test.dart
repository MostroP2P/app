import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/account/models/backup_rules.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/account/screens/account_screen.dart';
import 'package:mostro/features/account/widgets/backup_widgets.dart';
import 'package:mostro/l10n/app_localizations.dart';

const _words = <String>[
  'prefer',
  'olympic',
  'float',
  'negative',
  'alarm',
  'mechanic',
  'capital',
  'because',
  'sausage',
  'struggle',
  'travel',
  'trade',
];

/// The label of the semantics node carrying [identifier]. `getSemantics`
/// on the finder answers with the merged parent, whose label is empty; the
/// readout's own node, a child of it, is the one a driver reads.
String? _labelOf(WidgetTester tester, String identifier) {
  String? found;
  void walk(SemanticsNode node) {
    if (node.identifier == identifier) found = node.label;
    node.visitChildren((child) {
      walk(child);
      return found == null;
    });
  }

  walk(tester.getSemantics(find.bySemanticsIdentifier(identifier)));
  return found;
}

Future<void> _pumpAccount(
  WidgetTester tester, {
  required bool backedUp,
  Future<String?> Function()? publicKey,
}) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backupCompletedProvider.overrideWith(
          (ref) => BackupCompletedNotifier(initialValue: backedUp),
        ),
        backupReminderProvider.overrideWith(
          (ref) => BackupReminderNotifier(initialValue: !backedUp),
        ),
        privacyModeProvider.overrideWith(
          (ref) => PrivacyModeNotifier(initialValue: false),
        ),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AccountScreen(debugWords: _words, debugPublicKey: publicKey),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppLocalizations l10n;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('not backed up (15a)', () {
    testWidgets('shows only the banner, never the words card', (tester) async {
      await _pumpAccount(tester, backedUp: false);

      expect(find.text(l10n.backupBannerTitle), findsOneWidget);
      expect(find.text(l10n.secretWordsTitle), findsNothing);
      expect(find.text(l10n.showWordsButton), findsNothing);
    });

    testWidgets('the banner opens the sheet, and "later" keeps the banner', (
      tester,
    ) async {
      await _pumpAccount(tester, backedUp: false);

      await tester.tap(find.text(l10n.backupBannerTitle));
      await tester.pumpAndSettle();
      expect(find.text(l10n.backupNowButton), findsOneWidget);

      await tester.tap(find.text(l10n.backupLaterButton));
      await tester.pumpAndSettle();

      expect(find.text(l10n.backupNowButton), findsNothing);
      expect(find.text(l10n.backupBannerTitle), findsOneWidget);
    });
  });

  group('backed up (15b)', () {
    testWidgets('shows only the words card, masked, with the chip', (
      tester,
    ) async {
      await _pumpAccount(tester, backedUp: true);

      expect(find.text(l10n.backupBannerTitle), findsNothing);
      expect(find.text(l10n.secretWordsTitle), findsOneWidget);
      expect(find.text(l10n.backedUpBadgeLabel), findsOneWidget);
      expect(find.text(backupWordMask), findsNWidgets(12));
      expect(find.text('prefer'), findsNothing);
    });

    testWidgets('Show words reveals the 12 words with Hide and Copy only', (
      tester,
    ) async {
      await _pumpAccount(tester, backedUp: true);

      await tester.tap(find.text(l10n.showWordsButton));
      await tester.pumpAndSettle();

      for (final word in _words) {
        expect(find.text(word), findsOneWidget);
      }
      expect(find.text(backupWordMask), findsNothing);
      expect(find.text(l10n.hideButtonLabel), findsOneWidget);
      expect(find.text(l10n.copyButtonLabel), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('Hide masks the words again', (tester) async {
      await _pumpAccount(tester, backedUp: true);
      await tester.tap(find.text(l10n.showWordsButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.hideButtonLabel));
      await tester.pumpAndSettle();

      expect(find.text(backupWordMask), findsNWidgets(12));
      expect(find.text('prefer'), findsNothing);
    });

    testWidgets('Copy puts the space-separated phrase on the clipboard', (
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
      await _pumpAccount(tester, backedUp: true);
      await tester.tap(find.text(l10n.showWordsButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.copyButtonLabel));
      await tester.pump();

      expect(copied, _words.join(' '));
      // Let the check turn back into the copy icon so no timer is left.
      await tester.pump(backupCopyFeedback);
    });
  });

  group('keys.public_key readout (automation contract)', () {
    const key =
        'f00d000000000000000000000000000000000000000000000000000000000001';

    testWidgets('carries the full key once it is loaded', (tester) async {
      await _pumpAccount(tester, backedUp: true, publicKey: () async => key);

      expect(_labelOf(tester, AutomationIds.keysPublicKey), key);
    });

    testWidgets('is absent until the key is loaded — never an empty label', (
      tester,
    ) async {
      // A black-box driver that finds the identifier must read the key; one
      // that could find it first with '' would make identity checks
      // timing-dependent.
      final loading = Completer<String?>();
      await _pumpAccount(
        tester,
        backedUp: false,
        publicKey: () => loading.future,
      );

      expect(
        find.bySemanticsIdentifier(AutomationIds.keysPublicKey),
        findsNothing,
      );

      loading.complete(key);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsIdentifier(AutomationIds.keysPublicKey),
        findsOneWidget,
      );
    });

    testWidgets('does not move the visible cards', (tester) async {
      // The readout sits over the viewport, outside its spaced block list.
      await _pumpAccount(tester, backedUp: false, publicKey: () async => null);
      final without = tester.getTopLeft(find.text(l10n.backupBannerTitle));

      await _pumpAccount(tester, backedUp: false, publicKey: () async => key);
      final with_ = tester.getTopLeft(find.text(l10n.backupBannerTitle));

      expect(with_, without);
    });
  });
}
