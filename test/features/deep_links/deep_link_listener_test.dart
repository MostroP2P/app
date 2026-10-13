import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/features/deep_links/deep_link_listener.dart';
import 'package:mostro/features/walkthrough/providers/first_run_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/provider_harness.dart';

const _link =
    'mostro:e215c07e-b1f9-45b0-9640-0295067ee99a?relays=wss://nos.lol';

/// The listener under a container whose first run is [firstRunDone], fed by
/// the returned controller; every destination it opens lands in [opened].
Future<(StreamController<String>, ProviderContainer)> _pump(
  WidgetTester tester,
  List<String> opened, {
  bool firstRunDone = true,
}) async {
  final links = StreamController<String>();
  addTearDown(links.close);
  final container = createContainer(
    overrides: [
      firstRunProvider.overrideWith(
        (ref) => FirstRunNotifier(initialValue: firstRunDone),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: DeepLinkListener(
        links: links.stream,
        open: opened.add,
        child: const SizedBox.shrink(),
      ),
    ),
  );
  // The listener subscribes after the first frame.
  await tester.pump();
  return (links, container);
}

void main() {
  testWidgets('a mostro: link opens the order link screen', (tester) async {
    // Arrange
    final opened = <String>[];
    final (links, _) = await _pump(tester, opened);

    // Act
    links.add(' $_link ');
    await tester.pump();

    // Assert
    expect(opened, [AppRoute.orderLinkPath(_link)]);
  });

  testWidgets('any other link is left alone', (tester) async {
    // Arrange
    final opened = <String>[];
    final (links, _) = await _pump(tester, opened);

    // Act
    links
      ..add('https://mostro.network/app/')
      ..add('nostr:npub1abc');
    await tester.pump();

    // Assert
    expect(opened, isEmpty);
  });

  testWidgets(
    'the same link handed over twice in a row opens once, and again later',
    (tester) async {
      var now = DateTime.utc(2026, 10, 13, 12);
      await withClock(Clock(() => now), () async {
        // Arrange
        final opened = <String>[];
        final (links, _) = await _pump(tester, opened);

        // Act
        links
          ..add(_link)
          ..add(_link);
        await tester.pump();
        now = now.add(DeepLinkListener.duplicateWindow);
        links.add(_link);
        await tester.pump();

        // Assert
        expect(opened, hasLength(2));
      });
    },
  );

  testWidgets('a link that arrives during the first run waits for its end', (
    tester,
  ) async {
    // Arrange
    SharedPreferences.setMockInitialValues({});
    final opened = <String>[];
    final (links, container) = await _pump(tester, opened, firstRunDone: false);
    links.add(_link);
    await tester.pump();
    expect(opened, isEmpty, reason: 'the router would bounce it');

    // Act
    await container.read(firstRunProvider.notifier).markFirstRunComplete();
    await tester.pump();

    // Assert
    expect(opened, [AppRoute.orderLinkPath(_link)]);
  });
}
