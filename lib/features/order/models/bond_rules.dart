/// Pure rules of the pay-bond screen (`design_handoff_deposito_anti_abuso`,
/// 14a · default, 14b · explanation expanded). No Flutter here so every rule
/// is unit-testable; the widgets only render what these return.
library;

import 'package:intl/intl.dart';

import 'package:mostro/src/rust/api/types.dart'
    show OrderKind, TradeRole, TradeUpdateReason;

/// What the bond is worth in the order's fiat at [rate] (fiat per BTC), or
/// null without a usable rate. For the hero's context line only — the
/// daemon never charges fiat.
double? bondFiatEquivalent({required int sats, required double? rate}) {
  if (rate == null || !rate.isFinite || rate <= 0 || sats <= 0) return null;
  return sats / 100000000 * rate;
}

/// `2` / `1.5` — the node's `bond_amount_pct` (a fraction, `0.02`) as the
/// percentage the 14b context row shows, without a trailing `.0`. Null when
/// the node advertises no percentage: the row is not drawn rather than
/// invented (handoff, "decisión abierta").
String? bondSharePercent(double? fraction) {
  if (fraction == null || !fraction.isFinite || fraction < 0) return null;
  final pct = fraction * 100;
  // The node parser lets any finite fraction through; scaled, it can
  // overflow (1e308 × 100), and rounding infinity throws.
  if (!pct.isFinite) return null;
  if (pct == pct.roundToDouble()) return pct.round().toString();
  return pct.toStringAsFixed(1).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Whether the screen warns that a missed step can cost the bond. [policy]
/// is the node's `bond_slash_on_waiting_timeout`, null while the node's
/// status is still loading or could not be fetched: then the stricter
/// warning stands, since the user is about to lock sats and the softer copy
/// would claim a safety the node may not offer (docs/ANTI_ABUSE_BOND.md §8.2).
bool bondWarnsTimeout(bool? policy) => policy ?? true;

/// Whether the taker of an order of [kind] is buying sats.
bool takerIsBuying(OrderKind kind) => kind == OrderKind.sell;

/// Whether [role] means the taker pays a second hold invoice after the bond
/// (a seller-as-taker locks the trade amount next; a buyer waits for the
/// seller).
bool bondIsFollowedByEscrow(TradeRole role) => role == TradeRole.seller;

/// The message the user reads when a `canceled` ends the bond window, by
/// the cause the core attached (docs/ANTI_ABUSE_BOND.md §6.1).
enum BondCancelCopy {
  /// Another taker locked first: "taken by another user before your bond
  /// was paid".
  lostRace,

  /// The maker cancelled the order.
  makerCanceled,

  /// The user's own cancel: nothing to explain.
  own,

  /// No cause known: neutral.
  neutral,
}

BondCancelCopy bondCancelCopy(TradeUpdateReason? reason) => switch (reason) {
  TradeUpdateReason.bondLostRace => BondCancelCopy.lostRace,
  TradeUpdateReason.makerCanceled => BondCancelCopy.makerCanceled,
  TradeUpdateReason.userCanceled => BondCancelCopy.own,
  TradeUpdateReason.bondExpired || null => BondCancelCopy.neutral,
};

/// The explainer accordion is open the first time a user sees the screen
/// and then remembers what they did with it — per user, not per screen
/// (handoff, "estado del acordeón persistente").
bool bondExplainerOpens({required bool? stored}) => stored ?? true;

/// `2 060 ARS`: the fiat equivalent rounded to whole units in [locale]'s
/// digit grouping, with the order's currency code.
String formatBondFiat(String locale, double amount, String fiatCode) {
  final formatted = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: 0,
  ).format(amount);
  return '$formatted $fiatCode';
}
