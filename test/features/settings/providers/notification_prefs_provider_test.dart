import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/providers/notification_prefs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('NotificationPrefs', () {
    test('an unwritten preference reads as on', () {
      const prefs = NotificationPrefs.allEnabled();
      expect(prefs.enabledCount, 4);
      expect(prefs.total, 4);
      expect(prefs.allDisabled, isFalse);
    });

    test('allDisabled only when every event is off', () {
      var prefs = const NotificationPrefs.allEnabled();
      for (final event in NotificationEvent.values) {
        prefs = prefs.withEvent(event, false);
      }
      expect(prefs.enabledCount, 0);
      expect(prefs.allDisabled, isTrue);
    });

    test('withEvent returns a new value rather than mutating', () {
      const before = NotificationPrefs.allEnabled();
      final after = before.withEvent(NotificationEvent.newMessages, false);
      expect(before.isEnabled(NotificationEvent.newMessages), isTrue);
      expect(after.isEnabled(NotificationEvent.newMessages), isFalse);
      expect(after.enabledCount, 3);
    });
  });

  group('NotificationPrefsNotifier', () {
    test('loads what was persisted', () async {
      SharedPreferences.setMockInitialValues({
        NotificationEvent.paymentAlerts.prefsKey: false,
      });
      final notifier = NotificationPrefsNotifier();
      // The load is async; wait for it before reading.
      await Future<void>.delayed(Duration.zero);

      expect(
        notifier.state.isEnabled(NotificationEvent.paymentAlerts),
        isFalse,
      );
      expect(notifier.state.isEnabled(NotificationEvent.newMessages), isTrue);
      expect(notifier.state.enabledCount, 3);
      notifier.dispose();
    });

    test('setEvent persists under the key the push service gates on', () async {
      final notifier = NotificationPrefsNotifier();
      await Future<void>.delayed(Duration.zero);

      final ok = await notifier.setEvent(
        NotificationEvent.disputeUpdates,
        false,
      );

      expect(ok, isTrue);
      final prefs = await SharedPreferences.getInstance();
      // The literal key, because push_notification_service.dart reads it by
      // name — a rename on one side only silently stops delivery.
      expect(prefs.getBool('notify_disputes'), isFalse);
      notifier.dispose();
    });

    test('the four keys are the ones the push service reads', () {
      expect(
        NotificationEvent.values.map((e) => e.prefsKey),
        const [
          'notify_trade_updates',
          'notify_new_messages',
          'notify_payments',
          'notify_disputes',
        ],
      );
    });
  });
}
