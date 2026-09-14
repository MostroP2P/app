/// Pure rules of the order-detail screens (handoffs 6a/6b · own order and
/// 7a · take order). No Flutter here so every rule is unit-testable; the
/// widgets only render what these return.
library;

// ── Order id ──────────────────────────────────────────────────────────────────

/// `09150348…99b5`: the head and the tail of [id], cut in the middle.
///
/// The tail is what people compare when verifying an order, so an id is never
/// truncated at its end. Ids too short to gain anything are returned whole.
String shortOrderId(String id, {int head = 8, int tail = 4}) {
  if (id.length <= head + tail + 1) return id;
  return '${id.substring(0, head)}…${id.substring(id.length - tail)}';
}

// ── Countdown ─────────────────────────────────────────────────────────────────

/// `23:12` (h:mm) above an hour; `12:40` (mm:ss) under it. Seconds above an
/// hour would force a repaint every second for nothing.
String formatRemaining(Duration remaining) {
  final d = remaining.isNegative ? Duration.zero : remaining;
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.inHours >= 1) return '${d.inHours}:${two(d.inMinutes % 60)}';
  return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

/// How often the countdown should repaint for [remaining].
Duration countdownTick(Duration remaining) =>
    remaining.inHours >= 1
        ? const Duration(minutes: 1)
        : const Duration(seconds: 1);

/// Urgency of the taker's countdown: calm above an hour, warning under it,
/// urgent under five minutes (handoff 7a).
enum CountdownTone { calm, warning, urgent }

CountdownTone countdownTone(Duration remaining) {
  if (remaining.inHours >= 1) return CountdownTone.calm;
  if (remaining >= const Duration(minutes: 5)) return CountdownTone.warning;
  return CountdownTone.urgent;
}

/// Share of the order's lifetime already elapsed, in `[0, 1]`. Zero when
/// the order carries no expiry.
double orderLifeProgress({
  required DateTime createdAt,
  required DateTime? expiresAt,
  required DateTime now,
}) {
  if (expiresAt == null) return 0;
  final lifetime = expiresAt.difference(createdAt).inSeconds;
  if (lifetime <= 0) return 0;
  final elapsed = now.difference(createdAt).inSeconds;
  return (elapsed / lifetime).clamp(0.0, 1.0);
}

// ── Sats estimate ─────────────────────────────────────────────────────────────

/// Whole sats [fiat] buys at [rate] (fiat per BTC) once [premium] percent is
/// applied to the price, or null when there is no usable rate.
///
/// An estimate only: the daemon prices the order when it is taken, from its
/// own rate at that moment.
int? estimateSats({
  required double fiat,
  required double? rate,
  required double premium,
}) {
  if (rate == null || !rate.isFinite || rate <= 0) return null;
  final price = rate * (1 + premium / 100);
  if (!price.isFinite || price <= 0) return null;
  return (fiat / price * 100000000).round();
}

// ── Payment methods ───────────────────────────────────────────────────────────

/// How the data row shows the order's payment methods: up to two joined by
/// `, `; beyond two, the first one and a `+N` count (handoff 6a §3).
class PaymentMethodsSummary {
  const PaymentMethodsSummary({required this.all, required this.shown});

  final List<String> all;
  final List<String> shown;

  int get hidden => all.length - shown.length;
}

PaymentMethodsSummary paymentMethodsSummary(String paymentMethod) {
  final all =
      paymentMethod
          .split(',')
          .map((method) => method.trim())
          .where((method) => method.isNotEmpty)
          .toList(growable: false);
  final shown = all.length > 2 ? all.sublist(0, 1) : all;
  return PaymentMethodsSummary(all: all, shown: shown);
}

// ── Premium colour, taker's side ──────────────────────────────────────────────

/// Whom a premium favours. On the take-order screen it is read from the
/// **taker's** side — the inverse of `premiumFavour` in
/// `create_order_rules.dart`, where the owner of the number is the maker.
enum PremiumSide { good, bad, zero }

/// Lime when the premium plays for whoever takes the order: buying below
/// market (a sell order with a negative premium) or selling above it (a buy
/// order with a positive one). Amber otherwise; neutral at zero.
PremiumSide takerPremiumFavour({required String kind, required double premium}) {
  if (premium == 0) return PremiumSide.zero;
  final advantage = kind == 'sell' ? -premium : premium;
  return advantage > 0 ? PremiumSide.good : PremiumSide.bad;
}
