import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/rate/providers/rating_providers.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

/// One card of the My Trades list (handoff 11a): the persisted trade, its
/// live status, and what that makes of it.
@immutable
class TradeRow {
  const TradeRow({
    required this.orderId,
    required this.status,
    required this.state,
    required this.isSelling,
    required this.isMaker,
    required this.fiatAmount,
    required this.fiatAmountMin,
    required this.fiatAmountMax,
    required this.fiatCode,
    required this.premium,
    required this.amountSats,
    required this.paymentMethod,
    required this.startedAt,
    required this.peerHandle,
  });

  final String orderId;

  /// Live when the order is still moving, else the persisted status.
  final rust_types.OrderStatus status;
  final TradeRowState state;
  final bool isSelling;

  /// The user published the order: a pending one opens the order screen.
  final bool isMaker;
  final double? fiatAmount;
  final double? fiatAmountMin;
  final double? fiatAmountMax;
  final String fiatCode;
  final double premium;

  /// Fixed by the daemon once the trade is priced; null or 0 before.
  final int? amountSats;
  final String paymentMethod;

  /// Unix seconds; the activity the groups sort by.
  final int startedAt;

  /// Null until the counterparty is known (the trade has not gone active)
  /// or while its pseudonym resolves.
  final String? peerHandle;
}

const _terminal = {
  rust_types.OrderStatus.success,
  rust_types.OrderStatus.settledByAdmin,
  rust_types.OrderStatus.completedByAdmin,
  rust_types.OrderStatus.canceled,
  rust_types.OrderStatus.expired,
  rust_types.OrderStatus.cooperativelyCanceled,
  rust_types.OrderStatus.canceledByAdmin,
};

const _successes = {
  rust_types.OrderStatus.success,
  rust_types.OrderStatus.settledByAdmin,
  rust_types.OrderStatus.completedByAdmin,
};

/// Every trade of the user as a [TradeRow], unfiltered.
///
/// Only a trade that can still change watches [tradeStatusProvider] — a
/// terminal one would open a watcher per closed trade for nothing.
final tradeRowsProvider = Provider<AsyncValue<List<TradeRow>>>((ref) {
  final canRate = !ref.watch(privacyModeProvider);
  return ref.watch(rawTradesProvider).whenData((trades) {
    return [for (final trade in trades) _row(ref, trade, canRate: canRate)];
  });
});

TradeRow _row(Ref ref, rust_types.TradeInfo trade, {required bool canRate}) {
  final order = trade.order;
  final persisted = order.status;
  final status =
      _terminal.contains(persisted)
          ? persisted
          : ref.watch(tradeStatusProvider(order.id)).valueOrNull ?? persisted;
  final ratedByMe =
      trade.ratedAt != null ||
      (_successes.contains(status) && ref.watch(ratedByMeProvider(order.id)));
  final isSelling = trade.role == rust_types.TradeRole.seller;
  final peer = trade.counterpartyPubkey;
  return TradeRow(
    orderId: order.id,
    status: status,
    state: TradeRowState.of(
      status: status,
      isBuyer: !isSelling,
      ratedByMe: ratedByMe,
      canRate: canRate,
    ),
    isSelling: isSelling,
    isMaker: order.isMine,
    fiatAmount: order.fiatAmount,
    fiatAmountMin: order.fiatAmountMin,
    fiatAmountMax: order.fiatAmountMax,
    fiatCode: order.fiatCode,
    premium: order.premium,
    amountSats: order.amountSats?.toInt(),
    paymentMethod: order.paymentMethod,
    startedAt: platformInt64ToInt(trade.startedAt),
    peerHandle:
        peer.isEmpty
            ? null
            : ref.watch(peerNymProvider(peer)).valueOrNull?.pseudonym,
  );
}

// ── Filter ────────────────────────────────────────────────────────────────────

const kTradeListFilterKey = 'trades_list_filter';

/// The header filter, kept across sessions.
class TradeListFilterNotifier extends StateNotifier<TradeListFilter> {
  TradeListFilterNotifier({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance,
      super(TradeListFilter.all) {
    _load();
  }

  final Future<SharedPreferences> Function() _prefs;
  bool _chosen = false;

  Future<void> _load() async {
    try {
      final prefs = await _prefs();
      // A pick made while the disk was being read is newer than the disk.
      if (!mounted || _chosen) return;
      state = TradeListFilter.fromStored(prefs.getString(kTradeListFilterKey));
    } catch (e) {
      debugPrint('[trades] filter load failed: $e');
    }
  }

  Future<void> select(TradeListFilter filter) async {
    _chosen = true;
    state = filter;
    try {
      final prefs = await _prefs();
      await prefs.setString(kTradeListFilterKey, filter.name);
    } catch (e) {
      // The filter still applies for this session.
      debugPrint('[trades] filter save failed: $e');
    }
  }
}

final tradeListFilterProvider =
    StateNotifierProvider<TradeListFilterNotifier, TradeListFilter>(
      (ref) => TradeListFilterNotifier(),
    );

/// The list as grouped for display, after the filter.
final groupedTradeRowsProvider =
    Provider<AsyncValue<List<TradeRowGroup<TradeRow>>>>((ref) {
      final filter = ref.watch(tradeListFilterProvider);
      return ref
          .watch(tradeRowsProvider)
          .whenData(
            (rows) => groupTradeRows(
              rows.where((r) => filter.matches(r.state)).toList(),
              groupOf: (r) => r.state.group,
              activityOf: (r) => r.startedAt,
            ),
          );
    });

/// Trades whose next step is the user's, whatever the filter: the counter of
/// `Requieren tu acción` and the badge of the trades tab are the same figure.
final needsActionCountProvider = Provider<int>((ref) {
  final rows = ref.watch(tradeRowsProvider).valueOrNull ?? const <TradeRow>[];
  return rows.where((r) => r.state.needsAction).length;
});
