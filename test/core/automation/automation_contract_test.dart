import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/test_environment.dart';
import 'package:mostro/features/trades/screens/trade_detail_screen.dart'
    show TradeStatus, TradeStatusMachineName;
import 'package:mostro/shared/widgets/test_environment_banner.dart';

/// Guards the Mortsom automation contract (`docs/automation-contract.md`).
///
/// The contract's failure mode is silent rot: an identifier keeps existing as
/// a constant while the control it named is renamed, removed, or rebuilt
/// without it. A harness then waits for an element the app never renders and
/// times out with no way to say why. These tests make that a build failure.
void main() {
  group('the identifier registry', () {
    test('every identifier is unique, dotted and free of whitespace', () {
      final seen = <String>{};
      for (final id in _declaredIdentifiers()) {
        expect(seen.add(id), isTrue, reason: 'duplicate identifier $id');
        expect(id, contains('.'), reason: '$id is not namespaced');
        expect(id, isNot(contains(' ')), reason: '$id contains whitespace');
        expect(id, equals(id.trim()));
      }
      expect(seen, hasLength(greaterThan(40)),
          reason: 'the parser found almost nothing — has the file moved?');
    });

    test('every declared identifier is attached to a control', () {
      final source = _librarySources();
      final unattached = <String>[];
      for (final member in _declaredMembers()) {
        // The declaration itself lives in automation_ids.dart; a member used
        // nowhere else names nothing.
        final uses = source.entries
            .where((e) => !e.key.endsWith('automation_ids.dart'))
            .where((e) => e.value.contains('AutomationIds.$member'))
            .length;
        if (uses == 0) unattached.add(member);
      }
      expect(
        unattached,
        isEmpty,
        reason: 'declared but attached to no control in lib/: $unattached',
      );
    });
  });

  group('AutomationId', () {
    testWidgets('exposes the identifier and merges the control it names',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedButton(
              onPressed: () {},
              child: const Text('Submit'),
            ).withAutomationId(AutomationIds.orderCreateSubmit),
          ),
        ),
      );

      // The identifier, the visible label, the enabled flag and the tap
      // action all travel on one node — that is what the Android
      // accessibility bridge exposes as a `resource-id`.
      expect(
        tester.getSemantics(find.byType(ElevatedButton)),
        containsSemantics(
          identifier: AutomationIds.orderCreateSubmit,
          label: 'Submit',
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('an explicit label overrides the visible copy',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const Text('Esperando pago…').withAutomationId(
              AutomationIds.orderStatus,
              label: 'waiting-payment',
            ),
          ),
        ),
      );

      // State readouts are asserted on by machine name, never by the copy,
      // which changes with the locale.
      expect(
        tester.getSemantics(find.text('Esperando pago…')),
        containsSemantics(
          identifier: AutomationIds.orderStatus,
          label: 'waiting-payment',
        ),
      );
    });

    testWidgets('merge: false keeps nested controls addressable',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.delete),
                ).withAutomationId(
                  AutomationIds.settingsRelayDelete('ws://10.0.2.2:7000'),
                ),
              ],
            ).withAutomationId(
              AutomationIds.settingsRelayItem('ws://10.0.2.2:7000'),
              merge: false,
              label: 'ws://10.0.2.2:7000',
            ),
          ),
        ),
      );

      // A merged row would swallow the delete button's own node, and
      // automation could no longer choose which relay to remove.
      expect(
        tester.getSemantics(find.byType(IconButton)),
        containsSemantics(
          identifier:
              AutomationIds.settingsRelayDelete('ws://10.0.2.2:7000'),
          hasTapAction: true,
        ),
      );
    });
  });

  group('dynamic identifiers', () {
    test('embed the key they are built from', () {
      expect(AutomationIds.orderBookItem('o1'), 'order.book.item.o1');
      expect(AutomationIds.tradesItem('o1'), 'trades.item.o1');
      expect(
        AutomationIds.orderCreateCurrencyOption('USD'),
        'order.create.currency.USD',
      );
      expect(
        AutomationIds.settingsRelayItem('ws://10.0.2.2:7000'),
        'settings.relays.item.ws://10.0.2.2:7000',
      );
    });

    test('a relay keeps one identifier however its url is written', () {
      const canonical = 'settings.relays.item.ws://10.0.2.2:7000';
      for (final written in [
        'ws://10.0.2.2:7000',
        'ws://10.0.2.2:7000/',
        'ws://10.0.2.2:7000//',
        '  ws://10.0.2.2:7000/  ',
      ]) {
        expect(AutomationIds.settingsRelayItem(written), canonical,
            reason: written);
      }
    });
  });

  group('order.status', () {
    test('every trade status has a kebab-case machine name', () {
      final names = {
        for (final status in TradeStatus.values) status: status.machineName,
      };
      expect(names[TradeStatus.waitingInvoice], 'waiting-invoice');
      expect(names[TradeStatus.waitingPayment], 'waiting-payment');
      expect(names[TradeStatus.inProgress], 'in-progress');
      expect(names[TradeStatus.fiatSent], 'fiat-sent');
      expect(names[TradeStatus.pendingRating], 'pending-rating');
      expect(names[TradeStatus.active], 'active');

      for (final name in names.values) {
        expect(name, matches(RegExp(r'^[a-z]+(-[a-z]+)*$')), reason: name);
      }
      expect(names.values.toSet(), hasLength(TradeStatus.values.length));
    });
  });

  group('the test environment', () {
    tearDown(TestEnvironment.disarm);

    test('stays disabled unless the build carries the define', () {
      TestEnvironment.arm();
      expect(TestEnvironment.enabled, TestEnvironment.defineEnabled);
      expect(TestEnvironment.allowInsecureRelays, TestEnvironment.enabled);
    });

    test('is disabled for a build that never armed it', () {
      expect(TestEnvironment.enabled, isFalse);
      expect(TestEnvironment.seedRelays, isEmpty);
      expect(TestEnvironment.allowInsecureRelays, isFalse);
    });

    test('parses a relay seed list, trimming and dropping blanks', () {
      expect(
        TestEnvironment.parseRelays(' ws://a:1 , ,ws://b:2, '),
        ['ws://a:1', 'ws://b:2'],
      );
      expect(TestEnvironment.parseRelays(''), isEmpty);
    });

    testWidgets('the banner renders nothing outside the test environment',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TestEnvironmentBanner(child: Text('app')),
        ),
      );

      expect(find.text(TestEnvironment.markerLabel), findsNothing);
      expect(
        find.bySemanticsLabel(TestEnvironment.markerLabel),
        findsNothing,
      );
      expect(find.text('app'), findsOneWidget);
    });
  });
}

