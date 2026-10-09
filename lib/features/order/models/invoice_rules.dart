/// Pure rules of the Lightning invoice screens (`design_handoff_factura_lightning`,
/// 13a · the buyer's invoice and 13b · the seller's hold invoice). No Flutter
/// here so every rule is unit-testable; the widgets only render what these
/// return.
library;

import 'package:intl/intl.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;
import 'package:mostro/src/rust/api/types.dart'
    show
        InvoiceVerdict,
        InvoiceVerdict_Empty,
        InvoiceVerdict_Unverified,
        InvoiceVerdict_Address,
        InvoiceVerdict_Valid,
        InvoiceVerdict_Rejected;

// ── Amounts ───────────────────────────────────────────────────────────────────

/// Whole sats grouped the way the locale groups every other amount in the
/// app (`2.439` in `es`, `2,439` in `en`), so an invoice screen reads like the
/// order it belongs to (#720).
String formatInvoiceSats(int sats, String locale) =>
    NumberFormat.decimalPattern(locale).format(sats);

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

// ── Step expiry ───────────────────────────────────────────────────────────────

/// What mostrod does with the order when a waiting step runs out
/// (`scheduler.rs`): it goes back to the book when the taker owed the step,
/// and is cancelled when the maker did. Both sides of the trade read the same
/// outcome.
enum StepExpiry { backToBook, cancelled }

/// [buyerStep] is the buyer's invoice; otherwise the step is the seller's
/// hold-invoice payment. The taker owes the buyer's invoice on a sell order
/// and the seller's payment on a buy order, so [kind] is enough to tell who
/// owes the step without knowing which side the user took.
StepExpiry stepExpiry({
  required bool buyerStep,
  required rust_types.OrderKind kind,
}) =>
    buyerStep == (kind == rust_types.OrderKind.sell)
        ? StepExpiry.backToBook
        : StepExpiry.cancelled;

/// Whether [status] says the order was called off, however it ended: an
/// invoice screen then has nothing left to ask for and leaves for home.
bool invoiceOrderCancelled(rust_types.OrderStatus status) => switch (status) {
  rust_types.OrderStatus.canceled ||
  rust_types.OrderStatus.cooperativelyCanceled ||
  rust_types.OrderStatus.canceledByAdmin ||
  rust_types.OrderStatus.expired => true,
  _ => false,
};

// ── Buyer input ───────────────────────────────────────────────────────────────

const _scheme = 'lightning:';

final _whitespace = RegExp(r'\s+');

/// [raw] without any whitespace — an invoice copied from a mail arrives cut
/// by line breaks — or a `lightning:` prefix, which QR codes and wallet
/// shares often carry. Field tidying only: the Rust core normalizes again
/// before it judges or sends anything.
String normalizeInvoiceInput(String raw) {
  final compact = raw.replaceAll(_whitespace, '');
  if (compact.toLowerCase().startsWith(_scheme)) {
    return compact.substring(_scheme.length);
  }
  return compact;
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

/// An msat amount as sats: `2.439`, or `2.439,5` when it carries a remainder,
/// in [locale]'s separators.
///
/// The whole sats and the remainder are formatted apart, in integer
/// arithmetic: `msat / 1000` as a double would round an amount past 2^53.
String formatInvoiceMsat(int msat, String locale) {
  final format = NumberFormat.decimalPattern(locale);
  final whole = format.format(msat ~/ 1000);
  final remainder = (msat % 1000).abs();
  if (remainder == 0) return whole;
  final fraction = remainder
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '$whole${format.symbols.DECIMAL_SEP}$fraction';
}

/// Whether [check] lets the buyer submit.
bool invoiceCheckAllowsSubmit(InvoiceCheck check) => switch (check) {
  InvoiceCheckNone() || InvoiceCheckPending() || InvoiceCheckError() => false,
  InvoiceCheckUnverified() ||
  InvoiceCheckAddress() ||
  InvoiceCheckValid() => true,
};

/// [check] as the stable word automation reads off `invoice.check`, or null
/// in the three states that draw no row at all.
///
/// Null is "not judged yet", never "fine": the amount an invoice is checked
/// against arrives with the trade, and the node's expiry window with its
/// capabilities, so a perfectly good invoice reads
/// [InvoiceCheckUnverified] — no row, no word — until both land. A harness
/// waits for the word it expects instead of reading once.
///
/// Kebab-case like `order.status`, and never the row's sentence, which is
/// translated.
String? invoiceCheckWord(InvoiceCheck check) => switch (check) {
  InvoiceCheckNone() ||
  InvoiceCheckPending() ||
  InvoiceCheckUnverified() => null,
  InvoiceCheckAddress() => 'address',
  InvoiceCheckValid() => 'valid',
  InvoiceCheckError(:final problem) => switch (problem) {
    InvoiceProblem.unrecognized => 'unrecognized',
    InvoiceProblem.malformed => 'malformed',
    InvoiceProblem.wrongAmount => 'wrong-amount',
    InvoiceProblem.expired => 'expired',
    InvoiceProblem.expiresTooSoon => 'expires-too-soon',
    InvoiceProblem.wrongNetwork => 'wrong-network',
  },
};

// ── Counterpart ───────────────────────────────────────────────────────────────

/// The reputation beside the counterpart's name: `★ 4.9`, or null when the
/// counterpart has no rated trade (the caller writes `no trades` instead of
/// a misleading `0.0 ★`) or no snapshot has arrived yet.
String? counterpartStars(double? rating, int? reviews) {
  if (rating == null || reviews == null || reviews <= 0) return null;
  return '★ ${rating.toStringAsFixed(1)}';
}

/// Lifetime an NWC invoice gets beyond the node's `invoice_expiration_window`.
const kNwcInvoiceExpiryMarginSecs = 3600;

/// The expiry to ask an NWC wallet for. Left to the wallet's default, the
/// invoice may expire inside the node's window, and the check refuses it on
/// every try with nothing the buyer can change.
int nwcInvoiceExpirySecs(int? nodeWindowSecs) =>
    (nodeWindowSecs ?? 0) + kNwcInvoiceExpiryMarginSecs;
