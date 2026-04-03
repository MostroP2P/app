import 'package:flutter/foundation.dart';

/// Dart model parsed from a Nostr Kind 38385 (Mostro instance status) event.
///
/// All fields are derived from individual tags — the event `content` is empty
/// per the Mostro protocol. See:
/// https://mostro.network/protocol/other_events.html#mostro-instance-status
@immutable
class MostroInstance {
  const MostroInstance({
    required this.pubKey,
    this.mostroVersion,
    this.commitHash,
    this.maxOrderAmount,
    this.minOrderAmount,
    this.expirationHours,
    this.expirationSeconds,
    this.fiatCurrenciesAccepted,
    this.fee,
    this.pow,
    this.holdInvoiceExpirationWindow,
    this.holdInvoiceCltvDelta,
    this.invoiceExpirationWindow,
    this.lndVersion,
    this.lndNodePublicKey,
    this.lndCommitHash,
    this.lndNodeAlias,
    this.lndChains,
    this.lndNetworks,
    this.lndUris,
    this.maxOrdersPerResponse,
  });

  /// Mostro daemon pubkey (from `d` tag).
  final String pubKey;

  // ── General Info ────────────────────────────────────────────────────────────

  final String? mostroVersion;
  final String? commitHash;
  final int? maxOrderAmount;
  final int? minOrderAmount;
  /// Pending order lifetime in hours.
  final int? expirationHours;
  /// Fee as a fraction, e.g. 0.006 = 0.6 %.
  final double? fee;
  final String? fiatCurrenciesAccepted;

  // ── Technical Details ───────────────────────────────────────────────────────

  /// Waiting-state timeout in seconds.
  final int? expirationSeconds;
  final int? holdInvoiceExpirationWindow;
  final int? holdInvoiceCltvDelta;
  final int? invoiceExpirationWindow;
  final int? pow;
  final int? maxOrdersPerResponse;

  // ── Lightning Network ───────────────────────────────────────────────────────

  final String? lndVersion;
  final String? lndNodePublicKey;
  final String? lndCommitHash;
  final String? lndNodeAlias;
  final String? lndChains;
  final String? lndNetworks;
  final String? lndUris;

  // ── Factory ─────────────────────────────────────────────────────────────────

  /// Parse a Kind 38385 event's tag list into a [MostroInstance].
  ///
  /// [tags] is `List<List<String>>` where each inner list is
  /// `[tagName, value, ...]`.
  factory MostroInstance.fromTags(List<List<String>> tags) {
    String? get(String name) {
      for (final tag in tags) {
        if (tag.isNotEmpty && tag[0] == name) {
          return tag.length > 1 ? tag[1] : null;
        }
      }
      return null;
    }

    return MostroInstance(
      pubKey: get('d') ?? '',
      mostroVersion: get('mostro_version'),
      commitHash: get('mostro_commit_hash'),
      maxOrderAmount: int.tryParse(get('max_order_amount') ?? ''),
      minOrderAmount: int.tryParse(get('min_order_amount') ?? ''),
      expirationHours: int.tryParse(get('expiration_hours') ?? ''),
      expirationSeconds: int.tryParse(get('expiration_seconds') ?? ''),
      fiatCurrenciesAccepted: get('fiat_currencies_accepted'),
      fee: double.tryParse(get('fee') ?? ''),
      pow: int.tryParse(get('pow') ?? ''),
      holdInvoiceExpirationWindow:
          int.tryParse(get('hold_invoice_expiration_window') ?? ''),
      holdInvoiceCltvDelta:
          int.tryParse(get('hold_invoice_cltv_delta') ?? ''),
      invoiceExpirationWindow:
          int.tryParse(get('invoice_expiration_window') ?? ''),
      lndVersion: get('lnd_version'),
      lndNodePublicKey: get('lnd_node_pubkey'),
      lndCommitHash: get('lnd_commit_hash'),
      lndNodeAlias: get('lnd_node_alias'),
      lndChains: get('lnd_chains'),
      lndNetworks: get('lnd_networks'),
      lndUris: get('lnd_uris'),
      maxOrdersPerResponse:
          int.tryParse(get('max_orders_per_response') ?? ''),
    );
  }

  /// Fee formatted as a percentage string, e.g. "0.6%".
  String? get feePercent {
    if (fee == null) return null;
    final pct = fee! * 100;
    return pct == pct.truncateToDouble()
        ? '${pct.toInt()}%'
        : '${pct.toStringAsFixed(2)}%';
  }
}
