import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/src/rust/api/reputation.dart' as reputation_api;
import 'package:mostro/src/rust/api/types.dart';

/// Reads one trade's rating through the bridge; injectable for tests.
final ratingReaderProvider = Provider<Future<RatingInfo?> Function(String)>(
  (ref) => (tradeId) => reputation_api.getRatingForTrade(tradeId: tradeId),
);

/// The rating held for [tradeId], or `null` when neither side has rated.
///
/// The Rust store is in-memory (ratings live in the daemon's kind 38383 tags,
/// not in the local DB), but the local user's own rating is backed by a durable
/// `rated_at` marker on the trade row (issue #339): on a restart the in-memory
/// store rehydrates from it, so a trade the user already rated still resolves as
/// rated and the rate prompt does not come back.
///
/// Read again whenever the trade is touched (or a resync asks every trade to
/// be): a `rate-received` that a replay brings after the screen already read
/// the trade writes that marker and touches the row, and the step must close
/// under the open screen, not on the next visit.
final tradeRatingProvider = FutureProvider.autoDispose
    .family<RatingInfo?, String>((ref, tradeId) async {
  ref.listen<AsyncValue<TradeTouch>>(tradeTouchProvider, (_, next) {
    final touched = next.valueOrNull?.orderId;
    if (next.hasValue && (touched == null || touched == tradeId)) {
      ref.invalidateSelf();
    }
  });
  return ref.watch(ratingReaderProvider)(tradeId);
});

/// Whether the local user has rated their counterpart on [tradeId].
///
/// `getRatingForTrade` falls back to the counterpart's rating when the local
/// user has not submitted one, so `isMine` is what separates "I rated them"
/// from "they rated me" — only the former resolves the rate prompt.
final ratedByMeProvider =
    Provider.autoDispose.family<bool, String>((ref, tradeId) {
  final rating = ref.watch(tradeRatingProvider(tradeId)).valueOrNull;
  return rating != null && rating.isMine;
});

/// The score the local user gave on a trade, or `null` when they gave none
/// this device knows. A rating rehydrated from the durable `rated_at`
/// marker carries a placeholder score of `0` (the note is not persisted):
/// the step is closed, but "rated with 0" would be made up.
int? myRatingScore(RatingInfo? rating) =>
    rating != null && rating.isMine && rating.score > 0 ? rating.score : null;