// ── Source scanning ──────────────────────────────────────────────────────────
//
// The contract is a promise about the shipped widget tree, and most of that
// tree needs the Rust bridge to build. Reading the sources checks the one
// thing a unit test can check without it: that nothing is declared and then
// left unattached.

const _registryPath = 'lib/core/automation/automation_ids.dart';

/// Member names declared in the registry (constants and helper methods).
List<String> _declaredMembers() {
  final source = File(_registryPath).readAsStringSync();
  final constants = RegExp(r'static const String (\w+) =')
      .allMatches(source)
      .map((m) => m.group(1)!);
  final helpers = RegExp(r'static String (\w+)\(')
      .allMatches(source)
      .map((m) => m.group(1)!)
      // Private helpers are implementation, not contract.
      .where((name) => !name.startsWith('_'));
  return [...constants, ...helpers];
}

/// Identifier values declared in the registry.
List<String> _declaredIdentifiers() {
  final source = File(_registryPath).readAsStringSync();
  return RegExp(r"static const String \w+ =\s*'([^']+)'")
      .allMatches(source)
      .map((m) => m.group(1)!)
      // The wallet-connection readout values are machine words, not ids.
      .where((id) => id.contains('.'))
      .toList();
}

Map<String, String> _librarySources() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      // Generated code never attaches identifiers.
      .where((f) => !f.path.startsWith('lib/src/'))
      .where((f) => !f.path.startsWith('lib/generated/'))
      .where((f) => !f.path.startsWith('lib/l10n/'));
  return {for (final f in files) f.path: f.readAsStringSync()};
}
