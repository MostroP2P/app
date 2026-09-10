import 'dart:math';

import 'package:flutter/foundation.dart';

/// Expresses a Mostro node's sats order limits in the fiat currency the user
/// types in, so a market-price order can be checked before it is submitted
/// (#337).
///
/// A market-price order carries no sats amount: the daemon derives one from
/// the fiat amount at its own rate and rejects the order with
/// `OutOfRangeSatsAmount` when the result falls outside
/// `min_order_amount`/`max_order_amount`. Everything here mirrors that
/// derivation so the client reaches the same verdict beforehand.

/// Sats per BTC.
const int _satsPerBtc = 100000000;

/// The value every conversion below saturates at: every sat that will ever
/// exist.
///
/// `truncate`, `ceil` and `floor` throw on a non-finite double and are
/// undefined beyond the signed 64-bit range, and a large enough amount or rate
/// overflows the multiplication into infinity on its way there. Saturating
/// keeps such an input on the "out of range" side of every comparison here —
/// the verdict it deserves — instead of crashing the form.
const int _saturationCap = 21000000 * _satsPerBtc;

/// [value] rounded by [rounder], saturating at [_saturationCap].
int _saturate(double value, int Function(double) rounder) =>
    value >= _saturationCap ? _saturationCap : rounder(value);

/// The fiat amount the daemon will actually price, given the [fiat] the user
/// typed.
///
/// `new_order` casts every fiat amount to `i64` before it reaches the wire
/// (`rust/src/mostro/actions.rs`), so a decimal is truncated there and the
/// daemon never sees the fraction. Pricing the untruncated value here would
/// accept an amount the daemon then prices lower and rejects — the exact
/// surprise this check exists to remove.
double wireFiatAmount(double fiat) => fiat.truncateToDouble();

/// The sats amount the daemon will price [fiat] at, given [rate] (the price of
/// one BTC in that fiat).
///
/// Truncates rather than rounds, because that is what the daemon does:
/// `(fiat_amount / price * 1E8) as i64` (`mostro/src/app/order.rs`). Rounding
/// up would let the client accept an amount one sat below the node's minimum
/// and still see it rejected. Pass [fiat] through [wireFiatAmount] first: this
/// mirrors the daemon's arithmetic, not the wire's own truncation.
///
/// Returns 0 for a conversion that is not a number, which every caller reads
/// as below any minimum.
int satsFromFiat(double fiat, double rate) {
  final sats = fiat / rate * _satsPerBtc;
  if (sats.isNaN) return 0;
  return _saturate(sats, (v) => v.truncate());
}

/// Whether [rate] can price an order: a real, positive price for one BTC.
bool _isUsableRate(double? rate) =>
    rate != null && rate.isFinite && rate > 0;

/// A node's sats limits converted to whole fiat units.
@immutable
class FiatAmountLimits {
  const FiatAmountLimits({required this.minFiat, required this.maxFiat});

  final int minFiat;
  final int maxFiat;

  /// Whether the range is worth showing. False when the node's whole valid
  /// range collapses below one unit of fiat, leaving no enterable whole
  /// number; callers then fall back to the raw sats bounds.
  bool get isDisplayable => minFiat >= 1 && maxFiat >= minFiat;
}

/// Converts the node's sats limits to whole-fiat bounds at [rate].
///
/// The minimum rounds up and the maximum rounds down, so every whole number
/// inside the returned range converts back to a sats amount inside the node's
/// real range — a bound shown to the user is never itself rejected. The
/// minimum is floored at 1 because the amount field takes whole numbers only.
FiatAmountLimits fiatAmountLimits({
  required int minSats,
  required int maxSats,
  required double rate,
}) {
  if (!_isUsableRate(rate)) {
    return const FiatAmountLimits(minFiat: 0, maxFiat: 0);
  }
  return FiatAmountLimits(
    minFiat: max(1, _saturate(minSats / _satsPerBtc * rate, (v) => v.ceil())),
    maxFiat: _saturate(maxSats / _satsPerBtc * rate, (v) => v.floor()),
  );
}

/// Returns the node's accepted range — in sats, and converted to fiat — when
/// the entered market-price [fiatStr] prices outside it, otherwise null.
///
/// Pure and testable, like `satsOutOfNodeRange` in `add_order_screen.dart`,
/// its fixed-sats counterpart. Fails open on everything it cannot
/// judge: no rate ([rate] null, non-finite or non-positive, i.e. the node
/// publishes none), a node advertising only one bound, or an amount that is
/// not a finite positive number. In those cases the daemon stays the only
/// authority, exactly as it was before this check existed.
({int minSats, int maxSats, FiatAmountLimits limits})? fiatOutOfNodeRange(
  String fiatStr,
  int? minOrder,
  int? maxOrder,
  double? rate,
) {
  if (minOrder == null || maxOrder == null) return null;
  if (!_isUsableRate(rate)) return null;
  final usableRate = rate!;
  final fiat = double.tryParse(fiatStr.trim());
  // `Infinity` and `NaN` parse as doubles and would pass a bare positivity
  // check; the form rejects them outright, so there is nothing to warn about.
  if (fiat == null || !fiat.isFinite || fiat <= 0) return null;

  final sats = satsFromFiat(wireFiatAmount(fiat), usableRate);
  if (sats >= minOrder && sats <= maxOrder) return null;

  return (
    minSats: minOrder,
    maxSats: maxOrder,
    limits: fiatAmountLimits(
      minSats: minOrder,
      maxSats: maxOrder,
      rate: usableRate,
    ),
  );
}
