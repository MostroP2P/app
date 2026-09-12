/// Pure rules of the Lightning invoice screens (`design_handoff_factura_lightning`,
/// 13a · the buyer's invoice and 13b · the seller's hold invoice). No Flutter
/// here so every rule is unit-testable; the widgets only render what these
/// return.
library;

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

/// `14:38` (mm:ss) under an hour; `1 h 05` above it.
String formatInvoiceCountdown(Duration remaining) {
  final d = remaining.isNegative ? Duration.zero : remaining;
  String two(int n) => n.toString().padLeft(2, '0');
  if (d.inHours >= 1) return '${d.inHours} h ${two(d.inMinutes % 60)}';
  return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

bool isInvoiceCountdownUrgent(Duration remaining) =>
    remaining < kInvoiceUrgentThreshold;

/// How long until the displayed value changes: every second under an hour,
/// at the next whole minute above it.
Duration invoiceCountdownTick(Duration remaining) {
  if (remaining <= const Duration(hours: 1)) return const Duration(seconds: 1);
  final intoMinute = remaining.inSeconds % 60;
  return Duration(seconds: intoMinute == 0 ? 60 : intoMinute);
}

// ── Buyer input ───────────────────────────────────────────────────────────────

/// What the buyer typed, told apart by its shape alone.
enum InvoiceInputKind {
  empty,

  /// `lnbc…` / `lntb…` (BOLT11).
  bolt11,

  /// `user@domain` or `lnurl…`: resolved into an invoice on submission.
  address,

  /// Anything else.
  unknown,
}

const _scheme = 'lightning:';

/// [raw] without surrounding whitespace or a `lightning:` prefix, which QR
/// codes and wallet shares often carry.
String normalizeInvoiceInput(String raw) {
  final trimmed = raw.trim();
  if (trimmed.toLowerCase().startsWith(_scheme)) {
    return trimmed.substring(_scheme.length).trim();
  }
  return trimmed;
}

final _lnAddress = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

InvoiceInputKind classifyInvoiceInput(String raw) {
  final text = normalizeInvoiceInput(raw).toLowerCase();
  if (text.isEmpty) return InvoiceInputKind.empty;
  if (text.startsWith('lnbc') || text.startsWith('lntb')) {
    return InvoiceInputKind.bolt11;
  }
  if (text.startsWith('lnurl') || _lnAddress.hasMatch(text)) {
    return InvoiceInputKind.address;
  }
  return InvoiceInputKind.unknown;
}

/// Verdict of the validation row under the invoice field.
sealed class InvoiceCheck {
  const InvoiceCheck();
}

/// Nothing typed: the row is not drawn and submission stays disabled.
final class InvoiceCheckNone extends InvoiceCheck {
  const InvoiceCheckNone();
}

/// Nothing to say locally — the decoder is unavailable, or the amount is not
/// known yet — so submission is allowed and the daemon decides.
final class InvoiceCheckUnverified extends InvoiceCheck {
  const InvoiceCheckUnverified();
}

/// A Lightning address (or LNURL), resolved into an invoice on submission.
final class InvoiceCheckAddress extends InvoiceCheck {
  const InvoiceCheckAddress();
}

/// A BOLT11 invoice for [sats], unexpired.
final class InvoiceCheckValid extends InvoiceCheck {
  const InvoiceCheckValid(this.sats);
  final int sats;
}

enum InvoiceProblem {
  /// Neither an invoice nor an address.
  unrecognized,

  /// Starts like an invoice but does not decode (typo, truncated copy).
  malformed,

  /// Decodes, but its amount is not the trade's.
  wrongAmount,

  expired,
}

final class InvoiceCheckError extends InvoiceCheck {
  const InvoiceCheckError(this.problem, {this.actualSats, this.expectedSats});
  final InvoiceProblem problem;

  /// Set for [InvoiceProblem.wrongAmount].
  final int? actualSats;
  final int? expectedSats;
}

/// The decoded fields of a BOLT11 invoice, as the bridge returns them.
typedef DecodedInvoice = ({int? amountSats, int expiresAt});

/// Judges [raw] for a trade that pays [expectedSats].
///
/// [decoded] is the local decoder's reading of a BOLT11 input: `null` when it
/// did not decode. [decoderAvailable] is false when the decoder itself could
/// not run, in which case a BOLT11 input is left to the daemon. [now] is unix
/// seconds.
InvoiceCheck checkInvoiceInput({
  required String raw,
  required int? expectedSats,
  required DecodedInvoice? decoded,
  required bool decoderAvailable,
  required int now,
}) {
  switch (classifyInvoiceInput(raw)) {
    case InvoiceInputKind.empty:
      return const InvoiceCheckNone();
    case InvoiceInputKind.unknown:
      return const InvoiceCheckError(InvoiceProblem.unrecognized);
    case InvoiceInputKind.address:
      return const InvoiceCheckAddress();
    case InvoiceInputKind.bolt11:
      if (!decoderAvailable) return const InvoiceCheckUnverified();
      if (decoded == null) {
        return const InvoiceCheckError(InvoiceProblem.malformed);
      }
      if (decoded.expiresAt <= now) {
        return const InvoiceCheckError(InvoiceProblem.expired);
      }
      final actual = decoded.amountSats;
      // An open-amount invoice is the daemon's to accept or refuse.
      if (actual == null || expectedSats == null) {
        return const InvoiceCheckUnverified();
      }
      if (actual != expectedSats) {
        return InvoiceCheckError(
          InvoiceProblem.wrongAmount,
          actualSats: actual,
          expectedSats: expectedSats,
        );
      }
      return InvoiceCheckValid(actual);
  }
}

/// Whether [check] lets the buyer submit.
bool invoiceCheckAllowsSubmit(InvoiceCheck check) => switch (check) {
  InvoiceCheckNone() || InvoiceCheckError() => false,
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
