import 'package:mostro/features/home/providers/home_order_providers.dart';

/// Anchor so timestamp-based sort assertions don't depend on the wall clock.
final DateTime kFakeNow = DateTime.utc(2026, 1, 1, 12);

/// Builds a fixed-amount [OrderItem], exposing only the fields filter logic
/// reads. [minutesAgo] controls recency for sort assertions.
OrderItem fakeOrder({
  String id = 'order-1',
  String kind = 'sell',
  double fiatAmount = 100,
  String fiatCode = 'USD',
  String paymentMethod = 'Wire',
  double premium = 0,
  String creatorPubkey = 'pubkey-1',
  double rating = 5.0,
  OrderStatus status = OrderStatus.pending,
  bool isMine = false,
  int minutesAgo = 0,
}) {
  return OrderItem(
    id: id,
    kind: kind,
    fiatAmount: fiatAmount,
    fiatCode: fiatCode,
    paymentMethod: paymentMethod,
    premium: premium,
    creatorPubkey: creatorPubkey,
    createdAt: kFakeNow.subtract(Duration(minutes: minutesAgo)),
    rating: rating,
    status: status,
    isMine: isMine,
  );
}
