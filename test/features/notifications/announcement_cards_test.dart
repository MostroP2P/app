import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/models/notification_view_rules.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/notifications/screens/notifications_screen.dart';
import 'package:mostro/features/notifications/services/announcement_cards.dart';
import 'package:mostro/features/notifications/widgets/system_notification_banner.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/l10n/app_localizations_es.dart';
import 'package:mostro/shared/widgets/notification_bell.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Project announcements in the notification surface
/// (specs/006-announcement-channel §3.4, §6.2): the card picks its locale,
/// paints its level, keeps its link out of the body; the store follows
/// Rust's snapshots; a dismissed `critical` stays; the bell turns red.

const _locales = ['en', 'es', 'fr', 'de', 'it', 'nl', 'pt'];

AnnouncementInfo _info({
  String d = 'release-2-1',
  String revision = '1800000000:aa',
  AnnouncementSeverity severity = AnnouncementSeverity.info,
  String? url = 'https://mostro.network/blog/2-1',
  bool read = false,
  bool dismissed = false,
  int createdAt = 1800000000,
}) => AnnouncementInfo(
  address: '38387:ab:$d',
  revision: revision,
  createdAt: createdAt,
  expiration: 1900000000,
  severity: severity,
  texts: [
    for (final l in _locales)
      AnnouncementText(locale: l, title: 'Title $l', body: 'Body $l'),
  ],
  url: url,
  read: read,
  dismissed: dismissed,
);

/// Records what the notifier reports to Rust.
class _RecordingFlags extends AnnouncementFlags {
  final reads = <String>[];
  final dismissals = <String>[];

  @override
  Future<void> read(String address) async => reads.add(address);

  @override
  Future<void> dismiss(String address) async => dismissals.add(address);
}

NotificationModel _card(NotificationsNotifier notifier, String id) =>
    notifier.state.singleWhere((n) => n.id == id);

