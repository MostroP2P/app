import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/notifications/screens/notifications_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:sembast/sembast_memory.dart';

/// Issue #610, part A: a notice turns read when the user opens it, or opens
/// its trade — never only through a menu.

NotificationModel _status(String orderId, String status, int hour) =>
    NotificationModel.tradeStatus(
      orderId: orderId,
      status: status,
      at: DateTime.utc(2026, 1, 1, hour),
    );

NotificationModel _chat(String orderId) => NotificationModel.chatMessages(
  tradeId: orderId,
  fromSolver: false,
  count: 2,
  at: DateTime.utc(2026, 1, 1, 12),
);

NotificationModel _system() => NotificationModel(
  id: 'system-1',
  type: NotificationType.system,
  title: 'Node notice',
  message: 'Something about the node.',
  timestamp: DateTime.utc(2026, 1, 1, 13),
);

Future<NotificationsNotifier> _notifierWith(
  List<NotificationModel> notices,
) async {
  final notifier = NotificationsNotifier();
  for (final n in notices) {
    await notifier.add(n);
  }
  return notifier;
}

bool _isRead(NotificationsNotifier notifier, String id) =>
    notifier.state.singleWhere((n) => n.id == id).isRead;

/// Pumps the screen under a router, so a tap that navigates lands on a
/// placeholder instead of throwing.
Future<void> _pumpScreen(
  WidgetTester tester,
  NotificationsNotifier notifier,
) async {
  final router = GoRouter(
    initialLocation: AppRoute.notifications,
    routes: [
      GoRoute(
        path: AppRoute.notifications,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoute.tradeDetail,
        builder: (_, state) => Text('trade ${state.pathParameters['orderId']}'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsProvider.overrideWith((_) => notifier),
        backupReminderProvider.overrideWith(
          (_) => BackupReminderNotifier(initialValue: false),
        ),
      ],
      child: MaterialApp.router(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(NotificationsScreen)));

void main() {
  group('markOrderAsRead', () {
    test(
      'reads the trade\'s notices, not its chat card or other trades',
      () async {
        // Arrange
        final notifier = await _notifierWith([
          _status('a', 'waitingPayment', 1),
          _status('a', 'active', 2),
          _chat('a'),
          _status('b', 'active', 3),
        ]);

        // Act
        await notifier.markOrderAsRead('a');

        // Assert
        expect(_isRead(notifier, 'trade-a-waitingPayment'), isTrue);
        expect(_isRead(notifier, 'trade-a-active'), isTrue);
        expect(
          _isRead(
            notifier,
            NotificationModel.chatCardId('a', fromSolver: false),
          ),
          isFalse,
        );
        expect(_isRead(notifier, 'trade-b-active'), isFalse);
      },
    );

    test('the store applies the same filter to persisted records', () async {
      // Arrange
      final store = SembastNotificationsStore(
        factory: databaseFactoryMemory,
        path: 'mark-order-read.db',
      );
      for (final n in [
        _status('a', 'active', 1),
        _chat('a'),
        _status('b', 'active', 2),
      ]) {
        await store.save(n);
      }

      // Act
      final updated = await store.markRead(orderId: 'a');

      // Assert
      expect(updated.map((n) => n.id), ['trade-a-active']);
      final read = {for (final n in await store.loadAll()) n.id: n.isRead};
      expect(read, {
        'trade-a-active': true,
        NotificationModel.chatCardId('a', fromSolver: false): false,
        'trade-b-active': false,
      });
    });
  });

  group('NotificationsScreen', () {
    testWidgets('tapping an event marks it read and opens the trade', (
      tester,
    ) async {
      // Arrange
      final notifier = await _notifierWith([_status('a', 'active', 1)]);
      await _pumpScreen(tester, notifier);

      // Act
      await tester.tap(find.text(_l10n(tester).tradeCardActiveTitle));
      await tester.pumpAndSettle();

      // Assert
      expect(_isRead(notifier, 'trade-a-active'), isTrue);
      expect(find.text('trade a'), findsOneWidget);
    });

    testWidgets('a resolver chat card opens the trade and stays unread', (
      tester,
    ) async {
      // Arrange: the dispute chat owns its read state, not the trade.
      final solver = NotificationModel.chatMessages(
        tradeId: 'a',
        fromSolver: true,
        count: 1,
        at: DateTime.utc(2026, 1, 1, 1),
      );
      final notifier = await _notifierWith([solver]);
      await _pumpScreen(tester, notifier);

      // Act
      await tester.tap(find.text(_l10n(tester).chatCardSolverTitle));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('trade a'), findsOneWidget);
      expect(_isRead(notifier, solver.id), isFalse);
    });

    testWidgets('Go to trade marks every event of the group read', (
      tester,
    ) async {
      // Arrange
      final notifier = await _notifierWith([
        _status('a', 'waitingPayment', 1),
        _status('a', 'active', 2),
        _status('b', 'active', 3),
      ]);
      await _pumpScreen(tester, notifier);
      final goToTrade = find.text(_l10n(tester).goToTrade);

      // Act: order "a" is the second card, its latest event being older.
      await tester.tap(goToTrade.at(1));
      await tester.pumpAndSettle();

      // Assert
      expect(_isRead(notifier, 'trade-a-waitingPayment'), isTrue);
      expect(_isRead(notifier, 'trade-a-active'), isTrue);
      expect(_isRead(notifier, 'trade-b-active'), isFalse);
    });

    testWidgets('tapping a system notice marks it read', (tester) async {
      // Arrange
      final notifier = await _notifierWith([_system()]);
      await _pumpScreen(tester, notifier);

      // Act
      await tester.tap(find.text('Node notice'));
      await tester.pumpAndSettle();

      // Assert
      expect(_isRead(notifier, 'system-1'), isTrue);
    });
  });
}
