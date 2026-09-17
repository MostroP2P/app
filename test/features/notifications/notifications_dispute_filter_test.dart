import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/notifications/screens/notifications_screen.dart';
import 'package:mostro/features/notifications/widgets/notification_group_card.dart';
import 'package:mostro/l10n/app_localizations.dart';

void main() {
  for (final status in [
    'dispute',
    'canceledByAdmin',
    'settledByAdmin',
    'completedByAdmin',
    'solver',
  ]) {
    testWidgets('Disputes filter includes persisted $status cards', (
      tester,
    ) async {
      final notifier = NotificationsNotifier();
      final dispute =
          status == 'solver'
              ? NotificationModel.chatMessages(
                tradeId: 'dispute-order',
                fromSolver: true,
                count: 1,
                at: DateTime.utc(2026),
              )
              : NotificationModel.tradeStatus(
                orderId: 'dispute-order',
                status: status,
                at: DateTime.utc(2026),
              );
      await notifier.add(NotificationModel.fromJson(dispute.toJson()));
      await notifier.add(
        NotificationModel.tradeStatus(
          orderId: 'active-order',
          status: 'active',
          at: DateTime.utc(2026),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsProvider.overrideWith((_) => notifier),
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
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NotificationsScreen)),
      );
      await tester.tap(find.text(l10n.notifFilterDisputesCount(1)));
      await tester.pumpAndSettle();
      final group = tester.widget<NotificationGroupCard>(
        find.byType(NotificationGroupCard),
      );
      expect(group.notifications.single.orderId, 'dispute-order');
    });
  }
}
