import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/settings/widgets/mostro_node_selector.dart';
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;

/// Price of one BTC in [fiatCode], as published by the active Mostro node in
/// its Kind 30078 (`d` = `mostro-rates`) event.
///
/// Exists so a market-price order can be checked against the node's sats
/// limits before it is submitted (#337): the daemon prices such an order from
/// this same rate, so it is the number its range check will use.
///
/// Reads the node pubkey from [mostroPubkeyProvider], like
/// `mostroNodeProvider`, so the rate always belongs to the node the order will
/// be sent to.
///
/// Resolves to `null` whenever the node has no usable rate to give — it
/// publishes none (publishing is optional), the event has expired, or it
/// quotes no such currency — and an unreachable relay surfaces as an error.
/// Callers must treat both as "not checkable" and submit anyway, leaving the
/// daemon as the authority, which is what PR #302 chose for fixed-sats
/// amounts.
///
/// `autoDispose` and keyed by currency: switching currency starts a fetch for
/// the new one, which the Rust-side cache usually answers without another
/// relay query.
final exchangeRateProvider =
    FutureProvider.autoDispose.family<double?, String>((ref, fiatCode) async {
  final code = fiatCode.trim();
  if (code.isEmpty) return null;

  final pubkey = ref.watch(mostroPubkeyProvider);
  final resolvedPubkey =
      pubkey.trim().isEmpty ? defaultMostroPubkey : pubkey.trim();

  return nostr_api.fetchExchangeRate(
    mostroPubkeyHex: resolvedPubkey,
    fiatCode: code,
  );
});
