/// What the payout card and the add-invoice screen read from a trade's
/// payout destinations (#823), oldest first as Rust keeps them.
library;

import 'package:mostro/features/order/models/invoice_rules.dart'
    show normalizeInvoiceInput;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart'
    show OrderStatus, PayoutDestination, PayoutOutcome, PayoutSource;

/// Whether the node is paying the buyer, or has tried to: the seller
/// released (or a solver settled) the sats, or the record already holds
/// news of a payment. Before that a destination is only where the sats will
/// go, not one being paid (PR #824 review).
bool payoutHasStarted(OrderStatus? status, List<PayoutDestination> route) =>
    switch (status) {
      OrderStatus.settledHoldInvoice ||
      OrderStatus.success ||
      OrderStatus.settledByAdmin ||
      OrderStatus.completedByAdmin => true,
      _ => false,
    } ||
    route.any(
      (d) =>
          d.outcome == PayoutOutcome.retrying ||
          d.outcome == PayoutOutcome.failed ||
          d.outcome == PayoutOutcome.paid ||
          d.outcome == PayoutOutcome.maybePaid,
    );

/// The destination the card leads with: the one the node paid, else the
/// latest one sent.
PayoutDestination? leadingDestination(List<PayoutDestination> route) {
  for (final d in route) {
    if (d.outcome == PayoutOutcome.paid) return d;
  }
  return route.isEmpty ? null : route.last;
}

/// Every other destination, newest first: what was tried before.
List<PayoutDestination> earlierDestinations(List<PayoutDestination> route) {
  final lead = leadingDestination(route);
  return [
    for (final d in route.reversed)
      if (!identical(d, lead)) d,
  ];
}

/// The destination the node gave up on, while no other has been sent since:
/// the buyer is being asked for a new invoice because of it.
PayoutDestination? unreplacedFailure(List<PayoutDestination> route) =>
    route.isNotEmpty && route.last.outcome == PayoutOutcome.failed
        ? route.last
        : null;

/// How a submission's destination was chosen: by the NWC wallet when it made
/// the invoice, the default address when the buyer sent that one unchanged,
/// and the buyer otherwise.
///
/// Both sides are compared as the invoice field holds them: Settings keeps
/// the address as typed, `lightning:` included, while the field pre-fills it
/// without (PR #824 review).
PayoutSource payoutSourceFor({
  required bool fromWallet,
  required String submitted,
  String? defaultAddress,
}) {
  if (fromWallet) return PayoutSource.nwcWallet;
  final saved = normalizeInvoiceInput(defaultAddress ?? '').toLowerCase();
  if (saved.isNotEmpty &&
      normalizeInvoiceInput(submitted).toLowerCase() == saved) {
    return PayoutSource.defaultLightningAddress;
  }
  return PayoutSource.entered;
}

/// The node's refusal of [submitted], the destination the add-invoice screen
/// sent and is still waiting on (#941): the newest destination in [route]
/// that is the same text, when the node refused it. Null while it is not
/// refused, or not recorded.
///
/// The newest, because the same invoice can be sent twice and only the last
/// submission is the one waited on. Compared as the field holds it and case
/// aside, like [payoutSourceFor]: an address may be stored lower-cased.
PayoutDestination? refusalOf(List<PayoutDestination> route, String submitted) {
  final sent = normalizeInvoiceInput(submitted).toLowerCase();
  if (sent.isEmpty) return null;
  for (final d in route.reversed) {
    if (normalizeInvoiceInput(d.destination).toLowerCase() != sent) continue;
    return d.outcome == PayoutOutcome.rejected ? d : null;
  }
  return null;
}

/// `lnbc16770n1p4…x55sqp378xg`: enough of an invoice to tell it from
/// another, never the whole string.
String shortInvoice(String invoice) =>
    invoice.length <= 24
        ? invoice
        : '${invoice.substring(0, 12)}…${invoice.substring(invoice.length - 8)}';

/// `00010203…08090102`, like an order id (DS-CMP-22) but over a hash.
String shortPaymentHash(String hash) =>
    hash.length <= 16
        ? hash
        : '${hash.substring(0, 8)}…${hash.substring(hash.length - 8)}';

/// Where a destination sends the sats, in words: the address itself, the
/// NWC wallet that made the invoice, or the shortened invoice.
String destinationLabel(AppLocalizations l10n, PayoutDestination d) {
  if (d.isLightningAddress) return d.destination;
  if (d.source == PayoutSource.nwcWallet) {
    final name = d.walletName;
    return name == null || name.trim().isEmpty
        ? l10n.payoutNwcWallet
        : l10n.payoutNwcWalletNamed(name);
  }
  return l10n.payoutInvoice(shortInvoice(d.destination));
}

/// Who chose the destination, in words.
String sourceLabel(AppLocalizations l10n, PayoutSource source) =>
    switch (source) {
      PayoutSource.defaultLightningAddress => l10n.payoutSourceDefaultAddress,
      PayoutSource.nwcWallet => l10n.payoutSourceNwcWallet,
      PayoutSource.entered => l10n.payoutSourceEntered,
    };

/// What became of a destination, in words.
String outcomeLabel(AppLocalizations l10n, PayoutDestination d) => switch (d
    .outcome) {
  PayoutOutcome.submitted => l10n.payoutOutcomeSubmitted,
  PayoutOutcome.retrying => l10n.payoutOutcomeRetrying,
  PayoutOutcome.failed =>
    d.attempts == null
        ? l10n.payoutOutcomeFailed
        : l10n.payoutOutcomeFailedAttempts(d.attempts!),
  PayoutOutcome.rejected => l10n.payoutOutcomeRejected,
  PayoutOutcome.replaced => l10n.payoutOutcomeReplaced,
  PayoutOutcome.paid => l10n.payoutOutcomePaid,
  PayoutOutcome.maybePaid => l10n.payoutOutcomeMaybePaid,
};

/// The machine word of an outcome for the `trade.payout` readout.
String outcomeMachineName(PayoutOutcome outcome) => switch (outcome) {
  PayoutOutcome.submitted => 'submitted',
  PayoutOutcome.retrying => 'retrying',
  PayoutOutcome.failed => 'failed',
  PayoutOutcome.rejected => 'rejected',
  PayoutOutcome.replaced => 'replaced',
  PayoutOutcome.paid => 'paid',
  PayoutOutcome.maybePaid => 'maybe-paid',
};
