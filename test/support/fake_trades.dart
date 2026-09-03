import 'package:mostro/src/rust/api/types.dart';

/// Builds a [TradeInfo] exposing only the fields the trades-list mapping reads.
/// [startedAt] is the newest-first sort key. `currentStep` is unread by the
/// mapping, so it takes an arbitrary value.
TradeInfo fakeTrade({
  String id = 'trade-1',
  OrderStatus status = OrderStatus.active,
  TradeRole role = TradeRole.buyer,
  String fiatCode = 'USD',
  String paymentMethod = 'Wire',
  bool isMine = false,
  int startedAt = 1000,
  BigInt? amountSats,
  String? holdInvoice,
  double? peerRating,
  int? peerReviews,
  int? peerDays,
}) {
  final order = OrderInfo(
    id: 'order-$id',
    kind: OrderKind.sell,
    status: status,
    amountSats: amountSats,
    fiatAmount: 100,
    fiatCode: fiatCode,
    paymentMethod: paymentMethod,
    premium: 0,
    creatorPubkey: 'pubkey-$id',
    createdAt: startedAt,
    isMine: isMine,
    rating: 0,
    totalReviews: 0,
    daysActive: 0,
  );

  return TradeInfo(
    id: id,
    order: order,
    role: role,
    counterpartyPubkey: 'counterparty-$id',
    currentStep: const TradeStep.disputed(),
    tradeKeyIndex: 0,
    startedAt: startedAt,
    holdInvoice: holdInvoice,
    peerRating: peerRating,
    peerReviews: peerReviews,
    peerDays: peerDays,
  );
}
