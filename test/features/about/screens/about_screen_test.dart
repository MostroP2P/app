import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/about/screens/about_screen.dart';
import 'package:mostro/features/settings/widgets/mostro_node_selector.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../../support/provider_harness.dart';

List<List<String>> _tags(Map<String, String> extra) => [
      ['d', 'npub_test'],
      for (final entry in extra.entries) [entry.key, entry.value],
    ];

const _enabledBondTags = {
  'bond_enabled': 'true',
  'bond_apply_to': 'both',
  'bond_slash_on_waiting_timeout': 'true',
  'bond_amount_pct': '0.05',
  'bond_base_amount_sats': '1000',
  'bond_slash_node_share_pct': '0.5',
  'bond_payout_claim_window_days': '15',
};

/// Every bond parameter label, used to assert they stay hidden unless the
/// policy is enabled.
const _parameterLabels = [
  'Applies to',
  'Bond amount',
  'Minimum bond',
  'Node share on slash',
  'Slash on waiting timeout',
  'Payout claim window',
];

/// Pumps [AboutScreen] with the node fetch and app version overridden, so no
/// Rust bridge call is made.
///
/// The bond section sits in the third card of a lazily-built `ListView`, so the
/// surface is made tall enough to keep it built and findable without scrolling.
Future<void> _pumpAbout(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = createContainer(overrides: [
    appVersionProvider.overrideWith((ref) async => '2.0.0'),
    ...overrides,
  ]);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
    ),
  );

  // One frame to build, one to resolve the overridden futures.
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpWithNode(WidgetTester tester, MostroInstance node) {
  return _pumpAbout(
    tester,
    overrides: [mostroNodeProvider.overrideWith((ref) async => node)],
  );
}

