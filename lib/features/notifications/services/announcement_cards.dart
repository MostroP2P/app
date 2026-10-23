/// Project announcements as notification cards
/// (specs/006-announcement-channel §6.2).
///
/// Rust is the authority: it verifies, caches, sweeps and holds the read and
/// dismissed flags, and hands Dart the whole list every time it changes. This
/// turns each snapshot into the cards the list should show and lets
/// [NotificationsNotifier.reconcileAnnouncements] make the store match — a new
/// address appears unread, a correction replaces its card unread, an address
/// Rust no longer lists loses its card. Nothing here decides anything about
/// an announcement beyond what §3.4 says of a dismissed one.
library;

import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Whether a cached announcement still has a card: a dismissed `critical`
/// stays listed, read, until it expires; the other levels leave on dismiss
/// (§3.4).
bool announcementListed(AnnouncementInfo info) =>
    !info.dismissed || info.severity == AnnouncementSeverity.critical;

/// The cards a snapshot of the cache should show.
List<NotificationModel> announcementCards(List<AnnouncementInfo> snapshot) => [
  for (final info in snapshot)
    if (announcementListed(info)) NotificationModel.announcement(info),
];

/// Feeds Rust's snapshots into the notifications store.
class AnnouncementCards {
  AnnouncementCards({required this.notifications});

  final NotificationsNotifier Function() notifications;

  Future<void> onChanged(List<AnnouncementInfo> snapshot) =>
      notifications().reconcileAnnouncements(announcementCards(snapshot));
}
