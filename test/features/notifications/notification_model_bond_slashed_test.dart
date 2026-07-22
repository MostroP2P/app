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

  group('NotificationModel.bondSlashed', () {
    test('timeout cause is reflected in message and detail', () {
      final n = NotificationModel.bondSlashed(
        l10n: l10n,
        orderId: 'order-1',
        amountSats: 1000,
        disputeCause: false,
      );

      expect(n.type, NotificationType.bondSlashed);
      expect(n.orderId, 'order-1');
      expect(n.message, contains('waiting-state timeout'));
      expect(n.message, contains('order status is unchanged'));
      expect(n.detail?['Cause'], 'Waiting-state timeout');
      expect(n.detail?['Bond amount'], '1000 sats');
    });

    test('dispute cause is reflected in message and detail', () {
      final n = NotificationModel.bondSlashed(
        l10n: l10n,
        orderId: 'order-2',
        amountSats: 500,
        disputeCause: true,
      );

      expect(n.message, contains('dispute resolution'));
      expect(n.detail?['Cause'], 'Dispute resolution');
    });

    test('optional fiat and payment method are included when provided', () {
      final n = NotificationModel.bondSlashed(
        l10n: l10n,
        orderId: 'order-3',
        amountSats: 250,
        disputeCause: false,
        fiatCode: 'USD',
        fiatAmount: 20,
        paymentMethod: 'SEPA',
      );

      expect(n.detail?['Fiat'], '20 USD');
      expect(n.detail?['Payment method'], 'SEPA');
    });

    test('optional fields are omitted when absent', () {
      final n = NotificationModel.bondSlashed(
        l10n: l10n,
        orderId: 'order-4',
        amountSats: 250,
        disputeCause: false,
      );

      expect(n.detail?.containsKey('Fiat'), isFalse);
      expect(n.detail?.containsKey('Payment method'), isFalse);
    });
  });
}