void main() {
  group('AboutScreen — anti-abuse bond section', () {
    testWidgets('an enabled policy renders every parameter', (tester) async {
      await _pumpWithNode(
        tester,
        MostroInstance.fromTags(_tags(_enabledBondTags)),
      );

      expect(find.text('Anti-abuse Bond'), findsOneWidget);
      expect(find.text('Bond status'), findsOneWidget);
      // Status row plus the slash-on-timeout row.
      expect(find.text('Enabled'), findsNWidgets(2));
      expect(find.text('Makers and takers'), findsOneWidget);
      expect(find.text('5%'), findsOneWidget);
      expect(find.text('1,000 Satoshis'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('15 days'), findsOneWidget);
    });

    testWidgets('a one-day claim window renders the singular form',
        (tester) async {
      await _pumpWithNode(
        tester,
        MostroInstance.fromTags(
          _tags({..._enabledBondTags, 'bond_payout_claim_window_days': '1'}),
        ),
      );

      expect(find.text('1 day'), findsOneWidget);
      expect(find.text('1 days'), findsNothing);
    });

    testWidgets('a disabled policy shows the status row alone', (tester) async {
      await _pumpWithNode(
        tester,
        // The tags are present but the policy is off: the parser must gate them
        // and the screen must render none of them.
        MostroInstance.fromTags(
          _tags({..._enabledBondTags, 'bond_enabled': 'false'}),
        ),
      );

      expect(find.text('Anti-abuse Bond'), findsOneWidget);
      expect(find.text('Disabled'), findsOneWidget);
      for (final label in _parameterLabels) {
        expect(find.text(label), findsNothing, reason: '$label must be hidden');
      }
    });

    testWidgets('a legacy node reports the policy as unsupported',
        (tester) async {
      await _pumpWithNode(
        tester,
        MostroInstance.fromTags(_tags({'mostro_version': '0.12.0'})),
      );

      expect(find.text('Anti-abuse Bond'), findsOneWidget);
      expect(find.text('Not supported'), findsOneWidget);
      for (final label in _parameterLabels) {
        expect(find.text(label), findsNothing, reason: '$label must be hidden');
      }
    });

    testWidgets('the policy follows an instance switch', (tester) async {
      const enabledPubkey = 'node-with-bond';
      final container = createContainer(overrides: [
        appVersionProvider.overrideWith((ref) async => '2.0.0'),
        mostroPubkeyProvider.overrideWith((ref) => enabledPubkey),
        mostroNodeProvider.overrideWith((ref) async {
          final pubkey = ref.watch(mostroPubkeyProvider);
          return MostroInstance.fromTags(
            _tags(pubkey == enabledPubkey
                ? _enabledBondTags
                : {'bond_enabled': 'false'}),
          );
        }),
      ]);

      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildDarkTheme(),
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AboutScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Bond amount'), findsOneWidget);

      // Switching the active node re-resolves the policy.
      container.read(mostroPubkeyProvider.notifier).state = 'node-without-bond';
      await tester.pump();
      await tester.pump();

      expect(find.text('Disabled'), findsOneWidget);
      expect(find.text('Bond amount'), findsNothing);
    });
  });

  group('AboutScreen — settlement backend section', () {
    /// Every string that would betray Cashu to a user whose node does not run
    /// it. None may appear unless the node itself advertised Cashu.
    const cashuStrings = [
      'Cashu escrow',
      'Mint',
      'Escrow locktime',
      'Settlement margin',
      'https://mint.example.com',
    ];

    const lndTags = {
      'lnd_version': '0.18.0',
      'lnd_node_alias': 'test-node',
    };

    const cashuTags = {
      'escrow_mode': 'cashu',
      'cashu_mint_url': 'https://mint.example.com',
      'cashu_escrow_locktime_days': '15',
      'cashu_settlement_margin_days': '3',
    };

    testWidgets('a legacy node shows Lightning and no trace of Cashu',
        (tester) async {
      // Arrange — no escrow tags at all: every daemon in the wild today.
      await _pumpWithNode(tester, MostroInstance.fromTags(_tags(lndTags)));

      // Assert — unchanged from before this feature existed.
      expect(find.text('Lightning Network'), findsOneWidget);
      expect(find.text('0.18.0'), findsOneWidget);
      for (final s in cashuStrings) {
        expect(find.text(s), findsNothing, reason: '$s must not be shown');
      }
    });

    testWidgets('a Lightning node shows no trace of Cashu either',
        (tester) async {
      // Arrange — explicitly Lightning, and carrying stale cashu tags the
      // parser must gate away.
      await _pumpWithNode(
        tester,
        MostroInstance.fromTags(
          _tags({...lndTags, ...cashuTags, 'escrow_mode': 'lightning'}),
        ),
      );

      // Assert
      expect(find.text('Lightning Network'), findsOneWidget);
      for (final s in cashuStrings) {
        expect(find.text(s), findsNothing, reason: '$s must not be shown');
      }
    });

    testWidgets('a Cashu node shows its parameters and no Lightning section',
        (tester) async {
      // Arrange — About reports what this node runs, so the two backends are
      // mutually exclusive on screen.
      await _pumpWithNode(
        tester,
        MostroInstance.fromTags(_tags({...lndTags, ...cashuTags})),
      );

      // Assert
      expect(find.text('Cashu escrow'), findsOneWidget);
      expect(find.text('https://mint.example.com'), findsOneWidget);
      expect(find.text('15 days'), findsOneWidget);
      expect(find.text('3 days'), findsOneWidget);
      expect(find.text('Lightning Network'), findsNothing);
      expect(find.text('0.18.0'), findsNothing);
    });

    testWidgets('a Cashu node with no mint says so rather than showing nothing',
        (tester) async {
      // Arrange — a misconfigured node: it claims Cashu but published no mint,
      // so no trade can run against it.
      await _pumpWithNode(
        tester,
        MostroInstance.fromTags(_tags({'escrow_mode': 'cashu'})),
      );

      // Assert
      expect(find.text('Cashu escrow'), findsOneWidget);
      expect(find.text('Not advertised'), findsOneWidget);
    });
  });
}
