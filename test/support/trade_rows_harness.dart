import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/rate/providers/rating_providers.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/src/rust/api/types.dart';

import 'provider_harness.dart';

/// A container whose trades are [trades], each live status taken from
/// [live] (falling back to the persisted one), nobody rated, and every
/// counterparty named `peer`. Call from inside a `test(...)` body.
ProviderContainer tradeRowsContainer(
  List<TradeInfo> trades, {
  Map<String, OrderStatus> live = const {},
  List<BondClaim> claims = const [],
}) => createContainer(
  overrides: [
    // A list of its own on every read, as the bridge returns: a test that
    // changes [trades] then sees the read before and the one after apart.
    rawTradesProvider.overrideWith((ref) async => List.of(trades)),
    bondClaimsProvider.overrideWith((ref) async => claims),
    for (final t in trades)
      tradeStatusProvider(
        t.order.id,
      ).overrideWith((ref) => Stream.value(live[t.order.id] ?? t.order.status)),
    for (final t in trades)
      tradeRatingProvider(t.order.id).overrideWith((ref) async => null),
    for (final t in trades)
      peerNymProvider(t.counterpartyPubkey).overrideWith(
        (ref) async =>
            const NymIdentity(pseudonym: 'peer', iconIndex: 0, colorHue: 0),
      ),
  ],
);

/// The [tradeRowsProvider] rows of [container], once the trades, their live
/// statuses and the pseudonyms have loaded.
Future<List<TradeRow>> loadTradeRows(ProviderContainer container) async {
  // Subscribe first, as a screen would: the live status and the pseudonym
  // are only fetched once something listens to the rows.
  container.listen(tradeRowsProvider, (_, _) {});
  await container.read(rawTradesProvider.future);
  await pumpEventQueue();
  return container.read(tradeRowsProvider).value!;
}
