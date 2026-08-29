import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/reputation.dart' as reputation_api;
import 'package:mostro/src/rust/api/types.dart';

/// The rating held for [tradeId], or `null` when neither side has rated.
///
/// The Rust store is in-memory by design (ratings live in the daemon's kind
/// 38383 tags, not in the local DB), so this resolves to `null` again after a
/// restart and the rate prompt comes back.
final tradeRatingProvider = FutureProvider.autoDispose
    .family<RatingInfo?, String>((ref, tradeId) async {
  return reputation_api.getRatingForTrade(tradeId: tradeId);
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
