import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:mostro/features/order/models/order_detail_rules.dart'
    show estimateSats;
import 'package:mostro/features/trades/models/trade_status.dart';
import 'package:mostro/features/trades/models/trade_view.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

/// Pure rules of the My Trades list (handoff 11a): which group a trade sits
/// in, what its one chip says, and which action the row promises. Kept free
/// of widgets so every mapping is unit-tested.

/// The list groups by what a trade asks of the user, never by date.
enum TradeGroup { needsAction, inProgress, closed }

/// The chip's colour family.
enum TradeChipKind { action, waiting, done, dispute }

/// The chip's copy. One per row — the role chip is gone.
enum TradeChipLabel {
  yourTurn,
  published,
  inProgress,
  waitingInvoice,
  waitingPayment,
  waitingSats,
  dispute,
  completed,
  cancelled,
  expired,
}

/// The lime verb at the right of a row that needs the user. Each one names
/// the trade screen's primary button it opens (handoff 8).
enum TradeRowVerb {
  none,
  addInvoice,
  payBond,
  payInvoice,
  sendPayment,
  releaseSats,
  rate,
}

@immutable
class TradeRowState {
  const TradeRowState({
    required this.group,
    required this.chip,
    required this.verb,
  });

  final TradeGroup group;
  final TradeChipLabel chip;
  final TradeRowVerb verb;

  bool get needsAction => group == TradeGroup.needsAction;

  TradeChipKind get chipKind => switch (chip) {
    TradeChipLabel.yourTurn => TradeChipKind.action,
    TradeChipLabel.dispute => TradeChipKind.dispute,
    TradeChipLabel.completed ||
    TradeChipLabel.cancelled ||
    TradeChipLabel.expired => TradeChipKind.done,
    _ => TradeChipKind.waiting,
  };

  /// Derived from [TradeView.of], the trade screen's own mapping, so the
  /// list, the screen and the tab badge cannot disagree about whose turn it
  /// is. [ratedByMe] overlays the local rating the protocol does not carry
  /// (#327); [canRate] is false in privacy mode.
  factory TradeRowState.of({
    required OrderStatus status,
    required bool isBuyer,
    required bool ratedByMe,
    required bool canRate,
  }) {
    var trade = tradeStatusFromOrderStatus(status);
    if (trade == TradeStatus.pendingRating && ratedByMe) {
      trade = TradeStatus.rated;
    }
    final view = TradeView.of(
      status: trade,
      isBuyer: isBuyer,
      canRate: canRate,
    );

    final verb = switch (view.primary) {
      TradePrimaryAction.addInvoice => TradeRowVerb.addInvoice,
      TradePrimaryAction.payBond => TradeRowVerb.payBond,
      TradePrimaryAction.payHoldInvoice => TradeRowVerb.payInvoice,
      TradePrimaryAction.fiatSent => TradeRowVerb.sendPayment,
      TradePrimaryAction.release => TradeRowVerb.releaseSats,
      TradePrimaryAction.sendRating => TradeRowVerb.rate,
      // Viewing a dispute and closing a finished trade are navigation, not a
      // step the user owes.
      TradePrimaryAction.viewDispute ||
      TradePrimaryAction.close ||
      TradePrimaryAction.none => TradeRowVerb.none,
    };
    if (verb != TradeRowVerb.none) {
      return TradeRowState(
        group: TradeGroup.needsAction,
        chip: TradeChipLabel.yourTurn,
        verb: verb,
      );
    }

    const inProgress = TradeGroup.inProgress;
    const closed = TradeGroup.closed;
    final (group, chip) = switch (trade) {
      TradeStatus.pending => (inProgress, TradeChipLabel.published),
      // The seller waits for the buyer's invoice.
      TradeStatus.waitingInvoice => (inProgress, TradeChipLabel.waitingInvoice),
      // The buyer waits for the seller to lock the sats.
      TradeStatus.waitingPayment => (inProgress, TradeChipLabel.waitingPayment),
      // `waitingBond` never reaches here: it always carries the pay-bond
      // verb above (docs/ANTI_ABUSE_BOND.md §6.1).
      TradeStatus.loading ||
      TradeStatus.inProgress ||
      TradeStatus.waitingBond => (inProgress, TradeChipLabel.inProgress),
      // The seller waits for the fiat.
      TradeStatus.active => (inProgress, TradeChipLabel.waitingPayment),
      TradeStatus.fiatSent ||
      TradeStatus.payoutPending => (inProgress, TradeChipLabel.waitingSats),
      TradeStatus.disputed => (inProgress, TradeChipLabel.dispute),
      TradeStatus.pendingRating ||
      TradeStatus.completed ||
      TradeStatus.rated => (closed, TradeChipLabel.completed),
      TradeStatus.cancelled =>
        status == OrderStatus.expired
            ? (closed, TradeChipLabel.expired)
            : (closed, TradeChipLabel.cancelled),
    };
    return TradeRowState(group: group, chip: chip, verb: TradeRowVerb.none);
  }
}

/// One group of rows, in display order.
@immutable
class TradeRowGroup<T> {
  const TradeRowGroup(this.group, this.rows);

  final TradeGroup group;
  final List<T> rows;
}

