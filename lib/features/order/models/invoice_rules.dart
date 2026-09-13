/// Pure rules of the Lightning invoice screens (`design_handoff_factura_lightning`,
/// 13a · the buyer's invoice and 13b · the seller's hold invoice). No Flutter
/// here so every rule is unit-testable; the widgets only render what these
/// return.
library;

import 'package:mostro/src/rust/api/types.dart' as rust_types;
import 'package:mostro/src/rust/api/types.dart'
    show
        InvoiceVerdict,
        InvoiceVerdict_Empty,
        InvoiceVerdict_Unverified,
        InvoiceVerdict_Address,
        InvoiceVerdict_Valid,
        InvoiceVerdict_Rejected;

// ── Order id ──────────────────────────────────────────────────────────────────

/// `#09150348`: the app bar shows the first eight characters of the UUID;
/// tapping it copies the whole id.
String invoiceOrderTag(String orderId) =>
    '#${orderId.length <= 8 ? orderId : orderId.substring(0, 8)}';

// ── Amounts ───────────────────────────────────────────────────────────────────

const _thinSpace = ' ';

/// Whole sats without a thousands separator up to five digits (`25000`), and
/// grouped by a thin space from six on (`300 000`).
String formatInvoiceSats(int sats) {
  final digits = sats.abs().toString();
  final sign = sats < 0 ? '-' : '';
  if (digits.length <= 5) return '$sign$digits';
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(_thinSpace);
    buffer.write(digits[i]);
  }
  return '$sign$buffer';
}

/// The Mostro fee a hold invoice of [holdSats] carries, given the node's fee
/// as a fraction ([nodeFee], `0.006` = 0.6 %), or null when it cannot be
/// derived.
///
/// mostrod charges each side half the fee, rounded: the seller's hold invoice
/// is `amount + round(nodeFee · amount / 2)` (`util::get_fee`,
/// `add_invoice.rs`). The trade record only keeps the hold amount, so the
/// order amount is recovered by searching the handful of integers that can
/// produce it.
int? holdInvoiceFee({required int holdSats, required double? nodeFee}) {
  if (nodeFee == null || !nodeFee.isFinite || nodeFee < 0 || holdSats <= 0) {
    return null;
  }
  if (nodeFee == 0) return 0;
  int feeOf(int amount) => (nodeFee * amount / 2).round();
  final guess = (holdSats / (1 + nodeFee / 2)).floor();
  for (var amount = guess + 2; amount >= guess - 2 && amount >= 0; amount--) {
    if (amount + feeOf(amount) == holdSats) return holdSats - amount;
  }
  return null;
}

// ── Countdown ─────────────────────────────────────────────────────────────────

/// Under this the time band turns red and the figure pulses.
const kInvoiceUrgentThreshold = Duration(seconds: 60);

/// `14:38` (mm:ss) under an hour; above it, [hours] builds the localized
/// form (`1 h 05`) from the hour count and the two-digit minutes.
String formatInvoiceCountdown(
  Duration remaining, {
  required String Function(String hours, String minutes) hours,
}) {
  final d = remaining.isNegative ? Duration.zero : remaining;
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.inHours >= 1) return hours('${d.inHours}', two(d.inMinutes % 60));
  return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

bool isInvoiceCountdownUrgent(Duration remaining) =>
    remaining < kInvoiceUrgentThreshold;

/// How long until the displayed value changes: every second under an hour;
/// above it, one second past the seconds into the current minute — the
/// display floors to whole minutes, so `2:00:15` still reads `2 h 00` after
/// 15 s and turns `1 h 59` one second later (and `2:00:00` after 1 s).
Duration invoiceCountdownTick(Duration remaining) {
  if (remaining <= const Duration(hours: 1)) return const Duration(seconds: 1);
  return Duration(seconds: remaining.inSeconds % 60 + 1);
}

// ── Buyer input ───────────────────────────────────────────────────────────────

const _scheme = 'lightning:';

/// [raw] without surrounding whitespace or a `lightning:` prefix, which QR
/// codes and wallet shares often carry. Field tidying only: the Rust core
/// normalizes again before it judges or sends anything.
String normalizeInvoiceInput(String raw) {
  final trimmed = raw.trim();
  if (trimmed.toLowerCase().startsWith(_scheme)) {
    return trimmed.substring(_scheme.length).trim();
  }
  return trimmed;
}

/// Verdict of the validation row under the invoice field, as the screen
/// renders it. The judgement itself is the Rust core's
/// (`api::invoice::check_buyer_invoice`); [invoiceCheckFromVerdict] maps it.
sealed class InvoiceCheck {
  const InvoiceCheck();
}

/// Nothing typed: the row is not drawn and submission stays disabled.
final class InvoiceCheckNone extends InvoiceCheck {
  const InvoiceCheckNone();
}

/// Nothing to say locally — the checker is unavailable, the amount is open
/// or not known yet — so submission is allowed and the daemon decides.
final class InvoiceCheckUnverified extends InvoiceCheck {
  const InvoiceCheckUnverified();
}

