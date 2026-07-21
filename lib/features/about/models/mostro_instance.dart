import 'package:flutter/foundation.dart';

/// Anti-abuse bond policy advertised by a Mostro daemon via its kind-38385
/// info event.
///
/// Three states must be distinguished:
/// - [unsupported]: the `bond_enabled` tag is absent (legacy daemon that
///   predates the anti-abuse bond feature) or carries a malformed value.
/// - [disabled]: `bond_enabled="false"` — the operator left the feature off.
/// - [enabled]: `bond_enabled="true"` — the bond is active and the remaining
///   bond tags are meaningful.
enum BondPolicy { unsupported, disabled, enabled }

/// Which side of a trade a bond applies to (`bond_apply_to` tag).
enum BondApplyTo { take, make, both }

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
    this.bondPolicy = BondPolicy.unsupported,
    this.bondApplyTo,
    this.bondSlashOnWaitingTimeout,
    this.bondAmountPct,
    this.bondBaseAmountSats,
    this.bondSlashNodeSharePct,
    this.bondPayoutClaimWindowDays,
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

  // ── Anti-abuse bond ─────────────────────────────────────────────────────────

  /// Bond policy state; defaults to [BondPolicy.unsupported]. See [BondPolicy].
  final BondPolicy bondPolicy;

  // The six bond parameters are non-null only when [bondPolicy] is
  // [BondPolicy.enabled]; otherwise, or on an absent/invalid tag, they are null.

  final BondApplyTo? bondApplyTo;
  final bool? bondSlashOnWaitingTimeout;

  /// Bond fraction of the order amount (0.01 = 1%). Non-negative and finite;
  /// not capped at 1.0 (the daemon does not constrain its upper bound).
  final double? bondAmountPct;

  /// Minimum bond floor in sats, `>= 0`.
  final int? bondBaseAmountSats;

  /// Node's share of a slashed bond, constrained to `[0.0, 1.0]`.
  final double? bondSlashNodeSharePct;

  /// Days to claim a payout before forfeit, `> 0`.
  final int? bondPayoutClaimWindowDays;

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

    // Treats empty/whitespace-only as missing, so an empty `bond_enabled=""`
    // stays `unsupported` rather than being read as `disabled`.
    String? getOptional(String name) {
      final raw = get(name);
      if (raw == null) return null;
      final value = raw.trim();
      return value.isEmpty ? null : value;
    }

    BondPolicy parseBondPolicy() {
      switch (getOptional('bond_enabled')?.toLowerCase()) {
        case 'true':
          return BondPolicy.enabled;
        case 'false':
          return BondPolicy.disabled;
        default:
          return BondPolicy.unsupported;
      }
    }

    BondApplyTo? parseBondApplyTo() {
      switch (getOptional('bond_apply_to')?.toLowerCase()) {
        case 'take':
          return BondApplyTo.take;
        case 'make':
          return BondApplyTo.make;
        case 'both':
          return BondApplyTo.both;
        default:
          return null;
      }
    }

    bool? parseBool(String name) {
      switch (getOptional(name)?.toLowerCase()) {
        case 'true':
          return true;
        case 'false':
          return false;
        default:
          return null;
      }
    }

    // Rejects NaN/Infinity and negatives. [max] caps the upper bound only when
    // the protocol constrains it: the daemon validates `slash_node_share_pct`
    // to `<= 1.0`, but `amount_pct` is an unbounded fraction (0.01 = 1%).
    double? parseFraction(String name, {double? max}) {
      final value = double.tryParse(getOptional(name) ?? '');
      if (value == null || !value.isFinite || value < 0.0) return null;
      if (max != null && value > max) return null;
      return value;
    }

    int? parseNonNegativeInt(String name) {
      final value = int.tryParse(getOptional(name) ?? '');
      if (value == null) return null;
      return value >= 0 ? value : null;
    }

    int? parsePositiveInt(String name) {
      final value = int.tryParse(getOptional(name) ?? '');
      if (value == null) return null;
      return value > 0 ? value : null;
    }

    // Parameters are gated on an enabled policy so a disabled or malformed
    // event never exposes live bond values (consumers key off nullability).
    final bondPolicy = parseBondPolicy();
    final isEnabled = bondPolicy == BondPolicy.enabled;

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
      holdInvoiceExpirationWindow: int.tryParse(
        get('hold_invoice_expiration_window') ?? '',
      ),
      holdInvoiceCltvDelta: int.tryParse(get('hold_invoice_cltv_delta') ?? ''),
      invoiceExpirationWindow: int.tryParse(
        get('invoice_expiration_window') ?? '',
      ),
      lndVersion: get('lnd_version'),
      lndNodePublicKey: get('lnd_node_pubkey'),
      lndCommitHash: get('lnd_commit_hash'),
      lndNodeAlias: get('lnd_node_alias'),
      lndChains: get('lnd_chains'),
      lndNetworks: get('lnd_networks'),
      lndUris: get('lnd_uris'),
      maxOrdersPerResponse: int.tryParse(get('max_orders_per_response') ?? ''),
      bondPolicy: bondPolicy,
      bondApplyTo: isEnabled ? parseBondApplyTo() : null,
      bondSlashOnWaitingTimeout:
          isEnabled ? parseBool('bond_slash_on_waiting_timeout') : null,
      bondAmountPct: isEnabled ? parseFraction('bond_amount_pct') : null,
      bondBaseAmountSats:
          isEnabled ? parseNonNegativeInt('bond_base_amount_sats') : null,
      bondSlashNodeSharePct:
          isEnabled
              ? parseFraction('bond_slash_node_share_pct', max: 1.0)
              : null,
      bondPayoutClaimWindowDays:
          isEnabled ? parsePositiveInt('bond_payout_claim_window_days') : null,
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
