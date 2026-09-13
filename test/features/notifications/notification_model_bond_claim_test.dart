import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('NotificationModel.bondClaim (docs/ANTI_ABUSE_BOND.md §8.5)', () {
    test(
      'a claim to act on: stable data, localized copy, id per re-prompt',
      () {
        final n = NotificationModel.bondClaim(
          orderId: 'order-1',
          amountSats: 1500,
          completed: false,
          updatedAt: 600,
        );
        expect(n.type, NotificationType.bondClaim);
        expect(n.id, 'bond-claim-order-1-pending-600');
        expect(n.orderId, 'order-1');
        expect(n.title, isEmpty);
        expect(n.detail?['bondAmountSats'], '1500');
        expect(n.resolvedTitle(l10n), 'Bond payout to claim');
        expect(n.resolvedMessage(l10n), contains('claim 1500 sats'));
        // A re-prompt is a new record; the cadence retry is not.
        final again = NotificationModel.bondClaim(
          orderId: 'order-1',
          amountSats: 1500,
          completed: false,
          updatedAt: 900,
        );
        expect(again.id, isNot(n.id));
      },
    );

    test('a payout received: one record per order', () {
      final n = NotificationModel.bondClaim(
        orderId: 'order-1',
        amountSats: 1500,
        completed: true,
        updatedAt: 999,
      );
      expect(n.id, 'bond-claim-order-1-completed');
      expect(n.resolvedTitle(l10n), 'Bond payout received');
      expect(n.resolvedMessage(l10n), 'Bond payout of 1500 sats received.');
    });

    test('survives the JSON round trip', () {
      final n = NotificationModel.bondClaim(
        orderId: 'order-1',
        amountSats: 1500,
        completed: false,
        updatedAt: 600,
      );
      final back = NotificationModel.fromJson(n.toJson());
      expect(back.type, NotificationType.bondClaim);
      expect(back.resolvedMessage(l10n), n.resolvedMessage(l10n));
    });
  });
}
