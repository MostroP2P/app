import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart'
    show TradeChipKind;
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/shared/utils/reputation_age.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Pure rules of the chat room's two info panels (issue #139): which figures
/// the trade panel shows and where each comes from, and whose reputation the
/// user panel shows. Kept free of widgets so every choice is unit-tested.

/// The figures of the Trade Information panel.
///
/// Each one is taken from the trade row when it has it, else from [OrderItem]
/// the trade header resolves (`chatTradeOrderProvider`). The row comes first
/// because it holds the amount a take priced out of a range, where the book
/// keeps the whole range (MostroP2P/app#620), as on the trade screen.
class TradePanelFacts {
  const TradePanelFacts({
    required this.fiatAmount,
    required this.fiatAmountMin,
    required this.fiatAmountMax,
    required this.fiatCode,
    required this.sats,
    required this.paymentMethod,
    required this.createdAt,
  });

  final double? fiatAmount;
  final double? fiatAmountMin;
  final double? fiatAmountMax;
  final String fiatCode;

  /// `null` until the order is priced: a market order carries `0` sats until
  /// a take resolves them, and `0` is not an amount to show.
  final int? sats;

  /// `null` when the order names none.
  final String? paymentMethod;
  final DateTime createdAt;

  /// Whether there is a fiat amount to show: a fixed one, or a range.
  bool get hasFiat =>
      (fiatAmount != null && fiatAmount! > 0) ||
      (fiatAmountMin != null && fiatAmountMax != null);

  /// `null` when neither the row nor the book entry is known yet.
  static TradePanelFacts? of(TradeInfo? trade, OrderItem? order) {
    final row = trade?.order;
    if (row != null) {
      return TradePanelFacts(
        fiatAmount: row.fiatAmount,
        fiatAmountMin: row.fiatAmountMin,
        fiatAmountMax: row.fiatAmountMax,
        fiatCode: row.fiatCode,
        sats: _positive(row.amountSats) ?? _positive(order?.amountSats),
        paymentMethod:
            _nonEmpty(row.paymentMethod) ?? _nonEmpty(order?.paymentMethod),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          platformInt64ToInt(row.createdAt) * 1000,
        ),
      );
    }
    if (order == null) return null;
    return TradePanelFacts(
      fiatAmount: order.fiatAmount,
      fiatAmountMin: order.fiatAmountMin,
      fiatAmountMax: order.fiatAmountMax,
      fiatCode: order.fiatCode,
      sats: _positive(order.amountSats),
      paymentMethod: _nonEmpty(order.paymentMethod),
      createdAt: order.createdAt,
    );
  }

  static int? _positive(BigInt? sats) =>
      sats == null || sats <= BigInt.zero ? null : sats.toInt();

  static String? _nonEmpty(String? text) {
    final trimmed = text?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// The status the panel shows: the same one the trade header shows (the
/// live status first, then the order it resolved), then the trade row's own
/// when the header has no order to show.
OrderStatus? tradePanelStatus({
  required OrderStatus? live,
  required OrderItem? order,
  required TradeInfo? trade,
}) => live ?? order?.status ?? trade?.order.status;

/// The colour family of a status chip, as the trades list gives it: amber
/// while the trade runs, neutral once it closed, red for a dispute.
TradeChipKind tradePanelChipKind(TradeStatusFilter status) => switch (status) {
  TradeStatusFilter.dispute => TradeChipKind.dispute,
  TradeStatusFilter.success ||
  TradeStatusFilter.canceled ||
  TradeStatusFilter.all => TradeChipKind.done,
  TradeStatusFilter.pending ||
  TradeStatusFilter.waitingInvoice ||
  TradeStatusFilter.waitingPayment ||
  TradeStatusFilter.active ||
  TradeStatusFilter.fiatSent ||
  TradeStatusFilter.payoutPending => TradeChipKind.waiting,
};

/// The counterparty's public reputation, as the app already holds it.
typedef PeerReputation = ({double rating, int reviews, int days});

/// Whose reputation the user panel shows, from what the app already has:
///
/// - the taker's snapshot the daemon sends the maker (`TradeInfo.peerRating`,
///   issue #305), whenever the row carries it;
/// - otherwise, for a taker, the maker's `rating` tag on the order the trade
///   header resolves ([order] is not the user's own, so its maker is the
///   peer).
///
/// `null` when neither is known: a maker whose taker shared no reputation
/// (full privacy), or before the order resolves. The maker's own rating tag
/// is never shown as the peer's.
PeerReputation? peerReputation(TradeInfo? trade, OrderItem? order) {
  final snapshot = trade?.peerRating;
  if (trade != null && snapshot != null) {
    return (
      rating: snapshot,
      reviews: trade.peerReviews ?? 0,
      days: trade.peerDaysOnMostro,
    );
  }
  final isMine = trade?.order.isMine ?? order?.isMine ?? true;
  if (order == null || isMine) return null;
  return (
    rating: order.rating,
    reviews: order.tradeCount,
    days: order.makerDaysOnMostro,
  );
}
