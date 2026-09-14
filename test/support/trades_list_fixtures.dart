import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/rate/providers/rating_providers.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Noon-ish on a Saturday: the fixtures' `startedAt` values read as
/// `hace 1 h`, `hace 13 h`, `ayer` and a weekday against it.
final kTradesNow = DateTime(2026, 9, 12, 15, 30);

int _ago(Duration d) => kTradesNow.subtract(d).millisecondsSinceEpoch ~/ 1000;

/// One trade of the My Trades fixtures, every field the card reads settable.
TradeInfo listTrade({
  required String id,
  required OrderStatus status,
  TradeRole role = TradeRole.seller,
  double? fiat = 55,
  String fiatCode = 'BOB',
  String paymentMethod = 'Mercado Pago',
  Duration ago = const Duration(hours: 1),
  int? amountSats,
  String counterparty = '',
  bool isMine = false,
  int? ratedAt,
}) => TradeInfo(
  id: id,
  order: OrderInfo(
    id: id,
    kind: role == TradeRole.seller ? OrderKind.sell : OrderKind.buy,
    status: status,
    amountSats: amountSats == null ? null : BigInt.from(amountSats),
    fiatAmount: fiat,
    fiatCode: fiatCode,
    paymentMethod: paymentMethod,
    premium: 0,
    creatorPubkey: 'creator-$id',
    createdAt: _ago(ago),
    isMine: isMine,
    rating: 0,
    totalReviews: 0,
    daysActive: 0,
  ),
  role: role,
  counterpartyPubkey: counterparty,
  currentStep: const TradeStep.disputed(),
  tradeKeyIndex: 0,
  startedAt: _ago(ago),
  ratedAt: ratedAt,
);

/// The handoff's 11a case: two trades waiting on the user, one on the
/// counterpart, two closed.
final kHandoffTrades = [
  listTrade(
    id: 'release',
    status: OrderStatus.fiatSent,
    paymentMethod: 'Mercado Pago, Transferencia, Efectivo',
    amountSats: 6900,
    counterparty: 'peer-jaguar',
  ),
  listTrade(
    id: 'pay',
    status: OrderStatus.active,
    role: TradeRole.buyer,
    fiat: 20000,
    fiatCode: 'ARS',
    paymentMethod: 'Transferencia',
    ago: const Duration(hours: 13),
    amountSats: 21450,
    counterparty: 'peer-otter',
  ),
  listTrade(
    id: 'waiting',
    status: OrderStatus.waitingPayment,
    role: TradeRole.buyer,
    fiat: 150,
    fiatCode: 'USD',
    paymentMethod: 'Zelle',
    ago: const Duration(minutes: 20),
  ),
  listTrade(
    id: 'done',
    status: OrderStatus.success,
    role: TradeRole.buyer,
    fiat: 6666,
    fiatCode: 'ARS',
    ago: const Duration(days: 1, hours: 4),
    amountSats: 7120,
    counterparty: 'peer-heron',
    ratedAt: 1,
  ),
  listTrade(
    id: 'cancelled',
    status: OrderStatus.canceled,
    fiat: 300,
    fiatCode: 'VES',
    paymentMethod: 'Pago Móvil',
    ago: const Duration(days: 5),
  ),
];

const _nyms = {
  'peer-jaguar': 'used-jaguar',
  'peer-otter': 'brave-otter',
  'peer-heron': 'quiet-heron',
};

/// Everything the trades tab reads, with no Rust behind it.
List<Override> tradesListOverrides(List<TradeInfo> trades) => [
  rawTradesProvider.overrideWith((ref) async => trades),
  for (final t in trades)
    tradeStatusProvider(
      t.order.id,
    ).overrideWith((ref) => Stream.value(t.order.status)),
  for (final t in trades)
    tradeRatingProvider(t.order.id).overrideWith((ref) async => null),
  for (final entry in _nyms.entries)
    peerNymProvider(entry.key).overrideWith(
      (ref) async =>
          NymIdentity(pseudonym: entry.value, iconIndex: 0, colorHue: 0),
    ),
  // BOB 7,97 per USD at ~115.000 USD per BTC.
  exchangeRateProvider.overrideWith((ref, code) async => 916000.0),
  unreadNotificationCountProvider.overrideWith((ref) => 0),
  backupReminderProvider.overrideWith(
    (ref) => BackupReminderNotifier(initialValue: false),
  ),
];
