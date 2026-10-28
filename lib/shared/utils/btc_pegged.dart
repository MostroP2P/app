import 'package:intl/intl.dart';

/// The order currencies pegged 1:1 to bitcoin itself: on-chain BTC, L-BTC on
/// Liquid and RBTC on Rootstock (#907, protocol "Bitcoin on other networks").
///
/// For these codes an order's fiat amount (`fa`, and a range order's `min`
/// and `max`) counts **sats of the asset**, not whole units: `fa` = 100000 is
/// 0.001 RBTC. The amount is entered in sats, which is what goes on the wire,
/// and shown in the asset's unit next to its code ([formatBtcPeggedAmount]).
///
/// A set rather than a catalogue lookup, so pure formatting code can tell
/// the unit without loading the catalogue asset.
const btcPeggedCodes = {'BTC', 'LBTC', 'RBTC'};

/// Sats in one unit of a BTC-pegged asset.
const _satsPerUnit = 100000000;

/// Whether [code] (any case) is pegged to bitcoin, so its amounts are sats.
bool isBtcPeggedCode(String code) =>
    btcPeggedCodes.contains(code.toUpperCase());

/// [sats] of a BTC-pegged asset in the asset's own unit, with the locale's
/// separators and 8 decimals at most: `0.001` for 100000 in `en`.
String formatBtcPeggedAmount(num sats, String locale) =>
    NumberFormat('#,##0.########', locale).format(sats / _satsPerUnit);