Future<void> _pumpApp(
  WidgetTester tester,
  Widget home, {
  required NotificationsNotifier notifier,
  String locale = 'en',
}) async {
  final router = GoRouter(
    initialLocation: AppRoute.notifications,
    routes: [GoRoute(path: AppRoute.notifications, builder: (_, _) => home)],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationsProvider.overrideWith((_) => notifier),
        tradeRowsProvider.overrideWithValue(const AsyncValue.data([])),
        backupReminderProvider.overrideWith(
          (_) => BackupReminderNotifier(initialValue: false),
        ),
      ],
      child: MaterialApp.router(
        theme: buildDarkTheme(),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('NotificationModel.announcement', () {
    test('picks the copy of the locale on screen, English as fallback', () {
      // Arrange
      final card = NotificationModel.announcement(_info());

      // Act / Assert
      expect(card.resolvedTitle(AppLocalizationsEs()), 'Title es');
      expect(card.resolvedMessage(AppLocalizationsEs()), 'Body es');
      expect(card.resolvedTitle(AppLocalizationsEn()), 'Title en');
      // The stored fallback is English.
      expect(card.title, 'Title en');
      expect(card.message, 'Body en');
    });

    test('is keyed by its address and carries its revision and link', () {
      final card = NotificationModel.announcement(
        _info(revision: '1800000000:cafe'),
      );

      expect(card.id, '38387:ab:release-2-1');
      expect(card.isAnnouncement, isTrue);
      expect(card.announcementRevision, '1800000000:cafe');
      expect(card.announcementUrl, 'https://mostro.network/blog/2-1');
      expect(card.type, NotificationType.system);
      expect(card.timestamp.millisecondsSinceEpoch ~/ 1000, 1800000000);
      // Its stored keys are markers, not rows to show.
      expect(card.resolvedDetail(AppLocalizationsEn()), isEmpty);
    });

    test('a level this build does not know paints as warning', () {
      final card = NotificationModel.fromJson({
        ...NotificationModel.announcement(_info()).toJson(),
        'detail': {'announcement': '1:a', 'severity': 'emergency'},
      });

      expect(card.announcementSeverity, AnnouncementSeverity.warning);
      expect(card.isCriticalAnnouncement, isFalse);
    });

    test('each level has its own label', () {
      final l10n = AppLocalizationsEn();
      String label(AnnouncementSeverity s) =>
          NotificationModel.announcement(
            _info(severity: s),
          ).announcementLevelLabel(l10n)!;

      expect(label(AnnouncementSeverity.info), 'Announcement');
      expect(label(AnnouncementSeverity.warning), 'Notice');
      expect(label(AnnouncementSeverity.critical), 'Security update');
      expect(
        NotificationModel.backupReminder().announcementLevelLabel(l10n),
        isNull,
      );
    });

    test('survives a round trip through the store', () {
      final card = NotificationModel.announcement(
        _info(severity: AnnouncementSeverity.critical, read: true),
      );

      final back = NotificationModel.fromJson(card.toJson());

      expect(back.isCriticalAnnouncement, isTrue);
      expect(back.isRead, isTrue);
      expect(back.resolvedTitle(AppLocalizationsEs()), 'Title es');
    });
  });

  group('announcementCards', () {
    test('a dismissed critical keeps its card; the other levels lose it', () {
      final cards = announcementCards([
        _info(d: 'a', dismissed: true),
        _info(d: 'b', dismissed: true, severity: AnnouncementSeverity.warning),
        _info(d: 'c', dismissed: true, severity: AnnouncementSeverity.critical),
        _info(d: 'd'),
      ]);

      expect(cards.map((c) => c.id), ['38387:ab:c', '38387:ab:d']);
    });
  });

  group('NotificationsNotifier.reconcileAnnouncements', () {
    test(
      'a new address is added, a gone one removed, others untouched',
      () async {
        // Arrange
        final notifier = NotificationsNotifier();
        await notifier.add(NotificationModel.backupReminder());
        await notifier.reconcileAnnouncements(
          announcementCards([_info(d: 'a')]),
        );
        expect(notifier.state.map((n) => n.id), contains('38387:ab:a'));

        // Act: Rust now lists b only.
        await notifier.reconcileAnnouncements(
          announcementCards([_info(d: 'b')]),
        );

        // Assert
        final ids = notifier.state.map((n) => n.id).toList();
        expect(ids, contains('38387:ab:b'));
        expect(ids, isNot(contains('38387:ab:a')));
        expect(notifier.state.where((n) => !n.isAnnouncement), hasLength(1));
      },
    );

    test('a correction replaces the card and is unread again', () async {
      // Arrange
      final notifier = NotificationsNotifier();
      await notifier.reconcileAnnouncements(
        announcementCards([_info(revision: '1:a', read: true)]),
      );
      expect(_card(notifier, '38387:ab:release-2-1').isRead, isTrue);

      // Act
      await notifier.reconcileAnnouncements(
        announcementCards([_info(revision: '2:b')]),
      );

      // Assert
      final card = _card(notifier, '38387:ab:release-2-1');
      expect(card.announcementRevision, '2:b');
      expect(card.isRead, isFalse);
    });

    test('the same revision keeps the card, and Rust read flag wins', () async {
      final notifier = NotificationsNotifier();
      await notifier.reconcileAnnouncements(announcementCards([_info()]));
      expect(_card(notifier, '38387:ab:release-2-1').isRead, isFalse);

      await notifier.reconcileAnnouncements(
        announcementCards([_info(read: true)]),
      );

      expect(_card(notifier, '38387:ab:release-2-1').isRead, isTrue);
      expect(notifier.state, hasLength(1));
    });
  });

  group('read and dismiss reach Rust', () {
    test('reading an announcement reports it', () async {
      final flags = _RecordingFlags();
      final notifier = NotificationsNotifier(announcementFlags: flags);
      await notifier.reconcileAnnouncements(announcementCards([_info()]));

      await notifier.markAsRead('38387:ab:release-2-1');

      expect(flags.reads, ['38387:ab:release-2-1']);
    });

    test('swiping a non-critical removes it and reports the dismiss', () async {
      final flags = _RecordingFlags();
      final notifier = NotificationsNotifier(announcementFlags: flags);
      await notifier.reconcileAnnouncements(announcementCards([_info()]));

      await notifier.delete('38387:ab:release-2-1');

      expect(notifier.state, isEmpty);
      expect(flags.dismissals, ['38387:ab:release-2-1']);
    });

    test(
      'swiping a critical keeps it, read, and reports the dismiss',
      () async {
        final flags = _RecordingFlags();
        final notifier = NotificationsNotifier(announcementFlags: flags);
        await notifier.reconcileAnnouncements(
          announcementCards([_info(severity: AnnouncementSeverity.critical)]),
        );

        await notifier.delete('38387:ab:release-2-1');

        expect(_card(notifier, '38387:ab:release-2-1').isRead, isTrue);
        expect(flags.dismissals, ['38387:ab:release-2-1']);
      },
    );

    test(
      'clearing the list keeps a critical, read, and dismisses all',
      () async {
        final flags = _RecordingFlags();
        final notifier = NotificationsNotifier(announcementFlags: flags);
        await notifier.add(NotificationModel.backupReminder());
        await notifier.reconcileAnnouncements(
          announcementCards([
            _info(d: 'c', severity: AnnouncementSeverity.critical),
            _info(d: 'i'),
          ]),
        );

        await notifier.deleteAll();

        expect(notifier.state.map((n) => n.id), ['38387:ab:c']);
        expect(notifier.state.single.isRead, isTrue);
        expect(flags.dismissals, unorderedEquals(['38387:ab:c', '38387:ab:i']));
      },
    );
  });

  group('sectionNotices', () {
    test('a critical announcement sorts above a newer notice', () {
      final critical = NotificationModel.announcement(
        _info(d: 'c', severity: AnnouncementSeverity.critical, createdAt: 100),
      );
      final newer = NotificationModel.announcement(
        _info(d: 'i', createdAt: 200),
      );

      final sections = sectionNotices([
        newer,
        critical,
      ], needsAction: (_) => false);

      expect(
        sections.recent.map((e) => (e as NoticeSystemEntry).notification.id),
        ['38387:ab:c', '38387:ab:i'],
      );
    });
  });

  group('SystemNotificationBanner', () {
    testWidgets('shows the level, the locale copy and the link', (
      tester,
    ) async {
      // Arrange
      final notifier = NotificationsNotifier();
      await notifier.reconcileAnnouncements(
        announcementCards([_info(severity: AnnouncementSeverity.critical)]),
      );
      var opened = 0;

      // Act
      await _pumpApp(
        tester,
        Scaffold(
          body: SystemNotificationBanner(
            notification: notifier.state.single,
            onOpenLink: () => opened++,
          ),
        ),
        notifier: notifier,
        locale: 'es',
      );

      // Assert
      expect(find.text('ACTUALIZACIÓN DE SEGURIDAD'), findsOneWidget);
      expect(find.text('Title es'), findsOneWidget);
      expect(find.textContaining('Body es'), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
      await tester.tap(find.text('Abrir enlace'));
      expect(opened, 1);
    });

    testWidgets('a plain system notice keeps its amber and no link', (
      tester,
    ) async {
      final notifier = NotificationsNotifier();
      await notifier.add(NotificationModel.backupReminder());

      await _pumpApp(
        tester,
        Scaffold(
          body: SystemNotificationBanner(notification: notifier.state.single),
        ),
        notifier: notifier,
      );

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('Open link'), findsNothing);
      expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
    });
  });

  group('NotificationsScreen', () {
    testWidgets('tapping an announcement reads it and opens nothing', (
      tester,
    ) async {
      final flags = _RecordingFlags();
      final notifier = NotificationsNotifier(announcementFlags: flags);
      await notifier.reconcileAnnouncements(announcementCards([_info()]));
      await _pumpApp(tester, const NotificationsScreen(), notifier: notifier);

      await tester.tap(find.text('Title en'));
      await tester.pump();

      expect(_card(notifier, '38387:ab:release-2-1').isRead, isTrue);
      expect(flags.reads, ['38387:ab:release-2-1']);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('NotificationBell', () {
    testWidgets('an unread critical turns the dot red', (tester) async {
      final notifier = NotificationsNotifier();
      await notifier.reconcileAnnouncements(
        announcementCards([_info(severity: AnnouncementSeverity.critical)]),
      );

      await _pumpApp(
        tester,
        const Scaffold(body: NotificationBell()),
        notifier: notifier,
      );

      expect(
        find.bySemanticsLabel('Notifications, a security update is unread'),
        findsOneWidget,
      );
      // No count badge: the red dot is the whole signal.
      expect(find.text('1'), findsNothing);
    });

    testWidgets('an unread info announcement counts like any notice', (
      tester,
    ) async {
      final notifier = NotificationsNotifier();
      await notifier.reconcileAnnouncements(announcementCards([_info()]));

      await _pumpApp(
        tester,
        const Scaffold(body: NotificationBell()),
        notifier: notifier,
      );

      expect(find.text('1'), findsOneWidget);
    });
  });
}
