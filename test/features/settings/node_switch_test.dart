import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/restore/restore_after_switch.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/services/node_switch.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../support/provider_harness.dart';

const _target =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// Records the node changes it is asked for — no bridge.
class _FakeNodes extends MostroNodesNotifier {
  _FakeNodes({this.failSelect = false});

  final bool failSelect;
  final List<String> selected = [];

  @override
  Future<List<MostroNodeEntry>> build() async => const [];

  @override
  Future<void> refreshMetadata() async {}

  @override
  Future<void> selectNode(String pubkey) async {
    if (failSelect) throw Exception('boom');
    selected.add(pubkey);
  }
}

/// A button that switches to [_target] the way a caller does: the switch,
/// then what follows it only when it went through. Returns the fake nodes
/// and a count of the restores asked for.
Future<(_FakeNodes, List<int>)> _pump(
  WidgetTester tester, {
  bool failSelect = false,
}) async {
  final nodes = _FakeNodes(failSelect: failSelect);
  final restores = [0];
  final container = createContainer(
    overrides: [
      mostroNodesProvider.overrideWith(() => nodes),
      restoreAfterNodeSwitchProvider.overrideWithValue(
        (_) async => restores[0]++,
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder:
                (context, ref, _) => TextButton(
                  onPressed: () async {
                    if (await switchActiveNode(ref, _target) &&
                        context.mounted) {
                      await afterNodeSwitch(context, ref, 'Target node');
                    }
                  },
                  child: const Text('switch'),
                ),
          ),
        ),
      ),
    ),
  );
  return (nodes, restores);
}

void main() {
  testWidgets('a switch that goes through says so and restores the account', (
    tester,
  ) async {
    final (nodes, restores) = await _pump(tester);

    await tester.tap(find.text('switch'));
    await tester.pump();

    expect(nodes.selected, [_target]);
    expect(find.text('Now using Target node'), findsOneWidget);
    expect(restores.single, 1);
  });

  testWidgets('a failed switch says nothing and restores nothing', (
    tester,
  ) async {
    final (nodes, restores) = await _pump(tester, failSelect: true);

    await tester.tap(find.text('switch'));
    await tester.pump();

    expect(nodes.selected, isEmpty);
    expect(find.text('Now using Target node'), findsNothing);
    expect(restores.single, 0);
  });
}
