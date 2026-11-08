import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/settings/widgets/mostro_node_selector.dart';
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;
import 'package:mostro/src/rust/api/types.dart';

export 'package:mostro/src/rust/api/types.dart'
    show
        ExchangeRateLookup,
        ExchangeRateLookup_NoRates,
        ExchangeRateLookup_NotQuoted,
        ExchangeRateLookup_Quoted;

/// What the active Mostro node's Kind 30078 (`d` = `mostro-rates`) event says
/// about [fiatCode]: quoted at a price, not quoted, or no rates event at all.
///
/// Reads the node pubkey from [mostroPubkeyProvider], like
/// `mostroNodeProvider`, so the answer always belongs to the node the order
/// will be sent to. An unreachable relay surfaces as an error.
///
/// The two "no rate" cases are told apart for a stablecoin: a node that
/// publishes rates without the coin refuses every market order in it, so the
/// create-order screen locks Market on [ExchangeRateLookup.notQuoted] and
/// keeps failing open on [ExchangeRateLookup.noRates] (issue #884). A fiat is
/// never locked: both read as "not checkable".
///
/// `autoDispose` and keyed by currency: switching currency starts a fetch for
/// the new one, which the Rust-side cache usually answers without another
/// relay query. Invalidate this one to refetch; [exchangeRateProvider] reads
/// it.
final exchangeRateLookupProvider = FutureProvider.autoDispose
    .family<ExchangeRateLookup, String>((ref, fiatCode) async {
      final code = fiatCode.trim();
      if (code.isEmpty) return const ExchangeRateLookup.noRates();

      final pubkey = ref.watch(mostroPubkeyProvider);
      final resolvedPubkey =
          pubkey.trim().isEmpty ? defaultMostroPubkey : pubkey.trim();

      return nostr_api.lookupExchangeRate(
        mostroPubkeyHex: resolvedPubkey,
        fiatCode: code,
      );
    });

/// Price of one BTC in [fiatCode], as published by the active Mostro node in
/// its Kind 30078 (`d` = `mostro-rates`) event.
///
/// Exists so a market-price order can be checked against the node's sats
/// limits before it is submitted (#337): the daemon prices such an order from
/// this same rate, so it is the number its range check will use.
///
/// Resolves to `null` whenever the node has no usable rate to give — it
/// publishes none (publishing is optional), the event has expired, or it
/// quotes no such currency — and an unreachable relay surfaces as an error.
/// Callers must treat both as "not checkable" and submit anyway, leaving the
/// daemon as the authority, which is what PR #302 chose for fixed-sats
/// amounts. [exchangeRateLookupProvider] is the same answer with the two
/// "null" cases told apart.
final exchangeRateProvider = FutureProvider.autoDispose.family<double?, String>(
  (ref, fiatCode) async {
    final lookup = await ref.watch(exchangeRateLookupProvider(fiatCode).future);
    return switch (lookup) {
      ExchangeRateLookup_Quoted(:final rate) => rate,
      ExchangeRateLookup_NoRates() || ExchangeRateLookup_NotQuoted() => null,
    };
  },
);
