import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/widgets/notification_card.dart';

import '../../support/golden_harness.dart';

/// Fixed clock so the card's "Xm ago" label is deterministic.
final _now = DateTime.utc(2026, 1, 1, 12);

NotificationModel _notification({
  required String id,
  required Duration age,
  required bool isRead,
}) {
  return NotificationModel(
    id: id,
    type: NotificationType.orderTaken,
    title: 'Order taken',
    message: 'Your order has been taken by a counterpart.',
    timestamp: _now.subtract(age),
    isRead: isRead,
    detail: const {'Order': 'abc123', 'Amount': '50000 sats'},
  );
}

/// Unread + read cards stacked, keyed so the golden captures just the cards.
Widget _gallery() {
  return Padding(
    key: const ValueKey('notification-gallery'),
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NotificationCard(
          notification: _notification(
            id: 'unread',
            age: const Duration(minutes: 5),
            isRead: false,
          ),
          onMarkRead: () {},
          onDelete: () {},
        ),
        const SizedBox(height: 8),
        NotificationCard(
          notification: _notification(
            id: 'read',
            age: const Duration(hours: 3),
            isRead: true,
          ),
          onMarkRead: () {},
          onDelete: () {},
        ),
      ],
    ),
  );
}

void main() {
  group('NotificationCard goldens', () {
    testWidgets('dark theme', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        await pumpForGolden(tester, _gallery(),
            brightness: Brightness.dark, width: 380);
        await expectLater(
          find.byKey(const ValueKey('notification-gallery')),
          matchesGoldenFile('goldens/notification_card_dark.png'),
        );
      });
    });

    testWidgets('light theme', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        await pumpForGolden(tester, _gallery(),
            brightness: Brightness.light, width: 380);
        await expectLater(
          find.byKey(const ValueKey('notification-gallery')),
          matchesGoldenFile('goldens/notification_card_light.png'),
        );
      });
    });
  });
}