/// Rows grouped `Requieren tu acción` → `En curso` → `Cerradas`, each sorted
/// by most recent activity. A group with no rows is left out entirely.
List<TradeRowGroup<T>> groupTradeRows<T>(
  List<T> rows, {
  required TradeGroup Function(T) groupOf,
  required int Function(T) activityOf,
}) => [
  for (final group in TradeGroup.values)
    if (rows.where((r) => groupOf(r) == group).toList() case final inGroup
        when inGroup.isNotEmpty)
      TradeRowGroup(
        group,
        inGroup..sort((a, b) => activityOf(b).compareTo(activityOf(a))),
      ),
];

/// The header filter: the value alone (`Todas`, `Activas`…), persisted.
enum TradeListFilter {
  all,
  active,
  completed,
  cancelled;

  bool matches(TradeRowState row) => switch (this) {
    TradeListFilter.all => true,
    TradeListFilter.active => row.group != TradeGroup.closed,
    TradeListFilter.completed => row.chip == TradeChipLabel.completed,
    TradeListFilter.cancelled =>
      row.chip == TradeChipLabel.cancelled ||
          row.chip == TradeChipLabel.expired,
  };

  static TradeListFilter fromStored(String? name) =>
      values.where((f) => f.name == name).firstOrNull ?? TradeListFilter.all;
}

// ── Sats ──────────────────────────────────────────────────────────────────────

enum SatsFigureKind { exact, estimate, none }

/// The sats column: the amount the daemon fixed (no `≈`), an estimate from
/// the rate while it is not fixed (`≈`), or `—` for a cancelled trade, whose
/// sats never moved.
({SatsFigureKind kind, int? sats}) satsFigure({
  required OrderStatus status,
  required int? amountSats,
  required double? fiat,
  required double? rate,
  required double premium,
}) {
  const none = (kind: SatsFigureKind.none, sats: null);
  if (tradeStatusFromOrderStatus(status) == TradeStatus.cancelled) return none;
  if (amountSats != null && amountSats > 0) {
    return (kind: SatsFigureKind.exact, sats: amountSats);
  }
  if (fiat == null) return none;
  final estimate = estimateSats(fiat: fiat, rate: rate, premium: premium);
  return estimate == null
      ? none
      : (kind: SatsFigureKind.estimate, sats: estimate);
}

// ── Time ──────────────────────────────────────────────────────────────────────

enum RelativeTimeKind { now, minutes, hours, yesterday, weekday, date }

/// `hace 1 h`, `ayer`, `lun`, `12 sep` — resolved to copy by the widget.
@immutable
class RelativeTime {
  const RelativeTime.now() : kind = RelativeTimeKind.now, count = 0, at = null;
  const RelativeTime.minutes(this.count)
    : kind = RelativeTimeKind.minutes,
      at = null;
  const RelativeTime.hours(this.count)
    : kind = RelativeTimeKind.hours,
      at = null;
  const RelativeTime.yesterday()
    : kind = RelativeTimeKind.yesterday,
      count = 0,
      at = null;
  const RelativeTime.weekday(DateTime this.at)
    : kind = RelativeTimeKind.weekday,
      count = 0;
  const RelativeTime.date(DateTime this.at)
    : kind = RelativeTimeKind.date,
      count = 0;

  final RelativeTimeKind kind;
  final int count;
  final DateTime? at;

  @override
  bool operator ==(Object other) =>
      other is RelativeTime &&
      other.kind == kind &&
      other.count == count &&
      other.at == at;

  @override
  int get hashCode => Object.hash(kind, count, at);

  @override
  String toString() => 'RelativeTime(${kind.name}, $count, $at)';
}

/// Always in the past, with a preposition in the copy: `1h` alone does not
/// say whether it is due or gone.
RelativeTime relativeTime(DateTime then, {required DateTime now}) {
  final diff = now.difference(then);
  if (diff.inMinutes < 1) return const RelativeTime.now();
  if (diff.inMinutes < 60) return RelativeTime.minutes(diff.inMinutes);
  if (diff.inHours < 24) return RelativeTime.hours(diff.inHours);
  // Civil dates in UTC: two local midnights across a spring-forward change
  // are 23 h apart, which `inDays` would read as the same day.
  final today = DateTime.utc(now.year, now.month, now.day);
  final day = DateTime.utc(then.year, then.month, then.day);
  final days = today.difference(day).inDays;
  if (days == 1) return const RelativeTime.yesterday();
  if (days < 7) return RelativeTime.weekday(then);
  return RelativeTime.date(then);
}

/// `Mercado Pago`, or `Mercado Pago +2` for several.
String paymentMethodLabel(String paymentMethod) {
  final all = paymentMethod
      .split(',')
      .map((m) => m.trim())
      .where((m) => m.isNotEmpty)
      .toList(growable: false);
  if (all.isEmpty) return '';
  return all.length == 1 ? all.single : '${all.first} +${all.length - 1}';
}

/// The amount of a card: `966`, `1.250,50` or a range `100 – 500`, with the
/// locale's separators. `—` when the order carries no amount.
String formatFiatAmount({
  required double? amount,
  required double? min,
  required double? max,
  required String locale,
}) {
  String fmt(double v) => NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: v == v.truncateToDouble() ? 0 : 2,
  ).format(v);
  if (amount != null && amount > 0) return fmt(amount);
  if (min != null && max != null) return '${fmt(min)} – ${fmt(max)}';
  return '—';
}

/// Whole sats with the locale's thousands separator: `6.900` in `es`.
String formatSatsCount(int sats, String locale) =>
    NumberFormat.decimalPattern(locale).format(sats);
