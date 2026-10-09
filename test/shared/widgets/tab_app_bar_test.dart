import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/mascot/mostro_mascot.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';
import 'package:mostro/shared/providers/connection_state_provider.dart';
import 'package:mostro/shared/widgets/notification_bell.dart';
import 'package:mostro/shared/widgets/tab_app_bar.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../support/provider_harness.dart';

/// No anniversary, so no season badge joins the mascot.
final DateTime _plainDay = DateTime(2026, 6, 1, 12);

/// What a test drives the header with.
class _Harness {
  _Harness(this.updates, this.connection, this.visible);

  final StreamController<TradeUpdate> updates;
  final StreamController<ConnectionState> connection;

  /// Whether the tab is on screen. A route pushed over it, or another tab,
  /// mutes its tickers, and that is what the mascot reads.
  final ValueNotifier<bool> visible;

  void trade(OrderStatus status, {DateTime? at}) => updates.add(
    TradeUpdate(
      orderId: 'order-1',
      status: status,
      occurredAt: (at ?? clock.now()).millisecondsSinceEpoch ~/ 1000,
    ),
  );
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool waiting = false,
  Locale? locale,
}) async {
  final updates = StreamController<TradeUpdate>();
  final connection = StreamController<ConnectionState>();
  final visible = ValueNotifier(true);
  addTearDown(updates.close);
  addTearDown(connection.close);
  addTearDown(visible.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: createContainer(
        overrides: [
          tradeUpdatesProvider.overrideWith((ref) => updates.stream),
          connectionStateProvider.overrideWith((ref) => connection.stream),
          unreadNotificationCountProvider.overrideWith((ref) => 0),
          backupReminderProvider.overrideWith(
            (ref) => BackupReminderNotifier(initialValue: false),
          ),
        ],
      ),
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder:
                (_, shown, child) => TickerMode(enabled: shown, child: child!),
            child: TabAppBar(onMenuTap: () {}, waiting: waiting),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return _Harness(updates, connection, visible);
}

/// Lets a stream event, and the microtask the mascot answers it in, land.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

MostroMascot _mascot(WidgetTester tester) => tester.widget<MostroMascot>(
  find.descendant(
    of: find.byType(TabAppBar),
    matching: find.byType(MostroMascot),
  ),
);

void main() {
  group('TabAppBar', () {
    testWidgets('centres the mascot, not the app name in text', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester);

        expect(_mascot(tester).interactive, isTrue);
        expect(find.text('Mostro'), findsNothing);
      });
    });

    testWidgets('still announces the app name, with nothing to tap', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final semantics = tester.ensureSemantics();
        await _pump(tester);

        final name = find.bySemanticsLabel('Mostro');
        expect(name, findsOneWidget);
        expect(
          tester.getSemantics(name),
          isNot(isSemantics(hasTapAction: true)),
        );

        semantics.dispose();
      });
    });

    testWidgets('menu and bell glyphs are 22 dp in every tab', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester);

        final menu = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.menu_rounded),
        );
        expect(menu.iconSize, 22);
        expect(
          tester
              .widget<NotificationBell>(find.byType(NotificationBell))
              .iconSize,
          22,
        );
      });
    });

    testWidgets('a tap reaches the mascot under the menu and bell row', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester);
        bool moving() =>
            find
                .descendant(
                  of: find.byType(MostroMascot),
                  matching: find.byType(Transform),
                )
                .evaluate()
                .isNotEmpty;
        expect(moving(), isFalse);

        await tester.tap(find.byType(MostroMascot));
        await tester.pump(const Duration(milliseconds: 200));

        expect(moving(), isTrue);
      });
    });

    testWidgets('the backup dot is the order book red in every tab', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester);

        expect(
          tester
              .widget<NotificationBell>(find.byType(NotificationBell))
              .dotColor,
          OrderBookPalette.dark.notif,
        );
      });
    });

    testWidgets('the mascot shuffles while the tab waits too long', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester, waiting: true);
        expect(_mascot(tester).mood, MostroMood.neutral);

        await tester.pump(const Duration(seconds: 7));
        expect(_mascot(tester).mood, MostroMood.impatient);
      });
    });

    testWidgets('the mascot celebrates a completed trade', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final header = await _pump(tester);

        header.trade(OrderStatus.success);
        await _settle(tester);
        expect(_mascot(tester).mood, MostroMood.celebrating);

        // The party is over once the celebration has played.
        await tester.pump(mostroCueHold);
        expect(_mascot(tester).mood, MostroMood.neutral);
      });
    });

    testWidgets('the mascot locks up when the escrow does', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final header = await _pump(tester);

        header.trade(OrderStatus.active);
        await _settle(tester);

        expect(_mascot(tester).mood, MostroMood.escrowLocked);
      });
    });

    testWidgets('a step that happens out of sight waits to be seen', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final header = await _pump(tester);
        header.visible.value = false;
        await tester.pump();

        header.trade(OrderStatus.fiatSent);
        await _settle(tester);
        await tester.pump(mostroCueHold);
        expect(_mascot(tester).mood, MostroMood.neutral);

        header.visible.value = true;
        await _settle(tester);
        expect(_mascot(tester).mood, MostroMood.fiatSent);
      });
    });

    testWidgets('a step nobody saw in time is not shown late', (tester) async {
      final header = await withClock(Clock.fixed(_plainDay), () async {
        final header = await _pump(tester);
        header.visible.value = false;
        await tester.pump();
        header.trade(OrderStatus.fiatSent);
        await _settle(tester);
        return header;
      });

      await withClock(
        Clock.fixed(_plainDay.add(const Duration(minutes: 5))),
        () async {
          header.visible.value = true;
          await _settle(tester);
          expect(_mascot(tester).mood, MostroMood.neutral);
        },
      );
    });

    testWidgets('a route pushed over the tab hides the mascot too', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final header = await _pump(tester);
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(builder: (_) => const Scaffold()),
          ),
        );
        await tester.pumpAndSettle();

        header.trade(OrderStatus.dispute);
        await _settle(tester);
        // Long enough that a dispute shown under the route would be over.
        await tester.pump(mostroCueHold);
        navigator.pop();
        await tester.pump();
        await tester.pump();

        expect(
          tester
              .widget<MostroMascot>(
                find.byType(MostroMascot, skipOffstage: false),
              )
              .mood,
          MostroMood.disputed,
        );
      });
    });

    testWidgets('a dialog over the tab holds the cue until it closes', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final header = await _pump(tester);
        // A dialog leaves the tab painted, and its tickers running, but the
        // user is looking at the dialog: the tab's route is not current.
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        unawaited(
          showDialog<void>(
            context: navigator.context,
            builder: (_) => const AlertDialog(content: Text('dialog')),
          ),
        );
        await tester.pumpAndSettle();

        header.trade(OrderStatus.fiatSent);
        await _settle(tester);
        await tester.pump(mostroCueHold);
        expect(_mascot(tester).mood, MostroMood.neutral);

        navigator.pop();
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(_mascot(tester).mood, MostroMood.fiatSent);
      });
    });

    testWidgets('the same step told twice is shown once, not for longer', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final header = await _pump(tester);

        // Rust tells a local fiat-sent, then the daemon's echo of it.
        header.trade(OrderStatus.fiatSent);
        await _settle(tester);
        await tester.pump(const Duration(seconds: 1));
        header.trade(OrderStatus.fiatSent);
        await _settle(tester);
        expect(_mascot(tester).mood, MostroMood.fiatSent);

        await tester.pump(const Duration(seconds: 1));
        expect(_mascot(tester).mood, MostroMood.neutral);
      });
    });

    testWidgets('a dispute on show is not cut short by a lesser step', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final header = await _pump(tester);

        header.trade(OrderStatus.dispute);
        await _settle(tester);
        header.trade(OrderStatus.fiatSent);
        await _settle(tester);

        expect(_mascot(tester).mood, MostroMood.disputed);
      });
    });

    testWidgets('the mascot is scared once the relays stay out of reach', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final header = await _pump(tester);

        header.connection.add(ConnectionState.reconnecting);
        await _settle(tester);
        expect(_mascot(tester).mood, MostroMood.neutral);

        await tester.pump(mostroOfflineGrace);
        expect(_mascot(tester).mood, MostroMood.offline);

        header.connection.add(ConnectionState.online);
        await _settle(tester);
        expect(_mascot(tester).mood, MostroMood.neutral);
      });
    });

    testWidgets('a blip shorter than the grace never scares it', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final header = await _pump(tester);

        header.connection.add(ConnectionState.offline);
        await _settle(tester);
        await tester.pump(mostroOfflineGrace ~/ 2);
        header.connection.add(ConnectionState.online);
        await _settle(tester);
        await tester.pump(mostroOfflineGrace);

        expect(_mascot(tester).mood, MostroMood.neutral);
      });
    });

    testWidgets('a step during an outage waits for the relays to come back', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final header = await _pump(tester);
        header.connection.add(ConnectionState.offline);
        await _settle(tester);
        await tester.pump(mostroOfflineGrace);

        header.trade(OrderStatus.fiatSent);
        await _settle(tester);
        expect(_mascot(tester).mood, MostroMood.offline);

        header.connection.add(ConnectionState.online);
        await _settle(tester);
        expect(_mascot(tester).mood, MostroMood.fiatSent);
      });
    });

    testWidgets('fits 320 dp at 2× text in German, targets apart', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester, locale: const Locale('de'));
        expect(tester.takeException(), isNull);

        // The mascot's 48-dp target must not reach under the menu or bell,
        // or a tap near either edge of it would go to the wrong one.
        final mascot = tester.getRect(find.byType(MostroMascot));
        final menu = tester.getRect(
          find.widgetWithIcon(IconButton, Icons.menu_rounded),
        );
        final bell = tester.getRect(find.byType(NotificationBell));
        expect(mascot.width, greaterThanOrEqualTo(48));
        expect(mascot.overlaps(menu), isFalse);
        expect(mascot.overlaps(bell), isFalse);
      });
    });

    testWidgets('a completion replayed from history is not celebrated', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final header = await _pump(tester);

        // A restore re-emits a trade that ended days ago (#474).
        header.trade(
          OrderStatus.success,
          at: _plainDay.subtract(const Duration(days: 3)),
        );
        await _settle(tester);

        expect(_mascot(tester).mood, MostroMood.neutral);
      });
    });
  });
}