/// An input the checker has not judged yet: no row, and no submission until
/// it has, so a bad invoice cannot slip past the validation.
final class InvoiceCheckPending extends InvoiceCheck {
  const InvoiceCheckPending();
}

/// A Lightning address, resolved into an invoice on submission.
final class InvoiceCheckAddress extends InvoiceCheck {
  const InvoiceCheckAddress();
}

/// A BOLT11 invoice for [sats], unexpired. [expiresAt] (unix seconds) is
/// when it stops being so — the screen re-judges it before then.
final class InvoiceCheckValid extends InvoiceCheck {
  const InvoiceCheckValid(this.sats, {this.expiresAt});
  final int sats;
  final int? expiresAt;
}

enum InvoiceProblem {
  /// Neither an invoice nor an address.
  unrecognized,

  /// Starts like an invoice but does not decode (typo, truncated copy).
  malformed,

  /// Decodes, but its amount is not the trade's.
  wrongAmount,

  expired,

  /// Unexpired, but with less lifetime left than the node demands
  /// (`invoice_expiration_window`): the daemon would refuse it.
  expiresTooSoon,

  /// Decodes, but for another chain than the node's.
  wrongNetwork,
}

final class InvoiceCheckError extends InvoiceCheck {
  const InvoiceCheckError(
    this.problem, {
    this.actualMsat,
    this.expectedSats,
    this.invoiceNetwork,
    this.nodeNetwork,
    this.minRemainingSecs,
  });
  final InvoiceProblem problem;

  /// Set for [InvoiceProblem.wrongAmount]; msat, so a sub-sat remainder can
  /// be shown rather than rounded away.
  final int? actualMsat;
  final int? expectedSats;

  /// Set for [InvoiceProblem.wrongNetwork], in LND's naming.
  final String? invoiceNetwork;
  final String? nodeNetwork;

  /// Set for [InvoiceProblem.expiresTooSoon]: the node's minimum, seconds.
  final int? minRemainingSecs;
}

/// The Rust core's verdict as the row renders it.
InvoiceCheck invoiceCheckFromVerdict(
  InvoiceVerdict verdict,
) => switch (verdict) {
  InvoiceVerdict_Empty() => const InvoiceCheckNone(),
  InvoiceVerdict_Unverified() => const InvoiceCheckUnverified(),
  InvoiceVerdict_Address() => const InvoiceCheckAddress(),
  InvoiceVerdict_Valid(:final sats, :final expiresAt) => InvoiceCheckValid(
    sats.toInt(),
    expiresAt: expiresAt.toInt(),
  ),
  InvoiceVerdict_Rejected(
    :final problem,
    :final actualMsat,
    :final expectedSats,
    :final invoiceNetwork,
    :final nodeNetwork,
    :final minRemainingSecs,
  ) =>
    InvoiceCheckError(
      switch (problem) {
        rust_types.InvoiceProblem.unrecognized => InvoiceProblem.unrecognized,
        rust_types.InvoiceProblem.malformed => InvoiceProblem.malformed,
        rust_types.InvoiceProblem.wrongAmount => InvoiceProblem.wrongAmount,
        rust_types.InvoiceProblem.expired => InvoiceProblem.expired,
        rust_types.InvoiceProblem.expiresTooSoon =>
          InvoiceProblem.expiresTooSoon,
        rust_types.InvoiceProblem.wrongNetwork => InvoiceProblem.wrongNetwork,
      },
      actualMsat: actualMsat?.toInt(),
      expectedSats: expectedSats?.toInt(),
      invoiceNetwork: invoiceNetwork,
      nodeNetwork: nodeNetwork,
      minRemainingSecs: minRemainingSecs?.toInt(),
    ),
};

/// An msat amount as sats: `250`, or `250.5` when it carries a remainder.
String formatInvoiceMsat(int msat) {
  final sats = msat ~/ 1000;
  final rest = msat % 1000;
  if (rest == 0) return formatInvoiceSats(sats);
  final fraction = rest
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${formatInvoiceSats(sats)}.$fraction';
}

/// Whether [check] lets the buyer submit.
bool invoiceCheckAllowsSubmit(InvoiceCheck check) => switch (check) {
  InvoiceCheckNone() || InvoiceCheckPending() || InvoiceCheckError() => false,
  InvoiceCheckUnverified() ||
  InvoiceCheckAddress() ||
  InvoiceCheckValid() => true,
};

// ── Counterpart ───────────────────────────────────────────────────────────────

/// The reputation beside the counterpart's name: `★ 4.9`, or null when the
/// counterpart has no rated trade (the caller writes `no trades` instead of
/// a misleading `0.0 ★`) or no snapshot has arrived yet.
String? counterpartStars(double? rating, int? reviews) {
  if (rating == null || reviews == null || reviews <= 0) return null;
  return '★ ${rating.toStringAsFixed(1)}';
}
