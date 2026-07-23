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

  group('NotificationModel.bondSlashed — stored data is locale-independent', () {
    test('stores stable keys and raw values, not localized labels', () {
      final n = NotificationModel.bondSlashed(
        orderId: 'order-1',
        amountSats: 1000,
        disputeCause: false,
      );

      expect(n.type, NotificationType.bondSlashed);
      expect(n.orderId, 'order-1');
      expect(n.title, isEmpty);
      expect(n.message, isEmpty);
      expect(n.detail?['bondAmountSats'], '1000');
      expect(n.detail?['cause'], 'timeout');
    });

    test('dispute cause is stored as a stable marker', () {
      final n = NotificationModel.bondSlashed(
        orderId: 'order-2',
        amountSats: 500,
        disputeCause: true,
      );
      expect(n.detail?['cause'], 'dispute');
    });

    test('optional fiat and payment method use stable keys', () {
      final n = NotificationModel.bondSlashed(
        orderId: 'order-3',
        amountSats: 250,
        disputeCause: false,
        fiatCode: 'USD',
        fiatAmount: 20,
        paymentMethod: 'SEPA',
      );
      expect(n.detail?['fiatCode'], 'USD');
      expect(n.detail?['fiatAmount'], '20');
      expect(n.detail?['paymentMethod'], 'SEPA');
    });

    test('optional fields are omitted when absent', () {
      final n = NotificationModel.bondSlashed(
        orderId: 'order-4',
        amountSats: 250,
        disputeCause: false,
      );
      expect(n.detail?.containsKey('fiatCode'), isFalse);
      expect(n.detail?.containsKey('paymentMethod'), isFalse);
    });
  });

  group('NotificationModel.bondSlashed — localized at render time', () {
    test('timeout notice resolves localized title, message and detail', () {
      final n = NotificationModel.bondSlashed(
        orderId: 'order-1',
        amountSats: 1000,
        disputeCause: false,
      );

      expect(n.resolvedTitle(l10n), 'Bond slashed');
      expect(n.resolvedMessage(l10n), contains('waiting-state timeout'));
      expect(n.resolvedMessage(l10n), contains('order status is unchanged'));

      final detail = n.resolvedDetail(l10n);
      expect(detail['Cause'], 'Waiting-state timeout');
      expect(detail['Bond amount'], '1000 sats');
      expect(detail['Order'], 'order-1');
    });

    test('dispute notice resolves the dispute copy', () {
      final n = NotificationModel.bondSlashed(
        orderId: 'order-2',
        amountSats: 500,
        disputeCause: true,
      );

      expect(n.resolvedMessage(l10n), contains('dispute resolution'));
      expect(n.resolvedDetail(l10n)['Cause'], 'Dispute resolution');
    });

    test('resolved detail includes fiat and payment method when present', () {
      final n = NotificationModel.bondSlashed(
        orderId: 'order-3',
        amountSats: 250,
        disputeCause: false,
        fiatCode: 'USD',
        fiatAmount: 20,
        paymentMethod: 'SEPA',
      );

      final detail = n.resolvedDetail(l10n);
      expect(detail['Fiat'], '20 USD');
      expect(detail['Payment method'], 'SEPA');
    });
  });
}
