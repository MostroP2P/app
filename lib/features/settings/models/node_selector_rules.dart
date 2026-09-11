import 'package:intl/intl.dart';

import 'package:mostro/src/rust/api/node_stats.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Pure rules of the node selector (`design_handoff_selector_nodo`, 9a/9b):
/// ordering, availability, chip layout, figure formatting and the shape check
/// of a pasted pubkey. No widgets, no providers — unit-tested directly.

// ── Availability ──────────────────────────────────────────────────────────────

/// How long after its last kind 38385 heartbeat a node is still trusted to be
/// up. mostrod republishes the info event every `publish_mostro_info_interval`
/// (300 s by default), so this is six missed heartbeats — the handoff's
/// proposal. A node in Cashu mode publishes no info event at all, so
/// [availabilityOf] also accepts an open order as proof of life.
const nodeHeartbeatStaleAfter = Duration(minutes: 30);

enum NodeAvailability {
  /// Heartbeat recent (or open orders exist) and at least one order the user
  /// can use.
  online,

  /// Reachable but nothing to trade: no open orders at all, or none in the
  /// user's currency.
  noUsefulOrders,

  /// No fresh heartbeat and no open order: shown last, dimmed, not selectable.
  unreachable,
}

DateTime _fromUnix(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

/// Newest signal we have from the node — heartbeat or newest open order.
DateTime? lastSignalAt(MostroNodeStats stats) {
  final candidates =
      [stats.infoSeenAt, stats.latestOrderAt].whereType<int>().toList();
  if (candidates.isEmpty) return null;
  return _fromUnix(candidates.reduce((a, b) => a > b ? a : b));
}

/// Open orders in [fiatCode] on this node; the total when there is no
/// preferred currency.
int ordersIn(MostroNodeStats stats, String? fiatCode) {
  if (fiatCode == null) return stats.totalOrders;
  final code = fiatCode.toUpperCase();
  for (final c in stats.ordersByFiat) {
    if (c.fiatCode == code) return c.count;
  }
  return 0;
}

NodeAvailability availabilityOf(
  MostroNodeStats stats,
  String? myFiat,
  DateTime now,
) {
  final info = stats.infoSeenAt;
  final heartbeatFresh =
      info != null &&
      now.difference(_fromUnix(info)) <= nodeHeartbeatStaleAfter;
  if (!heartbeatFresh && stats.totalOrders == 0) {
    return NodeAvailability.unreachable;
  }
  if (ordersIn(stats, myFiat) == 0) return NodeAvailability.noUsefulOrders;
  return NodeAvailability.online;
}

/// Does the node accept [myFiat]? `null` when the node publishes no currency
/// list (nothing to say) or the user has no preferred currency.
bool? acceptsMyFiat(MostroNodeStats stats, String? myFiat) {
  if (myFiat == null || stats.acceptedCurrencies.isEmpty) return null;
  return stats.acceptedCurrencies.contains(myFiat.toUpperCase());
}

/// Why a card cannot be selected, if it cannot. Stats still loading (or
/// failed) never block a selection: missing data is shown as `—`, not as a
/// verdict.
enum NodeBlocker { bondUnsupported, unreachable }

NodeBlocker? blockerOf(MostroNodeStats? stats, String? myFiat, DateTime now) {
  if (stats == null) return null;
  if (stats.bondRequired == true) return NodeBlocker.bondUnsupported;
  if (availabilityOf(stats, myFiat, now) == NodeAvailability.unreachable) {
    return NodeBlocker.unreachable;
  }
  return null;
}

// ── Ordering ──────────────────────────────────────────────────────────────────

/// Unreachable nodes last; then by open orders in the user's currency, then
/// by total open orders, both descending; ties keep the registry order.
/// Nodes without stats sort as zero, above the unreachable.
List<MostroNodeEntry> sortNodes(
  List<MostroNodeEntry> entries,
  Map<String, MostroNodeStats> stats,
  String? myFiat,
  DateTime now,
) {
  (int, int, int) key(MostroNodeEntry e) {
    final s = stats[e.pubkey];
    if (s == null) return (0, 0, 0);
    final down =
        availabilityOf(s, myFiat, now) == NodeAvailability.unreachable ? 1 : 0;
    return (down, -ordersIn(s, myFiat), -s.totalOrders);
  }

  final indexed = entries.indexed.toList();
  indexed.sort((a, b) {
    final ka = key(a.$2);
    final kb = key(b.$2);
    if (ka.$1 != kb.$1) return ka.$1.compareTo(kb.$1);
    if (ka.$2 != kb.$2) return ka.$2.compareTo(kb.$2);
    if (ka.$3 != kb.$3) return ka.$3.compareTo(kb.$3);
    return a.$1.compareTo(b.$1);
  });
  return [for (final (_, e) in indexed) e];
}

// ── Currency chips ────────────────────────────────────────────────────────────

/// At most this many currency chips; the rest collapse into `+N`.
const maxCurrencyChips = 5;

typedef CurrencyChips = ({List<String> shown, int overflow});

/// The user's currency first, then the node's order, capped at
/// [maxCurrencyChips].
CurrencyChips currencyChips(List<String> accepted, String? myFiat) {
  final mine = myFiat?.toUpperCase();
  final ordered = <String>[
    if (mine != null && accepted.contains(mine)) mine,
    ...accepted.where((c) => c != mine),
  ];
  final shown = ordered.take(maxCurrencyChips).toList();
  return (shown: shown, overflow: ordered.length - shown.length);
}

// ── Figures ───────────────────────────────────────────────────────────────────

/// `5000` → `5k`, `2000000` → `2M`, `1500` → `1.5k` (locale separator),
/// `950` → `950`.
String abbreviateSats(BigInt sats, String locale) {
  final n = sats.toDouble();
  final fmt =
      NumberFormat.decimalPattern(locale)
        ..minimumFractionDigits = 0
        ..maximumFractionDigits = 1;
  if (n >= 1e9) return '${fmt.format(n / 1e9)}G';
  if (n >= 1e6) return '${fmt.format(n / 1e6)}M';
  if (n >= 1e3) return '${fmt.format(n / 1e3)}k';
  return NumberFormat.decimalPattern(locale).format(sats.toInt());
}

/// `5k–2M`, or `null` when either bound is missing (the column shows `—`).
String? satsRange(BigInt? min, BigInt? max, String locale) {
  if (min == null || max == null) return null;
  return '${abbreviateSats(min, locale)}–${abbreviateSats(max, locale)}';
}

/// `0.6` → `0,6` in `es`, always at least one decimal so `1` reads `1,0`.
String formatFeePct(double pct, String locale) {
  final fmt =
      NumberFormat.decimalPattern(locale)
        ..minimumFractionDigits = 1
        ..maximumFractionDigits = 2;
  return fmt.format(pct);
}

/// `≈ 1.800 – 720.000` for the sats range at [btcPrice] (fiat per BTC), or
/// `null` when there is no rate or no range — the line is then omitted.
String? fiatEquivalent(
  BigInt? min,
  BigInt? max,
  double? btcPrice,
  String locale,
) {
  if (min == null || max == null || btcPrice == null || btcPrice <= 0) {
    return null;
  }
  final fmt =
      NumberFormat.decimalPattern(locale)
        ..minimumFractionDigits = 0
        ..maximumFractionDigits = 0;
  String conv(BigInt sats) => fmt.format(sats.toDouble() / 1e8 * btcPrice);
  return '≈ ${conv(min)} – ${conv(max)}';
}

// ── Pubkey shape ──────────────────────────────────────────────────────────────

final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');
final _npub = RegExp(r'^npub1[02-9ac-hj-np-z]{58}$');

/// Shape check for the dialog (enables `Agregar`, paints the error on blur).
/// The authoritative parse — checksum, nsec rejection — stays in Rust.
bool looksLikeNodePubkey(String input) {
  final s = input.trim();
  return _hex64.hasMatch(s) || _npub.hasMatch(s.toLowerCase());
}

/// `nsec…` is a private key: refuse it before it ever reaches the bridge.
bool looksLikePrivateKey(String input) =>
    input.trim().toLowerCase().startsWith('nsec');
