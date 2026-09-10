import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/src/rust/api/types.dart';

OrderInfo _info({
  double rating = 0,
  int totalReviews = 0,
  int daysActive = 0,
}) {
  return OrderInfo(
    id: 'order-1',
    kind: OrderKind.sell,
    status: OrderStatus.pending,
    fiatAmount: 100,
    fiatCode: 'USD',
    paymentMethod: 'Wire',
    premium: 1.5,
    creatorPubkey: 'node-pubkey',
    createdAt: 1000,
    isMine: false,
    rating: rating,
    totalReviews: totalReviews,
    daysActive: daysActive,
  );
}

void main() {
  group('OrderItem.fromInfo reputation mapping', () {
    test('maps rating, totalReviews, and daysActive from the bridge', () {
      // Arrange
      final info = _info(rating: 4.9, totalReviews: 47, daysActive: 312);

      // Act
      final item = OrderItem.fromInfo(info);

      // Assert
      expect(item.rating, 4.9);
      expect(item.tradeCount, 47);
      expect(item.daysActive, 312);
    });

    test('keeps zeros for makers with no reputation (full privacy)', () {
      // Arrange
      final info = _info();

      // Act
      final item = OrderItem.fromInfo(info);

      // Assert
      expect(item.rating, 0.0);
      expect(item.tradeCount, 0);
      expect(item.daysActive, 0);
    });
  });
}
