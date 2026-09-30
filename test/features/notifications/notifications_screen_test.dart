import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/notifications/screens/notifications_screen.dart';
import 'package:mostro/features/notifications/widgets/notification_group_card.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

/// Issue #610, part B: one list, cards that say which trade they are and
/// what happened, and the trades that need the user pinned on top.

final _en = AppLocalizationsEn();

NotificationModel _status(String orderId, String status, int hour) =>
    NotificationModel.tradeStatus(
      orderId: orderId,
      status: status,
      at: DateTime.utc(2026, 1, 1, hour),
    );

TradeRow _row(
  String orderId, {
  required OrderStatus status,
  required bool isSelling,
}) => TradeRow(
  orderId: orderId,
  status: status,
  state: TradeRowState.of(
    status: status,
    isBuyer: !isSelling,
    ratedByMe: true,
    canRate: false,
  ),
  isSelling: isSelling,
  isMaker: false,
  fiatAmount: 50000,
  fiatAmountMin: null,
  fiatAmountMax: null,
  fiatCode: 'ARS',
  premium: 0,
  amountSats: 95004,
  paymentMethod: 'Bank transfer',
  startedAt: 0,
  peerHandle: null,
);

Future<NotificationsNotifier> _pump(
  WidgetTester tester, {
  required List<NotificationModel> notices,
  List<TradeRow> rows = const [],
}) async {
  final notifier = NotificationsNotifier();
  for (final n in notices) {
    await notifier.add(n);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsProvider.overrideWith((_) => notifier),
        tradeRowsProvider.overrideWithValue(AsyncValue.data(rows)),
        backupReminderProvider.overrideWith(
          (_) => BackupReminderNotifier(initialValue: false),
        ),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NotificationsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  testWidgets('one list: no filter tabs, disputes among the rest', (
    tester,
  ) async {
    // Arrange / Act
    await _pump(
      tester,
      notices: [
        _status('disputed', 'dispute', 2),
        _status('quiet', 'success', 1),
      ],
    );

    // Assert
    expect(find.text('All'), findsNothing);
    expect(find.text('Disputes'), findsNothing);
    expect(find.byType(NotificationGroupCard), findsNWidgets(2));
    expect(find.byIcon(Icons.gavel_rounded), findsWidgets);
  });

  testWidgets('the header names the trade from its row, not its id', (
    tester,
  ) async {
    // Arrange / Act
    await _pump(
      tester,
      notices: [_status('d5f425ca-1111', 'success', 1)],
      rows: [
        _row('d5f425ca-1111', status: OrderStatus.success, isSelling: true),
      ],
    );

    // Assert
    expect(
      find.text('${_en.tradesDirectionSell} · 50,000 ARS · 95,004 sats'),
      findsOneWidget,
    );
    expect(find.text('Bank transfer · #d5f425ca'), findsOneWidget);
  });

  testWidgets('without its row the header falls back to the short id', (
    tester,
  ) async {
    await _pump(tester, notices: [_status('d5f425ca-1111', 'success', 1)]);

    expect(find.text('${_en.tradeWord} #d5f425ca'), findsOneWidget);
  });

  testWidgets('the latest event shows its whole title and its message', (
    tester,
  ) async {
    // Arrange / Act
    await _pump(
      tester,
      notices: [_status('a', 'waitingPayment', 1), _status('a', 'active', 2)],
    );

    // Assert
    final title = tester.widget<Text>(find.text(_en.tradeCardActiveTitle));
    expect(title.maxLines, 2, reason: 'never cut to half the card (#610)');
    expect(find.text(_en.tradeCardActiveMessage), findsOneWidget);
    expect(find.text(_en.tradeCardWaitingPaymentTitle), findsNothing);
  });

  testWidgets('earlier events expand as a timeline with whole titles', (
    tester,
  ) async {
    // Arrange
    await _pump(
      tester,
      notices: [_status('a', 'waitingPayment', 1), _status('a', 'active', 2)],
    );

    // Act
    await tester.tap(find.text(_en.viewEarlierEvents(1)));
    await tester.pumpAndSettle();

    // Assert
    expect(find.text(_en.tradeCardWaitingPaymentTitle), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
  });

  testWidgets('a trade that needs the user is pinned, with its step', (
    tester,
  ) async {
    // Arrange / Act: the buyer of an active trade owes the fiat payment.
    await _pump(
      tester,
      notices: [_status('mine', 'active', 1), _status('theirs', 'active', 3)],
      rows: [
        _row('mine', status: OrderStatus.active, isSelling: false),
        _row('theirs', status: OrderStatus.active, isSelling: true),
      ],
    );

    // Assert
    expect(find.text(_en.tradesGroupNeedsAction.toUpperCase()), findsOneWidget);
    expect(find.text(_en.notifSectionRecent.toUpperCase()), findsOneWidget);
    expect(find.text(_en.tradeVerbSendPayment), findsOneWidget);
    final cards = tester.widgetList<NotificationGroupCard>(
      find.byType(NotificationGroupCard),
    );
    expect(
      cards.map((c) => c.notifications.first.orderId),
      ['mine', 'theirs'],
      reason: 'the pinned trade comes first even though it is older',
    );
  });

  testWidgets('with nothing to act on there are no section headers', (
    tester,
  ) async {
    await _pump(
      tester,
      notices: [_status('theirs', 'active', 1)],
      rows: [_row('theirs', status: OrderStatus.active, isSelling: true)],
    );

    expect(find.text(_en.tradesGroupNeedsAction.toUpperCase()), findsNothing);
    expect(find.text(_en.notifSectionRecent.toUpperCase()), findsNothing);
  });

  group('swipe to delete', () {
    testWidgets('no per-event menu: only the app bar keeps one', (
      tester,
    ) async {
      await _pump(
        tester,
        notices: [_status('a', 'waitingPayment', 1), _status('a', 'active', 2)],
      );

      expect(find.byType(PopupMenuButton<bool>), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('a swiped card hides at once and is deleted when the '
        'snack bar closes', (tester) async {
      // Arrange
      final notifier = await _pump(
        tester,
        notices: [_status('a', 'waitingPayment', 1), _status('a', 'active', 2)],
      );

      // Act
      await tester.drag(
        find.byType(NotificationGroupCard),
        const Offset(-600, 0),
      );
      await tester.pumpAndSettle();

      // Assert: gone from the list, still stored while Undo is offered.
      expect(find.byType(NotificationGroupCard), findsNothing);
      expect(find.text(_en.notificationDeletedSnack(2)), findsOneWidget);
      expect(notifier.state, hasLength(2));

      // The snack bar times out: now the notices are deleted.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(notifier.state, isEmpty);
    });

    testWidgets('Undo brings the card back and deletes nothing', (
      tester,
    ) async {
      // Arrange
      final notifier = await _pump(
        tester,
        notices: [_status('a', 'active', 1)],
      );
      await tester.drag(
        find.byType(NotificationGroupCard),
        const Offset(600, 0),
      );
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text(_en.notificationDeletedUndo));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(NotificationGroupCard), findsOneWidget);
      expect(notifier.state, hasLength(1));
    });
  });
}
